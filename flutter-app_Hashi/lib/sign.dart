import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';

import 'cards.dart' show speak;
import 'kit.dart';
import 'languages.dart';
import 'theme.dart';

/// Point the camera at a sign: read the text on the phone, translate it on the phone. No signal needed once the kit is downloaded.
class SignScreen extends StatefulWidget {
  final Profile profile;
  const SignScreen({super.key, required this.profile});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  bool japanese = true;
  File? image;
  bool busy = false;
  String note = '';
  final List<List<String>> results = []; // [original, translated]

  Future<void> run(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      image = File(picked.path);
      busy = true;
      results.clear();
      note = '';
    });
    final recognizer = TextRecognizer(script: japanese ? TextRecognitionScript.japanese : TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(picked.path));
      final l = langByCode(widget.profile.lang);
      final from = japanese ? TranslateLanguage.japanese : TranslateLanguage.english;
      final to = l.ml ?? TranslateLanguage.english;
      if (l.ml == null) note = '${l.name} has no on-device translation model, so you get English.';
      var missing = false;
      for (final b in text.blocks) {
        final t = b.text.trim();
        if (t.isEmpty) continue;
        final out = await Kit.translate(t, from, to);
        if (out == null) missing = true;
        results.add([t, out ?? '(download the language kit first)']);
      }
      if (text.blocks.isEmpty) note = 'No text found. Try again closer and in good light.';
      if (missing) note = 'Some models are missing. Open "Before you fly" and download the language kit while online.';
    } catch (e) {
      note = 'Could not read the picture: $e';
    } finally {
      await recognizer.close();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = langByCode(widget.profile.lang);
    return WashiPage(
      title: 'Read a sign',
      kanji: '標識',
      children: [
        const Text('Take a photo of a sign. It is read and translated on this phone, with no signal.', style: TextStyle(fontSize: 16, color: sumiSoft, height: 1.35)),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
          segments: const [ButtonSegment(value: true, label: Text('日本語 sign')), ButtonSegment(value: false, label: Text('English sign'))],
          selected: {japanese},
          onSelectionChanged: (s) => setState(() => japanese = s.first),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : () => run(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Camera'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: busy ? null : () => run(ImageSource.gallery), icon: const Icon(Icons.photo_rounded), label: const Text('Gallery'))),
        ]),
        const SizedBox(height: 14),
        if (image != null) ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.file(image!, height: 210, width: double.infinity, fit: BoxFit.cover)),
        if (busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: ai))),
        if (note.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: StatusBanner(icon: Icons.info_outline_rounded, color: warn, title: 'Note', detail: note)),
        for (var i = 0; i < results.length; i++)
          Entrance(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: PaperCard(
                spine: ai,
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(results[i][1], style: const TextStyle(fontFamily: serifFont, fontSize: 22, fontWeight: FontWeight.w800, color: aiDeep, height: 1.25)),
                      const SizedBox(height: 4),
                      Text(results[i][0], style: const TextStyle(fontSize: 15, color: sumiSoft)),
                    ]),
                  ),
                  IconButton(tooltip: 'Read aloud', icon: const Icon(Icons.volume_up_rounded, color: ai), onPressed: () => speak(results[i][1], l.ml == null ? 'en-US' : l.tts)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
