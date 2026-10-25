import 'dart:async';

import 'package:flutter/material.dart';
import 'theme.dart';
import 'discover.dart';
import 'inflight.dart';
import 'kit.dart';
import 'repo.dart';
import 'session.dart';
import 'backend/backend_config.dart';

/// Phase 2 and 3: the phone looks for the aircraft network by itself, boards with the signed pass from the booking
/// (so the crew see the seat and preferences without anyone typing them), and opens the in-flight screens.
class CabinScreen extends StatefulWidget {
  final Profile profile;
  final PassengerRepo repo;

  /// Gives the app-wide cabin session for the profile's current seat (made on first use).
  final CabinSession Function() ensureSession;

  /// Replaceable in tests.
  final Future<CabinConnection> Function(List<String> hosts)? connector;
  final Duration retryEvery;
  const CabinScreen({
    super.key,
    required this.profile,
    required this.repo,
    required this.ensureSession,
    this.connector,
    this.retryEvery = const Duration(seconds: 5),
  });

  @override
  State<CabinScreen> createState() => _CabinScreenState();
}

class _CabinScreenState extends State<CabinScreen> {
  final manualAddress = TextEditingController();
  CabinConnection? connection;
  bool searching = false;
  bool showManual = false;
  Timer? timer;

  Profile get p => widget.profile;

  @override
  void initState() {
    super.initState();
    search();
    timer = Timer.periodic(widget.retryEvery, (_) {
      if (connection?.connected != true && !searching) search();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    if (!mounted) return;
    setState(() => searching = true);
    final hosts = defaultCabinHosts(
      lastGood: p.server.isEmpty ? null : p.server,
      fromQr: manualAddress.text.trim().isEmpty
          ? null
          : manualAddress.text.trim(),
      configured: cabinBackendOverride,
    );
    final result =
        await (widget.connector ??
            (h) => connectToCabin(
              hosts: h,
              getGrant: widget.repo.boardingGrant,
              deviceId: widget.repo.deviceId,
              bookedSeat: p.seat.isEmpty ? null : p.seat,
              useCommunicationBackend: true,
              displayName: 'Passenger ${p.seat}',
            ))(hosts);
    if (!mounted) return;
    setState(() {
      connection = result;
      searching = false;
    });
    if (result.connected) {
      p.server = result.baseUrl!;
      if (result.seat != null) p.seat = result.seat!;
      if (result.credentials != null)
        await widget.repo.saveCabinCredentials(result.credentials!);
      await p.save();
      // Open the live line to the crew. Calling this again after a reconnect simply restarts it.
      if (p.seat.isNotEmpty)
        widget.ensureSession().connect(
          result.baseUrl!,
          credentials: result.credentials,
        );
    }
  }

  void enter() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => InFlightScreen(session: widget.ensureSession()),
    ),
  );

  ({IconData icon, Color color, String title, String detail}) status() {
    final c = connection;
    if (searching && c == null)
      return (
        icon: Icons.wifi_find,
        color: Colors.orange,
        title: 'Looking for the cabin…',
        detail:
            'Connect to the aircraft Wi-Fi. This page keeps trying by itself.',
      );
    switch (c?.state) {
      case CabinState.ready:
        return (
          icon: Icons.check_circle,
          color: Colors.green,
          title:
              'Connected${c!.flight?.isNotEmpty == true ? ' to ${c.flight}' : ''} · seat ${c.seat ?? p.seat}',
          detail: 'The crew can see your language and needs.',
        );
      case CabinState.readyWithoutPass:
        return (
          icon: Icons.check_circle_outline,
          color: Colors.green,
          title: 'Connected to the cabin · seat ${c!.seat ?? p.seat}',
          detail:
              'No boarding pass was used, so your saved seat is shown. The crew still see your requests.',
        );
      case CabinState.noPass:
        return (
          icon: Icons.warning_amber,
          color: Colors.deepOrange,
          title: 'Cabin found, but no boarding pass',
          detail:
              'Open the app with internet once before the flight, on the "Before you fly" step, to get your pass.',
        );
      case CabinState.refused:
        return (
          icon: Icons.block,
          color: Colors.red,
          title: 'The cabin did not accept the pass',
          detail: c?.message ?? 'Ask the crew for help.',
        );
      case CabinState.seatTaken:
        return (
          icon: Icons.event_seat,
          color: Colors.red,
          title: 'Another phone is using your seat',
          detail: 'Please tell a crew member.',
        );
      case CabinState.unreachable:
        return (
          icon: Icons.wifi_off,
          color: Colors.deepOrange,
          title: 'The cabin did not answer',
          detail: c?.message ?? 'Trying again…',
        );
      default:
        return (
          icon: Icons.wifi_off,
          color: Colors.deepOrange,
          title: 'Cabin not found yet',
          detail:
              'Check you are on the aircraft Wi-Fi. Your cards and sign reader still work offline.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = status();
    final c = connection;
    return WashiPage(
      title: 'On the aircraft',
      kanji: '機内',
      petals: false,
      children: [
        StatusBanner(
          icon: s.icon,
          color: s.color,
          title: s.title,
          detail: s.detail,
          busy: searching,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: shuBright,
            minimumSize: const Size.fromHeight(60),
          ),
          onPressed: c?.connected == true ? enter : null,
          icon: const Icon(Icons.flight_rounded),
          label: const Text('Enter the cabin', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: searching ? null : search,
          child: const Text('Try again now'),
        ),
        if (c != null && !c.connected)
          TextButton(
            onPressed: () => setState(() => showManual = !showManual),
            child: Text(
              showManual
                  ? 'Hide the address box'
                  : 'Cabin not found? Enter the address from the crew',
            ),
          ),
        if (showManual)
          TextField(
            controller: manualAddress,
            decoration: const InputDecoration(
              labelText: 'Cabin address',
              helperText: 'Shown by the crew under the QR code',
            ),
          ),
      ],
    );
  }
}
