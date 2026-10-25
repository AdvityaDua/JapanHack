import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/cabin.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/session.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:hashi_mobile/central.dart';
import 'package:hashi_mobile/discover.dart';
import 'package:hashi_mobile/kit.dart';
import 'package:hashi_mobile/repo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session whose line goes nowhere, so screens can be tested without a cabin.
CabinSession quietSession(Profile p) {
  final s = CabinSession.forProfile(p, makeLink: (store) => CabinLink(store, factory: (_) => StreamChannelController<dynamic>().local));
  addTearDown(s.dispose);
  return s;
}

Future<PassengerRepo> repo() async {
  SharedPreferences.setMockInitialValues({});
  return PassengerRepo.open('http://central.test', client: CentralClient('http://central.test', client: MockClient((http.Request r) async => http.Response('{}', 404))));
}

Future<void> show(WidgetTester t, CabinConnection result, {Profile? profile, List<List<String>>? seen}) async {
  final p = profile ?? Profile(lang: 'hi', seat: '24C');
  final session = quietSession(p);
  await t.pumpWidget(MaterialApp(
    home: CabinScreen(
      profile: p,
      repo: await repo(),
      ensureSession: () => session,
      retryEvery: const Duration(hours: 1),
      connector: (hosts) async {
        seen?.add(hosts);
        return result;
      },
    ),
  ));
  await t.pump();
  await t.pump();
}

bool openEnabled(WidgetTester t) => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enter the cabin')).onPressed != null;

void main() {
  testWidgets('connected: shows flight and seat from the cabin, open button enabled, no address or seat field', (t) async {
    await show(t, const CabinConnection(CabinState.ready, baseUrl: 'http://hashi-cabin.local:8000', seat: '24C', flight: 'JL740'));
    expect(find.text('Connected to JL740 · seat 24C'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(openEnabled(t), true);
  });

  testWidgets('the working cabin address and confirmed seat are remembered on the profile', (t) async {
    final p = Profile(lang: 'hi', seat: '24C', server: 'http://old:8000');
    await show(t, const CabinConnection(CabinState.ready, baseUrl: 'http://192.168.137.1:8000', seat: '31K'), profile: p);
    expect(p.server, 'http://192.168.137.1:8000');
    expect(p.seat, '31K');
  });

  testWidgets('not found: says so, open button is disabled, address box is hidden until asked for', (t) async {
    await show(t, const CabinConnection(CabinState.notFound));
    expect(find.text('Cabin not found yet'), findsOneWidget);
    expect(openEnabled(t), false);
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.text('Cabin not found? Enter the address from the crew'));
    await t.pump();
    expect(find.widgetWithText(TextField, 'Cabin address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Seat'), findsNothing);
  });

  testWidgets('the host list starts with the remembered address and includes the host name', (t) async {
    final seen = <List<String>>[];
    await show(t, const CabinConnection(CabinState.notFound), profile: Profile(lang: 'hi', server: 'http://192.168.137.1:8000'), seen: seen);
    expect(seen.first.first, 'http://192.168.137.1:8000');
    expect(seen.first, contains('http://hashi-cabin.local:8000'));
  });

  testWidgets('each problem has its own message and does not enable the cabin', (t) async {
    final cases = {
      CabinState.noPass: 'Cabin found, but no boarding pass',
      CabinState.refused: 'The cabin did not accept the pass',
      CabinState.seatTaken: 'Another phone is using your seat',
      CabinState.unreachable: 'The cabin did not answer',
    };
    for (final e in cases.entries) {
      await t.pumpWidget(const SizedBox()); // start each case from a fresh screen
      await show(t, CabinConnection(e.key, baseUrl: 'http://x'));
      expect(find.text(e.value), findsOneWidget, reason: '${e.key}');
      expect(openEnabled(t), false);
    }
  });

  testWidgets('keeps retrying by itself until it connects, then stops', (t) async {
    var calls = 0;
    final p = Profile(lang: 'hi', seat: '24C');
    final session = quietSession(p);
    await t.pumpWidget(MaterialApp(
      home: CabinScreen(
        profile: p,
        repo: await repo(),
        ensureSession: () => session,
        retryEvery: const Duration(seconds: 1),
        connector: (hosts) async => ++calls < 3 ? const CabinConnection(CabinState.notFound) : const CabinConnection(CabinState.ready, baseUrl: 'http://c', seat: '24C', flight: 'JL740'),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Connected to JL740 · seat 24C'), findsOneWidget);
    final before = calls;
    await t.pump(const Duration(seconds: 3));
    expect(calls, before);
  });
}
