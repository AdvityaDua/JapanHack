import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The big models that live on the phone (speech and translation). They are downloaded once, on Wi-Fi, and after that
/// everything works with no connection. Each model is a folder of files.

class ModelFile {
  final String name;
  final String url;

  /// Expected size in bytes; a download of a different size is rejected.
  final int bytes;
  const ModelFile(this.name, this.url, this.bytes);
}

class ModelSpec {
  final String id;
  final String title;
  final String purpose;
  final String dir;
  final List<ModelFile> files;
  const ModelSpec({
    required this.id,
    required this.title,
    required this.purpose,
    required this.dir,
    required this.files,
  });

  int get totalBytes => files.fold(0, (a, f) => a + f.bytes);
}

const _hf = 'https://huggingface.co';

/// Understands Indian and Southeast Asian languages (Hindi, Punjabi, Tamil, ...). Meta Omnilingual ASR, 300M, int8.
const omniModel = ModelSpec(
  id: 'omnilingual-300m',
  title: 'Speech: Indian languages',
  purpose: 'Listens to Hindi, Punjabi, Tamil and 1,600 other languages',
  // Keep the on-device folder identical to the aircraft manifest ID so a
  // copied/downloaded bundle has one unambiguous location everywhere.
  dir: 'omnilingual-300m',
  files: [
    ModelFile(
      'model.int8.onnx',
      '$_hf/csukuangfj/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-int8-2025-11-12/resolve/main/model.int8.onnx',
      365352120,
    ),
    ModelFile(
      'tokens.txt',
      '$_hf/csukuangfj/sherpa-onnx-omnilingual-asr-1600-languages-300M-ctc-int8-2025-11-12/resolve/main/tokens.txt',
      86423,
    ),
  ],
);

/// Listens to Japanese and English. OpenAI Whisper tiny, int8.
const whisperTinyModel = ModelSpec(
  id: 'whisper-tiny',
  title: 'Speech: Japanese and English',
  purpose: 'Listens to Japanese (the crew) and English',
  dir: 'whisper-tiny-int8',
  files: [
    ModelFile(
      'tiny-encoder.int8.onnx',
      '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
      12900000,
    ),
    ModelFile(
      'tiny-decoder.int8.onnx',
      '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
      89900000,
    ),
    ModelFile(
      'tiny-tokens.txt',
      '$_hf/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
      816730,
    ),
  ],
);

/// Finds where speech starts and stops. Silero VAD.
const vadModel = ModelSpec(
  id: 'silero-vad',
  title: 'Voice detector',
  purpose: 'Finds where a sentence starts and ends',
  dir: 'silero-vad',
  files: [
    ModelFile(
      'silero_vad.onnx',
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
      643854,
    ),
  ],
);

const speechModels = [vadModel, whisperTinyModel, omniModel];

/// Downloads and finds models. Looks first in the app's files folder (where models can also be copied by hand with adb).
class ModelStore {
  final Directory root;
  final http.Client _http;
  ModelStore(this.root, {http.Client? client})
    : _http = client ?? http.Client();

  static Future<ModelStore> open({http.Client? client}) async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    await dir.create(recursive: true);
    return ModelStore(dir, client: client);
  }

  String pathOf(ModelSpec m, String file) => '${root.path}/${m.dir}/$file';

  /// Every file is there and has the right size (within 1 percent, since sizes in the catalogue are rounded).
  bool installed(ModelSpec m) => m.files.every((f) {
    final file = File(pathOf(m, f.name));
    if (!file.existsSync()) return false;
    final have = file.lengthSync();
    return (have - f.bytes).abs() <= f.bytes * 0.01 + 2000;
  });

  /// Files that are absent or outside the catalogue's size tolerance.
  /// Keeping this audit in one place prevents the downloader and the loader
  /// from disagreeing about whether a model is ready.
  List<String> invalidFiles(ModelSpec m) => [
    for (final f in m.files)
      if (!_validFile(m, f)) '${m.id}/${f.name}',
  ];

  bool _validFile(ModelSpec m, ModelFile f) {
    final file = File(pathOf(m, f.name));
    if (!file.existsSync()) return false;
    final have = file.lengthSync();
    return (have - f.bytes).abs() <= f.bytes * 0.01 + 2000;
  }

  /// Bytes already on the phone for this model, counting a half-finished download.
  int bytesPresent(ModelSpec m) {
    var sum = 0;
    for (final f in m.files) {
      final file = File(pathOf(m, f.name));
      final part = File('${file.path}.part');
      if (file.existsSync()) {
        sum += file.lengthSync();
      } else if (part.existsSync()) {
        sum += part.lengthSync();
      }
    }
    return sum;
  }

  /// Downloads what is missing. Carries on from a half-finished file, and reports progress as 0.0 to 1.0.
  Future<void> download(
    ModelSpec m, {
    void Function(double progress)? onProgress,
  }) => _download(m, (file) => Uri.parse(file.url), onProgress: onProgress);

  /// Downloads the same model bundle from the aircraft edge server. The device
  /// token protects the local catalogue and the HTTP Range header lets a
  /// passenger resume after an in-flight Wi-Fi interruption.
  Future<void> downloadFromEdge(
    ModelSpec m, {
    required String baseUrl,
    required String deviceToken,
    void Function(double progress)? onProgress,
  }) => _download(
    m,
    (file) {
      final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
      return Uri.parse(
        '$base/api/v1/models/${Uri.encodeComponent(m.id)}/${Uri.encodeComponent(file.name)}',
      );
    },
    headers: {'Authorization': 'Bearer $deviceToken'},
    onProgress: onProgress,
  );

  Future<void> _download(
    ModelSpec m,
    Uri Function(ModelFile file) urlFor, {
    Map<String, String> headers = const {},
    void Function(double progress)? onProgress,
  }) async {
    await Directory('${root.path}/${m.dir}').create(recursive: true);
    final total = m.totalBytes;
    var done = 0;
    for (final f in m.files) {
      final target = File(pathOf(m, f.name));
      if (target.existsSync() &&
          (target.lengthSync() - f.bytes).abs() <= f.bytes * 0.01 + 2000) {
        done += target.lengthSync();
        onProgress?.call(done / total);
        continue;
      }
      final part = File('${target.path}.part');
      var have = part.existsSync() ? part.lengthSync() : 0;
      final request = http.Request('GET', urlFor(f));
      request.headers.addAll(headers);
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      final response = await _http.send(request);
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw ModelDownloadException(
          '${f.name}: the server answered ${response.statusCode}',
        );
      }
      // 200 means the server ignored the range and is sending the whole file again
      final append = response.statusCode == 206;
      if (!append) have = 0;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          have += chunk.length;
          onProgress?.call((done + have) / total);
        }
      } finally {
        await sink.close();
      }
      final got = part.lengthSync();
      if ((got - f.bytes).abs() > f.bytes * 0.01 + 2000) {
        await part
            .delete(); // a wrong-sized file is thrown away so the next try starts clean
        throw ModelDownloadException(
          '${f.name}: got $got bytes, expected about ${f.bytes}',
        );
      }
      await part.rename(target.path);
      done += target.lengthSync();
    }
    onProgress?.call(1);
  }

  /// Removes a model to free space.
  Future<void> remove(ModelSpec m) async {
    final dir = Directory('${root.path}/${m.dir}');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

class ModelDownloadException implements Exception {
  final String message;
  ModelDownloadException(this.message);
  @override
  String toString() => message;
}
