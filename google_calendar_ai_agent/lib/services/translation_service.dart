import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  OnDeviceTranslator? _translator;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    _translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.hebrew,
      targetLanguage: TranslateLanguage.english,
    );
    _isInitialized = true;
  }

  Future<String> translate(String text) async {
    if (!_isInitialized || _translator == null) {
      await initialize();
    }
    return await _translator!.translateText(text);
  }

  Future<List<String>> translateBatch(List<String> texts) async {
    if (texts.isEmpty) return <String>[];
    final results = <String>[];
    for (final text in texts) {
      results.add(await translate(text));
    }
    return results;
  }

  void dispose() {
    _translator?.close();
  }
}