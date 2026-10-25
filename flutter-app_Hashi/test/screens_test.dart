import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/cards.dart';
import 'package:hashi_mobile/central.dart';
import 'package:hashi_mobile/decks.dart';
import 'package:hashi_mobile/kit.dart';
import 'package:hashi_mobile/main.dart';
import 'package:hashi_mobile/repo.dart';
import 'package:hashi_mobile/session.dart';
import 'package:hashi_mobile/settings.dart';
import 'package:hashi_mobile/theme.dart';
import 'package:hashi_mobile/tiles.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<PassengerRepo> repo({bool signedIn = false, bool online = false}) async {
  SharedPreferences.setMockInitialValues({});
  final client = CentralClient('http://central.test', client: MockClient((http.Request r) async {
    if (!online) throw http.ClientException('offline');
    return http.Response(jsonEncode({'id': 'x', 'user_id': 'u', 'spoken_language': 'hi', 'display_language': 'hi', 'translation_mode': 'conversation', 'voice_input_enabled': true, 'text_to_speech_enabled': true, 'font_scale': 100, 'high_contrast_enabled': false, 'senior_mode_enabled': false, 'hearing_assistance_enabled': false, 'needs': [], 'extra_languages': [], 'version': 2}), 200);
  }));
  final r = await PassengerRepo.open('http://central.test', client: client);
  if (signedIn) {
    client.token = 'tok';
    await r.store.setString('central_prefs', jsonEncode({'spoken_language': 'hi', 'display_language': 'hi', 'senior_mode_enabled': false, 'needs': [], 'extra_languages': [], 'version': 1}));
  }
  return r;
}

const sample = [
  HashiCard(id: 'water', group: 'drink', ja: 'お水をお願いします', en: 'Water, please', icon: Icons.water_drop_rounded, labels: {'ja': 'お水をお願いします', 'en': 'Water, please', 'hi': 'पानी चाहिए'}),
  HashiCard(id: 'blanket', group: 'comfort', ja: '毛布をお願いします', en: 'A blanket, please', icon: Icons.bed_rounded, labels: {'ja': '毛布をお願いします', 'en': 'A blanket, please', 'hi': 'कंबल चाहिए'}),
  HashiCard(id: 'chest_pain', group: 'urgent', ja: '胸が痛いです', en: 'I have chest pain', icon: Icons.monitor_heart_rounded, urgency: 3, labels: {'ja': '胸が痛いです', 'en': 'I have chest pain', 'hi': 'सीने में दर्द है'}),
];

/// A tall test screen, so lists that only build what is on screen show all their rows.
void tallScreen(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t) async {
  tallScreen(t);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() {
    seniorMode.value = false;
    calmMotion.value = false;
  });

  group('home', () {
    testWidgets('shows just three categories: before, in and after the flight, and a settings button', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi', 'seat': '24C'});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      for (final text in ['出発前', '機内', '到着後', 'Before flight', 'In flight', 'After flight']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final gone in ['At the airport', 'On the aircraft', 'Show to staff', 'Read a sign']) {
        expect(find.text(gone), findsNothing, reason: '$gone is inside a category now');
      }
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(find.textContaining('Seat 24C'), findsOneWidget);
    });

    testWidgets('the settings button is a proper touch target and opens settings', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi'});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      final size = t.getSize(find.byTooltip('Settings'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      await t.tap(find.byTooltip('Settings'));
      await settle(t);
      expect(find.text('My settings'), findsOneWidget);
    });

    testWidgets('each category has Speak and translate first, then its own tiles', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi', 'seat': '24C'});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      await t.tap(find.text('Before flight'));
      await settle(t);
      expect(find.text('Speak & translate'), findsOneWidget);
      expect(find.textContaining('Help at the airport'), findsWidgets);
      await t.pageBack();
      await settle(t);
      await t.tap(find.text('After flight'));
      await settle(t);
      expect(find.text('Speak & translate'), findsOneWidget);
      expect(find.textContaining('Read a sign'), findsWidgets);
      expect(find.textContaining('Arriving'), findsWidgets);
    });

    testWidgets('a group tile opens the cards of that group', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'en', 'seat': '24C'});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      await t.tap(find.text('Before flight'));
      await settle(t);
      await t.tap(find.textContaining('My meal').first);
      await settle(t);
      expect(find.text('I would like a vegetarian meal.'), findsOneWidget);
      expect(find.text('I need a wheelchair at the airport.'), findsNothing);
    });

    testWidgets('In flight without a booking asks to open the booking first', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi'});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      await t.tap(find.text('In flight'));
      await settle(t);
      expect(find.text('Your seat comes from your booking'), findsOneWidget);
    });

    testWidgets('calm mode shows no drifting petals', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi', 'calm': true});
      await t.pumpWidget(const HashiApp());
      await settle(t);
      expect(find.byType(SakuraDrift), findsNothing);
    });

    testWidgets('senior mode makes text a quarter bigger everywhere', (t) async {
      SharedPreferences.setMockInitialValues({'lang': 'hi', 'senior': true});
      late double scale;
      await t.pumpWidget(HashiApp(home: Builder(builder: (c) {
        scale = MediaQuery.of(c).textScaler.scale(10);
        return const SizedBox();
      })));
      seniorMode.value = true;
      await t.pump();
      expect(scale, 12.5);
    });
  });

  group('deck', () {
    Future<void> showDeck(WidgetTester t, {Profile? p}) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: DeckScreen(deck: Deck.flight, profile: p ?? Profile(lang: 'hi', seat: '24C', server: 'http://cabin.test'), cards: sample)));
      await settle(t);
    }

    testWidgets("shows every card as a tile in the passenger's own language, and flags urgent ones in words", (t) async {
      await showDeck(t);
      expect(find.text('पानी चाहिए'), findsOneWidget);
      expect(find.text('कंबल चाहिए'), findsOneWidget);
      expect(find.text('सीने में दर्द है'), findsOneWidget);
      expect(find.text('URGENT · 緊急'), findsOneWidget);
      expect(find.byType(CardTile), findsNWidgets(3));
    });

    testWidgets('tiles are two to a row and big enough for older hands', (t) async {
      await showDeck(t);
      final a = t.getRect(find.byType(CardTile).at(0));
      final b = t.getRect(find.byType(CardTile).at(1));
      final c = t.getRect(find.byType(CardTile).at(2));
      expect((a.top - b.top).abs(), lessThan(1), reason: 'first two share a row');
      expect(c.top, greaterThan(a.bottom));
      expect(a.height, greaterThanOrEqualTo(tileHeight));
      expect(a.width, greaterThanOrEqualTo(150));
    });

    testWidgets('a group filter shows only that group, and All brings everything back', (t) async {
      await showDeck(t);
      // the group chips scroll sideways, like on the phone
      await t.dragUntilVisible(find.textContaining('Comfort'), find.byType(ListView).at(1), const Offset(-120, 0));
      await t.ensureVisible(find.textContaining('Comfort'));
      await t.pump();
      await t.tap(find.textContaining('Comfort'));
      await settle(t);
      expect(find.text('कंबल चाहिए'), findsOneWidget);
      expect(find.text('पानी चाहिए'), findsNothing);
      await t.dragUntilVisible(find.text('All'), find.byType(ListView).at(1), const Offset(200, 0));
      await t.ensureVisible(find.text('All'));
      await t.pump();
      await t.tap(find.text('All'));
      await settle(t);
      expect(find.text('पानी चाहिए'), findsOneWidget);
    });

    testWidgets('tapping a card opens it full screen', (t) async {
      await showDeck(t);
      await t.tap(find.text('पानी चाहिए'));
      await settle(t);
      expect(find.text('Send to crew · 乗務員に送る'), findsOneWidget);
      expect(find.text('お水をお願いします'), findsWidgets, reason: 'the full card shows the Japanese');
    });
  });

  group('full card', () {
    Future<(CabinSession, FakeCabin)> show(WidgetTester t, Profile p, {Deck deck = Deck.flight, bool online = true, bool withSession = true}) async {
      final cabin = FakeCabin();
      final session = CabinSession.forProfile(p, makeLink: (store) => CabinLink(store, factory: cabin.open, pingEvery: Duration.zero));
      addTearDown(session.dispose);
      if (online) {
        session.connect('http://cabin.test:8000');
        await t.pump();
        cabin.welcome();
        await t.pump();
      }
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: FullCard(card: sample[0], profile: p, deck: deck, session: withSession ? session : null)));
      await settle(t);
      return (session, cabin);
    }

    testWidgets("can be flipped to the passenger's language and back", (t) async {
      await show(t, Profile(lang: 'hi', seat: '24C'));
      expect(find.text('पानी चाहिए'), findsNothing);
      await t.tap(find.text('हिन्दी'));
      await settle(t);
      expect(find.text('पानी चाहिए'), findsOneWidget);
      await t.tap(find.text('Japanese'));
      await settle(t);
      expect(find.text('お水をお願いします'), findsWidgets);
    });

    testWidgets('sends the card to the crew over the live line and says so', (t) async {
      final (_, cabin) = await show(t, Profile(lang: 'hi', seat: '24C'));
      await t.tap(find.text('Send to crew · 乗務員に送る'));
      await settle(t);
      expect(cabin.lastInbox.last, {'t': 'request', 'intent': 'water', 'via': 'tap'});
      expect(find.text('Sent to the crew · 乗務員に送りました'), findsOneWidget);
    });

    testWidgets('with the line down the request is kept, and the screen says it will be sent later', (t) async {
      final (session, cabin) = await show(t, Profile(lang: 'hi', seat: '24C'), online: false);
      await t.tap(find.text('Send to crew · 乗務員に送る'));
      await settle(t);
      expect(find.textContaining('It will be sent as soon as you are connected'), findsOneWidget);
      expect(session.store.queued.single.intent, 'water');
      expect(cabin.connections, isEmpty);
    });

    testWidgets('without a seat it asks to join the cabin first and keeps nothing', (t) async {
      final (session, _) = await show(t, Profile(lang: 'hi', seat: ''), online: false);
      await t.tap(find.text('Send to crew · 乗務員に送る'));
      await settle(t);
      expect(find.textContaining('Join the cabin first'), findsOneWidget);
      expect(session.store.queued, isEmpty);
    });

    testWidgets('without a session it asks to join the cabin first', (t) async {
      await show(t, Profile(lang: 'hi', seat: '24C'), online: false, withSession: false);
      await t.tap(find.text('Send to crew · 乗務員に送る'));
      await settle(t);
      expect(find.textContaining('Join the cabin first'), findsOneWidget);
    });

    testWidgets('only the flight deck can send to the crew', (t) async {
      await show(t, Profile(lang: 'hi', seat: '24C'), deck: Deck.staff);
      expect(find.text('Send to crew · 乗務員に送る'), findsNothing);
      expect(find.text('Play · 音声'), findsOneWidget);
    });

    testWidgets('the main buttons are big enough to tap', (t) async {
      await show(t, Profile(lang: 'hi', seat: '24C'));
      for (final label in ['Send to crew · 乗務員に送る', 'Play · 音声']) {
        expect(t.getSize(find.ancestor(of: find.text(label), matching: find.byType(FilledButton)).first).height, greaterThanOrEqualTo(56), reason: label);
      }
    });
  });

  group('settings', () {
    Future<(Profile, PassengerRepo)> open(WidgetTester t, {bool signedIn = false, bool online = false}) async {
      final r = await repo(signedIn: signedIn, online: online);
      final p = Profile(lang: 'hi', seat: '24C');
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: SettingsScreen(profile: p, repo: r)));
      await settle(t);
      return (p, r);
    }

    testWidgets('signed out: a change is kept on the phone and the screen says how to keep it in the account', (t) async {
      final (p, _) = await open(t);
      await t.tap(find.text('I eat vegetarian food'));
      await settle(t);
      expect(p.needs, contains('veg'));
      expect(find.textContaining('Sign in under "Before you fly"'), findsOneWidget);
    });

    testWidgets('senior and calm switches take effect straight away', (t) async {
      final (p, _) = await open(t);
      await t.tap(find.text('Bigger text and buttons'));
      await settle(t);
      expect(p.senior, true);
      expect(seniorMode.value, true);
      await t.scrollUntilVisible(find.text('Calm screen'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Calm screen'));
      await settle(t);
      expect(p.calm, true);
      expect(calmMotion.value, true);
    });

    testWidgets('choosing a language saves it', (t) async {
      final (p, _) = await open(t);
      await t.tap(find.text('தமிழ்'));
      await settle(t);
      expect(p.lang, 'ta');
    });

    testWidgets('signed in but offline: the change waits and the screen says so', (t) async {
      final (p, r) = await open(t, signedIn: true);
      await t.tap(find.text('I do not hear well'));
      await settle(t);
      expect(p.needs, contains('hearing'));
      expect(r.hasPendingEdit, true);
      expect(find.textContaining('It will be sent when there is a signal'), findsOneWidget);
    });

    testWidgets('signed in and online: the change reaches the account', (t) async {
      final (_, r) = await open(t, signedIn: true, online: true);
      await t.tap(find.text('I have diabetes'));
      await settle(t);
      expect(r.hasPendingEdit, false);
      expect(find.text('Saved to your account.'), findsOneWidget);
    });

    testWidgets('every row is a proper touch target', (t) async {
      await open(t);
      for (final label in ['I eat vegetarian food', 'Bigger text and buttons']) {
        final tile = find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first;
        expect(t.getSize(tile).height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('sign out wipes the account and keeps the phone settings', (t) async {
      final (p, r) = await open(t, signedIn: true, online: true);
      p.needs.add('veg');
      await t.scrollUntilVisible(find.text('Sign out'), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Sign out'));
      await settle(t);
      expect(r.signedIn, false);
      expect(r.preferences, isNull);
      expect(p.needs, contains('veg'));
    });

    test('every need the settings offer is short enough for the account to store', () {
      for (final key in needOptions.keys) {
        expect(key.length, lessThanOrEqualTo(24));
      }
      expect(needOptions.length, lessThanOrEqualTo(8));
    });
  });
}
