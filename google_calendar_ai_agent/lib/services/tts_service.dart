import 'package:flutter_tts/flutter_tts.dart';
import 'cloud_tts_service.dart';

enum TtsEngine { device, cloud }

class TtsService {
  static const String _TAG = '[TtsService]';
  final FlutterTts _flutterTts = FlutterTts();
  CloudTtsService? _cloudTts;
  bool _isInitialized = false;
  bool _isSpeaking = false;
  TtsEngine _engine = TtsEngine.device;

  bool get isSpeaking => _isSpeaking;
  TtsEngine get currentEngine => _engine;

  Future<void> initialize() async {
    if (_isInitialized) return;
    print('$_TAG Initializing TTS...');
    await _flutterTts.setLanguage("en-US");
    print('$_TAG Language: en-US');
    await _flutterTts.setSpeechRate(0.5);
    print('$_TAG Speech rate: 0.5');
    await _flutterTts.setVolume(0.8);
    print('$_TAG Volume: 0.8');
    await _flutterTts.setPitch(1.0);
    print('$_TAG Pitch: 1.0');
    await _flutterTts.awaitSpeakCompletion(true);
    print('$_TAG Await completion: true');

    _flutterTts.setCompletionHandler(() {
      print('$_TAG *** TTS COMPLETE ***');
      _isSpeaking = false;
    });

    _flutterTts.setStartHandler(() {
      print('$_TAG *** TTS START ***');
      _isSpeaking = true;
    });

    _flutterTts.setErrorHandler((msg) {
      print('$_TAG *** TTS ERROR: $msg ***');
      _isSpeaking = false;
    });

    _isInitialized = true;
    print('$_TAG ✓ TTS initialized');
  }

  Future<void> setEngine(TtsEngine engine) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_engine == engine) return;
    await stop();
    _engine = engine;
    if (_engine == TtsEngine.cloud) {
      _cloudTts ??= CloudTtsService();
      await _cloudTts!.initialize();
    }
    print('$_TAG Engine switched to: ${engine.name}');
  }

  Future<void> speak(String text, {Function? onComplete}) async {
    print('$_TAG speak() called');
    print('$_TAG Text length: ${text.length} chars');

    if (!_isInitialized) {
      print('$_TAG ERROR: TTS not initialized!');
      return;
    }

    if (_isSpeaking) {
      print('$_TAG Already speaking, stopping first');
      await stop();
    }

    _isSpeaking = true;
    print(
        '$_TAG Starting speak: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

    try {
      if (_engine == TtsEngine.cloud) {
        print('$_TAG >>> Using CLOUD TTS');
        _cloudTts ??= CloudTtsService();
        await _cloudTts!.initialize();
        await _cloudTts!.speak(text);
        _isSpeaking = false;
      } else {
        print('$_TAG >>> Using DEVICE TTS');
        await _flutterTts.speak(text);
        print('$_TAG <<< speak() returned');
      }
    } catch (e) {
      print('$_TAG Cloud TTS failed, falling back to device TTS: $e');
      if (_engine == TtsEngine.cloud) {
        await _flutterTts.speak(text);
      }
      _isSpeaking = false;
    }

    onComplete?.call();
  }

  Future<void> stop() async {
    print('$_TAG stop() called, current state: isSpeaking=$_isSpeaking');
    await _flutterTts.stop();
    if (_cloudTts != null) {
      await _cloudTts!.stop();
    }
    _isSpeaking = false;
    print('$_TAG ✓ TTS stopped');
  }

  Future<void> dispose() async {
    print('$_TAG dispose() called');
    await _flutterTts.stop();
    if (_cloudTts != null) {
      await _cloudTts!.dispose();
      _cloudTts = null;
    }
    print('$_TAG ✓ TTS disposed');
  }
}
