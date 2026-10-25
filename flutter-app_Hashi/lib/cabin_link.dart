import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'discover.dart' show localHttpClient;
import 'protocol.dart';
import 'backend/communication_client.dart';

/// Opens the connection. Replaceable in tests.
typedef ChannelFactory = StreamChannel<dynamic> Function(Uri uri);

StreamChannel<dynamic> openWebSocket(Uri uri) => IOWebSocketChannel.connect(
  uri,
  customClient: localHttpClient(),
  pingInterval: null,
);

/// The phone's live line to the cabin server. It keeps itself connected: when the Wi-Fi blips it tries again with growing
/// pauses, and requests made meanwhile are kept and sent as soon as the line is back.
class CabinLink {
  final CabinStore store;
  final ChannelFactory _factory;
  final Duration pingEvery;
  final Duration pongWithin;
  final List<Duration> backoff;
  CommunicationClient? backend;

  CabinLink(
    this.store, {
    ChannelFactory? factory,
    this.backend,
    this.pingEvery = const Duration(seconds: 20),
    this.pongWithin = const Duration(seconds: 8),
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
  }) : _factory = factory ?? openWebSocket;

  Uri? _uri;
  Map<String, dynamic> Function()? _hello;
  StreamChannel<dynamic>? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _wanted = false;
  bool _gotWelcome = false;
  PairingCredentials? _credentials;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _pongTimer;
  int _lastSequence = 0;

  bool get online => store.link == LinkState.online;

  /// Turns "http://host:8000" into the passenger socket address for [seat].
  static Uri socketUri(String baseUrl, String seat) {
    final u = Uri.parse(baseUrl.replaceAll(RegExp(r'/+$'), ''));
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/passenger',
      queryParameters: {'seat': seat},
    );
  }

  /// Start (or restart) the connection. [hello] gives the profile to introduce this phone to the cabin with.
  void start(
    String baseUrl,
    Map<String, dynamic> Function() hello, {
    PairingCredentials? credentials,
  }) {
    stop();
    _credentials = credentials;
    backend ??= credentials == null ? null : CommunicationClient(baseUrl);
    _uri = backend != null && _credentials != null
        ? backend!.websocketUri(_credentials!)
        : socketUri(baseUrl, store.seat);
    _hello = hello;
    _wanted = true;
    _attempt = 0;
    _connect();
  }

  void stop() {
    _wanted = false;
    _retryTimer?.cancel();
    _closeChannel();
    store.setLink(LinkState.idle);
  }

  void _connect() {
    if (!_wanted || _uri == null) return;
    store.setLink(LinkState.connecting);
    _gotWelcome = false;
    try {
      final ch = _factory(_uri!);
      _channel = ch;
      _sub = ch.stream.listen(
        _onData,
        onError: (_) => _dropped(),
        onDone: _dropped,
        cancelOnError: true,
      );
      if (backend == null) {
        _raw({'t': 'hello', ...?_hello?.call()});
      } else {
        _gotWelcome = true;
        store.setLink(LinkState.online);
        _flushQueue();
        _replayBackendEvents();
        _startPing();
      }
    } catch (_) {
      _dropped();
    }
  }

  void _onData(dynamic data) {
    _pongTimer?.cancel(); // anything from the server proves the line is alive
    Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
    } catch (_) {
      return; // not for us
    }
    if (backend != null) {
      _applyBackendEvent(msg);
      return;
    }
    if (!_gotWelcome && msg['t'] == 'welcome') {
      _gotWelcome = true;
      _attempt = 0;
      store.apply(msg);
      store.setLink(LinkState.online);
      _flushQueue();
      _startPing();
      return;
    }
    store.apply(msg);
  }

  void _flushQueue() {
    if (backend != null) {
      _flushBackendQueue();
      return;
    }
    for (final q in store.takeQueued()) {
      _raw({'t': 'request', 'intent': q.intent, 'via': q.via});
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    if (pingEvery == Duration.zero || backend != null)
      return; // backend owns its WebSocket heartbeat
    _pingTimer = Timer.periodic(pingEvery, (_) {
      _raw({'t': 'ping'});
      _pongTimer?.cancel();
      _pongTimer = Timer(
        pongWithin,
        _dropped,
      ); // no answer: the line is dead even if the socket says it is open
    });
  }

  void _dropped() {
    _closeChannel();
    if (!_wanted) return;
    store.setLink(LinkState.offline);
    final wait = backoff[_attempt.clamp(0, backoff.length - 1)];
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(wait, _connect);
  }

  void _closeChannel() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        ch.sink.close();
      } catch (_) {}
    }
  }

  bool _raw(Map<String, dynamic> msg) {
    final ch = _channel;
    if (ch == null) return false;
    try {
      ch.sink.add(jsonEncode(msg));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _send(Map<String, dynamic> msg) => online && _raw(msg);

  void _applyBackendEvent(Map<String, dynamic> event) {
    final sequence = event['sequence'];
    if (sequence is num && sequence.toInt() > _lastSequence)
      _lastSequence = sequence.toInt();
    final type = event['event_type'] as String? ?? event['type'] as String?;
    final payload = event['payload'];
    if (type == 'request.created' && payload is Map) {
      store.applyBackendRequest(Map<String, dynamic>.from(payload));
    } else if (type == 'request.status_changed') {
      final requestId =
          (event['aggregate_id'] ?? event['request_id']) as String?;
      final status = payload is Map ? payload['status'] as String? : null;
      if (requestId != null && status != null)
        store.applyBackendStatus(requestId, status);
    } else if (type == 'message.created' && payload is Map) {
      store.applyBackendMessage(Map<String, dynamic>.from(payload));
    } else if (type == 'announcement.created' && payload is Map) {
      store.applyBackendAnnouncement(Map<String, dynamic>.from(payload));
    }
  }

  Future<void> _replayBackendEvents() async {
    final client = backend;
    final credentials = _credentials;
    if (client == null || credentials == null) return;
    try {
      final events = await client.replayEvents(
        credentials: credentials,
        afterSequence: _lastSequence,
      );
      for (final event in events) _applyBackendEvent(event);
    } on CommunicationException {
      // The live socket is still useful; a later reconnect will retry replay.
    }
  }

  String _urgencyFor(String intent) =>
      intent == 'help' || intent == 'medical' ? 'urgent' : 'normal';

  Future<void> _sendBackendRequest(String intent, String via) async {
    final client = backend;
    final credentials = _credentials;
    if (client == null || credentials == null) return;
    try {
      final request = await client.createRequest(
        credentials: credentials,
        category: intent,
        message: 'Passenger requested $intent via $via',
        passengerLanguage: _hello?.call()['lang'] as String? ?? 'English',
        urgency: _urgencyFor(intent),
        idempotencyKey:
            'passenger-${DateTime.now().microsecondsSinceEpoch}-$intent',
      );
      store.applyBackendRequest(request);
    } on CommunicationException {
      store.addQueued(QueuedRequest(intent, via));
    }
  }

  Future<void> _flushBackendQueue() async {
    final queued = store.takeQueued();
    for (final q in queued) {
      await _sendBackendRequest(q.intent, q.via);
    }
  }

  String _key(String action, [String? id]) =>
      'passenger-${DateTime.now().microsecondsSinceEpoch}-$action${id == null ? '' : '-$id'}';

  Future<void> _submitBackendAction(
    String action, {
    String? requestId,
    Map<String, dynamic> payload = const {},
  }) async {
    final client = backend;
    final credentials = _credentials;
    if (client == null || credentials == null || !online) return;
    try {
      await client.submitPassengerAction(
        credentials: credentials,
        action: action,
        requestId: requestId,
        payload: payload,
        idempotencyKey: _key(action, requestId),
      );
    } on CommunicationException {
      // Non-critical cabin actions are best-effort for the demo. The local UI
      // still applies the acknowledgement immediately.
    }
  }

  // ---- what the passenger can do ----

  /// A request from a card or the help button. Kept and sent later when the cabin cannot be reached.
  void sendRequest(String intent, {String via = 'tap'}) {
    if (backend != null) {
      if (!online) {
        store.addQueued(QueuedRequest(intent, via));
      } else {
        _sendBackendRequest(intent, via);
      }
      return;
    }
    if (!_send({'t': 'request', 'intent': intent, 'via': via})) {
      store.addQueued(QueuedRequest(intent, via));
    }
  }

  /// Opens one durable request that represents the live translation session.
  /// Every following translated turn is attached to this request so the crew
  /// can keep one conversation selected for the passenger's seat.
  Future<String?> ensureConversationRequest() async {
    final existing = store.activeRequests.where(
      (r) => r.intent == 'conversation',
    );
    if (existing.isNotEmpty) return existing.first.id;
    final client = backend;
    final credentials = _credentials;
    if (client == null || credentials == null || !online) return null;
    try {
      final request = await client.createRequest(
        credentials: credentials,
        category: 'conversation',
        message: 'Live translation conversation started',
        passengerLanguage: _hello?.call()['lang'] as String? ?? 'English',
        idempotencyKey: _key('conversation'),
      );
      store.applyBackendRequest(request);
      return request['id']?.toString();
    } on CommunicationException {
      return null;
    }
  }

  /// Sends a translated passenger turn to the crew device in real time.
  Future<bool> sendLiveTranslation({
    required String text,
    required String translatedText,
    required String sourceLanguage,
  }) async {
    final client = backend;
    final credentials = _credentials;
    if (client == null || credentials == null || !online) return false;
    final requestId = await ensureConversationRequest();
    if (requestId == null) return false;
    try {
      await client.sendPassengerMessage(
        credentials: credentials,
        requestId: requestId,
        text: text,
        translatedText: translatedText,
        sourceLanguage: sourceLanguage,
        idempotencyKey: _key('live-message', requestId),
      );
      return true;
    } on CommunicationException {
      return false;
    }
  }

  void cancelRequest(String id) {
    final client = backend;
    final credentials = _credentials;
    if (client != null && credentials != null) {
      if (!online) return;
      unawaited(
        client.cancelRequest(
          credentials: credentials,
          requestId: id,
          idempotencyKey: _key('cancel', id),
        ),
      );
      return;
    }
    _send({'t': 'cancel', 'req_id': id});
  }

  void understood(String requestId) {
    if (backend != null) {
      unawaited(
        _submitBackendAction('request_understood', requestId: requestId),
      );
      return;
    }
    _send({'t': 'understood', 'req_id': requestId});
  }

  void acknowledge(String announcementId) {
    if (backend != null) {
      unawaited(
        _submitBackendAction(
          'announcement_acknowledged',
          payload: {'announcement_id': announcementId},
        ),
      );
    } else {
      _send({'t': 'ack', 'ann_id': announcementId});
    }
    store.dismissAnnouncement(announcementId);
  }

  void answerExit(String checkId, {required bool willing, String answer = ''}) {
    if (backend != null) {
      unawaited(
        _submitBackendAction(
          'exit_row_answer',
          payload: {'check_id': checkId, 'willing': willing, 'answer': answer},
        ),
      );
      return;
    }
    _send({
      't': 'exit_answer',
      'check_id': checkId,
      'willing': willing,
      'answer': answer,
    });
  }

  void answerCheckin(String answer) {
    if (backend != null) {
      unawaited(
        _submitBackendAction(
          'quiet_seat_checkin_answer',
          payload: {'answer': answer},
        ),
      );
      return;
    }
    _send({'t': 'checkin_answer', 'answer': answer});
  }

  bool say(String text) {
    if (backend != null) {
      if (!online) return false;
      unawaited(
        _submitBackendAction('passenger_message', payload: {'text': text}),
      );
      return true;
    }
    return _send({'t': 'say', 'text': text});
  }

  void confirmSay(String id) {
    if (backend != null) {
      unawaited(
        _submitBackendAction('message_confirmed', payload: {'message_id': id}),
      );
      return;
    }
    _send({'t': 'say_confirm', 'id': id});
  }

  void cancelSay(String id) {
    if (backend != null) {
      unawaited(
        _submitBackendAction('message_cancelled', payload: {'message_id': id}),
      );
      return;
    }
    _send({'t': 'say_cancel', 'id': id});
  }

  /// Tell the cabin the passenger changed language, text size or needs.
  void updateProfile() {
    final h = _hello?.call();
    if (h != null) {
      if (backend != null) {
        unawaited(_submitBackendAction('profile_updated', payload: h));
      } else {
        _send({'t': 'profile', ...h});
      }
    }
  }

  void dispose() {
    stop();
  }
}
