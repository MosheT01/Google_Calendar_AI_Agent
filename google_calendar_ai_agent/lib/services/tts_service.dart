import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
    });

    _isInitialized = true;
  }

  Future<void> speak(String text, {Function? onComplete}) async {
    if (!_isInitialized) return;
    
    _isSpeaking = true;
    
    if (onComplete != null) {
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        onComplete();
      });
    }
    
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }

  void dispose() {
    _flutterTts.stop();
  }
}