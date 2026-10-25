// Runs the real client against a real central backend. Skipped unless CENTRAL_URL is set, e.g.
//   flutter test test/central_live_test.dart --dart-define=CENTRAL_URL=http://127.0.0.1:8100
// after `python scripts/seed_demo.py` in the central backend.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/central.dart';

const url = String.fromEnvironment('CENTRAL_URL');

void main() {
  final skip = url.isEmpty ? 'set CENTRAL_URL to run' : null;

  test('login, booking seat, preferences round trip and boarding grant against the real backend', () async {
    final c = CentralClient(url);
    expect(await c.login('demo.passenger@example.com', 'demo-pass-123'), isNotEmpty);

    final trip = await c.trip();
    expect(trip, isNotNull);
    expect(trip!.seat, '24C');
    expect(trip.flightNumber, 'JL740');

    final before = await c.preferences();
    final saved = await c.savePreferences(before.copyWith(needs: ['veg'], senior: true), expectedVersion: before.version);
    expect(saved.version, before.version + 1);
    expect(saved.needs, ['veg']);
    await expectLater(c.savePreferences(before, expectedVersion: before.version), throwsA(isA<VersionConflict>()));

    final grant = await c.boardingGrant(trip.bookingId, 'phone-livetest0001');
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(grant.split('.').first)))) as Map<String, dynamic>;
    expect(payload['seat'], '24C');
    expect(payload['flight'], 'JL740');
    expect(payload['device'], 'phone-livetest0001');
    expect(payload['needs'], ['veg']);
    expect(payload.containsKey('email'), false);
  }, skip: skip);

  test('a wrong password is a clean error', () async {
    await expectLater(CentralClient(url).login('demo.passenger@example.com', 'nope-nope-1'), throwsA(isA<CentralException>()));
  }, skip: skip);
}
