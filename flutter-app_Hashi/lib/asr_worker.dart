import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Where the speech model files are on the phone.
class AsrPaths {
  final String vad;
  final String omniModel;
  final String omniTokens;
  final String whisperEncoder;
  final String whisperDecoder;
  final String whisperTokens;
  const AsrPaths({required this.vad, required this.omniModel, required this.omniTokens, required this.whisperEncoder, required this.whisperDecoder, required this.whisperTokens});

  List<String> toList() => [vad, omniModel, omniTokens, whisperEncoder, whisperDecoder, whisperTokens];
  static AsrPaths fromList(List<dynamic> l) => AsrPaths(vad: l[0], omniModel: l[1], omniTokens: l[2], whisperEncoder: l[3], whisperDecoder: l[4], whisperTokens: l[5]);
}

class AsrEvent {
  /// loading, ready, partial, final or error
  final String kind;
  final String text;
  /// How long the model took for this result.
  final int ms;
  const AsrEvent(this.kind, [this.text = '', this.ms = 0]);
}

/// Which model listens to which language. Japanese and English go to Whisper (best for Japanese); everything else goes to
/// the multilingual Omnilingual model (best for Hindi, Punjabi, Tamil and the rest). Measured on the phone, see docs.
String engineFor(String lang) => (lang == 'ja' || lang == 'en') ? 'whisper' : 'omni';

/// Runs the speech models on a separate thread, so the screen never freezes while a sentence is being understood.
/// Audio goes in as small chunks; the worker finds where speech starts and ends, shows a partial result about every
/// second, and a final result when the speaker pauses.
class AsrWorker {
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final Isolate _isolate;
  final StreamController<AsrEvent> _events = StreamController<AsrEvent>.broadcast();

  AsrWorker._(this._toWorker, this._fromWorker, this._isolate) {
    _fromWorker.listen((m) {
      if (m is List && m.isNotEmpty && m[0] == 'event') _events.add(AsrEvent(m[1] as String, m[2] as String, m[3] as int));
    });
  }

  static Future<AsrWorker> start(AsrPaths paths) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, [ready.sendPort, paths.toList()], debugName: 'hashi-asr');
    final first = StreamIterator<dynamic>(ready);
    await first.moveNext();
    final toWorker = first.current as SendPort;
    final from = ReceivePort();
    toWorker.send(['events', from.sendPort]);
    await first.cancel();
    return AsrWorker._(toWorker, from, isolate);
  }

  Stream<AsrEvent> get events => _events.stream;

  /// Get the model for [lang] ready (it takes a second or two the first time).
  void prepare(String lang) => _toWorker.send(['prepare', lang]);

  /// Start a new utterance in [lang].
  void begin(String lang) => _toWorker.send(['begin', lang]);

  /// Feed audio: 16 kHz, mono, floats between -1 and 1.
  void audio(Float32List samples) => _toWorker.send(['audio', TransferableTypedData.fromList([samples])]);

  /// The speaker is done: understand what is buffered and send the final result.
  void end() => _toWorker.send(['end']);

  void dispose() {
    _toWorker.send(['dispose']);
    _isolate.kill();
    _fromWorker.close();
    _events.close();
  }

  // ---- the worker thread ----

  static void _main(List<dynamic> args) {
    final out = args[0] as SendPort;
    final paths = AsrPaths.fromList(args[1] as List<dynamic>);
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    SendPort? events;
    void emit(String kind, [String text = '', int ms = 0]) => events?.send(['event', kind, text, ms]);

    sherpa.initBindings();
    sherpa.VoiceActivityDetector? vad;
    final recognizers = <String, sherpa.OfflineRecognizer>{};
    var lang = 'hi';
    var active = false;
    var seg = <Float32List>[];
    var segSamples = 0;
    var lastPartialAt = 0;
    var silence = 0;
    var preroll = <Float32List>[];
    var prerollSamples = 0;
    const rate = 16000;

    sherpa.OfflineRecognizer recognizerFor(String l) {
      final key = engineFor(l) == 'omni' ? 'omni' : 'whisper-$l';
      return recognizers.putIfAbsent(key, () {
        emit('loading');
        final cfg = key == 'omni'
            ? sherpa.OfflineRecognizerConfig(model: sherpa.OfflineModelConfig(omnilingual: sherpa.OfflineOmnilingualAsrCtcModelConfig(model: paths.omniModel), tokens: paths.omniTokens, numThreads: 4, debug: false))
            : sherpa.OfflineRecognizerConfig(
                model: sherpa.OfflineModelConfig(
                  whisper: sherpa.OfflineWhisperModelConfig(encoder: paths.whisperEncoder, decoder: paths.whisperDecoder, language: l, task: 'transcribe'),
                  tokens: paths.whisperTokens,
                  numThreads: 4,
                  debug: false,
                ),
              );
        return sherpa.OfflineRecognizer(cfg);
      });
    }

    sherpa.VoiceActivityDetector detector() => vad ??= sherpa.VoiceActivityDetector(
          config: sherpa.VadModelConfig(sileroVad: sherpa.SileroVadModelConfig(model: paths.vad, threshold: 0.5, minSilenceDuration: 0.5, minSpeechDuration: 0.2, windowSize: 512, maxSpeechDuration: 25), sampleRate: rate, numThreads: 1, debug: false),
          bufferSizeInSeconds: 30,
        );

    Float32List joined(List<Float32List> parts, int n) {
      final all = Float32List(n);
      var o = 0;
      for (final p in parts) {
        all.setRange(o, o + p.length, p);
        o += p.length;
      }
      return all;
    }

    String decode(Float32List samples) {
      final rec = recognizerFor(lang);
      final stream = rec.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: rate);
      rec.decode(stream);
      final text = rec.getResult(stream).text.trim();
      stream.free();
      return text;
    }

    void finish() {
      if (segSamples >= rate ~/ 5) {
        final w = Stopwatch()..start();
        final text = decode(joined(seg, segSamples));
        emit('final', text, w.elapsedMilliseconds);
      } else {
        emit('final', '', 0);
      }
      active = false;
      seg = [];
      segSamples = 0;
      lastPartialAt = 0;
      silence = 0;
      detector().clear();
    }

    inbox.listen((m) {
      try {
        switch (m[0]) {
          case 'events':
            events = m[1] as SendPort;
          case 'prepare':
            recognizerFor(m[1] as String);
            detector();
            emit('ready');
          case 'begin':
            lang = m[1] as String;
            recognizerFor(lang);
            detector().clear();
            active = false;
            seg = [];
            segSamples = 0;
            lastPartialAt = 0;
            silence = 0;
            preroll = [];
            prerollSamples = 0;
            emit('ready');
          case 'audio':
            final chunk = (m[1] as TransferableTypedData).materialize().asFloat32List();
            final v = detector();
            v.acceptWaveform(chunk);
            while (!v.isEmpty()) {
              v.pop(); // we keep our own copy of the audio, so the detector's segments are not needed
            }
            if (v.isDetected()) {
              if (!active) {
                active = true;
                seg = [...preroll]; // a little audio from before the detector noticed, so the first word is not clipped
                segSamples = prerollSamples;
                lastPartialAt = 0;
              }
              seg.add(chunk);
              segSamples += chunk.length;
              silence = 0;
              if (segSamples - lastPartialAt >= rate * 6 ~/ 5) {
                lastPartialAt = segSamples;
                final w = Stopwatch()..start();
                final text = decode(joined(seg, segSamples));
                if (text.isNotEmpty) emit('partial', text, w.elapsedMilliseconds);
              }
              if (segSamples > rate * 24) finish();
            } else if (active) {
              seg.add(chunk);
              segSamples += chunk.length;
              silence += chunk.length;
              if (silence >= rate * 7 ~/ 10) finish(); // the speaker paused
            } else {
              preroll.add(chunk);
              prerollSamples += chunk.length;
              while (prerollSamples > rate * 3 ~/ 10 && preroll.length > 1) {
                prerollSamples -= preroll.removeAt(0).length;
              }
            }
          case 'end':
            if (active) {
              finish();
            } else {
              emit('final', '', 0);
            }
          case 'dispose':
            for (final r in recognizers.values) {
              r.free();
            }
            vad?.free();
            inbox.close();
        }
      } catch (e) {
        emit('error', e.toString());
      }
    });
  }
}
