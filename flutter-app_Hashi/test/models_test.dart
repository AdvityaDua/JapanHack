import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> bytes(int n) => List<int>.generate(n, (i) => i % 251);

const spec = ModelSpec(
  id: 'm',
  title: 'T',
  purpose: 'P',
  dir: 'mdir',
  files: [
    ModelFile('a.bin', 'https://x.test/a.bin', 50000),
    ModelFile('b.txt', 'https://x.test/b.txt', 20000),
  ],
);

Directory temp() {
  final d = Directory.systemTemp.createTempSync('hashi_models_');
  addTearDown(() => d.deleteSync(recursive: true));
  return d;
}

/// A server that holds [files] and honours Range requests unless [ignoreRange].
MockClient server(
  Map<String, List<int>> files, {
  bool ignoreRange = false,
  List<http.BaseRequest>? log,
  int? status,
}) => MockClient.streaming((request, body) async {
  log?.add(request);
  if (status != null)
    return http.StreamedResponse(const Stream.empty(), status);
  final data = files[request.url.path.substring(1)];
  if (data == null) return http.StreamedResponse(const Stream.empty(), 404);
  final range = request.headers['Range'];
  if (range != null && !ignoreRange) {
    final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
    return http.StreamedResponse(Stream.value(data.sublist(from)), 206);
  }
  // send in several chunks so progress has something to report
  final chunks = [
    for (var i = 0; i < data.length; i += 10000)
      data.sublist(i, (i + 10000).clamp(0, data.length)),
  ];
  return http.StreamedResponse(Stream.fromIterable(chunks), 200);
});

void main() {
  test(
    'downloads every file, reports progress up to 100 percent, and then the model counts as installed',
    () async {
      final store = ModelStore(
        temp(),
        client: server({'a.bin': bytes(50000), 'b.txt': bytes(20000)}),
      );
      expect(store.installed(spec), false);
      final progress = <double>[];
      await store.download(spec, onProgress: progress.add);
      expect(store.installed(spec), true);
      expect(File(store.pathOf(spec, 'a.bin')).lengthSync(), 50000);
      expect(progress.last, 1.0);
      expect(progress.first, lessThan(0.5));
      expect(
        progress,
        orderedEquals([...progress]..sort()),
        reason: 'progress never goes backwards',
      );
    },
  );

  test('a half-finished download carries on from where it stopped', () async {
    final root = temp();
    final data = bytes(50000);
    Directory('${root.path}/mdir').createSync(recursive: true);
    File(
      '${root.path}/mdir/a.bin.part',
    ).writeAsBytesSync(data.sublist(0, 30000));
    final log = <http.BaseRequest>[];
    final store = ModelStore(
      root,
      client: server({'a.bin': data, 'b.txt': bytes(20000)}, log: log),
    );
    expect(store.bytesPresent(spec), 30000);
    await store.download(spec);
    expect(log.first.headers['Range'], 'bytes=30000-');
    expect(File(store.pathOf(spec, 'a.bin')).readAsBytesSync(), data);
  });

  test(
    'if the server ignores the range and sends everything again, the file is still right',
    () async {
      final root = temp();
      final data = bytes(50000);
      Directory('${root.path}/mdir').createSync(recursive: true);
      File(
        '${root.path}/mdir/a.bin.part',
      ).writeAsBytesSync(data.sublist(0, 30000));
      final store = ModelStore(
        root,
        client: server({
          'a.bin': data,
          'b.txt': bytes(20000),
        }, ignoreRange: true),
      );
      await store.download(spec);
      expect(File(store.pathOf(spec, 'a.bin')).readAsBytesSync(), data);
      expect(store.installed(spec), true);
    },
  );

  test(
    'a file of the wrong size is rejected and removed, so the next try starts clean',
    () async {
      final store = ModelStore(
        temp(),
        client: server({'a.bin': bytes(40000), 'b.txt': bytes(20000)}),
      );
      await expectLater(
        store.download(spec),
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.message,
            'message',
            contains('a.bin'),
          ),
        ),
      );
      expect(store.installed(spec), false);
      expect(File('${store.pathOf(spec, 'a.bin')}.part').existsSync(), false);
    },
  );

  test('a server error is reported with the file name', () async {
    final store = ModelStore(temp(), client: server({}, status: 503));
    await expectLater(
      store.download(spec),
      throwsA(
        isA<ModelDownloadException>().having(
          (e) => e.message,
          'message',
          allOf(contains('a.bin'), contains('503')),
        ),
      ),
    );
  });

  test('a file that is not on the server is an error', () async {
    final store = ModelStore(temp(), client: server({'a.bin': bytes(50000)}));
    await expectLater(
      store.download(spec),
      throwsA(
        isA<ModelDownloadException>().having(
          (e) => e.message,
          'message',
          contains('b.txt'),
        ),
      ),
    );
    expect(store.installed(spec), false);
    // the first file did arrive, so the retry only fetches the missing one
    expect(File(store.pathOf(spec, 'a.bin')).existsSync(), true);
  });

  test('an installed model is not downloaded again', () async {
    final root = temp();
    final first = ModelStore(
      root,
      client: server({'a.bin': bytes(50000), 'b.txt': bytes(20000)}),
    );
    await first.download(spec);
    final log = <http.BaseRequest>[];
    final second = ModelStore(root, client: server({}, log: log));
    await second.download(spec);
    expect(log, isEmpty);
  });

  test(
    'copied-in files with the right sizes are recognised, a truncated one is not',
    () {
      final root = temp();
      Directory('${root.path}/mdir').createSync(recursive: true);
      File('${root.path}/mdir/a.bin').writeAsBytesSync(bytes(50000));
      File('${root.path}/mdir/b.txt').writeAsBytesSync(bytes(5000));
      final store = ModelStore(root);
      expect(store.installed(spec), false);
      File('${root.path}/mdir/b.txt').writeAsBytesSync(bytes(20000));
      expect(store.installed(spec), true);
    },
  );

  test('removing a model frees it', () async {
    final store = ModelStore(
      temp(),
      client: server({'a.bin': bytes(50000), 'b.txt': bytes(20000)}),
    );
    await store.download(spec);
    await store.remove(spec);
    expect(store.installed(spec), false);
    expect(Directory('${store.root.path}/mdir').existsSync(), false);
  });

  test(
    'the catalogue lists real sizes and https links, and the speech set is small enough for a phone',
    () {
      for (final m in speechModels) {
        for (final f in m.files) {
          expect(f.url, startsWith('https://'));
          expect(f.bytes, greaterThan(0));
        }
      }
      final mb = speechModels.fold<int>(0, (a, m) => a + m.totalBytes) / 1e6;
      expect(mb, lessThan(600));
    },
  );
}
