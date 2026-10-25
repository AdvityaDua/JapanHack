
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/protocol.dart';

import 'helpers.dart';

Future<void> pump(WidgetTester t, [Duration d = Duration.zero]) async {
  await t.pump(d);
  await t.pump();
}

({CabinStore store, CabinLink link, FakeCabin cabin}) setup({Duration pingEvery = const Duration(seconds: 20), Duration pongWithin = const Duration(seconds: 8)}) {
  final cabin = FakeCabin();
  final store = CabinStore('24C');
  final link = CabinLink(store, factory: cabin.open, pingEvery: pingEvery, pongWithin: pongWithin);
  return (store: store, link: link, cabin: cabin);
}

Map<String, dynamic> hello() => {'lang': 'hi', 'senior': true, 'needs': ['veg']};

void main() {
  group('connecting', () {
    testWidgets('opens the right address and introduces the phone, but is not online until the cabin welcomes it', (t) async {
      final s = setup();
      s.link.start('http://192.168.137.1:8000/', hello);
      await pump(t);
      expect(s.cabin.uris.single.toString(), 'ws://192.168.137.1:8000/ws/passenger?seat=24C');
      expect(s.cabin.lastInbox.single, {'t': 'hello', 'lang': 'hi', 'senior': true, 'needs': ['veg']});
      expect(s.store.link, LinkState.connecting);
      s.cabin.welcome();
      await pump(t);
      expect(s.store.link, LinkState.online);
      s.link.dispose();
    });

    test('https becomes wss', () {
      expect(CabinLink.socketUri('https://hashi-cabin.local:8000', '31K').toString(), 'wss://hashi-cabin.local:8000/ws/passenger?seat=31K');
    });

    testWidgets('a cabin that refuses the connection leaves the app offline and keeps trying', (t) async {
      final s = setup();
      s.cabin.refuse = true;
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      expect(s.store.link, LinkState.offline);
      s.cabin.refuse = false;
      await pump(t, const Duration(seconds: 1));
      expect(s.cabin.connections.length, 1);
      s.link.dispose();
    });
  });

  group('reconnecting', () {
    testWidgets('after a drop it waits 1, 2, 4, 8 seconds and never longer', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      final waits = <int>[];
      for (final expected in [1, 2, 4, 8, 8]) {
        final before = s.cabin.connections.length;
        await s.cabin.drop();
        await pump(t);
        expect(s.store.link, LinkState.offline);
        await pump(t, Duration(seconds: expected) - const Duration(milliseconds: 100));
        expect(s.cabin.connections.length, before, reason: 'too early for a ${expected}s wait');
        await pump(t, const Duration(milliseconds: 200));
        expect(s.cabin.connections.length, before + 1, reason: 'should retry after ${expected}s');
        waits.add(expected);
      }
      expect(waits, [1, 2, 4, 8, 8]);
      s.link.dispose();
    });

    testWidgets('once welcomed again the waits start over from one second', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      for (var i = 0; i < 3; i++) {
        await s.cabin.drop();
        await pump(t, const Duration(seconds: 10));
      }
      s.cabin.welcome();
      await pump(t);
      expect(s.store.link, LinkState.online);
      final before = s.cabin.connections.length;
      await s.cabin.drop();
      await pump(t, const Duration(milliseconds: 1100));
      expect(s.cabin.connections.length, before + 1);
      s.link.dispose();
    });

    testWidgets('the phone introduces itself again and gets the full state back after a reconnect', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome({'requests': [request('r1', 'water')]});
      await pump(t);
      await s.cabin.drop();
      await pump(t, const Duration(seconds: 2));
      expect(s.cabin.lastInbox.first['t'], 'hello');
      s.cabin.welcome({'requests': [request('r1', 'water', status: 'seen'), request('r2', 'blanket')]});
      await pump(t);
      expect(s.store.requests.length, 2);
      expect(s.store.requests['r1']!.status, RequestStatus.seen);
      s.link.dispose();
    });

    testWidgets('stop() ends the connection for good', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      s.link.stop();
      await pump(t, const Duration(seconds: 30));
      expect(s.cabin.connections.length, 1);
      expect(s.store.link, LinkState.idle);
    });
  });

  group('heartbeat', () {
    testWidgets('a silent line is treated as dead and reconnected', (t) async {
      final s = setup(pingEvery: const Duration(seconds: 5), pongWithin: const Duration(seconds: 2));
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      await pump(t, const Duration(seconds: 5));
      expect(s.cabin.lastInbox.last, {'t': 'ping'});
      await pump(t, const Duration(seconds: 2, milliseconds: 100));
      expect(s.store.link, LinkState.offline);
      await pump(t, const Duration(seconds: 1, milliseconds: 100));
      expect(s.cabin.connections.length, 2);
      s.link.dispose();
    });

    testWidgets('an answer keeps the line open', (t) async {
      final s = setup(pingEvery: const Duration(seconds: 5), pongWithin: const Duration(seconds: 2));
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      s.cabin.autoPong = true;
      for (var i = 0; i < 6; i++) {
        await pump(t, const Duration(seconds: 5));
      }
      expect(s.store.link, LinkState.online);
      expect(s.cabin.connections.length, 1);
      s.link.dispose();
    });
  });

  group('requests', () {
    testWidgets('a request goes out and the server\'s answer shows up', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      s.link.sendRequest('water', via: 'tap');
      await pump(t);
      expect(s.cabin.lastInbox.last, {'t': 'request', 'intent': 'water', 'via': 'tap'});
      s.cabin.push({'t': 'request', 'request': request('r1', 'water')});
      await pump(t);
      expect(s.store.activeRequests.single.intent, 'water');
      expect(s.store.queued, isEmpty);
      s.link.dispose();
    });

    testWidgets('a request made offline waits and is sent once, when the line is back', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      await s.cabin.drop();
      await pump(t);
      s.link.sendRequest('water');
      s.link.sendRequest('water'); // the same tap twice is still one request
      s.link.sendRequest('blanket');
      expect(s.store.queued.map((q) => q.intent), ['water', 'blanket']);
      await pump(t, const Duration(seconds: 2));
      s.cabin.welcome();
      await pump(t);
      final sent = s.cabin.lastInbox.where((m) => m['t'] == 'request').map((m) => m['intent']).toList();
      expect(sent, ['water', 'blanket']);
      expect(s.store.queued, isEmpty);
      s.link.dispose();
    });

    testWidgets('a request before the first connection is kept too', (t) async {
      final s = setup();
      s.link.sendRequest('help', via: 'sos');
      expect(s.store.queued.single.intent, 'help');
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      expect(s.cabin.lastInbox.any((m) => m['t'] == 'request' && m['intent'] == 'help' && m['via'] == 'sos'), true);
      s.link.dispose();
    });
  });

  group('what the passenger can send', () {
    Future<({CabinStore store, CabinLink link, FakeCabin cabin})> online(WidgetTester t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      return s;
    }

    testWidgets('each action sends the message the server expects', (t) async {
      final s = await online(t);
      s.link.understood('r1');
      s.link.cancelRequest('r2');
      s.link.acknowledge('a1');
      s.link.answerExit('x1', willing: true, answer: 'when_told');
      s.link.answerCheckin('fine');
      s.link.say('mujhe paani chahiye');
      s.link.confirmSay('m1');
      s.link.cancelSay('m2');
      s.link.updateProfile();
      await pump(t);
      final sent = s.cabin.lastInbox.skip(1).toList();
      expect(sent, [
        {'t': 'understood', 'req_id': 'r1'},
        {'t': 'cancel', 'req_id': 'r2'},
        {'t': 'ack', 'ann_id': 'a1'},
        {'t': 'exit_answer', 'check_id': 'x1', 'willing': true, 'answer': 'when_told'},
        {'t': 'checkin_answer', 'answer': 'fine'},
        {'t': 'say', 'text': 'mujhe paani chahiye'},
        {'t': 'say_confirm', 'id': 'm1'},
        {'t': 'say_cancel', 'id': 'm2'},
        {'t': 'profile', 'lang': 'hi', 'senior': true, 'needs': ['veg']},
      ]);
      s.link.dispose();
    });

    testWidgets('acting while offline does nothing and does not crash', (t) async {
      final s = setup();
      s.link.understood('r1');
      s.link.cancelRequest('r1');
      s.link.answerCheckin('fine');
      expect(s.link.say('hello'), false);
      s.link.updateProfile();
      s.link.dispose();
    });

    testWidgets('acknowledging an announcement removes it at once, even before the server answers', (t) async {
      final s = await online(t);
      s.cabin.push({'t': 'announce', 'announcement': {'id': 'a1', 'phrase': 'seatbelt_on', 'kind': 'safety', 'icon': 'Link2'}});
      await pump(t);
      expect(s.store.announcements.length, 1);
      s.link.acknowledge('a1');
      expect(s.store.announcements, isEmpty);
      s.link.dispose();
    });
  });

  group('messages from the cabin', () {
    testWidgets('junk and unknown messages are ignored', (t) async {
      final s = setup();
      s.link.start('http://cabin:8000', hello);
      await pump(t);
      s.cabin.welcome();
      await pump(t);
      s.cabin.last.foreign.sink.add('not json at all');
      s.cabin.last.foreign.sink.add('[1,2,3]');
      s.cabin.push({'t': 'something_new', 'x': 1});
      s.cabin.push({'t': 'pong'});
      await pump(t);
      expect(s.store.link, LinkState.online);
      expect(s.store.requests, isEmpty);
      s.link.dispose();
    });
  });
}

