import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engines.dart';
import 'languages.dart';

/// Who is speaking: the passenger (their own language, to Japanese) or the other person (Japanese, to the passenger's language).
enum Side { me, them }

/// One thing that was said, with how long each step took.
class Turn {
  final Side side;
  final String original;
  final String? translated;
  final String fromLang;
  final String toLang;

  /// Time from the end of speech to the translation being ready.
  final Duration? translateTime;
  const Turn({
    required this.side,
    required this.original,
    required this.translated,
    required this.fromLang,
    required this.toLang,
    this.translateTime,
  });
}

/// Runs a spoken or typed conversation: listens, shows the words and their translation as they appear, speaks the
/// translation aloud, and keeps the history. All of it on the phone.
class ConversationController extends ChangeNotifier {
  final SpeechEngine speech;
  final TextTranslator translator;
  final String myLang;

  /// Speaks a sentence in a language. Replaceable in tests.
  final Future<void> Function(String text, String lang) speak;
  final Future<void> Function(Turn turn)? onTranslated;
  final Duration partialDelay;
  bool speakAloud;

  ConversationController({
    required this.speech,
    required this.translator,
    required this.myLang,
    required this.speak,
    this.onTranslated,
    this.partialDelay = const Duration(milliseconds: 250),
    this.speakAloud = true,
  });

  final List<Turn> history = [];
  Side? listening;
  String heard = ''; // what is being said right now
  String? heardTranslation; // its translation so far
  String? problem;
  bool busy = false;

  StreamSubscription<SpeechEvent>? _sub;
  Timer? _partialTimer;
  int _partialSeq =
      0; // only the newest partial translation may update the screen
  int _generation =
      0; // bumps whenever the line of thought changes, so an old translation never overwrites a newer one

  String langOf(Side s) => s == Side.me ? myLang : 'ja';
  String otherLang(Side s) => s == Side.me ? 'ja' : myLang;

  /// Can this pair be translated at all right now (the engine knows the languages)?
  bool canTranslate(Side s) => translator.supports(langOf(s), otherLang(s));

  Future<void> startListening(Side side) async {
    await stopListening();
    problem = null;
    heard = '';
    heardTranslation = null;
    if (!canTranslate(side)) {
      problem = 'no_model:${langOf(side)}>${otherLang(side)}';
      notifyListeners();
      return;
    }
    final locale = speechLocale(langOf(side));
    try {
      if (!await speech.supports(locale)) {
        problem = 'no_speech:${langOf(side)}';
        notifyListeners();
        return;
      }
    } catch (e) {
      problem = 'speech_error:$e';
      notifyListeners();
      return;
    }
    listening = side;
    final gen = ++_generation;
    notifyListeners();
    _sub = speech
        .listen(locale)
        .listen(
          (e) => _onSpeech(side, gen, e),
          onDone: () => _ended(side, gen),
        );
  }

  void _onSpeech(Side side, int gen, SpeechEvent e) {
    if (gen != _generation) return;
    if (e.error != null) {
      problem = _isNoMatch(e.error!) ? null : 'speech_error:${e.error}';
      if (problem != null) {
        listening = null;
      }
      notifyListeners();
      return;
    }
    heard = e.text;
    notifyListeners();
    if (e.isFinal) {
      _partialSeq++; // any partial still being translated is now out of date
      _partialTimer?.cancel();
      _finish(side, e.text);
    } else {
      // translate while they are still talking, but not on every single word
      _partialTimer?.cancel();
      final seq = ++_partialSeq;
      _partialTimer = Timer(
        partialDelay,
        () => _translatePartial(side, gen, seq, e.text),
      );
    }
  }

  bool _isNoMatch(String error) =>
      error.contains('no_match') || error.contains('speech_timeout');

  Future<void> _translatePartial(
    Side side,
    int gen,
    int seq,
    String text,
  ) async {
    final out = await translator.translate(text, langOf(side), otherLang(side));
    if (gen != _generation ||
        seq != _partialSeq ||
        listening != side ||
        out == null)
      return; // out of date
    heardTranslation = out;
    notifyListeners();
  }

  void _ended(Side side, int gen) {
    if (gen != _generation) return;
    // The recogniser closed without a final result (it gave up waiting): use what we heard so far.
    if (listening == side) {
      final text = heard;
      listening = null;
      notifyListeners();
      if (text.trim().isNotEmpty) _finish(side, text);
    }
  }

  Future<void> stopListening() async {
    _partialTimer?.cancel();
    _generation++;
    unawaited(_sub?.cancel()); // no need to wait for it
    _sub = null;
    if (listening != null) {
      listening = null;
      notifyListeners(); // the screen shows "stopped" straight away
      await speech.stop();
    }
  }

  /// Typed text takes the same path as speech.
  Future<void> typed(Side side, String text) => _finish(side, text);

  Future<void> _finish(Side side, String text) async {
    final said = text.trim();
    if (said.isEmpty) return;
    listening = null;
    busy = true;
    notifyListeners();
    final watch = Stopwatch()..start();
    final out = await translator.translate(said, langOf(side), otherLang(side));
    watch.stop();
    busy = false;
    if (out == null) {
      final detail = translator.lastError;
      problem = detail == null
          ? 'no_model:${langOf(side)}>${otherLang(side)}'
          : 'translation_error:$detail';
    } else {
      history.add(
        Turn(
          side: side,
          original: said,
          translated: out,
          fromLang: langOf(side),
          toLang: otherLang(side),
          translateTime: watch.elapsed,
        ),
      );
      final turn = history.last;
      heard = '';
      heardTranslation = null;
      if (speakAloud && out.isNotEmpty) {
        // the translation is read aloud in the language the listener needs
        unawaited(speak(out, otherLang(side)));
      }
      if (onTranslated != null) unawaited(onTranslated!(turn));
    }
    notifyListeners();
  }

  void clearProblem() {
    problem = null;
    notifyListeners();
  }

  /// Read any line of the history aloud again.
  Future<void> replay(Turn t) async {
    if (t.translated != null) await speak(t.translated!, t.toLang);
  }

  @override
  void dispose() {
    _partialTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// A plain-words explanation of a problem code, for the screen.
String explainProblem(String code, String myLang) {
  final mine = langByCode(myLang).name;
  if (code.startsWith('no_speech:')) {
    final l = code.substring(10);
    final name = l == 'ja' ? '日本語 (Japanese)' : langByCode(l).name;
    return 'The offline speech model for $name is not ready. Check the model audit above, download the missing files from the aircraft network, then try again.';
  }
  if (code.startsWith('no_model:')) {
    final pair = code.substring(9).split('>');
    final l = pair.first == 'ja' ? pair.last : pair.first;
    final name = langByCode(l == 'ja' ? myLang : l).name;
    return 'The translation model for $name is not on this phone yet. Download the language kit while you have Wi-Fi ("Before flight"), then try again.';
  }
  if (code.startsWith('speech_error:'))
    return 'The microphone stopped ("${code.substring(13)}"). Tap and try again.';
  if (code.startsWith('translation_error:')) {
    final detail = code.substring('translation_error:'.length);
    if (detail.startsWith('missing_model:')) {
      return 'The offline translation model is missing (${detail.substring('missing_model:'.length)}). Download the language kit while you have Wi-Fi, then try again.';
    }
    if (detail.startsWith('unsupported_language:')) {
      return 'This language pair is not available in the current offline translator. Use a visual card or type instead.';
    }
    return 'Offline translation failed: $detail. Check the language kit and try again.';
  }
  if (code == 'speech_unavailable' || code == 'offline_speech_unavailable')
    return 'The offline speech engine is not available on this phone. Check the model audit above or type instead, in $mine.';
  return code;
}
