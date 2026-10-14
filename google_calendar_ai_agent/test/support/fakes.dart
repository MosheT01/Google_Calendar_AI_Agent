import 'package:google_calendar_ai_agent/domain/entities/chat_message.dart';
import 'package:google_calendar_ai_agent/services/ai_service.dart';
import 'package:google_calendar_ai_agent/services/calendar_service.dart';
import 'package:google_calendar_ai_agent/services/stt_service.dart';
import 'package:google_calendar_ai_agent/services/translation_service.dart';
import 'package:google_calendar_ai_agent/services/tts_service.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

class FakeCalendarService extends CalendarService {
  int initializeCalls = 0;
  final List<calendar.Event> listedEvents = [];
  final Map<String, calendar.Event> eventsById = {};
  final List<String> deletedIds = [];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<List<calendar.Event>> fetchEventsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? query,
    String? calendarId,
    bool includeDeleted = false,
  }) async {
    return List<calendar.Event>.from(listedEvents);
  }

  @override
  Future<calendar.Event> addEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
    String? visibility,
    String? transparency,
    String? status,
    List<String>? recurrence,
    List<String>? attendeeEmails,
    bool? remindersUseDefault,
    List<int>? reminderMinutes,
    String? sourceTitle,
    String? sourceUrl,
    bool? allDay,
    String? calendarId,
    Map<String, dynamic>? advancedFields,
  }) async {
    final event = calendar.Event(
      id: 'fake-event-${eventsById.length + 1}',
      summary: title,
      start: calendar.EventDateTime(dateTime: startTime),
      end: calendar.EventDateTime(
        dateTime: endTime ?? startTime.add(const Duration(hours: 1)),
      ),
    );
    eventsById[event.id!] = event;
    return event;
  }

  @override
  Future<calendar.Event> updateEvent(
    String eventId, {
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
    String? visibility,
    String? transparency,
    String? status,
    List<String>? recurrence,
    List<String>? attendeeEmails,
    bool? remindersUseDefault,
    List<int>? reminderMinutes,
    String? sourceTitle,
    String? sourceUrl,
    bool? allDay,
    String? calendarId,
    Map<String, dynamic>? advancedFields,
  }) async {
    final existing = eventsById[eventId] ??
        calendar.Event(
          id: eventId,
          summary: 'Updated Event',
          start: calendar.EventDateTime(dateTime: DateTime.now()),
          end: calendar.EventDateTime(
            dateTime: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
    if (title != null) {
      existing.summary = title;
    }
    if (startTime != null) {
      existing.start = calendar.EventDateTime(dateTime: startTime);
    }
    if (endTime != null) {
      existing.end = calendar.EventDateTime(dateTime: endTime);
    }
    eventsById[eventId] = existing;
    return existing;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    deletedIds.add(eventId);
    eventsById.remove(eventId);
  }

  @override
  Future<calendar.Event?> getEventById(String eventId) async {
    return eventsById[eventId];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFreeBusy(
    DateTime start,
    DateTime end,
  ) async {
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> findFreeSlots({
    required DateTime start,
    required DateTime end,
    required int minDurationMinutes,
    int dayStartHour = 8,
    int dayEndHour = 22,
    int maxResults = 10,
  }) async {
    return <Map<String, dynamic>>[
      {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'durationMinutes': minDurationMinutes,
      }
    ];
  }

  @override
  Future<Map<String, Map<String, String?>>> fetchEventColors() async {
    return <String, Map<String, String?>>{
      '1': {'background': '#7986CB', 'foreground': '#FFFFFF'}
    };
  }
}

class FakeAiService extends AiService {
  FakeAiService({
    this.defaultResponse = 'mode=generic Test response',
    this.responseDelay = Duration.zero,
    this.responsesByPrompt = const <String, String>{},
  });

  int initializeCalls = 0;
  CalendarService? boundCalendarService;
  String defaultResponse;
  Duration responseDelay;
  final Map<String, String> responsesByPrompt;
  bool wasInterrupted = false;
  String? changedModel;

  @override
  void setCalendarService(CalendarService calendarService) {
    boundCalendarService = calendarService;
  }

  @override
  Future<void> initialize(List<ChatMessage> history) async {
    initializeCalls++;
  }

  @override
  Future<void> changeModel(String modelName, List<ChatMessage> history) async {
    changedModel = modelName;
  }

  @override
  Future<String> sendMessage(String prompt) async {
    if (responseDelay > Duration.zero) {
      await Future.delayed(responseDelay);
    }
    if (wasInterrupted) {
      return 'Operation interrupted by user.';
    }
    return responsesByPrompt[prompt] ?? defaultResponse;
  }

  @override
  void interrupt() {
    wasInterrupted = true;
  }

  @override
  String? get lastPrompt => 'fake-last-prompt';

  @override
  String? get lastTrace => 'fake-last-trace';

  @override
  String? get lastFunctionCalls => 'fake-last-function-calls';

  @override
  String? get lastResponse => 'fake-last-response';
}

class FakeTtsService extends TtsService {
  int initializeCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  final List<String> spokenTexts = [];
  final List<TtsEngine> selectedEngines = [];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> setEngine(TtsEngine engine) async {
    selectedEngines.add(engine);
  }

  @override
  Future<void> speak(String text, {Function? onComplete}) async {
    spokenTexts.add(text);
    onComplete?.call();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class FakeSttService extends SttService {
  int initializeCalls = 0;
  int startListeningCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return true;
  }

  @override
  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartial,
    Function(bool)? onListeningStateChanged,
    Function? onError,
  }) async {
    startListeningCalls++;
    onListeningStateChanged?.call(true);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class FakeTranslationService extends TranslationService {
  FakeTranslationService({
    this.shouldTranslate = false,
    this.translatedPrefix = '[translated] ',
  });

  int initializeCalls = 0;
  int disposeCalls = 0;
  bool shouldTranslate;
  String translatedPrefix;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  bool containsNonEnglish(String text) {
    return shouldTranslate;
  }

  @override
  Future<String> translateForSpeech(String text) async {
    return '$translatedPrefix$text';
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}
