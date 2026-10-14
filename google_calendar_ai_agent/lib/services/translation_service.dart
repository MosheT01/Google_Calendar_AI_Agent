import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  static const String _TAG = '[TranslationService]';
  static final RegExp _nonAsciiRegex = RegExp(r'[^\x00-\x7F]');
  static final RegExp _nonAsciiSegmentRegex = RegExp(
    r'[^\x00-\x7F]+(?:\s+[^\x00-\x7F]+)*',
  );

  final Map<TranslateLanguage, OnDeviceTranslator> _translators = {};
  final Map<String, String> _segmentCache = {};
  LanguageIdentifier? _languageIdentifier;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    print('$_TAG Initializing translation service...');
    _languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);
    _isInitialized = true;
    print('$_TAG √ Translation service initialized');
  }

  bool containsNonEnglish(String text) => _nonAsciiRegex.hasMatch(text);

  Future<String> translate(String text) async {
    print('$_TAG translate() called');
    print('$_TAG Input: "$text"');

    if (!_isInitialized) {
      print('$_TAG Not initialized, initializing...');
      await initialize();
    }

    final sourceLanguage = await _detectSourceLanguage(text);
    if (sourceLanguage == null || sourceLanguage == TranslateLanguage.english) {
      print('$_TAG Source language unknown or English, skipping translation');
      return text;
    }

    try {
      final translator = _translators[sourceLanguage] ??
          OnDeviceTranslator(
            sourceLanguage: sourceLanguage,
            targetLanguage: TranslateLanguage.english,
          );
      _translators[sourceLanguage] = translator;

      final result = await translator.translateText(text);
      print('$_TAG Output: "$result"');
      return result;
    } catch (e) {
      print('$_TAG Translation failed: $e');
      return text;
    }
  }

  Future<String> translateForSpeech(String text) async {
    if (!containsNonEnglish(text)) {
      return text;
    }

    if (!_isInitialized) {
      await initialize();
    }

    final matches = _nonAsciiSegmentRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return text;
    }

    print('$_TAG translateForSpeech() found ${matches.length} segments');
    final output = StringBuffer();
    var cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        output.write(text.substring(cursor, match.start));
      }

      final segment = match.group(0)!;
      final cached = _segmentCache[segment];
      if (cached != null) {
        output.write(cached);
      } else {
        final translated = await translate(segment);
        _segmentCache[segment] = translated;
        output.write(translated);
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      output.write(text.substring(cursor));
    }

    final result = output.toString().replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    print('$_TAG translateForSpeech() output: "$result"');
    return result;
  }

  Future<TranslateLanguage?> _detectSourceLanguage(String text) async {
    if (!containsNonEnglish(text)) {
      return TranslateLanguage.english;
    }

    // 1) Try ML Kit language identification first.
    try {
      final languageTag = await _languageIdentifier?.identifyLanguage(text);
      if (languageTag != null &&
          languageTag.isNotEmpty &&
          languageTag != 'und') {
        final normalized = _normalizeLanguageTag(languageTag);
        final detected = BCP47Code.fromRawValue(normalized);
        if (detected != null) {
          return detected;
        }
      }
    } catch (e) {
      print('$_TAG Language identification failed, using script fallback: $e');
    }

    // 2) Script fallback for robustness.
    if (RegExp(r'[\u0590-\u05FF]').hasMatch(text)) {
      return TranslateLanguage.hebrew;
    }
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) {
      return TranslateLanguage.arabic;
    }
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) {
      return TranslateLanguage.russian;
    }
    if (RegExp(r'[\u0370-\u03FF]').hasMatch(text)) {
      return TranslateLanguage.greek;
    }
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) {
      return TranslateLanguage.chinese;
    }
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) {
      return TranslateLanguage.japanese;
    }
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) {
      return TranslateLanguage.korean;
    }
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) {
      return TranslateLanguage.hindi;
    }
    if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(text)) {
      return TranslateLanguage.thai;
    }
    return null;
  }

  String _normalizeLanguageTag(String rawTag) {
    final cleaned = rawTag.toLowerCase().trim();
    final primary = cleaned.split('-').first;
    if (primary == 'iw') return 'he';
    if (primary == 'ji') return 'yi';
    if (primary == 'in') return 'id';
    return primary;
  }

  void dispose() {
    print('$_TAG dispose() called');
    _languageIdentifier?.close();
    _languageIdentifier = null;
    for (final translator in _translators.values) {
      translator.close();
    }
    _translators.clear();
    _segmentCache.clear();
    print('$_TAG √ Translators closed');
  }
}
