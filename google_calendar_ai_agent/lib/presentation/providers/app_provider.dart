import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/csv_logger.dart';
import '../../core/utils/text_formatter.dart';
import '../../domain/entities/chat_message.dart';
import '../../services/calendar_service.dart';
import '../../services/ai_service.dart';
import '../../services/tts_service.dart';
import '../../services/stt_service.dart';
import '../../services/translation_service.dart';

class AppProvider extends ChangeNotifier {
  static const String _TAG = '[AppProvider]';
  final CalendarService _calendarService;
  final AiService _aiService;
  final TtsService? _ttsService;
  final SttService? _sttService;
  final TranslationService? _translationService;
  final bool _enableVoiceStack;
  final bool _autoStartListeningOnInit;
  final bool _enableCsvLogging;

  AppProvider({
    CalendarService? calendarService,
    AiService? aiService,
    TtsService? ttsService,
    SttService? sttService,
    TranslationService? translationService,
    bool enableVoiceStack = true,
    bool autoStartListeningOnInit = true,
    bool enableCsvLogging = true,
  })  : _calendarService = calendarService ?? CalendarService(),
        _aiService = aiService ?? AiService(),
        _enableVoiceStack = enableVoiceStack,
        _ttsService = enableVoiceStack ? (ttsService ?? TtsService()) : null,
        _sttService = enableVoiceStack ? (sttService ?? SttService()) : null,
        _translationService = enableVoiceStack
            ? (translationService ?? TranslationService())
            : null,
        _autoStartListeningOnInit = autoStartListeningOnInit,
        _enableCsvLogging = enableCsvLogging;

  List<ChatMessage> _chatMessages = [];
  String? _errorMessage;
  bool _isLoading = true;
  bool _isThinking = false;
  bool _isListening = false;
  bool _autoListenAfterResponse = true;
  String _draftInput = '';
  int _requestSequence = 0;
  int? _activeRequestId;
  String _currentModel = AppConstants.defaultModel;
  String _currentTtsEngine = 'device';
  // ignore: prefer_final_fields - used for loading message animation
  int _loadingMessageIndex = 0;

  List<ChatMessage> get chatMessages => _chatMessages;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isThinking => _isThinking;
  bool get isListening => _isListening;
  String get draftInput => _draftInput;
  String get currentModel => _currentModel;
  String get currentTtsEngine => _currentTtsEngine;
  int get loadingMessageIndex => _loadingMessageIndex;

  final loadingMessages = [
    "Initializing the app...",
    "Loading the AI assistant...",
    "Setting up the chat...",
    "Loading the calendar data...",
    "Almost there...",
    "Preparing your schedule...",
    "Fetching events...",
    "Syncing with Google Calendar...",
    "Configuring voice recognition...",
    "Initializing text-to-speech...",
    "Setting up user interface...",
    "Almost done...",
  ];

  Future<void> initialize() async {
    print('$_TAG initialize() called');
    try {
      await _loadSavedModel();
      print('$_TAG Model loaded: $_currentModel');
      await _loadSavedTtsEngine();
      print('$_TAG TTS engine loaded: $_currentTtsEngine');
      await _calendarService.initialize();
      print('$_TAG Calendar initialized');
      await _loadChatHistory();
      print('$_TAG Chat history loaded: ${_chatMessages.length} messages');
      _aiService.setCalendarService(_calendarService);
      print('$_TAG Calendar service set on AI');
      await _aiService.initialize(_chatMessages);
      print('$_TAG AI initialized (with tools)');
      if (_enableVoiceStack) {
        final tts = _ttsService;
        final stt = _sttService;
        final translation = _translationService;
        if (tts == null || stt == null || translation == null) {
          throw StateError(
            'Voice stack enabled but services were not created.',
          );
        }
        await tts.initialize();
        await tts.setEngine(_parseTtsEngine(_currentTtsEngine));
        print('$_TAG TTS initialized');
        await stt.initialize();
        print('$_TAG STT initialized');
        await translation.initialize();
        print('$_TAG Translation initialized');
      } else {
        print('$_TAG Voice stack disabled for this run');
      }
      print('$_TAG Initialization complete');
      if (_autoStartListeningOnInit) {
        unawaited(_startListeningSession());
      }
    } catch (e, st) {
      _errorMessage = e.toString();
      print('$_TAG ERROR in initialize(): $e');
      print(st);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadSavedModel() async {
    print('$_TAG _loadSavedModel() called');
    final prefs = await SharedPreferences.getInstance();
    _currentModel =
        prefs.getString('default_model') ?? AppConstants.defaultModel;
    print('$_TAG Loaded model: $_currentModel');
  }

  Future<void> _loadSavedTtsEngine() async {
    print('$_TAG _loadSavedTtsEngine() called');
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('tts_engine') ?? 'device';
    if (saved != 'device' && saved != 'cloud') {
      _currentTtsEngine = 'device';
      return;
    }
    _currentTtsEngine = saved;
    print('$_TAG Loaded TTS engine: $_currentTtsEngine');
  }

  Future<void> saveDefaultModel(String model) async {
    print('$_TAG saveDefaultModel() called with: $model');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_model', model);
    _currentModel = model;
    await _aiService.changeModel(model, _chatMessages);
    notifyListeners();
    print('$_TAG Model changed to: $model');
  }

  Future<void> saveTtsEngine(String engine) async {
    print('$_TAG saveTtsEngine() called with: $engine');
    final normalized = (engine == 'cloud') ? 'cloud' : 'device';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_engine', normalized);
    _currentTtsEngine = normalized;
    if (_enableVoiceStack) {
      final tts = _ttsService;
      if (tts == null) {
        throw StateError('Voice stack enabled but TTS service is unavailable.');
      }
      await tts.setEngine(_parseTtsEngine(_currentTtsEngine));
    }
    notifyListeners();
    print('$_TAG TTS engine changed to: $_currentTtsEngine');
  }

  TtsEngine _parseTtsEngine(String raw) {
    return raw == 'cloud' ? TtsEngine.cloud : TtsEngine.device;
  }

  Future<void> _loadChatHistory() async {
    print('$_TAG _loadChatHistory() called');
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString('chat_context_version');
    if (savedVersion != AppConstants.chatContextVersion) {
      print('$_TAG Chat context version changed. Clearing old history.');
      _chatMessages = [];
      await prefs.remove('chat_history');
      await prefs.setString(
        'chat_context_version',
        AppConstants.chatContextVersion,
      );
      return;
    }

    final jsonMessages = prefs.getString('chat_history');
    if (jsonMessages != null) {
      final dynamicMessages = jsonDecode(jsonMessages) as List;
      _chatMessages = dynamicMessages
          .map((message) =>
              ChatMessage.fromMap(Map<String, String>.from(message)))
          .toList();
      print('$_TAG Loaded ${_chatMessages.length} chat messages');
    } else {
      print('$_TAG No chat history found');
    }
  }

  Future<void> _saveChatHistory() async {
    print('$_TAG _saveChatHistory() called');
    final prefs = await SharedPreferences.getInstance();
    final jsonMessages = jsonEncode(
      _chatMessages.map((m) => m.toMap()).toList(),
    );
    await prefs.setString(
      'chat_context_version',
      AppConstants.chatContextVersion,
    );
    await prefs.setString('chat_history', jsonMessages);
    print('$_TAG Saved ${_chatMessages.length} chat messages');
  }

  Future<void> handleUserQuery(
    String query, {
    bool fromVoice = false,
  }) async {
    print('$_TAG handleUserQuery() called with: $query');
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    _autoListenAfterResponse = fromVoice;
    _draftInput = '';
    final requestId = ++_requestSequence;
    _activeRequestId = requestId;

    _chatMessages.add(ChatMessage(role: 'user', content: trimmedQuery));
    notifyListeners();
    print('$_TAG User message added to chat');

    _isThinking = true;
    notifyListeners();
    print('$_TAG Thinking: true');

    try {
      print('$_TAG Sending to AI...');
      final response = await _aiService.sendMessage(trimmedQuery);
      if (_activeRequestId != requestId) {
        print('$_TAG Ignoring stale/interrupted AI response');
        return;
      }
      print(
          '$_TAG AI response received: ${response.substring(0, response.length > 100 ? 100 : response.length)}...');

      if (_enableCsvLogging) {
        await CsvLogger.log(trimmedQuery, response);
      }
      if (_activeRequestId != requestId) {
        print('$_TAG Ignoring stale/interrupted response after logging');
        return;
      }
      if (_enableCsvLogging) {
        print('$_TAG Logged to CSV');
      }

      final displaySeed = TextFormatter.cleanResponseForDisplay(response);
      final displayBase = displaySeed.isEmpty ? response : displaySeed;
      final finalResponse = TextFormatter.humanizeDateTimes(displayBase);
      _chatMessages.add(ChatMessage(
        role: 'model',
        content: finalResponse,
        debugPrompt: kDebugMode ? _aiService.lastPrompt : null,
        debugTrace: kDebugMode ? _aiService.lastTrace : null,
        debugFunctionCalls: kDebugMode ? _aiService.lastFunctionCalls : null,
        debugResponse: kDebugMode ? _aiService.lastResponse : null,
      ));
      final speechSeed = TextFormatter.cleanResponseForSpeech(response);
      final speechBase = speechSeed.isEmpty ? finalResponse : speechSeed;
      final finalSpeech = TextFormatter.humanizeDateTimes(speechBase);
      unawaited(_speakInBackground(finalSpeech));
    } catch (e) {
      if (_activeRequestId != requestId) {
        print('$_TAG Ignoring stale/interrupted error');
        return;
      }
      _errorMessage = e.toString();
      _chatMessages.add(ChatMessage(
        role: 'model',
        content: 'I hit an error while processing that request: $_errorMessage',
      ));
      print('$_TAG ERROR in handleUserQuery(): $e');
    } finally {
      if (_activeRequestId == requestId) {
        _isThinking = false;
        _activeRequestId = null;
        await _saveChatHistory();
        notifyListeners();
      }
    }
    print('$_TAG handleUserQuery() complete');
  }

  Future<void> _speakInBackground(String text) async {
    print('$_TAG _speakInBackground() called');
    final tts = _ttsService;
    final translation = _translationService;
    if (!_enableVoiceStack || tts == null || translation == null) {
      print('$_TAG Skipping TTS - voice stack disabled');
      return;
    }
    if (_isListening) {
      print('$_TAG Skipping TTS - currently listening');
      return;
    }

    var speechText = text;
    if (translation.containsNonEnglish(speechText)) {
      print('$_TAG Non-English content detected for TTS, translating...');
      speechText = await translation.translateForSpeech(speechText);
    }

    final modifiedText = TextFormatter.formatForSpeech(speechText);
    print(
        '$_TAG Speaking: ${modifiedText.substring(0, modifiedText.length > 50 ? 50 : modifiedText.length)}...');
    await tts.speak(modifiedText);

    if (_autoListenAfterResponse && !_isThinking) {
      print('$_TAG Auto re-listen after TTS');
      await Future.delayed(const Duration(milliseconds: 250));
      await _startListeningSession();
    }
  }

  void setDraftInput(String value) {
    if (_draftInput == value) return;
    _draftInput = value;
    notifyListeners();
  }

  Future<void> resetConversationForTesting() async {
    print('$_TAG resetConversationForTesting() called');
    _chatMessages = <ChatMessage>[];
    await _saveChatHistory();
    await _aiService.initialize(_chatMessages);
    notifyListeners();
    print('$_TAG Testing conversation reset complete');
  }

  Future<void> _startListeningSession() async {
    final stt = _sttService;
    final tts = _ttsService;
    if (!_enableVoiceStack || stt == null || tts == null) {
      return;
    }
    if (_isListening || _isThinking) {
      return;
    }

    await tts.stop();
    _isListening = true;
    notifyListeners();

    await stt.startListening(
      onListeningStateChanged: (listening) {
        if (_isListening != listening) {
          _isListening = listening;
          notifyListeners();
        }
      },
      onPartial: (partial) {
        _draftInput = partial;
        notifyListeners();
      },
      onResult: (result) {
        _isListening = false;
        _draftInput = result;
        notifyListeners();
        final trimmed = result.trim();
        if (trimmed.isEmpty) {
          if (_autoListenAfterResponse) {
            unawaited(_startListeningSession());
          }
          return;
        }
        unawaited(handleUserQuery(trimmed, fromVoice: true));
      },
      onError: () {
        _isListening = false;
        notifyListeners();
        if (_autoListenAfterResponse) {
          unawaited(_startListeningSession());
        }
      },
    );
  }

  Future<void> toggleListening() async {
    print('$_TAG toggleListening() called, isListening: $_isListening');
    final stt = _sttService;
    if (!_enableVoiceStack || stt == null) {
      _isListening = false;
      notifyListeners();
      return;
    }
    if (_isListening) {
      _autoListenAfterResponse = false;
      await stt.stop();
      _isListening = false;
    } else {
      _autoListenAfterResponse = true;
      await _startListeningSession();
    }
    notifyListeners();
  }

  void interrupt() {
    print('$_TAG interrupt() called');
    _autoListenAfterResponse = false;
    _aiService.interrupt();
    _activeRequestId = null;
    final tts = _ttsService;
    if (_enableVoiceStack && tts != null) {
      unawaited(tts.stop());
    }
    _isThinking = false;
    _chatMessages.add(ChatMessage(
      role: 'model',
      content: '(Interrupted by user)',
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    final tts = _ttsService;
    final translation = _translationService;
    if (_enableVoiceStack && tts != null) {
      unawaited(tts.dispose());
    }
    if (_enableVoiceStack && translation != null) {
      translation.dispose();
    }
    super.dispose();
  }
}
