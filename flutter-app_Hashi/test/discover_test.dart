import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/discover.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int code = 200]) => http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

typedef Handler = http.Response Function(http.Request);

/// [routes] maps "host+path" to a handler. A host that appears in no route behaves like an unreachable one.
MockClient fake(Map<String, Handler> routes, {List<String>? log}) => MockClient((r) async {
      final key = '${r.url.host}${r.url.path}';
      log?.add('${r.method} $key');
      final h = routes[key];
      if (h == null) {
        if (routes.keys.any((k) => k.startsWith(r.url.host))) return http.Response('nope', 404);
        throw http.ClientException('unreachable');
      }
      return h(r);
    });

final cabinPing = json({'service': 'hashi-cabin', 'flight': 'JL740', 'version': '0.1.0'});

void main() {
  group('host list', () {
    test('goes name first, then fallbacks, then the QR address, without repeats', () {
      final hosts = defaultCabinHosts(fromQr: 'http://10.0.0.5:8000/', lastGood: 'http://hashi-cabin.local:8000');
      expect(hosts, ['http://hashi-cabin.local:8000', 'http://hashi.cabin:8000', 'http://192.168.137.1:8000', 'http://10.0.0.5:8000']);
    });

    test('puts the last host that worked first', () {
      expect(defaultCabinHosts(lastGood: 'http://192.168.137.1:8000').first, 'http://192.168.137.1:8000');
    });
  });

  group('discovery', () {
    test('falls through unreachable hosts to the one that answers', () async {
      final log = <String>[];
      final d = Discovery(client: fake({'192.168.137.1/api/ping': (_) => cabinPing}, log: log));
      final info = await d.find(defaultCabinHosts());
      expect(info!.baseUrl, 'http://192.168.137.1:8000');
      expect(info.flight, 'JL740');
      expect(log.first, 'GET hashi-cabin.local/api/ping'); // the name is tried first
    });

    test('a host that answers 200 with the wrong body is not the cabin', () async {
      final d = Discovery(client: fake({
        'hashi-cabin.local/api/ping': (_) => json({'service': 'captive-portal'}),
        '192.168.137.1/api/ping': (_) => cabinPing,
      }));
      expect((await d.find(defaultCabinHosts()))!.baseUrl, 'http://192.168.137.1:8000');
    });

    test('an HTML page (portal login) is rejected', () async {
      final d = Discovery(client: fake({'hashi-cabin.local/api/ping': (_) => http.Response('<html>login</html>', 200)}));
      expect(await d.find(['http://hashi-cabin.local:8000']), isNull);
    });

    test('an older cabin server without /api/ping is recognised by its health page', () async {
      final d = Discovery(client: fake({'192.168.137.1/api/health': (_) => json({'ok': true, 'version': '0.1.0', 'asr': 'x', 'crew_connected': 0})}));
      expect((await d.find(['http://192.168.137.1:8000']))!.baseUrl, 'http://192.168.137.1:8000');
    });

    test('an unrelated server with a health page is not the cabin', () async {
      final d = Discovery(client: fake({'192.168.137.1/api/health': (_) => json({'ok': true})}));
      expect(await d.find(['http://192.168.137.1:8000']), isNull);
    });

    test('a cabin running https is found too (self-signed certificates are expected on the aircraft network)', () async {
      final log = <String>[];
      final c = MockClient((r) async {
        log.add(r.url.toString());
        if (r.url.scheme == 'https' && r.url.host == '192.168.137.1') return cabinPing;
        throw http.ClientException('no');
      });
      final info = await Discovery(client: c).find(['http://192.168.137.1:8000']);
      expect(info!.baseUrl, 'https://192.168.137.1:8000');
      expect(log, containsAll(['http://192.168.137.1:8000/api/ping', 'https://192.168.137.1:8000/api/ping']));
    });

    test('all addresses are checked together, so one dead name does not delay the answer', () async {
      final c = MockClient((r) async {
        if (r.url.host == 'hashi-cabin.local') await Future.delayed(const Duration(milliseconds: 400));
        if (r.url.host == '192.168.137.1' && r.url.scheme == 'http') return cabinPing;
        throw http.ClientException('no');
      });
      final watch = Stopwatch()..start();
      final info = await Discovery(client: c, timeout: const Duration(seconds: 2)).find(defaultCabinHosts());
      expect(info!.baseUrl, 'http://192.168.137.1:8000');
      expect(watch.elapsedMilliseconds, lessThan(1500));
    });

    test('nothing reachable gives null, and a slow host is skipped', () async {
      expect(await Discovery(client: fake({})).find(defaultCabinHosts()), isNull);
      final slow = MockClient((r) => Future.delayed(const Duration(milliseconds: 300), () => cabinPing));
      expect(await Discovery(client: slow, timeout: const Duration(milliseconds: 20)).find(['http://hashi-cabin.local:8000']), isNull);
    });
  });

  group('boarding', () {
    test('sends the pass and device id, and takes the seat from the answer', () async {
      late Map<String, dynamic> sent;
      final c = fake({
        'cabin.test/api/board': (r) {
          sent = jsonDecode(r.body);
          return json({'seat': '24C', 'flight': 'JL740'});
        }
      });
      final res = await boardCabin('http://cabin.test:8000', 'GRANT', 'phone-1', client: c);
      expect(res.ok, true);
      expect(res.seat, '24C');
      expect(sent, {'grant': 'GRANT', 'device_id': 'phone-1'}); // no seat is ever sent
    });

    test('maps each failure to a clear outcome', () async {
      Future<BoardOutcome> outcome(int code) async => (await boardCabin('http://cabin.test', 'G', 'd', client: fake({'cabin.test/api/board': (_) => json({'detail': 'why'}, code)}))).outcome;
      expect(await outcome(403), BoardOutcome.refused);
      expect(await outcome(409), BoardOutcome.seatTaken);
      expect(await outcome(404), BoardOutcome.unsupported);
      expect(await outcome(500), BoardOutcome.unreachable);
      expect((await boardCabin('http://nowhere.test', 'G', 'd', client: fake({}))).outcome, BoardOutcome.unreachable);
    });
  });

  group('connectToCabin', () {
    Future<CabinConnection> run(Map<String, Handler> routes, {String? grant = 'G', String? seat = '24C'}) =>
        connectToCabin(hosts: ['http://cabin.test:8000'], getGrant: () async => grant, deviceId: 'phone-1', bookedSeat: seat, client: fake(routes));

    final Map<String, Handler> ping = {'cabin.test/api/ping': (_) => cabinPing};

    test('cabin not found', () async => expect((await run({})).state, CabinState.notFound));

    test('found and boarded: the seat is the one the cabin confirmed', () async {
      final c = await run({...ping, 'cabin.test/api/board': (_) => json({'seat': '31K', 'flight': 'JL740'})});
      expect(c.state, CabinState.ready);
      expect(c.seat, '31K');
      expect(c.flight, 'JL740');
      expect(c.connected, true);
    });

    test('no pass on the phone: does not call board, says so', () async {
      final log = <String>[];
      final c = await connectToCabin(hosts: ['http://cabin.test:8000'], getGrant: () async => null, deviceId: 'd', client: fake(ping, log: log));
      expect(c.state, CabinState.noPass);
      expect(c.connected, false);
      expect(log.any((l) => l.contains('board')), false);
    });

    test('no pass but a saved seat: still joins, using that seat', () async {
      final c = await connectToCabin(hosts: ['http://cabin.test:8000'], getGrant: () async => null, deviceId: 'd', bookedSeat: '24C', client: fake(ping));
      expect(c.state, CabinState.readyWithoutPass);
      expect(c.seat, '24C');
    });

    test('an older cabin without /api/board still connects using the booked seat', () async {
      final c = await run(ping);
      expect(c.state, CabinState.readyWithoutPass);
      expect(c.seat, '24C');
      expect(c.connected, true);
    });

    test('refused and seat-taken are not treated as connected', () async {
      expect((await run({...ping, 'cabin.test/api/board': (_) => json({'detail': 'bad'}, 403)})).connected, false);
      expect((await run({...ping, 'cabin.test/api/board': (_) => json({'detail': 'taken'}, 409)})).state, CabinState.seatTaken);
    });
  });
}
