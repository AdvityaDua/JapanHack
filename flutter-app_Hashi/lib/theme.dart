import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The whole look of the app lives here: colours, type, motion and the little drawn pieces (sakura, waves, hanko seal).
/// Everything is painted in code, so there are no image files to ship and it works offline.

// ---- Colours (Japanese traditional names) ----
const washi = Color(0xFFF6F1E7); // paper
const washiDeep = Color(0xFFEDE4D3);
const sumi = Color(0xFF1B1B1F); // ink
const sumiSoft = Color(0xFF4A4A55);
const ai = Color(0xFF1F2F5C); // indigo
const aiDeep = Color(0xFF0E1A3A);
const shu = Color(0xFFB3341F); // vermilion (dark enough for text on washi)
const shuBright = Color(0xFFD03C26); // vermilion for seals and fills
const kin = Color(0xFFC9A227); // gold
const kinSoft = Color(0xFFF3E3A6);
const sakura = Color(0xFFF2B8C6);
const matcha = Color(0xFF3F6B36);

// Old names still used by older screens
const navy = aiDeep;
const saffron = Color(0xFFF59E1B);
const paper = washi;
const good = matcha;
const warn = Color(0xFF8F4300);
const bad = shu;

const gap = 14.0;
const radius = 18.0;

/// Set by the profile: bigger text, bigger touch targets, calmer motion.
final seniorMode = ValueNotifier<bool>(false);

/// Passengers who dislike movement (or the phone's own "remove animations" setting) get a still screen.
final calmMotion = ValueNotifier<bool>(false);

bool motionAllowed(BuildContext context) => !calmMotion.value && !MediaQuery.of(context).disableAnimations;

const serifFont = 'serif'; // Android's serif has Mincho-style Japanese glyphs, which suits headings

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: ai, primary: ai, secondary: shu, surface: washi, brightness: Brightness.light);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: washi,
    textTheme: Typography.blackMountainView.apply(bodyColor: sumi, displayColor: sumi),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, foregroundColor: sumi, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ai,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 52), foregroundColor: ai, side: const BorderSide(color: ai, width: 1.4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: ai, minimumSize: const Size(48, 48))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: washiDeep)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: washiDeep)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: ai,
      secondarySelectedColor: ai,
      labelStyle: const TextStyle(color: sumi, fontSize: 16),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 16),
      checkmarkColor: Colors.white,
      side: const BorderSide(color: washiDeep),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: _InkTransitions(), TargetPlatform.iOS: _InkTransitions()}),
  );
}

/// New screens fade in while rising a little, like ink settling on paper.
class _InkTransitions extends PageTransitionsBuilder {
  const _InkTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(opacity: curved, child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved), child: child));
  }
}

// ---- Page frame ----

/// A page on washi paper: faint waves at the top, optional drifting sakura, a tidy header.
class WashiPage extends StatelessWidget {
  final String title;
  final String? kanji; // small Japanese subtitle shown beside the title
  final List<Widget> children;
  final List<Widget> actions;
  final bool petals;
  final EdgeInsets padding;
  final Widget? bottom;
  const WashiPage({super.key, required this.title, this.kanji, required this.children, this.actions = const [], this.petals = false, this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 28), this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: _PaperBackground()),
        if (petals && motionAllowed(context)) const Positioned.fill(child: IgnorePointer(child: SakuraDrift())),
        SafeArea(
          child: Column(children: [
            _Header(title: title, kanji: kanji, actions: actions, canPop: Navigator.of(context).canPop()),
            Expanded(child: ListView(padding: padding, children: children)),
            ?bottom,
          ]),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? kanji;
  final List<Widget> actions;
  final bool canPop;
  const _Header({required this.title, required this.kanji, required this.actions, required this.canPop});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Row(children: [
          if (canPop) IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back_ios_new_rounded, color: ai), onPressed: () => Navigator.maybePop(context)) else const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (kanji != null) Text(kanji!, style: const TextStyle(fontFamily: serifFont, fontSize: 13, color: shu, letterSpacing: 2, fontWeight: FontWeight.w700)),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: serifFont, fontSize: 26, fontWeight: FontWeight.w800, color: aiDeep, height: 1.15)),
            ]),
          ),
          ...actions,
        ]),
      );
}

class _PaperBackground extends StatelessWidget {
  const _PaperBackground();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [washi, Color(0xFFF1EADB)])),
        child: Align(alignment: Alignment.topCenter, child: SizedBox(height: 190, width: double.infinity, child: CustomPaint(painter: SeigaihaPainter()))),
      );
}

// ---- Drawn artwork ----

/// Seigaiha: the overlapping-wave pattern, very faint, fading out downwards.
class SeigaihaPainter extends CustomPainter {
  const SeigaihaPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const r = 26.0;
    final rows = (size.height / (r * 0.5)).ceil() + 1;
    final cols = (size.width / (r * 2)).ceil() + 2;
    for (var row = rows; row >= 0; row--) {
      final fade = (1 - row / rows).clamp(0.0, 1.0);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = ai.withValues(alpha: 0.07 * fade);
      for (var col = -1; col < cols; col++) {
        final cx = col * r * 2 + (row.isOdd ? r : 0);
        final cy = row * r * 0.5;
        for (var k = 3; k >= 1; k--) {
          canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r * k / 3), math.pi, math.pi, false, stroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// A red hanko (name seal) with a character in it. Used as a stamp: step numbers, status, the HASHI mark.
class Hanko extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final double turns;
  const Hanko(this.text, {super.key, this.size = 44, this.color = shuBright, this.turns = -0.012});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: turns * 2 * math.pi,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.18), boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]),
          child: Container(
            width: size * 0.82,
            height: size * 0.82,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.2), borderRadius: BorderRadius.circular(size * 0.12)),
            child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontFamily: serifFont, color: Colors.white, fontSize: text.length > 1 ? size * 0.3 : size * 0.52, fontWeight: FontWeight.w900, height: 1.05)),
          ),
        ),
      );
}

/// Sakura petals drifting down. A few dozen petals, each with its own speed and sway; one controller drives them all.
class SakuraDrift extends StatefulWidget {
  final int count;
  const SakuraDrift({super.key, this.count = 14});
  @override
  State<SakuraDrift> createState() => _SakuraDriftState();
}

class _SakuraDriftState extends State<SakuraDrift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  late final List<_Petal> _petals = List.generate(widget.count, (i) => _Petal(math.Random(i * 97 + 3)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _PetalPainter(_petals, _c.value)));
}

class _Petal {
  final double x, speed, sway, phase, size, spin;
  _Petal(math.Random r)
      : x = r.nextDouble(),
        speed = 0.6 + r.nextDouble() * 1.1,
        sway = 12 + r.nextDouble() * 26,
        phase = r.nextDouble(),
        size = 7 + r.nextDouble() * 7,
        spin = (r.nextDouble() - 0.5) * 6;
}

class _PetalPainter extends CustomPainter {
  final List<_Petal> petals;
  final double t;
  _PetalPainter(this.petals, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in petals) {
      final progress = ((t * p.speed * 2) + p.phase) % 1.0;
      final y = -20 + progress * (size.height + 40);
      final x = p.x * size.width + math.sin(progress * math.pi * 2 + p.phase * 6) * p.sway;
      final fadeEdge = math.min(1.0, math.min(progress * 6, (1 - progress) * 6));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * p.spin * math.pi);
      final path = Path()
        ..moveTo(0, -p.size)
        ..cubicTo(p.size * 0.9, -p.size * 0.9, p.size * 0.7, p.size * 0.6, 0, p.size)
        ..cubicTo(-p.size * 0.7, p.size * 0.6, -p.size * 0.9, -p.size * 0.9, 0, -p.size)
        ..close();
      canvas.drawPath(path, Paint()..color = sakura.withValues(alpha: 0.55 * fadeEdge));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PetalPainter old) => old.t != t;
}

// ---- Interaction pieces ----

/// Shrinks a little while pressed, then springs back.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  const Pressable({super.key, required this.child, this.onTap, this.label});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: widget.onTap != null,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTapUp: (_) => setState(() => down = false),
          onTap: widget.onTap,
          child: AnimatedScale(scale: down && motionAllowed(context) ? 0.97 : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child),
        ),
      );
}

/// Slides and fades its child in after [index] steps, so a list settles in one card at a time.
class Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const Entrance({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!motionAllowed(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index.clamp(0, 8) * 70),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 18), child: c)),
      child: child,
    );
  }
}

/// A paper card with a thin indigo edge and an optional coloured spine on the left.
class PaperCard extends StatelessWidget {
  final Widget child;
  final Color? spine;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color color;
  const PaperCard({super.key, required this.child, this.spine, this.onTap, this.padding = const EdgeInsets.all(16), this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ai.withValues(alpha: 0.12)),
        boxShadow: [BoxShadow(color: aiDeep.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      // The coloured spine is drawn beside the content (not with IntrinsicHeight, which breaks around QR codes and other builders)
      child: Stack(children: [
        Padding(padding: EdgeInsets.only(left: spine != null ? 6 : 0), child: Padding(padding: padding, child: child)),
        if (spine != null) Positioned(left: 0, top: 0, bottom: 0, width: 6, child: ColoredBox(color: spine!)),
      ]),
    );
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}

/// A banner that says what is happening: an icon (or spinner), a title and one line of detail. Never colour alone.
class StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool busy;
  const StatusBanner({super.key, required this.icon, required this.color, required this.title, required this.detail, this.busy = false});

  @override
  Widget build(BuildContext context) => PaperCard(
        spine: color,
        child: Row(children: [
          busy ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: ai)) : Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: sumi)),
            const SizedBox(height: 2),
            Text(detail, style: const TextStyle(fontSize: 15, color: sumiSoft, height: 1.3)),
          ])),
        ]),
      );
}

/// Section heading with a numbered hanko, used on forms and flows.
class SectionTitle extends StatelessWidget {
  final String number;
  final String text;
  const SectionTitle(this.number, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [Hanko(number, size: 34), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontFamily: serifFont, fontSize: 20, fontWeight: FontWeight.w800, color: aiDeep)))]),
      );
}

/// Contrast ratio of two colours (WCAG). Used by tests to keep text readable.
double contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
