import 'package:flutter/foundation.dart';

/// What the cabin server sends and what the phone keeps. The wire format is the one the web passenger app already uses
/// (server/hashi/hub.py), so the same server and crew tablet work with this app.

enum RequestStatus { fresh, seen, replied, done, cancelled }

RequestStatus _status(String s) => switch (s) {
  'seen' => RequestStatus.seen,
  'replied' => RequestStatus.replied,
  'done' => RequestStatus.done,
  'cancelled' => RequestStatus.cancelled,
  // Communication backend vocabulary.
  'acknowledged' => RequestStatus.seen,
  'in_progress' => RequestStatus.seen,
  'fulfilled' => RequestStatus.done,
  'expired' => RequestStatus.done,
  'escalated' => RequestStatus.seen,
  _ => RequestStatus.fresh,
};

class CrewReply {
  final String replyId;
  final double at;
  const CrewReply(this.replyId, this.at);
}

class CabinRequest {
  final String id;
  final String intent;
  final int urgency;
  final RequestStatus status;
  final List<CrewReply> replies;
  final double? understoodAt;
  final double created;
  const CabinRequest({
    required this.id,
    required this.intent,
    required this.urgency,
    required this.status,
    required this.replies,
    required this.understoodAt,
    required this.created,
  });

  factory CabinRequest.fromJson(Map<String, dynamic> j) => CabinRequest(
    id: j['id'] as String,
    intent: j['intent'] as String,
    urgency: (j['urgency'] as num?)?.toInt() ?? 1,
    status: _status(j['status'] as String? ?? 'new'),
    replies: [
      for (final r in (j['replies'] as List? ?? const []))
        CrewReply((r as Map)['reply'] as String, ((r['at']) as num).toDouble()),
    ],
    understoodAt: (j['understood_at'] as num?)?.toDouble(),
    created: (j['created'] as num?)?.toDouble() ?? 0,
  );

  factory CabinRequest.fromBackend(Map<String, dynamic> j) => CabinRequest(
    id: j['id'] as String,
    intent: (j['category'] as String?) ?? 'custom',
    urgency: switch (j['urgency']) {
      'urgent' => 3,
      'high' => 2,
      _ => 1,
    },
    status: _status((j['status'] as String?) ?? 'created'),
    replies: const [],
    understoodAt: null,
    created: _epochSeconds(j['created_at']),
  );

  static double _epochSeconds(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed == null ? 0 : parsed.millisecondsSinceEpoch / 1000;
    }
    return 0;
  }

  bool get active =>
      status == RequestStatus.fresh ||
      status == RequestStatus.seen ||
      status == RequestStatus.replied;
  CrewReply? get lastReply => replies.isEmpty ? null : replies.last;

  /// A reply that the passenger has not yet confirmed with "I understood".
  bool get needsUnderstood =>
      status == RequestStatus.replied && understoodAt == null;
}

class Announcement {
  final String id;
  final String? phrase;
  final String? custom;
  final Map<String, String>
  texts; // free announcements: text per language (the server translated it)
  final String kind;
  final String icon;
  const Announcement({
    required this.id,
    required this.phrase,
    required this.custom,
    required this.texts,
    required this.kind,
    required this.icon,
  });

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
    id: j['id'] as String,
    phrase: j['phrase'] as String?,
    custom: j['custom'] as String?,
    texts: {
      for (final e in ((j['texts'] as Map?) ?? const {}).entries)
        e.key as String: e.value as String,
    },
    kind: j['kind'] as String? ?? 'info',
    icon: j['icon'] as String? ?? 'Megaphone',
  );
}

class ExitCheck {
  final String id;
  final int row;
  final bool open;
  final Map<String, String> seatStates;
  const ExitCheck({
    required this.id,
    required this.row,
    required this.open,
    required this.seatStates,
  });

  factory ExitCheck.fromJson(Map<String, dynamic> j) => ExitCheck(
    id: j['id'] as String,
    row: (j['row'] as num).toInt(),
    open: j['open'] as bool? ?? true,
    seatStates: {
      for (final e in ((j['seats'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as Map)['state'] as String,
    },
  );
}

class Checkin {
  final String seat;
  final String? answer;
  const Checkin(this.seat, this.answer);
  factory Checkin.fromJson(Map<String, dynamic> j) =>
      Checkin(j['seat'] as String, j['answer'] as String?);
}

/// One line of the conversation with the crew.
class Message {
  final String id;
  final bool fromCrew;
  final String status; // pending, sent, cancelled
  final String original;
  final String? ja;
  final String? back;
  final String? translated;
  final bool warn;
  final String lane;
  const Message({
    required this.id,
    required this.fromCrew,
    required this.status,
    required this.original,
    this.ja,
    this.back,
    this.translated,
    this.warn = false,
    this.lane = 'machine',
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'] as String,
    fromCrew: j['from'] == 'crew',
    status: j['status'] as String? ?? 'sent',
    original: (j['original'] as String?) ?? '',
    ja: j['ja'] as String?,
    back: j['back'] as String?,
    translated: j['translated'] as String?,
    warn: j['warn'] as bool? ?? false,
    lane: j['lane'] as String? ?? 'machine',
  );
}

enum LinkState { idle, connecting, online, offline }

/// A request the passenger made while the cabin could not be reached. It is sent when the connection comes back.
class QueuedRequest {
  final String intent;
  final String via;
  const QueuedRequest(this.intent, this.via);
}

/// Everything the in-flight screens show. Messages from the server go in through [apply]; screens listen.
class CabinStore extends ChangeNotifier {
  LinkState link = LinkState.idle;
  final Map<String, CabinRequest> requests = {};
  final List<Announcement> announcements = [];
  ExitCheck? exitCheck;
  Checkin? checkin;
  final List<Message> thread = [];
  final List<QueuedRequest> queued = [];
  bool landed = false;
  String? lastError;
  final String seat;

  CabinStore(this.seat);

  List<CabinRequest> get activeRequests =>
      (requests.values.where((r) => r.active).toList()
        ..sort((a, b) => b.created.compareTo(a.created)));
  CabinRequest? get latestForUrgent =>
      activeRequests.where((r) => r.urgency >= 3).firstOrNull;
  Message? get pendingMessage =>
      thread.where((m) => !m.fromCrew && m.status == 'pending').lastOrNull;

  void setLink(LinkState s) {
    if (link == s) return;
    link = s;
    notifyListeners();
  }

  void _putRequest(Map<String, dynamic> j) {
    final r = CabinRequest.fromJson(j);
    requests[r.id] = r;
  }

  void applyBackendRequest(Map<String, dynamic> request) {
    final converted = CabinRequest.fromBackend(request);
    requests[converted.id] = converted;
    notifyListeners();
  }

  void applyBackendStatus(String requestId, String status) {
    final current = requests[requestId];
    if (current == null) return;
    final converted = CabinRequest.fromBackend({
      'id': current.id,
      'category': current.intent,
      'urgency': current.urgency >= 3
          ? 'urgent'
          : current.urgency >= 2
          ? 'high'
          : 'normal',
      'status': status,
      'created_at': DateTime.fromMillisecondsSinceEpoch(
        (current.created * 1000).round(),
      ).toIso8601String(),
    });
    requests[requestId] = converted;
    notifyListeners();
  }

  void applyBackendMessage(Map<String, dynamic> message) {
    _putMessage({
      'id': message['id'],
      'from': 'crew',
      'status': message['status'] ?? 'sent',
      'original': message['original'] ?? '',
      'translated': message['translated'],
      'lane': message['lane'] ?? 'machine',
    });
    notifyListeners();
  }

  void applyBackendAnnouncement(Map<String, dynamic> announcement) {
    final parsed = Announcement.fromJson(
      Map<String, dynamic>.from(announcement),
    );
    if (!announcements.any((item) => item.id == parsed.id))
      announcements.add(parsed);
    notifyListeners();
  }

  void _putMessage(Map<String, dynamic> j) {
    final m = Message.fromJson(j);
    final i = thread.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      thread[i] = m;
    } else {
      thread.add(m);
    }
    if (thread.length > 60) thread.removeRange(0, thread.length - 60);
  }

  /// Applies one message from the server.
  void apply(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'welcome':
        requests.clear();
        for (final r in (msg['requests'] as List? ?? const [])) {
          _putRequest(Map<String, dynamic>.from(r as Map));
        }
        announcements
          ..clear()
          ..addAll([
            for (final a in (msg['announcements'] as List? ?? const []))
              Announcement.fromJson(Map<String, dynamic>.from(a as Map)),
          ]);
        exitCheck = msg['exit_check'] == null
            ? null
            : ExitCheck.fromJson(
                Map<String, dynamic>.from(msg['exit_check'] as Map),
              );
        checkin = msg['checkin'] == null
            ? null
            : Checkin.fromJson(
                Map<String, dynamic>.from(msg['checkin'] as Map),
              );
        thread.clear();
        for (final m in (msg['thread'] as List? ?? const [])) {
          _putMessage(Map<String, dynamic>.from(m as Map));
        }
        landed = false;
      case 'request':
        _putRequest(Map<String, dynamic>.from(msg['request'] as Map));
      case 'announce':
        final a = Announcement.fromJson(
          Map<String, dynamic>.from(msg['announcement'] as Map),
        );
        if (!announcements.any((x) => x.id == a.id)) announcements.add(a);
      case 'exit_check':
        exitCheck = ExitCheck.fromJson(
          Map<String, dynamic>.from(msg['check'] as Map),
        );
      case 'exit_done':
        exitCheck = null;
      case 'checkin':
        checkin = Checkin.fromJson(
          Map<String, dynamic>.from(msg['checkin'] as Map),
        );
      case 'checkin_done':
        checkin = null;
      case 'say_check' || 'say_sent' || 'crew_say':
        _putMessage(Map<String, dynamic>.from(msg['msg'] as Map));
      case 'say_error':
        lastError = msg['error'] as String?;
      case 'error':
        lastError = msg['error'] as String?;
      case 'landed':
        // Everything is wiped at landing, on the aircraft and on the phone
        requests.clear();
        announcements.clear();
        exitCheck = null;
        checkin = null;
        thread.clear();
        queued.clear();
        landed = true;
      default:
        return; // pong and anything unknown change nothing
    }
    notifyListeners();
  }

  /// The passenger tapped "understood" on an announcement.
  void dismissAnnouncement(String id) {
    announcements.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  void addQueued(QueuedRequest q) {
    if (queued.any((x) => x.intent == q.intent))
      return; // the same tap twice is one request
    queued.add(q);
    notifyListeners();
  }

  List<QueuedRequest> takeQueued() {
    final out = List<QueuedRequest>.of(queued);
    queued.clear();
    notifyListeners();
    return out;
  }
}
