import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/central.dart';
import 'package:hashi_mobile/repo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny in-memory stand-in for the central backend.
class FakeCentral {
  bool online = true;
  int prefsVersion = 1;
  Map<String, dynamic> prefs = {'spoken_language': 'hi', 'display_language': 'hi', 'senior_mode_enabled': false, 'needs': [], 'extra_languages': []};
  final List<Map<String, dynamic>> saves = [];
  int grantCalls = 0;

  Map<String, dynamic> get prefsJson => {...prefs, 'version': prefsVersion};

  Map<String, dynamic> booking({String status = 'confirmed', String? seat = '24C', String seatStatus = 'confirmed'}) => {
        'id': 'b-1',
        'booking_status': status,
        'segments': [
          {
            'flight_number': 'JL740',
            'departure_airport': 'DEL',
            'arrival_airport': 'NRT',
            'departure_time': '2026-11-01T10:00:00Z',
            'arrival_time': '2026-11-01T18:00:00Z',
            'segment_status': 'confirmed',
            'seat_assignments': [
              {'seat_number': seat, 'seat_status': seatStatus}
            ],
          }
        ],
      };

  List<Map<String, dynamic>> bookings = [];

  MockClient get client => MockClient((http.Request r) async {
        if (!online) throw http.ClientException('offline');
        final path = r.url.path;
        if (path == '/api/v1/auth/login') {
          final ok = jsonDecode(r.body)['password'] == 'pw-12345';
          return ok ? http.Response(jsonEncode({'access_token': 'tok'}), 200) : http.Response(jsonEncode({'detail': 'Invalid credentials'}), 401);
        }
        if (r.headers['Authorization'] != 'Bearer tok') return http.Response(jsonEncode({'detail': 'Invalid or expired token'}), 401);
        if (path == '/api/v1/preferences' && r.method == 'GET') return http.Response(jsonEncode(prefsJson), 200);
        if (path == '/api/v1/preferences' && r.method == 'PUT') {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          saves.add(body);
          final expected = body['expected_version'];
          if (expected != null && expected != prefsVersion) return http.Response(jsonEncode({'detail': 'changed'}), 409);
          prefs = {...body}..remove('expected_version');
          prefsVersion++;
          return http.Response(jsonEncode(prefsJson), 200);
        }
        if (path == '/api/v1/users/me/bookings') return http.Response(jsonEncode(bookings), 200);
        if (path == '/api/v1/boarding-grants') {
          grantCalls++;
          final exp = DateTime.now().add(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000;
          final body = base64Url.encode(utf8.encode(jsonEncode({'v': 1, 'exp': exp}))).replaceAll('=', '');
          return http.Response(jsonEncode({'grant': '$body.sig'}), 200);
        }
        return http.Response('not found', 404);
      });
}

Future<(PassengerRepo, FakeCentral)> signedInRepo({FakeCentral? fake}) async {
  SharedPreferences.setMockInitialValues({});
  final f = fake ?? FakeCentral();
  f.bookings = [f.booking()];
  final repo = await PassengerRepo.open('http://central.test', client: CentralClient('http://central.test', client: f.client));
  await repo.signIn('a@b.c', 'pw-12345');
  return (repo, f);
}

void main() {
  group('Trip', () {
    test('takes the seat from the booking, never from the user', () {
      final trip = Trip.fromBookings([FakeCentral().booking()])!;
      expect((trip.flightNumber, trip.seat, trip.from, trip.to), ('JL740', '24C', 'DEL', 'NRT'));
    });

    test('ignores bookings that are not confirmed or have no confirmed seat', () {
      final f = FakeCentral();
      expect(Trip.fromBookings([f.booking(status: 'cancelled')]), isNull);
      expect(Trip.fromBookings([f.booking(seat: null)]), isNull);
      expect(Trip.fromBookings([f.booking(seatStatus: 'pending')]), isNull);
      expect(Trip.fromBookings([]), isNull);
    });

    test('picks the earliest leg', () {
      final late = FakeCentral().booking(seat: '10A');
      (late['segments'] as List)[0]['departure_time'] = '2026-12-01T10:00:00Z';
      expect(Trip.fromBookings([late, FakeCentral().booking()])!.seat, '24C');
    });
  });

  group('sign in and cache', () {
    test('a wrong password is reported and nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final f = FakeCentral();
      final repo = await PassengerRepo.open('http://central.test', client: CentralClient('http://central.test', client: f.client));
      await expectLater(repo.signIn('a@b.c', 'wrong'), throwsA(isA<CentralException>()));
      expect(repo.signedIn, false);
    });

    test('after sign in the preferences and seat are cached for offline use', () async {
      final (repo, f) = await signedInRepo();
      f.online = false;
      expect(repo.preferences!.displayLanguage, 'hi');
      expect(repo.trip!.seat, '24C');
      expect(await repo.refresh(), false); // offline: reports it, keeps the cache
      expect(repo.trip!.seat, '24C');
    });

    test('device id is made once and kept', () async {
      final (repo, _) = await signedInRepo();
      final id = repo.deviceId;
      expect(id, startsWith('phone-'));
      expect(repo.deviceId, id);
    });

    test('sign out wipes the cached account', () async {
      final (repo, _) = await signedInRepo();
      await repo.signOut();
      expect(repo.preferences, isNull);
      expect(repo.trip, isNull);
      expect(repo.signedIn, false);
    });
  });

  group('editing preferences', () {
    test('an online edit is saved and the version moves on', () async {
      final (repo, f) = await signedInRepo();
      expect(await repo.edit(repo.preferences!.copyWith(needs: ['veg'])), true);
      expect(f.prefs['needs'], ['veg']);
      expect(repo.preferences!.version, 2);
      expect(repo.hasPendingEdit, false);
    });

    test('an offline edit is kept, shown at once, and sent later', () async {
      final (repo, f) = await signedInRepo();
      f.online = false;
      expect(await repo.edit(repo.preferences!.copyWith(senior: true, needs: ['hearing'])), false);
      expect(repo.hasPendingEdit, true);
      expect(repo.preferences!.senior, true);
      expect(f.prefs['senior_mode_enabled'], false);

      f.online = true;
      expect(await repo.refresh(), true);
      expect(repo.hasPendingEdit, false);
      expect(f.prefs['senior_mode_enabled'], true);
      expect(f.prefs['needs'], ['hearing']);
    });

    test('several offline edits send one save that started from the first version', () async {
      final (repo, f) = await signedInRepo();
      f.online = false;
      await repo.edit(repo.preferences!.copyWith(needs: ['veg']));
      await repo.edit(repo.preferences!.copyWith(needs: ['veg', 'quiet']));
      f.online = true;
      await repo.refresh();
      expect(f.saves.length, 1);
      expect(f.saves.single['expected_version'], 1);
      expect(f.prefs['needs'], ['veg', 'quiet']);
    });

    test('a conflict from another device is resolved with the passenger\'s own edit winning', () async {
      final (repo, f) = await signedInRepo();
      f.online = false;
      await repo.edit(repo.preferences!.copyWith(needs: ['mobility']));
      f.prefsVersion = 5; // another phone saved meanwhile
      f.prefs = {...f.prefs, 'needs': ['veg']};
      f.online = true;
      await repo.refresh();
      expect(f.prefs['needs'], ['mobility']);
      expect(repo.preferences!.version, 6);
      expect(repo.hasPendingEdit, false);
    });
  });

  group('boarding grant', () {
    test('is fetched online with the device id and cached', () async {
      final (repo, f) = await signedInRepo();
      expect(await repo.boardingGrant(), isNotNull);
      expect(f.grantCalls, 1);
    });

    test('offline, the saved grant is used while it is valid', () async {
      final (repo, f) = await signedInRepo();
      final online = await repo.boardingGrant();
      f.online = false;
      expect(await repo.boardingGrant(), online);
    });

    test('offline with no saved grant gives null', () async {
      final (repo, f) = await signedInRepo();
      f.online = false;
      expect(await repo.boardingGrant(), isNull);
    });

    test('an expired or broken grant is not valid', () {
      String make(int exp) => '${base64Url.encode(utf8.encode(jsonEncode({'exp': exp}))).replaceAll('=', '')}.sig';
      expect(PassengerRepo.grantStillValid(make(1)), false);
      expect(PassengerRepo.grantStillValid('garbage'), false);
      expect(PassengerRepo.grantStillValid(make(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60)), true);
    });
  });
}
