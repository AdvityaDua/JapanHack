import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Passenger languages, written in their own script. [ml] is the ML Kit on-device translation language,
/// or null where ML Kit has no model (Punjabi, Malayalam, Khmer, Burmese): those fall back to English.
class Lang {
  final String code;
  final String name;
  final String tts;
  final TranslateLanguage? ml;
  const Lang(this.code, this.name, this.tts, this.ml);
}

const languages = <Lang>[
  Lang('pa', 'ਪੰਜਾਬੀ', 'pa-IN', null),
  Lang('hi', 'हिन्दी', 'hi-IN', TranslateLanguage.hindi),
  Lang('en', 'English', 'en-US', TranslateLanguage.english),
  Lang('ja', '日本語', 'ja-JP', TranslateLanguage.japanese),
  Lang('ta', 'தமிழ்', 'ta-IN', TranslateLanguage.tamil),
  Lang('te', 'తెలుగు', 'te-IN', TranslateLanguage.telugu),
  Lang('bn', 'বাংলা', 'bn-IN', TranslateLanguage.bengali),
  Lang('gu', 'ગુજરાતી', 'gu-IN', TranslateLanguage.gujarati),
  Lang('mr', 'मराठी', 'mr-IN', TranslateLanguage.marathi),
  Lang('kn', 'ಕನ್ನಡ', 'kn-IN', TranslateLanguage.kannada),
  Lang('ml', 'മലയാളം', 'ml-IN', null),
  Lang('th', 'ไทย', 'th-TH', TranslateLanguage.thai),
  Lang('vi', 'Tiếng Việt', 'vi-VN', TranslateLanguage.vietnamese),
  Lang('id', 'Bahasa Indonesia', 'id-ID', TranslateLanguage.indonesian),
  Lang('fil', 'Filipino', 'fil-PH', TranslateLanguage.tagalog),
  Lang('ms', 'Bahasa Melayu', 'ms-MY', TranslateLanguage.malay),
  Lang('km', 'ខ្មែរ', 'km-KH', null),
  Lang('my', 'မြန်မာ', 'my-MM', null),
];

Lang langByCode(String code) =>
    languages.firstWhere((l) => l.code == code, orElse: () => languages[2]);
