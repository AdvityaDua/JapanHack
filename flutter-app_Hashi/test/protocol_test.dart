import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/protocol.dart';

Map<String, dynamic> req(String id, {String intent = 'water', String status = 'new', int urgency = 1, double created = 1, List<Map<String, dynamic>> replies = const [], double? understood}) =>
    {'id': id, 'intent': intent, 'urgency': urgency, 'status': status, 'created': created, 'replies': replies, 'understood_at': understood};

Map<String, dynamic> welcome([Map<String, dynamic> extra = const {}]) => {'t': 'welcome', 'requests': [], 'announcements': [], 'exit_check': null, 'checkin': null, 'thread': [], ...extra};

void main() {
  late CabinStore s;
  late int notified;
  setUp(() {
    s = CabinStore('24C');
    notified = 0;
    s.addListener(() => notified++);
  });

  group('requests', () {
    test('welcome fills everything and replaces what was there', () {
      s.apply({'t': 'request', 'request': req('old')});
      s.apply(welcome({
        'requests': [req('r1'), req('r2', status: 'replied', replies: [{'reply': 'bringing', 'at': 5.0}])],
        'announcements': [{'id': 'a1', 'phrase': 'seatbelt_on', 'kind': 'safety', 'icon': 'Link2'}],
        'exit_check': {'id': 'x1', 'row': 24, 'open': true, 'seats': {'24C': {'state': 'waiting'}}},
        'checkin': {'seat': '24C', 'answer': null},
        'thread': [{'id': 'm1', 'from': 'crew', 'status': 'sent', 'original': 'こんにちは', 'translated': 'नमस्ते'}],
      }));
      expect(s.requests.keys.toSet(), {'r1', 'r2'});
      expect(s.announcements.single.id, 'a1');
      expect(s.exitCheck!.seatStates['24C'], 'waiting');
      expect(s.checkin!.answer, isNull);
      expect(s.thread.single.fromCrew, true);
    });

    test('a request update replaces the same request, newest first in the active list', () {
      s.apply({'t': 'request', 'request': req('r1', created: 1)});
      s.apply({'t': 'request', 'request': req('r2', created: 2)});
      s.apply({'t': 'request', 'request': req('r1', status: 'seen', created: 1)});
      expect(s.activeRequests.map((r) => r.id), ['r2', 'r1']);
      expect(s.requests['r1']!.status, RequestStatus.seen);
    });

    test('finished and cancelled requests are not active', () {
      s.apply({'t': 'request', 'request': req('a', status: 'done')});
      s.apply({'t': 'request', 'request': req('b', status: 'cancelled')});
      s.apply({'t': 'request', 'request': req('c', status: 'replied')});
      expect(s.activeRequests.map((r) => r.id), ['c']);
    });

    test('a reply needs "I understood" until the passenger answers, and a fresh reply asks again', () {
      s.apply({'t': 'request', 'request': req('r1', status: 'replied', replies: [{'reply': 'wait', 'at': 2.0}])});
      expect(s.requests['r1']!.needsUnderstood, true);
      expect(s.requests['r1']!.lastReply!.replyId, 'wait');
      s.apply({'t': 'request', 'request': req('r1', status: 'replied', replies: [{'reply': 'wait', 'at': 2.0}], understood: 3.0)});
      expect(s.requests['r1']!.needsUnderstood, false);
      s.apply({'t': 'request', 'request': req('r1', status: 'replied', replies: [{'reply': 'wait', 'at': 2.0}, {'reply': 'bringing', 'at': 4.0}])});
      expect(s.requests['r1']!.needsUnderstood, true);
      expect(s.requests['r1']!.lastReply!.replyId, 'bringing');
    });

    test('an urgent active request is found for the help screen', () {
      s.apply({'t': 'request', 'request': req('r1')});
      expect(s.latestForUrgent, isNull);
      s.apply({'t': 'request', 'request': req('r2', intent: 'help', urgency: 3)});
      expect(s.latestForUrgent!.id, 'r2');
    });
  });

  group('announcements, exit row and check-in', () {
    test('an announcement appears once even if the server repeats it, and can be dismissed', () {
      final a = {'t': 'announce', 'announcement': {'id': 'a1', 'phrase': null, 'custom': 'Turbulence', 'texts': {'hi': 'झटके', 'ja': '乱気流'}, 'kind': 'safety', 'icon': 'Megaphone'}};
      s.apply(a);
      s.apply(a);
      expect(s.announcements.length, 1);
      expect(s.announcements.single.texts['hi'], 'झटके');
      s.dismissAnnouncement('a1');
      expect(s.announcements, isEmpty);
    });

    test('exit-row question arrives and clears when answered', () {
      s.apply({'t': 'exit_check', 'check': {'id': 'x1', 'row': 24, 'open': true, 'seats': {'24C': {'state': 'waiting'}}}});
      expect(s.exitCheck!.id, 'x1');
      s.apply({'t': 'exit_done', 'state': 'passed'});
      expect(s.exitCheck, isNull);
    });

    test('check-in arrives and clears when answered', () {
      s.apply({'t': 'checkin', 'checkin': {'seat': '24C', 'answer': null}});
      expect(s.checkin!.seat, '24C');
      s.apply({'t': 'checkin_done', 'checkin': {'seat': '24C', 'answer': 'fine'}});
      expect(s.checkin, isNull);
    });
  });

  group('conversation', () {
    test('a checked message waits for confirmation, then becomes sent', () {
      s.apply({'t': 'say_check', 'msg': {'id': 'm1', 'from': 'passenger', 'status': 'pending', 'original': 'paani', 'ja': 'お水', 'back': 'water', 'warn': true}});
      expect(s.pendingMessage!.id, 'm1');
      expect(s.pendingMessage!.warn, true);
      s.apply({'t': 'say_sent', 'msg': {'id': 'm1', 'from': 'passenger', 'status': 'sent', 'original': 'paani', 'ja': 'お水'}});
      expect(s.pendingMessage, isNull);
      expect(s.thread.length, 1);
    });

    test('crew messages are added in order and the thread keeps the last 60', () {
      for (var i = 0; i < 70; i++) {
        s.apply({'t': 'crew_say', 'msg': {'id': 'm$i', 'from': 'crew', 'status': 'sent', 'original': 'x', 'translated': 'y'}});
      }
      expect(s.thread.length, 60);
      expect(s.thread.first.id, 'm10');
      expect(s.thread.last.id, 'm69');
    });

    test('errors from the server are kept and can be cleared', () {
      s.apply({'t': 'say_error', 'error': 'model_not_ready'});
      expect(s.lastError, 'model_not_ready');
      s.clearError();
      expect(s.lastError, isNull);
    });
  });

  group('landing', () {
    test('everything is wiped, including waiting requests, and the phone is told it landed', () {
      s.apply({'t': 'request', 'request': req('r1')});
      s.apply({'t': 'announce', 'announcement': {'id': 'a1', 'kind': 'info', 'icon': 'x'}});
      s.apply({'t': 'crew_say', 'msg': {'id': 'm1', 'from': 'crew', 'status': 'sent', 'original': 'x'}});
      s.addQueued(const QueuedRequest('water', 'tap'));
      s.apply({'t': 'landed'});
      expect(s.requests, isEmpty);
      expect(s.announcements, isEmpty);
      expect(s.thread, isEmpty);
      expect(s.queued, isEmpty);
      expect(s.landed, true);
    });

    test('a fresh welcome after landing clears the landed flag', () {
      s.apply({'t': 'landed'});
      s.apply(welcome());
      expect(s.landed, false);
    });
  });

  group('listeners and the queue', () {
    test('screens are told about every real change and not about noise', () {
      s.apply({'t': 'pong'});
      s.apply({'t': 'who_knows'});
      expect(notified, 0);
      s.apply({'t': 'request', 'request': req('r1')});
      expect(notified, 1);
      s.setLink(LinkState.online);
      s.setLink(LinkState.online);
      expect(notified, 2);
    });

    test('the queue keeps one of each intent and hands everything over once', () {
      s.addQueued(const QueuedRequest('water', 'tap'));
      s.addQueued(const QueuedRequest('water', 'voice'));
      s.addQueued(const QueuedRequest('blanket', 'tap'));
      expect(s.takeQueued().map((q) => q.intent), ['water', 'blanket']);
      expect(s.takeQueued(), isEmpty);
    });
  });
}
