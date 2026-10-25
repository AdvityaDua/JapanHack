import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'content.dart';
import 'hubs.dart';
import 'inflight.dart';
import 'kit.dart';
import 'languages.dart';
import 'overlays.dart';
import 'preflight.dart';
import 'repo.dart';
import 'asrbench.dart';
import 'selftest.dart';
import 'session.dart';
import 'settings.dart';
import 'theme.dart';

/// Lets the cabin put announcements and checks in front of the passenger on whatever screen they are on.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Content.load();
  runApp(const HashiApp());
  if (asrBenchEnabled) {
    unawaited(runAsrBench());
  } else if (selfTestEnabled) {
    unawaited(runSelfTest());
  }
}

class HashiApp extends StatelessWidget {
  /// Tests pass their own home screen; the app itself uses [Home].
  final Widget? home;
  const HashiApp({super.key, this.home});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: seniorMode,
        builder: (_, senior, _) => MaterialApp(
          title: 'HASHI',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: buildTheme(),
          // Senior mode makes every piece of text a quarter bigger
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(senior ? 1.25 : 1.0)), child: child!),
          home: home ?? const Home(),
        ),
      );
}

/// The passenger's journey from home to Japan: before you fly, on the aircraft, after landing.
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  Profile? profile;
  PassengerRepo? repo;
  CabinSession? session;
  late final OverlayCoordinator overlays = OverlayCoordinator(navigatorKey);
  late final AnimationController plane = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    Profile.load().then((p) async {
      seniorMode.value = p.senior;
      calmMotion.value = p.calm;
      final r = await PassengerRepo.open(p.central);
      applyAccountToProfile(p, r.preferences, r.trip);
      if (mounted) setState(() { profile = p; repo = r; });
      // pick up changes made elsewhere when there is a signal; silent when there is none
      if (await r.refresh() && mounted) {
        setState(() => applyAccountToProfile(p, r.preferences, r.trip));
        seniorMode.value = p.senior;
      }
    });
  }

  /// The one live session for the passenger's seat. Made on first use, and again if the seat changes (a new booking).
  CabinSession ensureSession() {
    final p = profile!;
    var s = session;
    if (s == null || s.store.seat != p.seat) {
      s?.dispose();
      s = session = CabinSession.forProfile(p);
      overlays.attach(s);
    }
    return s;
  }

  /// The in-flight screens need the seat from the booking, so without one the passenger is sent to their booking first.
  Future<void> openInFlight() async {
    final p = profile!;
    final r = repo!;
    if (p.seat.isEmpty) {
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.event_seat_rounded, color: ai, size: 36),
          title: const Text('Your seat comes from your booking'),
          content: const Text('Sign in under "Before flight" to load your booking. Speaking and translating work without it.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open my booking')),
          ],
        ),
      );
      if (open == true && mounted) go(PreflightScreen(profile: p, repo: r));
      return;
    }
    go(InFlightScreen(session: ensureSession(), repo: r));
  }

  @override
  void dispose() {
    overlays.detach();
    session?.dispose();
    plane.dispose();
    super.dispose();
  }

  void go(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)).then((_) {
        if (mounted) setState(() {});
        if (profile != null) { seniorMode.value = profile!.senior; calmMotion.value = profile!.calm; }
      });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final r = repo;
    if (p == null || r == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: ai)));
    final animate = motionAllowed(context);
    if (animate && !plane.isAnimating) plane.repeat();
    if (!animate && plane.isAnimating) plane.stop();
    final l = langByCode(p.lang);
    final trip = r.trip;

    final stops = <_Stop>[
      _Stop('一', Icons.luggage_rounded, 'Before flight', 'Booking, language kit, cards for the airport, speak', () => go(BeforeHub(profile: p, repo: r)), kanji: '出発前'),
      _Stop('二', Icons.flight_rounded, 'In flight', 'Talk to the crew, picture cards, speak and translate', openInFlight, kanji: '機内'),
      _Stop('三', Icons.travel_explore_rounded, 'After flight', 'Read signs, show cards to staff, speak and translate', () => go(AfterHub(profile: p)), kanji: '到着後', tint: kinSoft),
    ];

    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [washi, Color(0xFFF1EADB)])))),
        const Positioned(top: 0, left: 0, right: 0, height: 220, child: CustomPaint(painter: SeigaihaPainter())),
        if (animate) const Positioned.fill(child: IgnorePointer(child: SakuraDrift(count: 16))),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 30), children: [
            Row(children: [
              const Hanko('橋', size: 52),
              const SizedBox(width: 14),
              const Expanded(child: Text('HASHI', style: TextStyle(fontFamily: serifFont, fontSize: 34, fontWeight: FontWeight.w900, color: aiDeep, letterSpacing: 3))),
              IconButton.filledTonal(tooltip: 'Settings', style: IconButton.styleFrom(minimumSize: const Size(48, 48), backgroundColor: Colors.white), icon: const Icon(Icons.tune_rounded, color: ai), onPressed: () => go(SettingsScreen(profile: p, repo: r, session: session))),
            ]),
            const SizedBox(height: 10),
            const Text("Don't translate. Understand.", style: TextStyle(fontFamily: serifFont, fontSize: 21, fontStyle: FontStyle.italic, color: sumiSoft)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Chip(Icons.event_seat_rounded, p.seat.isEmpty ? 'Seat comes from your booking' : 'Seat ${p.seat}'),
              if (trip != null) _Chip(Icons.flight_takeoff_rounded, '${trip.flightNumber} · ${trip.from} → ${trip.to}'),
              _Chip(Icons.translate_rounded, l.name),
              if (p.senior) const _Chip(Icons.zoom_in_rounded, 'Bigger text'),
            ]),
            const SizedBox(height: 18),
            Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _JourneyLine(plane))),
              Column(children: [for (var i = 0; i < stops.length; i++) _StopTile(stop: stops[i], index: i)]),
            ]),
            const SizedBox(height: 10),
            const Text('Your data stays on this phone. Nothing is sent anywhere unless you join the cabin network.', style: TextStyle(color: sumiSoft, fontSize: 14, height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

class _Stop {
  final String numeral;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String kanji;
  final Color tint;
  _Stop(this.numeral, this.icon, this.title, this.subtitle, this.onTap, {required this.kanji, this.tint = Colors.white});
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(22), border: Border.all(color: ai.withValues(alpha: 0.15))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18, color: ai), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sumi))]),
      );
}

class _StopTile extends StatelessWidget {
  final _Stop stop;
  final int index;
  const _StopTile({required this.stop, required this.index});

  @override
  Widget build(BuildContext context) {
    return Entrance(
      index: index,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(width: 44, child: Center(child: Hanko(stop.numeral, size: 34, color: ai, turns: 0))),
            const SizedBox(width: 10),
            Expanded(
              child: PaperCard(
                color: stop.tint,
                onTap: stop.onTap,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: Row(children: [
                  Icon(stop.icon, color: ai, size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(stop.kanji, style: const TextStyle(fontFamily: serifFont, fontSize: 14, fontWeight: FontWeight.w900, color: shu, letterSpacing: 2)),
                      Text(stop.title, style: const TextStyle(fontFamily: serifFont, fontSize: 24, fontWeight: FontWeight.w800, color: aiDeep)),
                      const SizedBox(height: 2),
                      Text(stop.subtitle, style: const TextStyle(fontSize: 15, color: sumiSoft, height: 1.3)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: sumiSoft),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The dotted road down the left edge, with a little plane gliding along it.
class _JourneyLine extends CustomPainter {
  final Animation<double> t;
  _JourneyLine(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    const x = 22.0;
    final dash = Paint()..color = ai.withValues(alpha: 0.28)..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    for (var y = 6.0; y < size.height - 6; y += 12) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 5), dash);
    }
    final y = 10 + t.value * (size.height - 40);
    final edge = math.min(1.0, math.min(t.value * 8, (1 - t.value) * 8));
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(Icons.flight_rounded.codePoint), style: TextStyle(fontFamily: Icons.flight_rounded.fontFamily, package: Icons.flight_rounded.fontPackage, fontSize: 26, color: shuBright.withValues(alpha: edge))),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(math.pi); // nose pointing down the path
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JourneyLine old) => false;
}
