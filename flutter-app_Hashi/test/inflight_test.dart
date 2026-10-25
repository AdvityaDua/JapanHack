import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/content.dart';
import 'package:hashi_mobile/discover.dart';
import 'package:hashi_mobile/decks.dart';
import 'package:hashi_mobile/inflight.dart';
import 'package:hashi_mobile/kit.dart';
import 'package:hashi_mobile/languages.dart';
import 'package:hashi_mobile/overlays.dart';
import 'package:hashi_mobile/session.dart';
import 'package:hashi_mobile/talk.dart';
import 'package:hashi_mobile/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

const cards = [
  HashiCard(id: 'water', group: 'drink', ja: 'お水をお願いします', en: 'Water, please', icon: Icons.water_drop_rounded, labels: {'ja': 'お水をお願いします', 'en': 'Water, please', 'hi': 'पानी चाहिए'}),
  HashiCard(id: 'help', group: 'urgent', ja: '助けてください', en: 'Help', icon: Icons.emergency_rounded, urgency: 3, labels: {'ja': '助けてください', 'en': 'Help', 'hi': 'मदद चाहिए'}),
];

Map<String, dynamic> req(String id, {String intent = 'water', String status = 'new', int urgency = 1, double created = 1, List<Map<String, dynamic>> replies = const [], double? understood}) =>
    {'id': id, 'intent': intent, 'urgency': urgency, 'status': status, 'created': created, 'replies': replies, 'understood_at': understood};

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t) async {
  tall(t);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

final sound = SoundLog();

void main() {
  setUpAll(loadContentForTests);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sound.install();
  });
  tearDown(() {
    sound.restore();
    sound.clips.clear();
    sound.spoken.clear();
  });

  group('in-flight screen', () {
    Future<(CabinSession, FakeCabin)> open(WidgetTester t, {bool online = true}) async {
      tall(t);
      final (session, cabin) = online ? await onlineSession(t) : (CabinSession.forProfile(Profile(lang: 'hi', seat: '24C')), FakeCabin());
      if (!online) addTearDown(session.dispose);
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: InFlightScreen(session: session, cards: cards, autoJoin: false)));
      await settle(t);
      return (session, cabin);
    }

    testWidgets('says how the line to the crew is', (t) async {
      final (session, cabin) = await open(t);
      expect(find.text('Connected to the crew'), findsOneWidget);
      await cabin.drop();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.textContaining('requests are kept'), findsOneWidget);
      session.dispose();
    });

    testWidgets('not connected yet: says so, and that speaking still works with no connection', (t) async {
      await open(t, online: false);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.textContaining('still work with no connection'), findsWidgets);
    });

    testWidgets('the help button asks once, in the passenger\'s language, and sends an urgent request only on yes', (t) async {
      final (_, cabin) = await open(t);
      await t.tap(find.text('मदद चाहिए'));
      await settle(t);
      expect(find.text('क्रू को अभी बुलाएँ?'), findsOneWidget); // the question is in the passenger's language
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('नहीं'));
      await settle(t);
      expect(cabin.lastInbox.where((m) => m['t'] == 'request'), isEmpty);

      await t.tap(find.text('मदद चाहिए'));
      await settle(t);
      await t.tap(find.text('हाँ'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'request', 'intent': 'help', 'via': 'sos'});
    });

    testWidgets('the help button is big', (t) async {
      await open(t);
      final size = t.getSize(find.ancestor(of: find.text('मदद चाहिए'), matching: find.byType(FilledButton)).first);
      expect(size.height, greaterThanOrEqualTo(80));
    });

    testWidgets('a request shows its label in the passenger\'s language and three steps that fill in as the crew act', (t) async {
      final (session, cabin) = await open(t);
      cabin.push({'t': 'request', 'request': req('r1')});
      await settle(t);
      expect(find.text('पानी चाहिए'), findsWidgets);
      Finder done() => find.byIcon(Icons.check_circle_rounded);
      final before = done().evaluate().length;
      cabin.push({'t': 'request', 'request': req('r1', status: 'seen')});
      await settle(t);
      expect(done().evaluate().length, before + 1);
      session.dispose();
    });

    testWidgets('the crew\'s reply appears as picture, words and sound, with an "I understood" button that tells the crew', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'request', 'request': req('r1', status: 'replied', replies: [{'reply': 'bringing', 'at': 5.0}])});
      await settle(t);
      expect(find.text('हम अभी लेकर आते हैं।'), findsOneWidget);
      await t.tap(find.text('फिर से सुनिए'));
      await settle(t);
      expect(sound.clips, ['reply_bringing_hi.mp3']);
      await t.tap(find.text('समझ आ गया'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'understood', 'req_id': 'r1'});
    });

    testWidgets('after "understood" the button gives way to a thank-you', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'request', 'request': req('r1', status: 'replied', replies: [{'reply': 'wait', 'at': 5.0}], understood: 6.0)});
      await settle(t);
      expect(find.text('समझ आ गया'), findsNothing);
      expect(find.text('धन्यवाद, क्रू को पता चल गया'), findsOneWidget);
    });

    testWidgets('a request can be cancelled until the crew reply', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'request', 'request': req('r1')});
      await settle(t);
      await t.tap(find.text('माँग रद्द करें'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'cancel', 'req_id': 'r1'});
      cabin.push({'t': 'request', 'request': req('r2', status: 'replied', replies: [{'reply': 'wait', 'at': 1.0}])});
      await settle(t);
      expect(find.text('माँग रद्द करें'), findsOneWidget); // only the first request can still be cancelled
    });

    testWidgets('requests waiting for the line are listed as waiting', (t) async {
      final (session, _) = await open(t, online: false);
      session.link.sendRequest('water');
      await settle(t);
      expect(find.text('Waiting to be sent'), findsOneWidget);
      expect(find.text('Waiting for the line'), findsOneWidget);
    });

    testWidgets('with nothing going on it explains what to do', (t) async {
      await open(t);
      expect(find.textContaining('No requests yet'), findsOneWidget);
    });

    testWidgets("has Speak and translate first, then picture tiles in the passenger's language, and a way to type to the crew", (t) async {
      await open(t);
      expect(find.text('Speak & translate'), findsOneWidget);
      expect(find.text('पानी चाहिए'), findsOneWidget); // the water tile
      await t.tap(find.text('Type to the crew'));
      await settle(t);
      expect(find.byType(TalkScreen), findsOneWidget);
    });

    testWidgets('a picture tile opens its card, ready to send', (t) async {
      final (_, cabin) = await open(t);
      await t.tap(find.text('पानी चाहिए'));
      await settle(t);
      await t.tap(find.text('Send to crew · 乗務員に送る'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'request', 'intent': 'water', 'via': 'tap'});
    });

    testWidgets('the Speak button opens speak and translate', (t) async {
      await open(t);
      await t.tap(find.text('Speak & translate'));
      await settle(t);
      expect(find.text('I speak'), findsOneWidget);
      expect(find.text('They speak'), findsOneWidget);
    });

    group('finding the cabin by itself', () {
      Future<(CabinSession, FakeCabin)> openAuto(WidgetTester t, Future<CabinConnection> Function(List<String>) connector) async {
        tall(t);
        final cabin = FakeCabin();
        final session = CabinSession.forProfile(Profile(lang: 'hi', seat: '24C'), makeLink: (store) => CabinLink(store, factory: cabin.open, pingEvery: Duration.zero));
        addTearDown(session.dispose);
        await t.pumpWidget(MaterialApp(theme: buildTheme(), home: InFlightScreen(session: session, cards: cards, connector: connector)));
        await settle(t);
        return (session, cabin);
      }

      testWidgets('when the cabin is found it opens the live line without anyone typing an address', (t) async {
        final asked = <List<String>>[];
        final (session, cabin) = await openAuto(t, (hosts) async {
          asked.add(hosts);
          return const CabinConnection(CabinState.ready, baseUrl: 'http://192.168.137.1:8000', seat: '24C', flight: 'JL740');
        });
        expect(asked.first, contains('http://hashi-cabin.local:8000'));
        expect(cabin.uris.single.toString(), 'ws://192.168.137.1:8000/ws/passenger?seat=24C');
        cabin.welcome();
        await settle(t);
        expect(find.text('Connected to the crew'), findsOneWidget);
        expect(session.profile.server, 'http://192.168.137.1:8000');
      });

      testWidgets('when it is not found it says so, and tries again every few seconds', (t) async {
        var calls = 0;
        final (_, cabin) = await openAuto(t, (hosts) async {
          calls++;
          return calls < 3 ? const CabinConnection(CabinState.notFound) : const CabinConnection(CabinState.ready, baseUrl: 'http://192.168.137.1:8000', seat: '24C');
        });
        expect(find.text('Cabin not found yet'), findsOneWidget);
        expect(cabin.connections, isEmpty);
        await t.pump(const Duration(seconds: 6));
        await t.pump(const Duration(seconds: 6));
        await t.pump();
        expect(calls, 3);
        expect(cabin.connections.length, 1);
      });

      testWidgets('once the line is up it stops looking', (t) async {
        var calls = 0;
        final (_, cabin) = await openAuto(t, (hosts) async {
          calls++;
          return const CabinConnection(CabinState.ready, baseUrl: 'http://192.168.137.1:8000', seat: '24C');
        });
        cabin.welcome();
        await settle(t);
        final before = calls;
        await t.pump(const Duration(seconds: 20));
        expect(calls, before);
      });
    });
  });

  group('announcements and checks appear over any screen', () {
    Future<(CabinSession, FakeCabin)> app(WidgetTester t) async {
      tall(t);
      final (session, cabin) = await onlineSession(t);
      final key = GlobalKey<NavigatorState>();
      final overlays = OverlayCoordinator(key)..attach(session);
      addTearDown(overlays.detach);
      await t.pumpWidget(MaterialApp(navigatorKey: key, theme: buildTheme(), home: const Scaffold(body: Text('somewhere else in the app'))));
      await settle(t);
      return (session, cabin);
    }

    Map<String, dynamic> announce(String id, {String? phrase = 'seatbelt_on', String? custom, Map<String, String>? texts}) => {
          't': 'announce',
          'announcement': {'id': id, 'phrase': phrase, 'custom': custom, 'texts': texts, 'kind': 'safety', 'icon': 'Link2'}
        };

    testWidgets('a crew announcement fills the screen in the passenger\'s language, plays its recording, and is acknowledged', (t) async {
      final (_, cabin) = await app(t);
      cabin.push(announce('a1'));
      await settle(t);
      expect(find.text('सीट बेल्ट का संकेत जल गया है। कृपया बैठ जाइए और सीट बेल्ट बाँध लीजिए।'), findsOneWidget);
      expect(find.text('क्रू का संदेश'), findsOneWidget);
      expect(sound.clips, ['ann_seatbelt_on_hi.mp3']);
      await t.tap(find.text('समझ आ गया'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'ack', 'ann_id': 'a1'});
      expect(find.text('somewhere else in the app'), findsOneWidget);
    });

    testWidgets('it cannot be swiped away by accident', (t) async {
      final (_, cabin) = await app(t);
      cabin.push(announce('a1'));
      await settle(t);
      await t.binding.handlePopRoute(); // the phone's back gesture
      await settle(t);
      expect(find.byType(AnnouncementScreen), findsOneWidget);
    });

    testWidgets('a free announcement uses the server\'s translation, and is spoken with the phone\'s voice', (t) async {
      final (_, cabin) = await app(t);
      cabin.push(announce('a2', phrase: null, custom: 'Please stay seated', texts: {'hi': 'कृपया बैठे रहें', 'ja': 'お座りください'}));
      await settle(t);
      expect(find.text('कृपया बैठे रहें'), findsOneWidget);
      expect(find.text('Machine translation'), findsOneWidget);
      expect(sound.spoken.single, 'hi-IN:कृपया बैठे रहें');
    });

    testWidgets('with no translation for the language it falls back to the crew\'s own words', (t) async {
      final (_, cabin) = await app(t);
      cabin.push(announce('a3', phrase: null, custom: 'Please stay seated', texts: {'ja': 'お座りください'}));
      await settle(t);
      expect(find.text('Please stay seated'), findsOneWidget);
    });

    testWidgets('two announcements come one after the other', (t) async {
      final (_, cabin) = await app(t);
      cabin.push(announce('a1'));
      cabin.push(announce('a2', phrase: 'turbulence'));
      await settle(t);
      await t.tap(find.text('समझ आ गया'));
      await settle(t);
      expect(find.byType(AnnouncementScreen), findsOneWidget);
      expect(sound.clips, ['ann_seatbelt_on_hi.mp3', 'ann_turbulence_hi.mp3']);
      await t.tap(find.text('समझ आ गया'));
      await settle(t);
      expect(find.byType(AnnouncementScreen), findsNothing);
    });

    testWidgets('exit row: willing and able, then "only when the crew tell me" is a passing answer', (t) async {
      final (_, cabin) = await app(t);
      cabin.push({'t': 'exit_check', 'check': {'id': 'x1', 'row': 24, 'open': true, 'seats': {'24C': {'state': 'waiting'}}}});
      await settle(t);
      expect(find.byType(ExitCheckScreen), findsOneWidget);
      await t.tap(find.text('हाँ'));
      await settle(t);
      await t.tap(find.text('सिर्फ़ जब क्रू कहे'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'exit_answer', 'check_id': 'x1', 'willing': true, 'answer': 'when_told'});
      expect(find.text('OK'), findsOneWidget);
      await t.tap(find.text('OK'));
      await settle(t);
      expect(find.byType(ExitCheckScreen), findsNothing);
    });

    testWidgets('exit row: "not willing" is sent straight away', (t) async {
      final (_, cabin) = await app(t);
      cabin.push({'t': 'exit_check', 'check': {'id': 'x2', 'row': 24, 'open': true, 'seats': {'24C': {'state': 'waiting'}}}});
      await settle(t);
      await t.tap(find.text('नहीं'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'exit_answer', 'check_id': 'x2', 'willing': false, 'answer': ''});
    });

    testWidgets('exit row: a check for another seat, or one already answered, is not shown', (t) async {
      final (_, cabin) = await app(t);
      cabin.push({'t': 'exit_check', 'check': {'id': 'x3', 'row': 25, 'open': true, 'seats': {'25A': {'state': 'waiting'}}}});
      cabin.push({'t': 'exit_check', 'check': {'id': 'x4', 'row': 24, 'open': true, 'seats': {'24C': {'state': 'passed'}}}});
      await settle(t);
      expect(find.byType(ExitCheckScreen), findsNothing);
    });

    testWidgets('the crew\'s check-in has two big answers', (t) async {
      final (_, cabin) = await app(t);
      cabin.push({'t': 'checkin', 'checkin': {'seat': '24C', 'answer': null}});
      await settle(t);
      expect(find.text('सब ठीक है?'), findsOneWidget);
      expect(t.getSize(find.ancestor(of: find.text('मैं ठीक हूँ'), matching: find.byType(FilledButton)).first).height, greaterThanOrEqualTo(64));
      await t.tap(find.text('कृपया मेरे पास आइए'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'checkin_answer', 'answer': 'call'});
      expect(find.byType(CheckinScreen), findsNothing);
    });
  });

  group('conversation', () {
    Future<(CabinSession, FakeCabin)> open(WidgetTester t) async {
      tall(t);
      final (session, cabin) = await onlineSession(t);
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: TalkScreen(session: session)));
      await settle(t);
      return (session, cabin);
    }

    testWidgets('typing sends the text to be checked, and the field empties', (t) async {
      final (_, cabin) = await open(t);
      await t.enterText(find.byType(TextField), 'mujhe paani chahiye');
      await t.tap(find.byTooltip('Check my message'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'say', 'text': 'mujhe paani chahiye'});
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('an empty message sends nothing', (t) async {
      final (_, cabin) = await open(t);
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.byTooltip('Check my message'));
      await settle(t);
      expect(cabin.lastInbox.where((m) => m['t'] == 'say'), isEmpty);
    });

    testWidgets('the check step shows the Japanese and the translation back, and sends only after a yes', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'say_check', 'msg': {'id': 'm1', 'from': 'passenger', 'status': 'pending', 'original': 'paani chahiye', 'ja': 'お水が欲しいです', 'back': 'I want water', 'warn': false}});
      await settle(t);
      expect(find.text('お水が欲しいです'), findsOneWidget);
      expect(find.text('I want water'), findsOneWidget);
      expect(find.textContaining('may not say what you meant'), findsNothing);
      await t.tap(find.text('हाँ'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'say_confirm', 'id': 'm1'});
    });

    testWidgets('a poor round trip is flagged, and the passenger can cancel', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'say_check', 'msg': {'id': 'm2', 'from': 'passenger', 'status': 'pending', 'original': 'x', 'ja': 'y', 'back': 'z', 'warn': true}});
      await settle(t);
      expect(find.textContaining('may not say what you meant'), findsOneWidget);
      await t.tap(find.text('माँग रद्द करें'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'say_cancel', 'id': 'm2'});
    });

    testWidgets('crew messages show in the passenger\'s language, labelled by how they were made, and can be read aloud', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'crew_say', 'msg': {'id': 'c1', 'from': 'crew', 'status': 'sent', 'original': 'ただいまお持ちします', 'translated': 'हम अभी लाते हैं', 'lane': 'vetted'}});
      cabin.push({'t': 'crew_say', 'msg': {'id': 'c2', 'from': 'crew', 'status': 'sent', 'original': '少々お待ちください', 'translated': 'थोड़ा रुकिए', 'lane': 'machine'}});
      await settle(t);
      expect(find.text('हम अभी लाते हैं'), findsOneWidget);
      expect(find.text('Approved wording'), findsOneWidget);
      expect(find.textContaining('Machine translation'), findsOneWidget);
      await t.tap(find.text('फिर से सुनिए').first);
      await settle(t);
      expect(sound.spoken.single, startsWith('hi-IN:'));
    });

    testWidgets('while the translator is starting the passenger is told to use the cards', (t) async {
      final (_, cabin) = await open(t);
      cabin.push({'t': 'say_error', 'error': 'model_not_ready'});
      await settle(t);
      expect(find.text('The translator is still starting'), findsOneWidget);
    });

    testWidgets('when the line is down the message is not lost silently', (t) async {
      tall(t);
      final session = CabinSession.forProfile(Profile(lang: 'hi', seat: '24C'));
      addTearDown(session.dispose);
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: TalkScreen(session: session)));
      await settle(t);
      await t.enterText(find.byType(TextField), 'hello');
      await t.tap(find.byTooltip('Check my message'));
      await settle(t);
      expect(find.text('Not sent'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'hello');
    });
  });

  group('bundled wording and recordings', () {
    final langs = languages.map((l) => l.code).toList();

    test('every crew reply has words and a recording in every passenger language', () {
      final replies = Content.instance.replies;
      expect(replies.length, 17);
      for (final r in replies.values) {
        for (final l in langs) {
          expect((r.text[l] ?? '').trim().isNotEmpty, true, reason: '${r.id} has no $l text');
          expect(File('assets/audio/reply_${r.id}_$l.mp3').existsSync(), true, reason: 'missing recording reply_${r.id}_$l.mp3');
        }
        expect(r.text['ja'], isNotEmpty);
      }
    });

    test('every announcement has words and a recording in every language', () {
      final anns = Content.instance.announcements;
      expect(anns.length, 8);
      for (final a in anns.values) {
        for (final l in langs) {
          expect((a.text[l] ?? '').trim().isNotEmpty, true, reason: '${a.id} has no $l text');
          expect(File('assets/audio/ann_${a.id}_$l.mp3').existsSync(), true, reason: 'missing recording ann_${a.id}_$l.mp3');
        }
      }
    });

    test('the words the in-flight screens use exist in every language (or fall back to English)', () {
      const needed = ['sent', 'seen', 'replied', 'understood', 'understoodDone', 'cancel', 'play', 'helpBig', 'helpSure', 'yes', 'no', 'announcement', 'askWhat', 'exitTitle', 'exitIntro', 'exitQ1', 'exitQ2', 'exitA1', 'exitA2', 'exitA3', 'exitThanks'];
      for (final l in langs) {
        for (final k in needed) {
          expect(Content.instance.t(l, k).trim().isNotEmpty && Content.instance.t(l, k) != k, true, reason: '$l/$k');
        }
        expect(Content.instance.checkinWords(l).length, 3, reason: l);
      }
    });

    test('an unknown language falls back to English instead of showing nothing', () {
      expect(Content.instance.t('xx', 'sent'), Content.instance.t('en', 'sent'));
      expect(Content.instance.t('en', 'no_such_word'), 'no_such_word');
    });

    test('the yes and no replies kept their names (the YAML trap)', () {
      expect(Content.instance.replies.keys, containsAll(['yes', 'no']));
      expect(File('assets/audio/reply_yes_hi.mp3').existsSync(), true);
    });
  });
}
