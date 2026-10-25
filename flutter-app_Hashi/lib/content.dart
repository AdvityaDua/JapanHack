import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_tts/flutter_tts.dart';

import 'languages.dart';

/// The vetted wording the cabin screens need, bundled with the app so everything works with no signal:
/// the interface words, the crew's ready replies, and the announcements, each in the passenger's language.
class ReplyDef {
  final String id;
  final String icon;
  final Map<String, String> text;
  const ReplyDef(this.id, this.icon, this.text);
  String say(String lang) => text[lang] ?? text['en'] ?? '';
}

class AnnouncementDef {
  final String id;
  final String kind;
  final String icon;
  final Map<String, String> text;
  const AnnouncementDef(this.id, this.kind, this.icon, this.text);
  String say(String lang) => text[lang] ?? text['en'] ?? '';
}

class Content {
  final Map<String, Map<String, String>> ui;
  final Map<String, List<String>> checkin;
  final Map<String, ReplyDef> replies;
  final Map<String, AnnouncementDef> announcements;
  const Content({required this.ui, required this.checkin, required this.replies, required this.announcements});

  /// A word in the passenger's language, or English when that language has no translation of it yet.
  String t(String lang, String key) => ui[lang]?[key] ?? ui['en']?[key] ?? key;

  /// "Is everything OK?", "I'm fine", "Please come to me".
  List<String> checkinWords(String lang) => checkin[lang] ?? checkin['en'] ?? const ['Is everything OK?', "I'm fine", 'Please come to me'];

  static Content parse({required String ui, required String replies, required String announcements}) {
    final u = jsonDecode(ui) as Map<String, dynamic>;
    return Content(
      ui: {for (final e in (u['ui'] as Map).entries) e.key as String: {for (final w in (e.value as Map).entries) w.key as String: w.value as String}},
      checkin: {for (final e in (u['checkin'] as Map).entries) e.key as String: List<String>.from(e.value as List)},
      replies: {
        for (final r in (jsonDecode(replies)['replies'] as List).cast<Map<String, dynamic>>())
          r['id'] as String: ReplyDef(r['id'] as String, r['icon'] as String, Map<String, String>.from(r['text'] as Map)),
      },
      announcements: {
        for (final a in (jsonDecode(announcements)['announcements'] as List).cast<Map<String, dynamic>>())
          a['id'] as String: AnnouncementDef(a['id'] as String, a['kind'] as String, a['icon'] as String, Map<String, String>.from(a['text'] as Map)),
      },
    );
  }

  static Content? _instance;
  static Content get instance => _instance ?? (throw StateError('Content.load() has not run'));
  static set instance(Content c) => _instance = c;
  static bool get loaded => _instance != null;

  static Future<Content> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    return _instance = parse(
      ui: await b.loadString('assets/cards/ui.json'),
      replies: await b.loadString('assets/cards/replies.json'),
      announcements: await b.loadString('assets/cards/announcements.json'),
    );
  }
}

// ---- Sound ----

final _player = AudioPlayer();
final _tts = FlutterTts();

/// Plays the recorded clip for [asset] (for example "reply_bringing_hi.mp3"); if there is no recording in that language,
/// speaks [fallbackText] with the phone's own voice. Replaceable in tests.
Future<void> Function(String asset, String fallbackText, String lang) playClip = _playClip;

Future<void> _playClip(String asset, String fallbackText, String lang) async {
  try {
    await _player.stop();
    await _player.play(AssetSource('audio/$asset'));
  } catch (_) {
    if (fallbackText.isEmpty) return;
    await _tts.setLanguage(langByCode(lang).tts);
    await _tts.speak(fallbackText);
  }
}

/// Speaks a sentence with the phone's own voice.
Future<void> Function(String text, String locale) speakText = _speak;

Future<void> _speak(String text, String locale) async {
  await _tts.setLanguage(locale);
  await _tts.speak(text);
}
