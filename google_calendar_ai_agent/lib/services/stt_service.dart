import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static const String _TAG = '[SttService]';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  Function(bool)? _onListeningStateChanged;

  bool get isListening => _isListening;

  Future<bool> initialize() async {
    print('$_TAG initialize() called');
    _isInitialized = await _speech.initialize(
      onStatus: (status) {
        print('$_TAG Status: $status');
        if (status == "listening") {
          _isListening = true;
          _onListeningStateChanged?.call(true);
        } else if (status == "notListening" || status == "done") {
          _isListening = false;
          _onListeningStateChanged?.call(false);
          print('$_TAG isListening = false');
        }
      },
      onError: (error) {
        print('$_TAG ERROR: $error');
        _isListening = false;
        _onListeningStateChanged?.call(false);
      },
    );
    print('$_TAG Initialized: $_isInitialized');
    return _isInitialized;
  }

  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartial,
    Function(bool)? onListeningStateChanged,
    Function? onError,
  }) async {
    print('$_TAG startListening() called, initialized: $_isInitialized');

    if (!_isInitialized) {
      print('$_TAG Not initialized, initializing...');
      final success = await initialize();
      if (!success) {
        print('$_TAG Initialization failed');
        onError?.call();
        return;
      }
    }

    _onListeningStateChanged = onListeningStateChanged;
    _isListening = true;
    _onListeningStateChanged?.call(true);
    print('$_TAG isListening = true');
    print('$_TAG Starting speech recognition...');

    await _speech.listen(
      onResult: (result) {
        print('$_TAG Result received: ${result.recognizedWords}');
        print('$_TAG Final: ${result.finalResult}');
        if (result.recognizedWords.isNotEmpty) {
          onPartial?.call(result.recognizedWords);
        }
        if (result.finalResult) {
          _isListening = false;
          print('$_TAG Calling onResult callback');
          onResult(result.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        autoPunctuation: true,
        enableHapticFeedback: true,
        cancelOnError: false,
        partialResults: true,
      ),
      pauseFor: const Duration(seconds: 12),
      listenFor: const Duration(minutes: 2),
    );
    print('$_TAG listen() called');
  }

  Future<void> stop() async {
    print('$_TAG stop() called');
    await _speech.stop();
    _isListening = false;
    print('$_TAG ✓ Stopped');
  }
}
