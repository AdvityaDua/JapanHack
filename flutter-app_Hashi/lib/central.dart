import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talks to the central (cloud) backend: login, preferences, bookings and the boarding grant.
/// Nothing here knows about the cabin; that side lives in cabin_link.dart.

class CentralException implements Exception {
  final int? status;
  final String message;
  CentralException(this.message, {this.status});
  @override
  String toString() => message;
}

/// The server holds a newer version of the preferences than the one this phone edited.
class VersionConflict extends CentralException {
  VersionConflict() : super('Preferences changed elsewhere', status: 409);
}

class Preferences {
  final String spokenLanguage;
  final String displayLanguage;
  final bool senior;
  final List<String> needs;
  final List<String> extraLanguages;
  final int version;

  const Preferences({
    required this.spokenLanguage,
    required this.displayLanguage,
    this.senior = false,
    this.needs = const [],
    this.extraLanguages = const [],
    this.version = 1,
  });

  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
    spokenLanguage: j['spoken_language'] as String,
    displayLanguage: j['display_language'] as String,
    senior: j['senior_mode_enabled'] as bool? ?? false,
    needs: List<String>.from(j['needs'] as List? ?? const []),
    extraLanguages: List<String>.from(
      j['extra_languages'] as List? ?? const [],
    ),
    version: j['version'] as int? ?? 1,
  );

  /// Body for PUT /preferences. [expectedVersion] makes the server refuse the save if someone else changed it first.
  Map<String, dynamic> toUpdateJson({int? expectedVersion}) => {
    'spoken_language': spokenLanguage,
    'display_language': displayLanguage,
    'translation_mode': 'conversation',
    'senior_mode_enabled': senior,
    'font_scale': senior ? 140 : 100,
    'needs': needs,
    'extra_languages': extraLanguages,
    'expected_version': ?expectedVersion,
  };

  Map<String, dynamic> toJson() => {
    'spoken_language': spokenLanguage,
    'display_language': displayLanguage,
    'senior_mode_enabled': senior,
    'needs': needs,
    'extra_languages': extraLanguages,
    'version': version,
  };

  Preferences copyWith({
    String? spokenLanguage,
    String? displayLanguage,
    bool? senior,
    List<String>? needs,
    List<String>? extraLanguages,
    int? version,
  }) => Preferences(
    spokenLanguage: spokenLanguage ?? this.spokenLanguage,
    displayLanguage: displayLanguage ?? this.displayLanguage,
    senior: senior ?? this.senior,
    needs: needs ?? this.needs,
    extraLanguages: extraLanguages ?? this.extraLanguages,
    version: version ?? this.version,
  );
}

/// The one flight leg with a seat that the app shows and boards with.
class Trip {
  final String bookingId;
  final String flightNumber;
  final String from;
  final String to;
  final String seat;
  final DateTime departure;
  final DateTime arrival;

  const Trip({
    required this.bookingId,
    required this.flightNumber,
    required this.from,
    required this.to,
    required this.seat,
    required this.departure,
    required this.arrival,
  });

  Map<String, dynamic> toJson() => {
    'booking_id': bookingId,
    'flight_number': flightNumber,
    'from': from,
    'to': to,
    'seat': seat,
    'departure': departure.toIso8601String(),
    'arrival': arrival.toIso8601String(),
  };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
    bookingId: j['booking_id'] as String,
    flightNumber: j['flight_number'] as String,
    from: j['from'] as String,
    to: j['to'] as String,
    seat: j['seat'] as String,
    departure: DateTime.parse(j['departure'] as String),
    arrival: DateTime.parse(j['arrival'] as String),
  );

  /// Pick the next confirmed leg that has a seat from GET /users/me/bookings. Null when there is none.
  static Trip? fromBookings(List<dynamic> bookings) {
    final trips = <Trip>[];
    for (final b in bookings.cast<Map<String, dynamic>>()) {
      if (b['booking_status'] != 'confirmed') continue;
      for (final s in (b['segments'] as List).cast<Map<String, dynamic>>()) {
        if (s['segment_status'] != 'confirmed') continue;
        for (final a
            in (s['seat_assignments'] as List).cast<Map<String, dynamic>>()) {
          final seat = a['seat_number'] as String?;
          if (seat == null || a['seat_status'] != 'confirmed') continue;
          trips.add(
            Trip(
              bookingId: b['id'] as String,
              flightNumber: s['flight_number'] as String,
              from: s['departure_airport'] as String,
              to: s['arrival_airport'] as String,
              seat: seat,
              departure: DateTime.parse(s['departure_time'] as String),
              arrival: DateTime.parse(s['arrival_time'] as String),
            ),
          );
        }
      }
    }
    if (trips.isEmpty) return null;
    trips.sort((a, b) => a.departure.compareTo(b.departure));
    return trips.first;
  }
}

class CentralClient {
  String baseUrl;
  final http.Client _http;
  String? token;

  CentralClient(this.baseUrl, {http.Client? client, this.token})
    : _http = client ?? http.Client();

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
  Map<String, String> get _auth => {
    if (token != null) 'Authorization': 'Bearer $token',
  };
  static const _json = {'Content-Type': 'application/json'};

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 10));
    } catch (e) {
      throw CentralException('Cannot reach the booking server');
    }
  }

  Never _fail(http.Response r) {
    var detail = 'Request failed (${r.statusCode})';
    try {
      final d = jsonDecode(r.body)['detail'];
      if (d is String) detail = d;
    } catch (_) {}
    if (r.statusCode == 409) throw VersionConflict();
    throw CentralException(detail, status: r.statusCode);
  }

  Future<String> login(String email, String password) async {
    final r = await _send(
      () => _http.post(
        _uri('/api/v1/auth/login'),
        headers: _json,
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    if (r.statusCode != 200) _fail(r);
    return token = jsonDecode(r.body)['access_token'] as String;
  }

  Future<Preferences> preferences() async {
    final r = await _send(
      () => _http.get(_uri('/api/v1/preferences'), headers: _auth),
    );
    if (r.statusCode != 200) _fail(r);
    return Preferences.fromJson(jsonDecode(r.body));
  }

  Future<Preferences> savePreferences(
    Preferences p, {
    int? expectedVersion,
  }) async {
    final r = await _send(
      () => _http.put(
        _uri('/api/v1/preferences'),
        headers: {..._auth, ..._json},
        body: jsonEncode(p.toUpdateJson(expectedVersion: expectedVersion)),
      ),
    );
    if (r.statusCode != 200) _fail(r);
    return Preferences.fromJson(jsonDecode(r.body));
  }

  Future<Trip?> trip() async {
    final r = await _send(
      () => _http.get(_uri('/api/v1/users/me/bookings'), headers: _auth),
    );
    if (r.statusCode != 200) _fail(r);
    return Trip.fromBookings(jsonDecode(r.body) as List);
  }

  /// Ask for the signed pass that proves this phone's seat to the aircraft.
  Future<String> boardingGrant(String bookingId, String deviceId) async {
    final r = await _send(
      () => _http.post(
        _uri('/api/v1/boarding-grants'),
        headers: {..._auth, ..._json},
        body: jsonEncode({
          'booking_id': bookingId,
          'passenger_device_id': deviceId,
        }),
      ),
    );
    if (r.statusCode != 200) _fail(r);
    return jsonDecode(r.body)['grant'] as String;
  }

  Future<void> registerPushDevice({
    required String deviceId,
    required String token,
    String platform = 'android',
  }) async {
    final r = await _send(
      () => _http.post(
        _uri('/api/v1/notifications/devices'),
        headers: {..._auth, ..._json},
        body: jsonEncode({
          'device_id': deviceId,
          'token': token,
          'platform': platform,
          'app_id': 'jp.hashi.hashi_mobile',
        }),
      ),
    );
    if (r.statusCode != 200) _fail(r);
  }
}
