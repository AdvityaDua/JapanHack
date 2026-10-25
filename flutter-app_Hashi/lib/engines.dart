import 'dart:async';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'languages.dart';

/// The two engines behind "Speak": one turns speech into text, one turns text into another language.
/// Both run on the phone with no connection. They sit behind small interfaces so a stronger model (Whisper for speech,
/// NLLB for translation) can be dropped in without touching the screens.

class SpeechEvent {
  final String text;
  final bool isFinal;
  final String? error;
  const SpeechEvent(this.text, {this.isFinal = false, this.error});
}

abstract class SpeechEngine {
  /// Whether this phone can recognise [locale] (like "hi_IN") with no connection.
  Future<bool> supports(String locale);

  /// Checks that the recogniser for [locale] is available and loaded.
  /// Engines that do not have a separate loading phase can use the default.
  Future<bool> prepare(String locale) => supports(locale);

  /// Words as they are recognised: partial results while talking, then one final result.
  Stream<SpeechEvent> listen(String locale);

  Future<void> stop();
}

/// The phone's own speech recogniser.
///
/// Android's native recogniser is useful as the demo fallback, but it is not
/// the same thing as our bundled Sherpa models. Forcing `onDevice: true` here
/// makes the microphone appear to start while producing no words on devices
/// that do not have the requested Android speech pack installed. The real
/// offline path is [SherpaSpeechEngine] in `asr_engine.dart`; this engine is
/// deliberately network-capable so the demo can speak immediately.
class AndroidSpeechEngine implements SpeechEngine {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  StreamController<SpeechEvent>? _out;
  List<String>? _locales;

  Future<bool> _init() async {
    if (_ready) return true;
    return _ready = await _stt.initialize(
      onError: (e) {
        final out = _out;
        if (out != null && !out.isClosed) {
          out.add(SpeechEvent('', error: e.errorMsg));
        }
      },
      onStatus: (status) {
        // A status callback is useful when Android stops listening without
        // returning a transcript. Do not expose ordinary status transitions
        // as user-facing errors; the stream's error callback remains the
        // source of truth for failures.
        assert(status.isNotEmpty);
      },
      debugLogging: false,
    );
  }

  @override
  Future<bool> supports(String locale) async {
    if (!await _init()) return false;
    _locales ??= [
      for (final l in await _stt.locales()) l.localeId.replaceAll('-', '_'),
    ];
    return _locales!.contains(locale.replaceAll('-', '_'));
  }

  @override
  Future<bool> prepare(String locale) => supports(locale);

  @override
  Stream<SpeechEvent> listen(String locale) {
    _out?.close();
    final out = _out = StreamController<SpeechEvent>();
    () async {
      try {
        if (!await _init()) {
          out.add(const SpeechEvent('', error: 'speech_unavailable'));
          await out.close();
          return;
        }
        await _stt.listen(
          onResult: (r) {
            if (!out.isClosed)
              out.add(SpeechEvent(r.recognizedWords, isFinal: r.finalResult));
            if (r.finalResult && !out.isClosed) out.close();
          },
          listenOptions: SpeechListenOptions(
            localeId: locale,
            listenFor: const Duration(seconds: 30),
            // The native Android recogniser often has no offline pack for
            // Indian/Southeast Asian locales. In that case onDevice=true
            // silently starts and then returns no words. Use it only when the
            // app is explicitly built for that mode; the demo default must
            // remain usable on a stock Android phone.
            onDevice: const bool.fromEnvironment(
              'HASHI_NATIVE_OFFLINE_SPEECH',
              defaultValue: false,
            ),
            pauseFor: const Duration(seconds: 4),
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.dictation,
          ),
        );
      } catch (e) {
        if (!out.isClosed) {
          out.add(SpeechEvent('', error: 'speech_exception:$e'));
          await out.close();
        }
      }
    }();
    return out.stream;
  }

  @override
  Future<void> stop() async {
    await _stt.stop();
  }
}

abstract class TextTranslator {
  /// Whether this engine can translate [from] to [to] (language codes like "hi", "ja").
  bool supports(String from, String to);

  /// A diagnostic from the most recent failed translation, when available.
  /// This is intentionally optional so test and future engines can remain small.
  String? get lastError => null;

  /// The translation, or null when it cannot be produced (model missing).
  Future<String?> translate(String text, String from, String to);
}

TranslateLanguage? _mlOf(String code) =>
    code == 'ja' ? TranslateLanguage.japanese : langByCode(code).ml;

/// ML Kit's on-device translator. Translators are kept open between calls so each sentence costs milliseconds.
class MlKitTranslator implements TextTranslator {
  final Map<String, OnDeviceTranslator> _open = {};
  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();
  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  bool supports(String from, String to) =>
      _mlOf(from) != null && _mlOf(to) != null;

  @override
  Future<String?> translate(String text, String from, String to) async {
    _lastError = null;
    if (text.trim().isEmpty) return '';
    if (from == to) return text;
    final a = _mlOf(from), b = _mlOf(to);
    if (a == null || b == null) {
      _lastError = 'unsupported_language:$from>$to';
      return null;
    }
    try {
      final sourceReady = await _models.isModelDownloaded(a.bcpCode);
      final targetReady = await _models.isModelDownloaded(b.bcpCode);
      if (!sourceReady || !targetReady) {
        final missing = [
          if (!sourceReady) a.bcpCode,
          if (!targetReady) b.bcpCode,
        ].join(',');
        _lastError = 'missing_model:$missing';
        return null;
      }
      final t = _open.putIfAbsent(
        '$from>$to',
        () => OnDeviceTranslator(sourceLanguage: a, targetLanguage: b),
      );
      return await t.translateText(text);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<void> close() async {
    for (final t in _open.values) {
      await t.close();
    }
    _open.clear();
  }
}

/// Uses the first translator that supports the pair. Today that is ML Kit; the large model for Punjabi and the other
/// languages ML Kit lacks goes in front of or behind it here.
class CompositeTranslator implements TextTranslator {
  final List<TextTranslator> engines;
  CompositeTranslator(this.engines);

  @override
  String? get lastError =>
      engines.map((e) => e.lastError).whereType<String>().firstOrNull;

  @override
  bool supports(String from, String to) =>
      engines.any((e) => e.supports(from, to));

  @override
  Future<String?> translate(String text, String from, String to) async {
    for (final e in engines) {
      if (!e.supports(from, to)) continue;
      final out = await e.translate(text, from, to);
      if (out != null) return out;
    }
    return null;
  }
}

/// The recogniser's locale for a language code.
String speechLocale(String code) => switch (code) {
  'ja' => 'ja_JP',
  'en' => 'en_IN',
  _ => langByCode(code).tts.replaceAll('-', '_'),
};
