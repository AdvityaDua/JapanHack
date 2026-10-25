import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'content.dart';
import 'engines.dart';
import 'kit.dart';
import 'languages.dart';

/// Checks the real on-device translation and speech code and prints a report. Only runs in a test build:
///   flutter build apk --release --dart-define=SELFTEST=true
/// The report lines start with SELFTEST so they can be read with: adb logcat -s flutter
const selfTestEnabled = bool.fromEnvironment('SELFTEST');

void _log(String line) => debugPrint('SELFTEST $line');

Future<void> runSelfTest() async {
  _log('start');
  final translator = MlKitTranslator();

  // 1. Translation models: which are on the phone, and fetch the ones that are missing
  final needed = <String, TranslateLanguage>{
    'ja': TranslateLanguage.japanese,
    'en': TranslateLanguage.english,
    for (final l in languages) if (l.ml != null) l.code: l.ml!,
  };
  for (final e in needed.entries) {
    try {
      var have = await Kit.has(e.value);
      if (!have) {
        final w = Stopwatch()..start();
        _log('model ${e.key}: downloading…');
        have = await Kit.download(e.value);
        _log('model ${e.key}: ${have ? 'downloaded' : 'FAILED'} in ${w.elapsed.inSeconds}s');
      } else {
        _log('model ${e.key}: already on the phone');
      }
    } catch (err) {
      _log('model ${e.key}: ERROR $err');
    }
  }

  // 2. Translation quality and speed
  Future<void> tr(String from, String to, String text) async {
    final w = Stopwatch()..start();
    final first = await translator.translate(text, from, to);
    final firstMs = w.elapsedMilliseconds;
    w
      ..reset()
      ..start();
    await translator.translate(text, from, to);
    _log('translate $from>$to "$text" => "$first" (first ${firstMs}ms, again ${w.elapsedMilliseconds}ms)');
  }

  await tr('hi', 'ja', 'मुझे पानी चाहिए');
  await tr('hi', 'ja', 'मेरी तबीयत ठीक नहीं है, कृपया डॉक्टर बुलाइए');
  await tr('ja', 'hi', '少々お待ちください。すぐにお持ちします。');
  await tr('ja', 'hi', 'お客様、シートベルトをお締めください');
  await tr('en', 'ja', 'I need a wheelchair at the airport');
  await tr('ta', 'ja', 'எனக்கு தண்ணீர் வேண்டும்');
  await tr('pa', 'ja', 'ਮੈਨੂੰ ਪਾਣੀ ਚਾਹੀਦਾ ਹੈ');
  _log('punjabi supported by the translator: ${translator.supports('pa', 'ja')}');

  // 3. Speech: which languages the phone can recognise, and a real recognition
  final speech = AndroidSpeechEngine();
  for (final loc in ['hi_IN', 'ja_JP', 'pa_IN', 'en_IN', 'ta_IN']) {
    _log('speech locale $loc listed: ${await speech.supports(loc)}');
  }

  Future<void> hear(String locale, Future<void> Function() play, String what) async {
    final w = Stopwatch()..start();
    final partials = <String>[];
    int? firstMs;
    String? finalText;
    String? error;
    final done = Completer<void>();
    final sub = speech.listen(locale).listen((e) {
      if (e.error != null) {
        error = e.error;
      } else if (e.text.isNotEmpty) {
        firstMs ??= w.elapsedMilliseconds;
        partials.add(e.text);
        if (e.isFinal) finalText = e.text;
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200)); // let the recogniser start
    await play();
    await Future.any([done.future, Future<void>.delayed(const Duration(seconds: 12))]);
    await speech.stop();
    await sub.cancel();
    _log('hear $locale ($what): final="${finalText ?? (partials.isEmpty ? '' : partials.last)}" firstWordAfter=${firstMs}ms partials=${partials.length} error=$error');
  }

  await hear('ja_JP', () => speakText('お水をお願いします', 'ja-JP'), 'phone voice says "お水をお願いします"');
  await hear('hi_IN', () => playClip('reply_bringing_hi.mp3', '', 'hi'), 'recording says "हम अभी लेकर आते हैं"');
  await hear('pa_IN', () => playClip('reply_bringing_pa.mp3', '', 'pa'), 'recording says Punjabi "ਅਸੀਂ ਹੁਣੇ ਲੈ ਕੇ ਆਉਂਦੇ ਹਾਂ"');
  await hear('en_IN', () => playClip('reply_bringing_en.mp3', '', 'en'), 'recording says "I will bring it shortly"');
  _log('done');
}
