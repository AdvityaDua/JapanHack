import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'central.dart';
import 'backend/communication_client.dart';
import 'kit.dart';
import 'languages.dart';

/// Keeps the passenger's account data on the phone so every screen works with no signal,
/// and sends edits to the cloud when a connection is there.
class PassengerRepo {
  final CentralClient client;
  final SharedPreferences store;
  PassengerRepo(this.client, this.store);

  static const _kToken = 'central_token';
  static const _kPrefs = 'central_prefs';
  static const _kPending = 'central_prefs_pending';
  static const _kBase = 'central_prefs_base_version';
  static const _kTrip = 'central_trip';
  static const _kGrant = 'central_grant';
  static const _kDevice = 'device_id';
  static const _kCabinDevice = 'cabin_device_id';
  static const _kCabinToken = 'cabin_device_token';
  static const _kCabinFlight = 'cabin_flight_id';
  static const _kCabinSeatToken = 'cabin_seat_token';

  static Future<PassengerRepo> open(
    String baseUrl, {
    CentralClient? client,
  }) async {
    final store = await SharedPreferences.getInstance();
    return PassengerRepo(
      client ?? CentralClient(baseUrl, token: store.getString(_kToken)),
      store,
    );
  }

  bool get signedIn => client.token != null;

  Preferences? get preferences {
    final raw = store.getString(_kPrefs);
    return raw == null ? null : Preferences.fromJson(jsonDecode(raw));
  }

  Trip? get trip {
    final raw = store.getString(_kTrip);
    return raw == null ? null : Trip.fromJson(jsonDecode(raw));
  }

  /// True while a preference edit has not reached the cloud yet.
  bool get hasPendingEdit => store.getBool(_kPending) ?? false;

  /// A random id made once on this phone. The boarding grant is tied to it.
  String get deviceId {
    var id = store.getString(_kDevice);
    if (id == null) {
      final r = Random.secure();
      id =
          'phone-${List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join()}';
      store.setString(_kDevice, id);
    }
    return id;
  }

  Future<void> signIn(String email, String password) async {
    final token = await client.login(email, password);
    await store.setString(_kToken, token);
    await refresh();
  }

  Future<void> signOut() async {
    client.token = null;
    for (final k in [
      _kToken,
      _kPrefs,
      _kPending,
      _kBase,
      _kTrip,
      _kGrant,
      _kCabinDevice,
      _kCabinToken,
      _kCabinFlight,
      _kCabinSeatToken,
    ]) {
      await store.remove(k);
    }
  }

  PairingCredentials? get cabinCredentials {
    final deviceId = store.getString(_kCabinDevice);
    final deviceToken = store.getString(_kCabinToken);
    final flightId = store.getString(_kCabinFlight);
    if (deviceId == null || deviceToken == null || flightId == null)
      return null;
    return PairingCredentials(
      deviceId: deviceId,
      deviceToken: deviceToken,
      flightId: flightId,
      seatToken: store.getString(_kCabinSeatToken),
    );
  }

  Future<void> saveCabinCredentials(PairingCredentials credentials) async {
    await store.setString(_kCabinDevice, credentials.deviceId);
    await store.setString(_kCabinToken, credentials.deviceToken);
    await store.setString(_kCabinFlight, credentials.flightId);
    if (credentials.seatToken != null)
      await store.setString(_kCabinSeatToken, credentials.seatToken!);
  }

  /// Send any waiting edit, then pull the latest preferences and booking. Returns false when the cloud is out of reach;
  /// the cached copies stay in use.
  Future<bool> refresh() async {
    if (!signedIn) return false;
    try {
      await _pushPending();
      await _cachePrefs(await client.preferences());
      final t = await client.trip();
      if (t != null) await store.setString(_kTrip, jsonEncode(t.toJson()));
      return true;
    } on CentralException {
      return false;
    }
  }

  /// Save an edit. It is kept on the phone at once and sent when possible, so it is never lost.
  Future<bool> edit(Preferences next) async {
    final current = preferences;
    // the version the edit started from; keep the oldest one if several offline edits stack up
    if (!hasPendingEdit) await store.setInt(_kBase, current?.version ?? 1);
    await store.setString(_kPrefs, jsonEncode(next.toJson()));
    await store.setBool(_kPending, true);
    try {
      await _pushPending();
      return true;
    } on CentralException {
      return false;
    }
  }

  Future<void> _pushPending() async {
    if (!hasPendingEdit || !signedIn) return;
    final local = preferences!;
    var expected = store.getInt(_kBase);
    try {
      await _cachePrefs(
        await client.savePreferences(local, expectedVersion: expected),
      );
    } on VersionConflict {
      // Someone else saved first (for example another phone). The passenger's own latest edit wins:
      // take the server's version number and save again.
      final server = await client.preferences();
      await _cachePrefs(
        await client.savePreferences(local, expectedVersion: server.version),
      );
    }
    await store.setBool(_kPending, false);
  }

  Future<void> _cachePrefs(Preferences p) =>
      store.setString(_kPrefs, jsonEncode(p.toJson()));

  /// The signed boarding pass for the cabin. Fetched when online, otherwise the saved one if it is still valid.
  Future<String?> boardingGrant() async {
    final t = trip;
    if (t != null && signedIn) {
      try {
        final g = await client.boardingGrant(t.bookingId, deviceId);
        await store.setString(_kGrant, g);
        return g;
      } on CentralException {
        // fall through to the saved grant
      }
    }
    final saved = store.getString(_kGrant);
    return saved != null && grantStillValid(saved) ? saved : null;
  }

  /// Reads the expiry from the grant without checking the signature (the aircraft does that).
  static bool grantStillValid(String grant, {DateTime? now}) {
    try {
      final body = grant.split('.').first;
      final json =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body))))
              as Map<String, dynamic>;
      final exp = (json['exp'] as num).toInt();
      return exp > (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return false;
    }
  }
}

/// Copy what the account holds into the on-phone profile. The seat only ever arrives this way.
void applyAccountToProfile(Profile p, Preferences? prefs, Trip? trip) {
  if (prefs != null) {
    if (languages.any((l) => l.code == prefs.displayLanguage))
      p.lang = prefs.displayLanguage;
    p.senior = prefs.senior;
    p.needs = prefs.needs.toSet();
  }
  if (trip != null) p.seat = trip.seat;
}

/// The preferences to save for the current profile, keeping the version and other-language list the account already has.
Preferences preferencesFromProfile(Profile p, Preferences? current) =>
    (current ?? Preferences(spokenLanguage: p.lang, displayLanguage: p.lang))
        .copyWith(
          spokenLanguage: p.lang,
          displayLanguage: p.lang,
          senior: p.senior,
          needs: p.needs.toList()..sort(),
        );
