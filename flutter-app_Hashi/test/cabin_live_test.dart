// Runs the real CabinLink against a real cabin server, with a crew tablet played by this test. Skipped unless CABIN_URL is set:
//   flutter test test/cabin_live_test.dart --dart-define=CABIN_URL=https://127.0.0.1:8000
// (start the server first: python run.py --https)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/discover.dart';
import 'package:hashi_mobile/protocol.dart';

const url = String.fromEnvironment('CABIN_URL');

Future<void> until(bool Function() ok, {Duration within = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(within);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final skip = url.isEmpty ? 'set CABIN_URL to run' : null;

  test('a passenger request reaches the crew, the crew reply comes back, and "understood" is recorded', () async {
    final seat = '${40 + DateTime.now().second % 15}${'ABCDEF'[DateTime.now().millisecond % 6]}';
    final store = CabinStore(seat);
    final link = CabinLink(store, pingEvery: Duration.zero);
    link.start(url, () => {'lang': 'hi', 'senior': false, 'needs': ['veg']});
    await until(() => store.link == LinkState.online);

    // the crew tablet
    final crewUri = Uri.parse(url).replace(scheme: url.startsWith('https') ? 'wss' : 'ws', path: '/ws/crew');
    final crew = await WebSocket.connect(crewUri.toString(), customClient: localHttpClient());
    final crewSeen = <Map<String, dynamic>>[];
    crew.listen((m) => crewSeen.add(jsonDecode(m as String) as Map<String, dynamic>));

    link.sendRequest('water');
    await until(() => store.activeRequests.isNotEmpty);
    final request = store.activeRequests.single;
    expect(request.intent, 'water');
    expect(request.status, RequestStatus.fresh);
    await until(() => crewSeen.any((m) => m['t'] == 'request' && m['request']['seat'] == seat));

    crew.add(jsonEncode({'t': 'seen', 'req_id': request.id}));
    await until(() => store.requests[request.id]!.status == RequestStatus.seen);
    crew.add(jsonEncode({'t': 'reply', 'req_id': request.id, 'reply_id': 'bringing'}));
    await until(() => store.requests[request.id]!.needsUnderstood);
    expect(store.requests[request.id]!.lastReply!.replyId, 'bringing');

    link.understood(request.id);
    await until(() => store.requests[request.id]!.understoodAt != null);
    await until(() => crewSeen.any((m) => m['t'] == 'request' && m['request']['id'] == request.id && m['request']['understood_at'] != null));

    // the crew see this phone's profile, as sent in hello
    final snapshotSeat = crewSeen.expand((m) => m['t'] == 'passenger' ? [m['passenger']] : (m['passengers'] as List? ?? const [])).firstWhere((p) => p['seat'] == seat);
    expect(snapshotSeat['lang'], 'hi');
    expect(snapshotSeat['needs'], ['veg']);

    // an announcement from the crew reaches the phone
    crew.add(jsonEncode({'t': 'announce', 'phrase_id': 'seatbelt_on', 'target': {'seats': [seat]}}));
    await until(() => store.announcements.isNotEmpty);
    expect(store.announcements.single.phrase, 'seatbelt_on');
    link.acknowledge(store.announcements.single.id);
    expect(store.announcements, isEmpty);

    // the crew start a check-in and the passenger answers it
    crew.add(jsonEncode({'t': 'checkin', 'seat': seat}));
    await until(() => store.checkin != null);
    link.answerCheckin('fine');
    await until(() => store.checkin == null);

    link.dispose();
    await crew.close();
  }, skip: skip);

  test('a seat that never connected still queues a request and sends it when the line opens', () async {
    final seat = '${55 + DateTime.now().second % 4}${'ABCDEF'[DateTime.now().millisecond % 6]}';
    final store = CabinStore(seat);
    final link = CabinLink(store, pingEvery: Duration.zero);
    link.sendRequest('blanket');
    expect(store.queued.single.intent, 'blanket');
    link.start(url, () => {'lang': 'pa'});
    await until(() => store.requests.values.any((r) => r.intent == 'blanket'));
    expect(store.queued, isEmpty);
    link.dispose();
  }, skip: skip);
}
