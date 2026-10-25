import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/central.dart';
import 'package:hashi_mobile/kit.dart';
import 'package:hashi_mobile/preflight.dart';
import 'package:hashi_mobile/repo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PassengerRepo> repoWith({required bool signedIn, String seat = '24C'}) async {
  SharedPreferences.setMockInitialValues({});
  final client = CentralClient('http://central.test', client: MockClient((http.Request r) async => http.Response('{}', 404)));
  final repo = await PassengerRepo.open('http://central.test', client: client);
  if (signedIn) {
    final store = repo.store;
    await store.setString('central_trip', '{"booking_id":"b","flight_number":"JL740","from":"DEL","to":"NRT","seat":"$seat","departure":"2026-11-01T10:00:00Z","arrival":"2026-11-01T18:00:00Z"}');
    await store.setString('central_prefs', '{"spoken_language":"hi","display_language":"hi","senior_mode_enabled":false,"needs":[],"extra_languages":[],"version":1}');
    client.token = 'tok';
  }
  return repo;
}

Future<void> show(WidgetTester t, PassengerRepo repo, Profile p) async {
  await t.pumpWidget(MaterialApp(home: PreflightScreen(profile: p, repo: repo)));
  await t.pump();
}

void main() {
  testWidgets('signed out: asks for the account and has no seat input', (t) async {
    await show(t, await repoWith(signedIn: false), Profile());
    expect(find.text('Sign in to get your booking'), findsOneWidget);
    expect(find.text('Seat comes from your booking'), findsNothing); // that line belongs to the home screen
    expect(find.widgetWithText(TextField, 'Seat'), findsNothing);
  });

  testWidgets('signed in: shows the seat from the booking and no seat field anywhere', (t) async {
    final repo = await repoWith(signedIn: true, seat: '31K');
    final p = Profile();
    applyAccountToProfile(p, repo.preferences, repo.trip);
    await show(t, repo, p);
    expect(find.text('Seat 31K · from your booking'), findsOneWidget);
    await t.tap(find.text('Show the notification the passenger would get'));
    await t.pump();
    final labels = t.widgetList<TextField>(find.byType(TextField)).map((f) => f.decoration?.labelText).toList();
    final forms = t.widgetList<TextFormField>(find.byType(TextFormField)).length;
    expect(labels.where((l) => (l ?? '').toLowerCase().contains('seat')), isEmpty);
    expect(forms, 0);
  });

  test('profile takes language, needs and seat from the account only', () async {
    final repo = await repoWith(signedIn: true, seat: '9F');
    final p = Profile(seat: 'typed-by-hand');
    applyAccountToProfile(p, repo.preferences!.copyWith(displayLanguage: 'ta', needs: ['veg'], senior: true), repo.trip);
    expect(p.lang, 'ta');
    expect(p.seat, '9F');
    expect(p.senior, true);
    expect(p.needs, {'veg'});
    expect(Profile().seat, isEmpty);
  });

  test('cabin address leaves the seat out until the booking is known', () {
    expect(Profile(lang: 'hi').cabinUrl(), isNot(contains('seat=')));
    expect(Profile(lang: 'hi', seat: '24C').cabinUrl(), contains('seat=24C'));
  });

  test('preferences sent to the account are built from the profile and keep the version', () async {
    final repo = await repoWith(signedIn: true);
    final p = Profile(lang: 'hi', senior: true, needs: {'veg', 'hearing'});
    final out = preferencesFromProfile(p, repo.preferences);
    expect(out.displayLanguage, 'hi');
    expect(out.senior, true);
    expect(out.needs, ['hearing', 'veg']);
    expect(out.version, 1);
  });
}
