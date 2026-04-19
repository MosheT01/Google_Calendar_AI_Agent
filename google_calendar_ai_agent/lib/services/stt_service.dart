import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    _isInitialized = await _speech.initialize(
      onStatus: (status) {
        if (status == "notListening" || status == "done") {
          _isListening = false;
        }
      },
      onError: (error) {
        _isListening = false;
      },
    );
    return _isInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    Function? onError,
  }) async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) {
        onError?.call();
        return;
      }
    }

    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _isListening = false;
          onResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        autoPunctuation: true,
        enableHapticFeedback: true,
        cancelOnError: false,
      ),
      pauseFor: const Duration(seconds: 5),
    );
  }

  Future<void> stop() async {
    await _speech.stop();
    _isListening = false;
  }
}