import 'dart:convert';

import 'package:http/http.dart' as http;

class CommunicationException implements Exception {
  final String message;
  final int? statusCode;
  const CommunicationException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class PairingCredentials {
  final String deviceId;
  final String deviceToken;
  final String flightId;
  final String? seatToken;

  const PairingCredentials({
    required this.deviceId,
    required this.deviceToken,
    required this.flightId,
    required this.seatToken,
  });

  factory PairingCredentials.fromJson(Map<String, dynamic> json) =>
      PairingCredentials(
        deviceId: json['device_id'] as String,
        deviceToken: json['device_token'] as String,
        flightId: json['flight_id'] as String,
        seatToken: json['seat_token'] as String?,
      );
}

/// HTTP boundary for the aircraft communication backend.
/// It intentionally knows nothing about Flutter widgets or the offline translator.
class CommunicationClient {
  final String baseUrl;
  final http.Client _http;

  CommunicationClient(this.baseUrl, {http.Client? client})
    : _http = client ?? http.Client();

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<PairingCredentials> pair({
    required String seat,
    String? displayName,
  }) async {
    final response = await _http
        .post(
          _uri('/api/v1/devices/pair'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_type': 'passenger',
            'display_name': displayName ?? 'Passenger $seat',
            'seat_number': seat,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw _error(response);
    return PairingCredentials.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> createRequest({
    required PairingCredentials credentials,
    required String category,
    required String passengerLanguage,
    required String idempotencyKey,
    String? message,
    String urgency = 'normal',
  }) async {
    final seatToken = credentials.seatToken;
    if (seatToken == null || seatToken.isEmpty) {
      throw const CommunicationException('Passenger has no seat token');
    }
    final response = await _http
        .post(
          _uri('/api/v1/passenger/requests'),
          headers: _headers(credentials.deviceToken),
          body: jsonEncode({
            'device_id': credentials.deviceId,
            'seat_token': seatToken,
            'category': category,
            'message': message,
            'passenger_language': passengerLanguage,
            'urgency': urgency,
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 201 && response.statusCode != 200)
      throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelRequest({
    required PairingCredentials credentials,
    required String requestId,
    required String idempotencyKey,
  }) async {
    final response = await _http
        .patch(
          _uri('/api/v1/passenger/requests/$requestId/cancel'),
          headers: _headers(credentials.deviceToken),
          body: jsonEncode({
            'status': 'cancelled',
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendPassengerMessage({
    required PairingCredentials credentials,
    required String requestId,
    required String text,
    String? translatedText,
    required String idempotencyKey,
  }) async {
    final response = await _http
        .post(
          _uri('/api/v1/passenger/requests/$requestId/messages'),
          headers: _headers(credentials.deviceToken),
          body: jsonEncode({
            'text': text,
            'translated_text': translatedText,
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201)
      throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitPassengerAction({
    required PairingCredentials credentials,
    required String action,
    String? requestId,
    Map<String, dynamic> payload = const {},
    required String idempotencyKey,
  }) async {
    final response = await _http
        .post(
          _uri('/api/v1/passenger/actions'),
          headers: _headers(credentials.deviceToken),
          body: jsonEncode({
            'action': action,
            'request_id': requestId,
            'payload': payload,
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201)
      throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> replayEvents({
    required PairingCredentials credentials,
    int afterSequence = 0,
  }) async {
    final response = await _http
        .get(
          _uri('/api/v1/events?after_sequence=$afterSequence'),
          headers: _headers(credentials.deviceToken),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw _error(response);
    return [
      for (final item in jsonDecode(response.body) as List)
        Map<String, dynamic>.from(item as Map),
    ];
  }

  Future<Map<String, dynamic>> sendCrewMessage({
    required String requestId,
    required String crewToken,
    required String text,
    String? translatedText,
    required String idempotencyKey,
  }) async {
    final response = await _http
        .post(
          _uri('/api/v1/crew/requests/$requestId/messages'),
          headers: _headers(crewToken),
          body: jsonEncode({
            'text': text,
            'translated_text': translatedText,
            'idempotency_key': idempotencyKey,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 && response.statusCode != 201)
      throw _error(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Uri websocketUri(PairingCredentials credentials) {
    final uri = _uri(
      '/api/v1/ws/passenger/${Uri.encodeComponent(credentials.deviceId)}',
    );
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      queryParameters: {'token': credentials.deviceToken},
    );
  }

  CommunicationException _error(http.Response response) {
    var detail =
        'Communication backend request failed (${response.statusCode})';
    try {
      final value = (jsonDecode(response.body) as Map)['detail'];
      if (value is String && value.isNotEmpty) detail = value;
    } catch (_) {}
    return CommunicationException(detail, statusCode: response.statusCode);
  }
}
