import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

const languages = [
  ('en', 'English'), ('hi', 'हिन्दी'), ('ta', 'தமிழ்'), ('te', 'తెలుగు'), ('kn', 'ಕನ್ನಡ'), ('ml', 'മലയാളം'),
  ('mr', 'मराठी'), ('bn', 'বাংলা'), ('gu', 'ગુજરાતી'), ('pa', 'ਪੰਜਾਬੀ'), ('ur', 'اردو'),
];

/// The reader's chosen language, shared by all chats.
final targetLang = ValueNotifier<String>('en');

Future<void> loadTargetLang() async {
  final p = await SharedPreferences.getInstance();
  targetLang.value = p.getString('translate_to') ?? 'en';
  targetLang.addListener(() => p.setString('translate_to', targetLang.value));
}

final _scripts = <(RegExp, String)>[
  (RegExp(r'[஀-௿]'), 'ta'), (RegExp(r'[ఀ-౿]'), 'te'), (RegExp(r'[ಀ-೿]'), 'kn'),
  (RegExp(r'[ഀ-ൿ]'), 'ml'), (RegExp(r'[ঀ-৿]'), 'bn'), (RegExp(r'[઀-૿]'), 'gu'),
  (RegExp(r'[਀-੿]'), 'pa'), (RegExp(r'[؀-ۿ]'), 'ur'), (RegExp(r'[ऀ-ॿ]'), 'hi'),
];

bool needsTranslation(String text, String target) =>
    !(target == 'en' && !RegExp(r'[^\u0000-ɏ]').hasMatch(text));

Future<String> _detect(String text) async {
  for (final (re, code) in _scripts) {
    if (re.hasMatch(text)) return code;
  }
  try {
    final id = LanguageIdentifier(confidenceThreshold: .5);
    final code = await id.identifyLanguage(text);
    await id.close();
    if (code != 'und') return code.split('-').first;
  } catch (_) {}
  return 'en';
}

final _translators = <String, OnDeviceTranslator>{};

/// On-device ML Kit translation (private: text never leaves the phone; the language model
/// downloads once). Falls back to the server for languages ML Kit doesn't cover.
Future<String> translateText(String text, String target) async {
  final from = await _detect(text);
  if (from == target) return text;
  final s = BCP47Code.fromRawValue(from), t = BCP47Code.fromRawValue(target);
  if (s != null && t != null) {
    final key = '$from>$target';
    final tr = _translators[key] ??= OnDeviceTranslator(sourceLanguage: s, targetLanguage: t);
    try {
      return await tr.translateText(text);
    } catch (_) {
      _translators.remove(key);
    }
  }
  final r = await memberApi.post('/translate', {'text': text, 'target': target}) as Map;
  return r['text'] as String;
}
