import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Measures speech models on the phone: how long each takes to load and to listen to a clip, and how many characters it
/// gets wrong. Only runs in a test build:  flutter build apk --release --dart-define=SELFTEST=asr
/// Models are pushed to the app files folder (models, asrtest); lines start with ASRBENCH.
const asrBenchEnabled = String.fromEnvironment('SELFTEST') == 'asr';

void _log(String line) => debugPrint('ASRBENCH $line');

/// Character error rate: edits needed to turn [hyp] into [ref], over the length of [ref]. Spaces and punctuation are ignored.
double cer(String ref, String hyp) {
  String clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
  final a = clean(ref).runes.toList(), b = clean(hyp).runes.toList();
  if (a.isEmpty) return b.isEmpty ? 0 : 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length] / a.length;
}

class _Model {
  final String name;
  final sherpa.OfflineRecognizerConfig Function(String dir, String lang) config;
  const _Model(this.name, this.config);
}

sherpa.OfflineRecognizerConfig _whisper(String dir, String size, String lang, {int threads = 4}) => sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(encoder: '$dir/$size-encoder.int8.onnx', decoder: '$dir/$size-decoder.int8.onnx', language: lang, task: 'transcribe'),
        tokens: '$dir/$size-tokens.txt',
        numThreads: threads,
        debug: false,
      ),
    );

Future<void> runAsrBench() async {
  _log('start');
  sherpa.initBindings();
  final root = (await getExternalStorageDirectory())!.path;
  final models = Directory('$root/models');
  final clips = Directory('$root/asrtest');
  final manifest = (jsonDecode(File('${clips.path}/manifest.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  final all = <_Model>[
    _Model('whisper-tiny', (d, l) => _whisper('$d/sherpa-onnx-whisper-tiny', 'tiny', l)),
    _Model('whisper-base', (d, l) => _whisper('$d/sherpa-onnx-whisper-base', 'base', l)),
    _Model('whisper-small', (d, l) => _whisper('$d/sherpa-onnx-whisper-small', 'small', l)),
    _Model(
      'sensevoice',
      (d, l) => sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(model: '$d/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/model.int8.onnx', language: l == 'ja' || l == 'en' ? l : 'auto', useInverseTextNormalization: true),
          tokens: '$d/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/tokens.txt',
          numThreads: 4,
          debug: false,
        ),
      ),
    ),
    _Model(
      'omnilingual-300m',
      (d, l) => sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          omnilingual: sherpa.OfflineOmnilingualAsrCtcModelConfig(model: '$d/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-v2-int8-2026-02-05/model.int8.onnx'),
          tokens: '$d/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-v2-int8-2026-02-05/tokens.txt',
          numThreads: 4,
          debug: false,
        ),
      ),
    ),
  ];

  for (final m in all) {
    // Whisper and SenseVoice are told the language per clip, so one recogniser is built per language; the load time is the first.
    final byLang = <String, sherpa.OfflineRecognizer>{};
    try {
      for (final c in manifest) {
        final lang = c['lang'] as String;
        sherpa.OfflineRecognizer? rec = byLang[lang];
        if (rec == null) {
          final w = Stopwatch()..start();
          rec = sherpa.OfflineRecognizer(m.config(models.path, lang));
          byLang[lang] = rec;
          _log('${m.name} $lang loaded in ${w.elapsedMilliseconds}ms');
        }
        final wave = sherpa.readWave('${clips.path}/${c['file']}');
        final stream = rec.createStream();
        final w = Stopwatch()..start();
        stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
        rec.decode(stream);
        final text = rec.getResult(stream).text;
        final ms = w.elapsedMilliseconds;
        stream.free();
        final secs = wave.samples.length / wave.sampleRate;
        _log('${m.name} | $lang | ${c['noise']} | audio ${secs.toStringAsFixed(1)}s | decode ${ms}ms | cer ${cer(c['text'] as String, text).toStringAsFixed(2)} | "$text" | ref "${c['text']}"');
      }
    } catch (e) {
      _log('${m.name} FAILED: $e');
    } finally {
      for (final r in byLang.values) {
        r.free();
      }
    }
  }
  _log('done');
}
