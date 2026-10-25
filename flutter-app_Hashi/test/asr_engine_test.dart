import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/asr_engine.dart';
import 'package:hashi_mobile/asr_worker.dart';
import 'package:hashi_mobile/engines.dart';
import 'package:hashi_mobile/models.dart';

class FakeBackend implements AsrBackend {
  final StreamController<AsrEvent> out = StreamController<AsrEvent>.broadcast();
  final List<String> log = [];
  final List<Float32List> heard = [];
  @override
  Stream<AsrEvent> get events => out.stream;
  @override
  void prepare(String lang) => log.add('prepare $lang');
  @override
  void begin(String lang) => log.add('begin $lang');
  @override
  void audio(Float32List samples) => heard.add(samples);
  @override
  void end() => log.add('end');
  @override
  void dispose() => log.add('dispose');
}

class FakeMic implements Mic {
  final StreamController<Float32List> chunks = StreamController<Float32List>();
  bool allowed = true;
  int starts = 0, stops = 0;
  @override
  Future<Stream<Float32List>?> start() async {
    starts++;
    return allowed ? chunks.stream : null;
  }

  @override
  Future<void> stop() async => stops++;
}

/// Puts empty files of the right sizes in the model folders (sparse, so it is instant).
ModelStore storeWith(List<ModelSpec> models) {
  final root = Directory.systemTemp.createTempSync('hashi_asr_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final m in models) {
    Directory('${root.path}/${m.dir}').createSync(recursive: true);
    for (final f in m.files) {
      final file = File('${root.path}/${m.dir}/${f.name}')..createSync();
      file.openSync(mode: FileMode.write)
        ..truncateSync(f.bytes)
        ..closeSync();
    }
  }
  return ModelStore(root);
}

({SherpaSpeechEngine engine, FakeBackend backend, FakeMic mic}) make({List<ModelSpec>? models, FakeBackend? backend, FakeMic? mic}) {
  final b = backend ?? FakeBackend();
  final m = mic ?? FakeMic();
  final e = SherpaSpeechEngine(storeWith(models ?? [vadModel, omniModel, whisperTinyModel]), mic: m, startBackend: (_) async => b);
  addTearDown(() {
    m.chunks.close();
    b.out.close();
  });
  return (engine: e, backend: b, mic: m);
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('which languages it can listen to', () {
    test('Indian languages need the multilingual model, Japanese and English need the Whisper model, all need the voice detector', () async {
      final all = make();
      for (final l in ['hi_IN', 'pa_IN', 'ta_IN', 'ml_IN', 'ja_JP', 'en_IN']) {
        expect(await all.engine.supports(l), true, reason: l);
      }
      final onlyWhisper = make(models: [vadModel, whisperTinyModel]);
      expect(await onlyWhisper.engine.supports('ja_JP'), true);
      expect(await onlyWhisper.engine.supports('hi_IN'), false);
      final onlyOmni = make(models: [vadModel, omniModel]);
      expect(await onlyOmni.engine.supports('pa_IN'), true);
      expect(await onlyOmni.engine.supports('ja_JP'), false);
      final noVad = make(models: [omniModel, whisperTinyModel]);
      expect(await noVad.engine.supports('hi_IN'), false);
      expect(await make(models: []).engine.supports('hi_IN'), false);
    });

    test('the model a language needs is named, so the screen can offer the right download', () {
      expect(SherpaSpeechEngine.modelFor('pa').id, 'omnilingual-300m');
      expect(SherpaSpeechEngine.modelFor('ja').id, 'whisper-tiny');
      expect(SherpaSpeechEngine.modelFor('en').id, 'whisper-tiny');
      expect(engineFor('ta'), 'omni');
    });

    test('locale codes are reduced to the language', () {
      expect(SherpaSpeechEngine.langOf('hi_IN'), 'hi');
      expect(SherpaSpeechEngine.langOf('ja-JP'), 'ja');
      expect(SherpaSpeechEngine.langOf('fil_PH'), 'fil');
    });
  });

  group('listening', () {
    test('starts the microphone, tells the worker the language, and sends the audio to it', () async {
      final m = make();
      final events = <SpeechEvent>[];
      m.engine.listen('pa_IN').listen(events.add);
      await tick();
      expect(m.backend.log, ['begin pa']);
      expect(m.mic.starts, 1);
      m.mic.chunks.add(Float32List.fromList([0.1, 0.2]));
      m.mic.chunks.add(Float32List.fromList([0.3]));
      await tick();
      expect(m.backend.heard.length, 2);
      expect(m.backend.heard.first, [0.1, 0.2].map((x) => closeTo(x, 1e-6)).toList());
    });

    test('words appear as partial results and then one final result, after which the microphone stops and the stream ends', () async {
      final m = make();
      final events = <SpeechEvent>[];
      var done = false;
      m.engine.listen('hi_IN').listen(events.add, onDone: () => done = true);
      await tick();
      m.backend.out.add(const AsrEvent('partial', 'mujhe paani', 600));
      await tick();
      m.backend.out.add(const AsrEvent('final', 'मुझे पानी चाहिए', 900));
      await tick();
      expect(events.map((e) => (e.text, e.isFinal)), [('mujhe paani', false), ('मुझे पानी चाहिए', true)]);
      expect(m.mic.stops, greaterThanOrEqualTo(1));
      expect(done, true);
    });

    test('a final result with no words ends the stream without a final event', () async {
      final m = make();
      final events = <SpeechEvent>[];
      var done = false;
      m.engine.listen('hi_IN').listen(events.add, onDone: () => done = true);
      await tick();
      m.backend.out.add(const AsrEvent('final', '', 0));
      await tick();
      expect(events, isEmpty);
      expect(done, true);
    });

    test('a worker error is passed on and stops the microphone', () async {
      final m = make();
      final events = <SpeechEvent>[];
      m.engine.listen('hi_IN').listen(events.add);
      await tick();
      m.backend.out.add(const AsrEvent('error', 'model could not load'));
      await tick();
      expect(events.single.error, 'model could not load');
      expect(m.mic.stops, greaterThanOrEqualTo(1));
    });

    test('without microphone permission it says so', () async {
      final m = make(mic: FakeMic()..allowed = false);
      final events = <SpeechEvent>[];
      m.engine.listen('hi_IN').listen(events.add);
      await tick();
      expect(events.single.error, 'microphone_permission');
    });

    test('if the worker cannot start, the error is reported and nothing is left running', () async {
      final mic = FakeMic();
      final e = SherpaSpeechEngine(storeWith([vadModel, omniModel]), mic: mic, startBackend: (_) async => throw StateError('no native library'));
      addTearDown(mic.chunks.close);
      final events = <SpeechEvent>[];
      var done = false;
      e.listen('hi_IN').listen(events.add, onDone: () => done = true);
      await tick();
      expect(events.single.error, contains('no native library'));
      expect(done, true);
      expect(mic.starts, 0);
    });

    test('stop() stops the microphone and asks the worker for whatever was said so far', () async {
      final m = make();
      m.engine.listen('ja_JP').listen((_) {});
      await tick();
      await m.engine.stop();
      expect(m.mic.stops, 1);
      expect(m.backend.log, ['begin ja', 'end']);
    });

    test('the worker is started once and reused for the next sentence', () async {
      var starts = 0;
      final b = FakeBackend();
      final mic = FakeMic();
      final e = SherpaSpeechEngine(storeWith([vadModel, omniModel]), mic: mic, startBackend: (_) async {
        starts++;
        return b;
      });
      addTearDown(() {
        mic.chunks.close();
        b.out.close();
      });
      e.listen('hi_IN').listen((_) {});
      await tick();
      e.listen('hi_IN').listen((_) {});
      await tick();
      expect(starts, 1);
      expect(b.log, ['begin hi', 'begin hi']);
    });

    test('the model paths point into the model folders', () {
      final m = make();
      final p = m.engine.paths;
      expect(p.omniModel, endsWith('omnilingual-asr-300m-int8/model.int8.onnx'));
      expect(p.whisperEncoder, endsWith('whisper-tiny-int8/tiny-encoder.int8.onnx'));
      expect(p.vad, endsWith('silero-vad/silero_vad.onnx'));
    });
  });
}
