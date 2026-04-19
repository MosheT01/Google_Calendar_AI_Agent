import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/csv_logger.dart';
import '../../core/utils/text_formatter.dart';
import '../../core/utils/command_parser.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/ai_response.dart';
import '../../services/calendar_service.dart';
import '../../services/ai_service.dart';
import '../../services/tts_service.dart';
import '../../services/stt_service.dart';
import '../../services/translation_service.dart';

class AppProvider extends ChangeNotifier {
  final CalendarService _calendarService = CalendarService();
  final AiService _aiService = AiService();
  final TtsService _ttsService = TtsService();
  final SttService _sttService = SttService();
  final TranslationService _translationService = TranslationService();

  List<calendar.Event> _upcomingEvents = [];
  List<ChatMessage> _chatMessages = [];
  String? _errorMessage;
  bool _isLoading = true;
  bool _isThinking = false;
  bool _isListening = false;
  String _currentModel = AppConstants.defaultModel;
  // ignore: prefer_final_fields - used for loading message animation
  int _loadingMessageIndex = 0;

  List<calendar.Event> get upcomingEvents => _upcomingEvents;
  List<ChatMessage> get chatMessages => _chatMessages;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isThinking => _isThinking;
  bool get isListening => _isListening;
  String get currentModel => _currentModel;
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
    await _loadSavedModel();
    await _calendarService.initialize();
    await _loadChatHistory();
    await _aiService.initialize(_chatMessages);
    await _ttsService.initialize();
    await _sttService.initialize();
    await _translationService.initialize();
    await _fetchEvents();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadSavedModel() async {
    final prefs = await SharedPreferences.getInstance();
    _currentModel = prefs.getString('default_model') ?? AppConstants.defaultModel;
  }

  Future<void> saveDefaultModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_model', model);
    _currentModel = model;
    await _aiService.changeModel(model, _chatMessages);
    notifyListeners();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMessages = prefs.getString('chat_history');
    if (jsonMessages != null) {
      final dynamicMessages = jsonDecode(jsonMessages) as List;
      _chatMessages = dynamicMessages
          .map((message) => ChatMessage.fromMap(Map<String, String>.from(message)))
          .toList();
    }
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMessages = jsonEncode(
      _chatMessages.map((m) => m.toMap()).toList(),
    );
    await prefs.setString('chat_history', jsonMessages);
  }

  Future<void> _fetchEvents() async {
    _upcomingEvents = await _calendarService.fetchEvents();
    
    final nonLatinRegex = RegExp(r'[^\x00-\x7F]');
    final needsTranslation = _upcomingEvents.any(
      (e) => e.summary != null && nonLatinRegex.hasMatch(e.summary!),
    );
    
    if (needsTranslation) {
      _upcomingEvents = await Future.wait(_upcomingEvents.map((event) async {
        if (event.summary != null && nonLatinRegex.hasMatch(event.summary!)) {
          event.summary = await _translationService.translate(event.summary!);
        }
        return event;
      }));
    }
    notifyListeners();
  }

  Future<void> handleUserQuery(String query) async {
    if (query.isEmpty) return;

    _chatMessages.add(ChatMessage(role: 'user', content: query));
    notifyListeners();

    _isThinking = true;
    notifyListeners();

    final formattedEvents = _calendarService.formatEventsForAi(_upcomingEvents);
    final now = DateTime.now();
    final end = now.add(Duration(days: AppConstants.daysOfAccess));
    final busyPeriods = await _calendarService.fetchFreeBusy(now, end);
    final freeBusyData = _calendarService.formatFreeBusy(busyPeriods);

    // ignore: prefer_const_constructors - variable interpolation needed
    final calendarContext = '''
Here is the user's calendar data:
$formattedEvents

Here is the user's free/busy data:
$freeBusyData
''';

    final response = await _aiService.sendMessage(query, calendarContext);
    
    await CsvLogger.log(query, response);

    final aiResponse = AiResponse.parse(response);

    switch (aiResponse.mode) {
      case ResponseMode.clarifying:
        _chatMessages.add(ChatMessage(
          role: 'model',
          content: TextFormatter.cleanResponse(response),
        ));
        _speakInBackground(TextFormatter.cleanResponse(response).replaceAll('\n', ' '));
        break;
      case ResponseMode.codeOutput:
        _executeCommandStack(aiResponse.commands ?? []);
        _chatMessages.add(ChatMessage(
          role: 'model',
          content: aiResponse.content,
        ));
        _speakInBackground(aiResponse.content);
        break;
      case ResponseMode.generic:
        _chatMessages.add(ChatMessage(
          role: 'model',
          content: TextFormatter.cleanResponse(response),
        ));
        _speakInBackground(TextFormatter.cleanResponse(response).replaceAll('\n', ' '));
        break;
    }

    _isThinking = false;
    await _saveChatHistory();
    notifyListeners();
  }

  void _executeCommandStack(List<String> commands) {
    for (final command in commands.reversed) {
      if (command.startsWith('addEvent')) {
        final args = CommandParser.parseArguments(command);
        final title = args['title'];
        final startTime = args['startTime'] != null
            ? DateTime.parse(args['startTime']!)
            : null;
        final endTime = args['endTime'] != null
            ? DateTime.parse(args['endTime']!)
            : null;
        if (title != null && startTime != null) {
          _calendarService.addEvent(
            title: title,
            startTime: startTime,
            endTime: endTime,
            description: args['description'],
            location: args['location'],
            colorId: args['colorId'],
          ).then((_) => _fetchEvents());
        }
      } else if (command.startsWith('updateEvent')) {
        final args = CommandParser.parseArguments(command);
        final eventId = args['eventId'];
        if (eventId != null) {
          _calendarService.updateEvent(
            eventId,
            title: args['title'],
            startTime: args['startTime'] != null
                ? DateTime.parse(args['startTime']!)
                : null,
            endTime: args['endTime'] != null
                ? DateTime.parse(args['endTime']!)
                : null,
            description: args['description'],
            location: args['location'],
            colorId: args['colorId'],
          ).then((_) => _fetchEvents());
        }
      } else if (command.startsWith('deleteEvent')) {
        final args = CommandParser.parseArguments(command);
        final eventId = args['eventId'];
        if (eventId != null) {
          _calendarService.deleteEvent(eventId).then((_) => _fetchEvents());
        }
      }
    }
  }

  void _speakInBackground(String text) {
    if (_isListening) return;
    final modifiedText = TextFormatter.formatForSpeech(text);
    _ttsService.speak(modifiedText);
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await _sttService.stop();
      _isListening = false;
    } else {
      await _ttsService.stop();
      _isListening = true;
      await _sttService.startListening(
        onResult: (result) {
          _isListening = false;
          handleUserQuery(result);
        },
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _translationService.dispose();
    super.dispose();
  }
}