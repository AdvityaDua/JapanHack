import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'content.dart';
import 'decks.dart';
import 'languages.dart';
import 'kit.dart';
import 'protocol.dart';
import 'session.dart';
import 'theme.dart';

/// Watches the cabin and puts the right full-screen message in front of the passenger, wherever they are in the app:
/// a crew announcement (with sound and a buzz), the exit-row question, or the crew's "is everything OK?".
class OverlayCoordinator {
  final GlobalKey<NavigatorState> navigatorKey;
  OverlayCoordinator(this.navigatorKey);

  CabinSession? _session;
  bool _showing = false;
  final Set<String> _handledExit = {};
  bool _checkinShown = false;

  void attach(CabinSession session) {
    _session?.store.removeListener(_onChange);
    _session = session;
    session.store.addListener(_onChange);
    _onChange();
  }

  void detach() {
    _session?.store.removeListener(_onChange);
    _session = null;
  }

  void _onChange() {
    final s = _session;
    if (s == null || _showing) return;
    if (s.store.checkin == null) _checkinShown = false;
    final WidgetBuilder? screen = _next(s);
    final nav = navigatorKey.currentState;
    if (screen == null || nav == null) return;
    _showing = true;
    // never push while the framework is still building
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await nav.push(
        MaterialPageRoute<void>(fullscreenDialog: true, builder: screen),
      );
      _showing = false;
      _onChange();
    });
  }

  WidgetBuilder? _next(CabinSession s) {
    final store = s.store;
    if (store.announcements.isNotEmpty) {
      final a = store.announcements.first;
      return (_) => AnnouncementScreen(announcement: a, session: s);
    }
    final x = store.exitCheck;
    if (x != null &&
        x.open &&
        x.seatStates[s.profile.seat] == 'waiting' &&
        !_handledExit.contains(x.id)) {
      _handledExit.add(x.id);
      return (_) => ExitCheckScreen(check: x, session: s);
    }
    final c = store.checkin;
    if (c != null && c.answer == null && !_checkinShown) {
      _checkinShown = true;
      return (_) => CheckinScreen(session: s);
    }
    return null;
  }
}

class _Overlay extends StatelessWidget {
  final Color background;
  final Widget child;
  const _Overlay({required this.background, required this.child});

  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        false, // the passenger answers; the screen is not swiped away by accident
    child: Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    ),
  );
}

/// A crew announcement: big icon, the words in the passenger's language, sound, and the "I understood" button the crew can see.
class AnnouncementScreen extends StatefulWidget {
  final Announcement announcement;
  final CabinSession session;
  const AnnouncementScreen({
    super.key,
    required this.announcement,
    required this.session,
  });

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  String? translated;
  bool translating = false;
  String? translationError;
  String get lang => widget.session.profile.lang;
  Announcement get a => widget.announcement;

  AnnouncementDef? get phrase =>
      a.phrase == null ? null : Content.instance.announcements[a.phrase];

  String get sourceWords =>
      phrase?.say(a.sourceLanguage) ??
      a.custom ??
      a.texts[a.sourceLanguage] ??
      '';
  String get words => phrase != null
      ? phrase!.say(lang)
      : translated ?? a.texts[lang] ?? a.custom ?? '';

  Future<void> play() {
    final p = phrase;
    return p != null
        ? playClip('ann_${p.id}_$lang.mp3', words, lang)
        : speakText(words, langByCode(lang).tts);
  }

  Future<void> _translateAnnouncement() async {
    if (phrase != null || a.sourceLanguage == lang || a.texts[lang] != null) {
      if (mounted)
        setState(
          () => translated = phrase?.say(lang) ?? a.texts[lang] ?? a.custom,
        );
      return;
    }
    if (mounted)
      setState(() {
        translating = true;
        translationError = null;
      });
    try {
      final from = a.sourceLanguage == 'ja'
          ? TranslateLanguage.japanese
          : langByCode(a.sourceLanguage).ml;
      final to = langByCode(lang).ml;
      if (from == null || to == null) {
        throw StateError(
          'This language is not available for offline translation yet.',
        );
      }
      final result = await Kit.translate(sourceWords, from, to);
      if (result == null)
        throw StateError('Required language model is not downloaded.');
      if (mounted)
        setState(() {
          translated = result;
          translating = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          translating = false;
          translationError = e.toString().replaceFirst('Bad state: ', '');
        });
    }
  }

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _translateAnnouncement().then((_) => play());
  }

  @override
  Widget build(BuildContext context) {
    final t = Content.instance.t;
    final senior = widget.session.profile.senior;
    return _Overlay(
      background: a.kind == 'safety' ? aiDeep : ai,
      child: Column(
        children: [
          Text(
            t(lang, 'announcement'),
            style: const TextStyle(
              color: kin,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      flightIcon(a.icon),
                      color: kin,
                      size: senior ? 120 : 92,
                    ),
                    const SizedBox(height: 22),
                    if (translating)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: CircularProgressIndicator(color: kin),
                      ),
                    Text(
                      words,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: senior ? 30 : 26,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    if (phrase == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          translationError ??
                              'Translated on your device from ${a.sourceLanguage}',
                          style: const TextStyle(
                            color: Color(0xFFD5DBF0),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70, width: 1.4),
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: play,
            icon: const Icon(Icons.volume_up_rounded),
            label: Text(t(lang, 'play')),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: good,
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: () {
              widget.session.link.acknowledge(a.id);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.verified_rounded),
            label: Text(
              t(lang, 'understood'),
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exit-row teach-back: willing and able, then when do you open the door.
class ExitCheckScreen extends StatefulWidget {
  final ExitCheck check;
  final CabinSession session;
  const ExitCheckScreen({
    super.key,
    required this.check,
    required this.session,
  });

  @override
  State<ExitCheckScreen> createState() => _ExitCheckScreenState();
}

class _ExitCheckScreenState extends State<ExitCheckScreen> {
  int step = 0; // 0 willing?, 1 when do you open it?, 2 thanks

  String get lang => widget.session.profile.lang;
  String t(String k) => Content.instance.t(lang, k);

  void answerWilling(bool yes) {
    if (yes) {
      setState(() => step = 1);
    } else {
      widget.session.link.answerExit(widget.check.id, willing: false);
      setState(() => step = 2);
    }
  }

  void answerWhen(String code) {
    widget.session.link.answerExit(
      widget.check.id,
      willing: true,
      answer: code,
    );
    setState(() => step = 2);
  }

  @override
  Widget build(BuildContext context) {
    final big = const TextStyle(
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );
    return _Overlay(
      background: aiDeep,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.door_front_door_rounded, color: kin),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('exitTitle'),
                  style: const TextStyle(
                    color: kin,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (step == 0) ...[
                      Text(
                        t('exitIntro'),
                        style: const TextStyle(
                          color: Color(0xFFD5DBF0),
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(t('exitQ1'), style: big),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: good,
                          minimumSize: const Size.fromHeight(60),
                        ),
                        onPressed: () => answerWilling(true),
                        child: Text(
                          t('yes'),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          minimumSize: const Size.fromHeight(60),
                        ),
                        onPressed: () => answerWilling(false),
                        child: Text(
                          t('no'),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ],
                    if (step == 1) ...[
                      Text(t('exitQ2'), style: big),
                      const SizedBox(height: 22),
                      for (final o in const [
                        ('exitA1', 'when_told'),
                        ('exitA2', 'immediately'),
                        ('exitA3', 'dont_know'),
                      ]) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(
                              color: Colors.white70,
                              width: 1.4,
                            ),
                            minimumSize: const Size.fromHeight(60),
                            padding: const EdgeInsets.all(14),
                          ),
                          onPressed: () => answerWhen(o.$2),
                          child: Text(
                            t(o.$1),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (step == 2) ...[
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF9BD08F),
                        size: 80,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t('exitThanks'),
                        textAlign: TextAlign.center,
                        style: big,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kin,
                          foregroundColor: aiDeep,
                          minimumSize: const Size.fromHeight(60),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK', style: TextStyle(fontSize: 20)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The crew's check-in: "Is everything OK?" with two big answers.
class CheckinScreen extends StatelessWidget {
  final CabinSession session;
  const CheckinScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final words = Content.instance.checkinWords(session.profile.lang);
    void answer(String a) {
      session.link.answerCheckin(a);
      Navigator.pop(context);
    }

    return _Overlay(
      background: ai,
      child: Column(
        children: [
          const Icon(Icons.favorite_rounded, color: sakura, size: 64),
          Expanded(
            child: Center(
              child: Text(
                words[0],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: good,
              minimumSize: const Size.fromHeight(72),
            ),
            onPressed: () => answer('fine'),
            icon: const Icon(Icons.thumb_up_rounded),
            label: Text(words[1], style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: shuBright,
              minimumSize: const Size.fromHeight(72),
            ),
            onPressed: () => answer('call'),
            icon: const Icon(Icons.record_voice_over_rounded),
            label: Text(words[2], style: const TextStyle(fontSize: 22)),
          ),
        ],
      ),
    );
  }
}
