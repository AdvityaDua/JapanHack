import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/backend/communication_client.dart';
import 'package:hashi_mobile/cabin_link.dart';
import 'package:hashi_mobile/protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  test('pairs a passenger and creates an authenticated request', () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/devices/pair')) {
        return http.Response(
          jsonEncode({
            'device_id': 'device-1',
            'device_token': 'token-1',
            'flight_id': 'DEMO0001',
            'device_type': 'passenger',
            'seat_token': 'seat-token-1',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'request-1',
          'flight_id': 'DEMO0001',
          'passenger_device_id': 'device-1',
          'seat_token': 'seat-token-1',
          'seat_number': '24C',
          'passenger_language': 'ta',
          'category': 'water',
          'message': 'Water please',
          'urgency': 'normal',
          'status': 'created',
          'created_at': '2026-10-25T10:00:00Z',
          'updated_at': '2026-10-25T10:00:00Z',
        }),
        201,
      );
    });
    final client = CommunicationClient(
      'http://cabin.test:8001',
      client: httpClient,
    );
    final credentials = await client.pair(seat: '24C');
    final result = await client.createRequest(
      credentials: credentials,
      category: 'water',
      passengerLanguage: 'ta',
      idempotencyKey: 'idempotency-1',
      message: 'Water please',
    );

    expect(credentials.deviceId, 'device-1');
    expect(result['id'], 'request-1');
    expect(requests[1].headers['authorization'], 'Bearer token-1');
    expect(jsonDecode(requests[1].body)['seat_token'], 'seat-token-1');
  });

  test('builds the authenticated passenger WebSocket URI', () {
    final client = CommunicationClient('https://hashi-cabin.local:8001');
    final uri = client.websocketUri(
      const PairingCredentials(
        deviceId: 'device/1',
        deviceToken: 'token',
        flightId: 'flight',
        seatToken: 'seat',
      ),
    );
    expect(
      uri.toString(),
      'wss://hashi-cabin.local:8001/api/v1/ws/passenger/device%2F1?token=token',
    );
  });

  test(
    'uses the new HTTP passenger protocol for actions and cancellation',
    () async {
      final requests = <http.Request>[];
      final client = CommunicationClient(
        'http://cabin.test:8001',
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/cancel')) {
            return http.Response(
              jsonEncode({'id': 'request-1', 'status': 'cancelled'}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'id': 'action-1', 'action': 'profile_updated'}),
            200,
          );
        }),
      );
      const credentials = PairingCredentials(
        deviceId: 'device-1',
        deviceToken: 'token-1',
        flightId: 'DEMO0001',
        seatToken: 'seat-token-1',
      );

      await client.submitPassengerAction(
        credentials: credentials,
        action: 'profile_updated',
        payload: {'lang': 'ta'},
        idempotencyKey: 'action-key-1',
      );
      await client.cancelRequest(
        credentials: credentials,
        requestId: 'request-1',
        idempotencyKey: 'cancel-key-1',
      );

      expect(requests[0].url.path, '/api/v1/passenger/actions');
      expect(requests[0].headers['authorization'], 'Bearer token-1');
      expect(jsonDecode(requests[0].body)['action'], 'profile_updated');
      expect(
        requests[1].url.path,
        '/api/v1/passenger/requests/request-1/cancel',
      );
      expect(requests[1].method, 'PATCH');
    },
  );

  testWidgets('backend events update the existing passenger store', (
    tester,
  ) async {
    final credentials = const PairingCredentials(
      deviceId: 'device-1',
      deviceToken: 'token-1',
      flightId: 'DEMO0001',
      seatToken: 'seat-token-1',
    );
    final controller = StreamChannelController<dynamic>();
    final store = CabinStore('24C');
    final link = CabinLink(
      store,
      backend: CommunicationClient('http://cabin.test:8001'),
      factory: (_) => controller.local,
      pingEvery: Duration.zero,
    );
    link.start(
      'http://cabin.test:8001',
      () => {'lang': 'ta'},
      credentials: credentials,
    );
    await tester.pump();
    expect(store.link, LinkState.online);

    controller.foreign.sink.add(
      jsonEncode({
        'event_type': 'request.created',
        'aggregate_id': 'request-1',
        'payload': {
          'id': 'request-1',
          'category': 'water',
          'urgency': 'normal',
          'status': 'created',
          'created_at': '2026-10-25T10:00:00Z',
        },
      }),
    );
    await tester.pump();
    expect(store.requests['request-1']!.intent, 'water');
    expect(store.requests['request-1']!.status, RequestStatus.fresh);

    controller.foreign.sink.add(
      jsonEncode({
        'event_type': 'request.status_changed',
        'aggregate_id': 'request-1',
        'payload': {'status': 'in_progress'},
      }),
    );
    await tester.pump();
    expect(store.requests['request-1']!.status, RequestStatus.seen);

    controller.foreign.sink.add(
      jsonEncode({
        'event_type': 'message.created',
        'aggregate_id': 'request-1',
        'payload': {
          'id': 'message-1',
          'original': 'I will help you.',
          'status': 'sent',
        },
      }),
    );
    controller.foreign.sink.add(
      jsonEncode({
        'event_type': 'announcement.created',
        'aggregate_id': 'announcement-1',
        'payload': {
          'id': 'announcement-1',
          'custom': 'Please remain seated.',
          'texts': {'English': 'Please remain seated.'},
          'kind': 'info',
          'icon': 'Megaphone',
        },
      }),
    );
    await tester.pump();
    expect(store.thread.single.original, 'I will help you.');
    expect(store.announcements.single.custom, 'Please remain seated.');
    link.dispose();
  });
}
