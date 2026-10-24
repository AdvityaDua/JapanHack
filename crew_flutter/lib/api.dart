import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

class CrewApi {
  CrewApi(this.baseUrl);
  final String baseUrl;
  DeviceSession? session;
  WebSocketChannel? _socket;

  Future<DeviceSession> pair(String pairingCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/devices/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'device_type': 'crew',
        'display_name': 'Crew tablet',
        'pairing_code': pairingCode,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Pairing failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return session = DeviceSession(
      deviceId: data['device_id'].toString(),
      deviceToken: data['device_token'].toString(),
      flightId: data['flight_id'].toString(),
    );
  }

  Future<List<CrewRequest>> fetchRequests() async {
    if (session == null) {
      throw Exception('Pair the crew tablet first');
    }
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/crew/requests'),
      headers: _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Could not load requests (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List)
        .map((item) => CrewRequest.fromJson(item))
        .toList();
  }

  Future<Map<String, dynamic>> fetchSession() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/session/current'));
    if (response.statusCode != 200) {
      throw Exception('Could not load flight session (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<CrewRequest> updateStatus(CrewRequest request, String status) async {
    if (session == null) {
      throw Exception('Pair the crew tablet first');
    }
    final response = await http.patch(
      Uri.parse('$baseUrl/api/v1/crew/requests/${request.id}/status'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': status,
        'crew_device_id': session!.deviceId,
        'idempotency_key': 'flutter-${DateTime.now().microsecondsSinceEpoch}',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Status update failed (${response.statusCode})');
    }
    return CrewRequest.fromJson(jsonDecode(response.body));
  }

  Stream<Map<String, dynamic>> connectToEvents() {
    if (session == null) return const Stream.empty();
    final base = Uri.parse(
      '$baseUrl/api/v1/ws/crew/${session!.deviceId}?token=${Uri.encodeComponent(session!.deviceToken)}',
    );
    final socketUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
    );
    _socket = WebSocketChannel.connect(socketUri);
    _socket!.sink.add('ping');
    return _socket!.stream.map(
      (event) => jsonDecode(event as String) as Map<String, dynamic>,
    );
  }

  void dispose() => _socket?.sink.close();

  Map<String, String> _headers() => {
    'Authorization': 'Bearer ${session!.deviceToken}',
  };
}
