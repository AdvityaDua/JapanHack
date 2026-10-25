import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'languages.dart';
import 'backend/backend_config.dart';

/// Saved passenger profile (kept on the phone only).
class Profile {
  String lang;
  String seat;
  bool senior;

  /// Less movement on screen: no drifting petals, no card flips.
  bool calm;
  Set<String> needs;
  String server;
  String central;

  /// The seat comes from the booking and is never typed. Empty until the booking has been read.
  Profile({
    this.lang = 'ta',
    this.seat = '',
    this.senior = false,
    this.calm = false,
    Set<String>? needs,
    this.server = 'http://127.0.0.1:8001',
    this.central = 'http://127.0.0.1:8100',
  }) : needs = needs ?? {};

  static Future<Profile> load() async {
    final p = await SharedPreferences.getInstance();
    final savedServer = p.getString('server');
    final savedCentral = p.getString('central');
    return Profile(
      lang: p.getString('lang') ?? 'ta',
      seat: p.getString('seat') ?? '',
      senior: p.getBool('senior') ?? false,
      calm: p.getBool('calm') ?? false,
      needs: (p.getStringList('needs') ?? []).toSet(),
      server: configuredCabinBackendUrl.isEmpty
          ? (savedServer == 'http://192.168.137.1:8000' ||
                    savedServer == 'http://192.168.137.1:8001'
                ? 'http://127.0.0.1:8001'
                : (savedServer ?? 'http://127.0.0.1:8001'))
          : configuredCabinBackendUrl,
      central: configuredCentralBackendUrl.isEmpty
          ? (savedCentral ?? 'http://127.0.0.1:8100')
          : configuredCentralBackendUrl,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', lang);
    await p.setString('seat', seat);
    await p.setBool('senior', senior);
    await p.setBool('calm', calm);
    await p.setStringList('needs', needs.toList());
    await p.setString('server', server);
    await p.setString('central', central);
  }

  /// Address of the cabin web app, with the profile in the URL fragment so it never reaches a server log.
  String cabinUrl() {
    final frag = 'lang=$lang&senior=${senior ? 1 : 0}&needs=${needs.join(',')}';
    final query = seat.isEmpty ? '' : '?seat=$seat';
    return '${server.replaceAll(RegExp(r'/+$'), '')}/p/$query#$frag';
  }
}

/// On-device translation through ML Kit. Models are downloaded once (on Wi-Fi at home) and then work with no signal.
class Kit {
  static final _manager = OnDeviceTranslatorModelManager();

  /// The two-letter codes of languages this phone can translate for [lang] (always Japanese and English too).
  static List<TranslateLanguage> needed(String lang) {
    final l = langByCode(lang);
    return {
      TranslateLanguage.japanese,
      TranslateLanguage.english,
      if (l.ml != null) l.ml!,
    }.toList();
  }

  static Future<bool> has(TranslateLanguage l) =>
      _manager.isModelDownloaded(l.bcpCode);

  static Future<bool> download(TranslateLanguage l) =>
      _manager.downloadModel(l.bcpCode, isWifiRequired: false);

  /// Translate text. Returns null when the model is missing or the pair is not supported.
  static Future<String?> translate(
    String text,
    TranslateLanguage from,
    TranslateLanguage to,
  ) async {
    if (from == to || text.trim().isEmpty) return text;
    if (!await has(from) || !await has(to)) return null;
    final t = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
    try {
      return await t.translateText(text);
    } finally {
      await t.close();
    }
  }

  /// Translate many short texts with one translator (much faster than opening one each time). Texts that cannot be
  /// translated (a missing model, no plugin) are simply left out of the answer.
  static Future<Map<String, String>> translateMany(
    List<String> texts,
    TranslateLanguage from,
    TranslateLanguage to,
  ) async {
    final out = <String, String>{};
    try {
      if (from == to) return {for (final t in texts) t: t};
      if (!await has(from) || !await has(to)) return out;
      final t = OnDeviceTranslator(sourceLanguage: from, targetLanguage: to);
      try {
        for (final text in texts) {
          out[text] = await t.translateText(text);
        }
      } finally {
        await t.close();
      }
    } catch (_) {
      // leave what we have
    }
    return out;
  }
}
