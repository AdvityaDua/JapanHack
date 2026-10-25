import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'asr_worker.dart';
import 'engines.dart';
import 'models.dart';

/// The thing that turns audio into words (the worker thread, or a fake in tests).
abstract class AsrBackend {
  Stream<AsrEvent> get events;
  void prepare(String lang);
  void begin(String lang);
  void audio(Float32List samples);
  void end();
  void dispose();
}

class WorkerBackend implements AsrBackend {
  final AsrWorker w;
  WorkerBackend(this.w);
  @override
  Stream<AsrEvent> get events => w.events;
  @override
  void prepare(String lang) => w.prepare(lang);
  @override
  void begin(String lang) => w.begin(lang);
  @override
  void audio(Float32List samples) => w.audio(samples);
  @override
  void end() => w.end();
  @override
  void dispose() => w.dispose();
}

/// The microphone as a stream of 16 kHz mono floats.
abstract class Mic {
  /// Null when there is no permission or the microphone cannot start.
  Future<Stream<Float32List>?> start();
  Future<void> stop();
}

class RecordMic implements Mic {
  final AudioRecorder _rec = AudioRecorder();

  @override
  Future<Stream<Float32List>?> start() async {
    if (!await _rec.hasPermission()) return null;
    final bytes = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        autoGain: true,
        echoCancel: true,
      ),
    );
    return bytes.map((b) {
      final pcm = Int16List.view(Uint8List.fromList(b).buffer);
      final out = Float32List(pcm.length);
      for (var i = 0; i < pcm.length; i++) {
        out[i] = pcm[i] / 32768;
      }
      return out;
    });
  }

  @override
  Future<void> stop() async {
    if (await _rec.isRecording()) await _rec.stop();
  }
}

/// Speech recognition with our own models (no Google speech packs needed, no connection needed). Plugs into the same
/// [SpeechEngine] interface as before, so the screens did not change.
class SherpaSpeechEngine implements SpeechEngine {
  final ModelStore store;
  final Mic mic;

  /// Starts the worker thread; replaced in tests.
  final Future<AsrBackend> Function(AsrPaths) startBackend;
  AsrBackend? _backend;
  StreamSubscription<Float32List>? _audio;
  StreamSubscription<AsrEvent>? _events;
  StreamController<SpeechEvent>? _out;
  final Set<String> _prepared = {};

  SherpaSpeechEngine(
    this.store, {
    Mic? mic,
    Future<AsrBackend> Function(AsrPaths)? startBackend,
  }) : mic = mic ?? RecordMic(),
       startBackend =
           startBackend ??
           ((p) async => WorkerBackend(await AsrWorker.start(p)));

  AsrPaths get paths => AsrPaths(
    vad: store.pathOf(vadModel, 'silero_vad.onnx'),
    omniModel: store.pathOf(omniModel, 'model.int8.onnx'),
    omniTokens: store.pathOf(omniModel, 'tokens.txt'),
    whisperEncoder: store.pathOf(whisperTinyModel, 'tiny-encoder.int8.onnx'),
    whisperDecoder: store.pathOf(whisperTinyModel, 'tiny-decoder.int8.onnx'),
    whisperTokens: store.pathOf(whisperTinyModel, 'tiny-tokens.txt'),
  );

  static String langOf(String locale) => locale.split(RegExp('[_-]')).first;

  /// Which model a language needs, so the screen can say what to download.
  static ModelSpec modelFor(String lang) =>
      engineFor(lang) == 'omni' ? omniModel : whisperTinyModel;

  @override
  Future<bool> supports(String locale) async =>
      store.installed(vadModel) && store.installed(modelFor(langOf(locale)));

  @override
  Future<bool> prepare(String locale) async {
    final lang = langOf(locale);
    if (!await supports(locale)) return false;
    if (_prepared.contains(lang)) return true;
    try {
      final backend = _backend ??= await startBackend(paths);
      final errors = <Object>[];
      final ready = backend.events.firstWhere((e) {
        if (e.kind == 'error') {
          errors.add(StateError(e.text));
          return true;
        }
        return e.kind == 'ready';
      });
      backend.prepare(lang);
      final event = await ready;
      if (errors.isNotEmpty || event.kind == 'error') return false;
      _prepared.add(lang);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<SpeechEvent> listen(String locale) {
    _closeOutput();
    final out = _out = StreamController<SpeechEvent>();
    final lang = langOf(locale);
    () async {
      try {
        final backend = _backend ??= await startBackend(paths);
        _events?.cancel();
        _events = backend.events.listen((e) {
          if (out.isClosed) return;
          switch (e.kind) {
            case 'partial':
              out.add(SpeechEvent(e.text));
            case 'final':
              if (e.text.isNotEmpty)
                out.add(SpeechEvent(e.text, isFinal: true));
              _stopMic();
              out.close();
            case 'error':
              out.add(SpeechEvent('', error: e.text));
              _stopMic();
              out.close();
          }
        });
        backend.begin(lang);
        final audio = await mic.start();
        if (audio == null) {
          out.add(const SpeechEvent('', error: 'microphone_permission'));
          await out.close();
          return;
        }
        _audio = audio.listen(backend.audio);
      } catch (e) {
        if (!out.isClosed) {
          out.add(SpeechEvent('', error: e.toString()));
          // Do not await the close from inside the producer's error path.
          // The listener receives the error and onDone completes normally;
          // awaiting here can keep a failed worker alive during teardown.
          unawaited(out.close());
        }
      }
    }();
    return out.stream;
  }

  Future<void> _stopMic() async {
    await _audio?.cancel();
    _audio = null;
    await mic.stop();
  }

  void _closeOutput() {
    final o = _out;
    if (o != null && !o.isClosed) o.close();
  }

  @override
  Future<void> stop() async {
    await _stopMic();
    _backend?.end(); // understand whatever was said so far
  }

  void dispose() {
    _stopMic();
    _events?.cancel();
    _backend?.dispose();
    _backend = null;
  }
}
