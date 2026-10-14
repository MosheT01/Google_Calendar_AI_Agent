import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import '../core/constants/app_constants.dart';
import '../core/constants/system_prompt.dart';
import '../domain/entities/chat_message.dart';
import '../services/calendar_service.dart';
import '../firebase_options.dart';

class AiService {
  static const String _TAG = '[AiService]';
  static const Map<String, String> _colorAliases = {
    'lavender': '1',
    'light purple': '1',
    'sage': '2',
    'light green': '2',
    'grape': '3',
    'purple': '3',
    'flamingo': '4',
    'pink': '4',
    'banana': '5',
    'yellow': '5',
    'tangerine': '6',
    'orange': '6',
    'peacock': '7',
    'turquoise': '7',
    'cyan': '7',
    'graphite': '8',
    'gray': '8',
    'grey': '8',
    'blueberry': '9',
    'blue': '9',
    'basil': '10',
    'green': '10',
    'tomato': '11',
    'red': '11',
  };
  GenerativeModel? _model;
  ChatSession? _chat;
  String _currentModel = AppConstants.defaultModel;
  bool _isInitialized = false;
  CalendarService? _calendarService;
  bool _interrupted = false;

  String? _lastPrompt;
  String? _lastTrace;
  String? _lastFunctionCalls;
  String? _lastResponse;
  final List<String> _traceEntries = [];

  bool get isInitialized => _isInitialized;
  String get currentModel => _currentModel;
  String? get lastPrompt => _lastPrompt;
  String? get lastTrace => _lastTrace;
  String? get lastFunctionCalls => _lastFunctionCalls;
  String? get lastResponse => _lastResponse;

  void setCalendarService(CalendarService calendarService) {
    _calendarService = calendarService;
  }

  void interrupt() {
    _interrupted = true;
    _appendTrace('Interrupted by user');
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    if (kIsWeb) {
      final webOptions = _loadWebFirebaseOptionsFromDefine();
      if (webOptions != null) {
        await Firebase.initializeApp(options: webOptions);
        print('$_TAG Firebase initialized from web runtime define');
        return;
      }

      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('$_TAG Firebase initialized from default options');
        return;
      } on UnsupportedError {
        throw StateError(
          'Web Firebase options are not configured. '
          'Pass --dart-define=WEB_FIREBASE_OPTIONS_B64=<base64-json> '
          'or --dart-define=E2E_WEB_FIREBASE_OPTIONS_B64=<base64-json>.',
        );
      }
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('$_TAG Firebase initialized from default options');
  }

  FirebaseOptions? _loadWebFirebaseOptionsFromDefine() {
    const explicit = String.fromEnvironment(
      'WEB_FIREBASE_OPTIONS_B64',
      defaultValue: '',
    );
    const e2eEncoded = String.fromEnvironment(
      'E2E_WEB_FIREBASE_OPTIONS_B64',
      defaultValue: '',
    );
    final encoded = explicit.trim().isNotEmpty ? explicit : e2eEncoded;
    final trimmed = encoded.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final normalized = base64.normalize(trimmed);
      final decoded = utf8.decode(base64.decode(normalized));
      final parsed = jsonDecode(decoded);
      if (parsed is! Map) {
        throw const FormatException(
            'Decoded web Firebase options are not JSON object');
      }
      final map = parsed.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      String requireString(String key) {
        final value = map[key]?.toString().trim();
        if (value == null || value.isEmpty) {
          throw FormatException('Missing required Firebase option: $key');
        }
        return value;
      }

      String? optionalString(String key) {
        final value = map[key]?.toString().trim();
        if (value == null || value.isEmpty) {
          return null;
        }
        return value;
      }

      return FirebaseOptions(
        apiKey: requireString('apiKey'),
        appId: requireString('appId'),
        messagingSenderId: requireString('messagingSenderId'),
        projectId: requireString('projectId'),
        authDomain: optionalString('authDomain'),
        storageBucket: optionalString('storageBucket'),
        measurementId: optionalString('measurementId'),
        databaseURL: optionalString('databaseURL'),
        iosBundleId: optionalString('iosBundleId'),
        androidClientId: optionalString('androidClientId'),
        iosClientId: optionalString('iosClientId'),
        deepLinkURLScheme: optionalString('deepLinkURLScheme'),
        appGroupId: optionalString('appGroupId'),
      );
    } catch (e) {
      throw StateError(
        'Invalid WEB_FIREBASE_OPTIONS_B64/E2E_WEB_FIREBASE_OPTIONS_B64 payload: $e',
      );
    }
  }

  Future<void> initialize(List<ChatMessage> history) async {
    print('$_TAG Initializing with model: $_currentModel');
    await _ensureFirebaseInitialized();

    final ai = FirebaseAI.googleAI();

    final addEventTool = FunctionDeclaration(
      'addEvent',
      'Add a new event to the Google Calendar. Call this when user wants to CREATE/SCHEDULE an event.',
      parameters: {
        'title': Schema.string(
            description: 'Event title - what the event is called'),
        'startTime': Schema.string(
            description:
                'Start time in ISO 8601 format (e.g., 2026-04-19T15:00:00)'),
        'endTime': Schema.string(
            description:
                'End time in ISO 8601 format - leave empty for 1 hour default'),
        'description':
            Schema.string(description: 'Optional event description/body'),
        'location': Schema.string(description: 'Optional event location'),
        'colorId': Schema.string(
            description:
                'Optional Google Calendar color ID. Use getEventColors first when color choices are needed.'),
        'visibility': Schema.string(
            description:
                'Optional visibility: default, public, private, confidential'),
        'transparency': Schema.string(
            description: 'Optional transparency: opaque or transparent'),
        'status': Schema.string(
            description: 'Optional status: confirmed, tentative, cancelled'),
        'recurrenceRules': Schema.string(
            description:
                'Optional comma-separated recurrence rules (e.g., RRULE:FREQ=WEEKLY;COUNT=10)'),
        'attendeeEmails': Schema.string(
            description: 'Optional comma-separated attendee emails'),
        'remindersUseDefault':
            Schema.string(description: 'Optional boolean string true/false'),
        'reminderMinutes': Schema.string(
            description:
                'Optional comma-separated reminder minutes (e.g., 10,30,60)'),
        'sourceTitle':
            Schema.string(description: 'Optional source title metadata'),
        'sourceUrl': Schema.string(description: 'Optional source URL metadata'),
        'allDay': Schema.string(
            description:
                'Optional boolean string true/false for all-day event'),
        'calendarId': Schema.string(
            description:
                'Optional target calendar ID/email. Defaults to configured primary calendar.'),
        'advancedFieldsJson': Schema.string(
            description:
                'Optional JSON object patch encoded as a STRING. Example: {"guestsCanModify":true} or {"extendedProperties":{"private":{"tag":"vip"}}}.'),
      },
    );

    final listEventsTool = FunctionDeclaration(
      'listEvents',
      'List calendar events for a date range. Returns full event details and event IDs. IDs are REQUIRED before delete/update. Use this for read queries and follow-up detail questions.',
      parameters: {
        'startDate': Schema.string(
            description:
                'Start date in ISO 8601 format (e.g., 2026-04-19T00:00:00)'),
        'endDate': Schema.string(
            description:
                'End date in ISO 8601 format (e.g., 2026-04-19T23:59:59)'),
        'query': Schema.string(
            description:
                'Optional free-text filter against event fields (title, description, location, etc.)'),
        'calendarId': Schema.string(
            description: 'Optional specific calendar ID/email to search in.'),
        'includeDeleted': Schema.string(
            description:
                'Optional boolean string true/false to include deleted events'),
      },
    );

    final getEventByIdTool = FunctionDeclaration(
      'getEventById',
      'Get one event by eventId with full details, including description, location, attendees, recurrence, reminders, and raw JSON.',
      parameters: {
        'eventId': Schema.string(
            description: 'Exact event ID from listEvents or mutation results'),
      },
    );

    final deleteEventTool = FunctionDeclaration(
      'deleteEvent',
      'Delete a calendar event. YOU MUST call listEvents first to get the eventId. Never guess the eventId.',
      parameters: {
        'eventId': Schema.string(
            description: 'The event ID from listEvents result - get it first!'),
      },
    );

    final updateEventTool = FunctionDeclaration(
      'updateEvent',
      'Update an existing calendar event. YOU MUST call listEvents first to get the eventId. Never guess the eventId.',
      parameters: {
        'eventId': Schema.string(
            description: 'The event ID from listEvents result - get it first!'),
        'title': Schema.string(
            description:
                'New event title (optional - only include what changes)'),
        'startTime':
            Schema.string(description: 'New start time in ISO 8601 format'),
        'endTime':
            Schema.string(description: 'New end time in ISO 8601 format'),
        'description': Schema.string(description: 'Optional new description'),
        'location': Schema.string(description: 'Optional new location'),
        'colorId': Schema.string(
            description:
                'Optional new Google Calendar color ID. Use getEventColors if needed.'),
        'visibility': Schema.string(
            description:
                'Optional visibility: default, public, private, confidential'),
        'transparency': Schema.string(
            description: 'Optional transparency: opaque or transparent'),
        'status': Schema.string(
            description: 'Optional status: confirmed, tentative, cancelled'),
        'recurrenceRules': Schema.string(
            description:
                'Optional comma-separated recurrence rules (e.g., RRULE:FREQ=WEEKLY;COUNT=10)'),
        'attendeeEmails': Schema.string(
            description: 'Optional comma-separated attendee emails'),
        'remindersUseDefault':
            Schema.string(description: 'Optional boolean string true/false'),
        'reminderMinutes': Schema.string(
            description:
                'Optional comma-separated reminder minutes (e.g., 10,30,60)'),
        'sourceTitle':
            Schema.string(description: 'Optional source title metadata'),
        'sourceUrl': Schema.string(description: 'Optional source URL metadata'),
        'allDay': Schema.string(
            description:
                'Optional boolean string true/false for all-day event'),
        'calendarId': Schema.string(
            description:
                'Optional explicit calendar ID/email (normally inferred from eventId).'),
        'advancedFieldsJson': Schema.string(
            description:
                'Optional JSON object patch encoded as a STRING. Example: {"guestsCanModify":true} or {"extendedProperties":{"private":{"tag":"vip"}}}.'),
      },
    );

    final getFreeBusyTool = FunctionDeclaration(
      'getFreeBusy',
      'Get busy time windows for a date range. Use this for explicit busy-time queries.',
      parameters: {
        'startDate': Schema.string(
            description:
                'Start date/time in ISO 8601 format (e.g., 2026-04-19T00:00:00)'),
        'endDate': Schema.string(
            description:
                'End date/time in ISO 8601 format (e.g., 2026-04-19T23:59:59)'),
      },
    );

    final findFreeSlotsTool = FunctionDeclaration(
      'findFreeSlots',
      'Find concrete free time slots in a range using calendar busy data. Use this for availability/free-slot requests.',
      parameters: {
        'startDate': Schema.string(
            description:
                'Start date/time in ISO 8601 format (e.g., 2026-04-19T00:00:00)'),
        'endDate': Schema.string(
            description:
                'End date/time in ISO 8601 format (e.g., 2026-04-26T23:59:59)'),
        'minDurationMinutes': Schema.string(
            description:
                'Required minimum free-slot duration in minutes (e.g., 180 for 3 hours)'),
        'dayStartHour': Schema.string(
            description:
                'Optional local-day window start hour in 24h format (default 8)'),
        'dayEndHour': Schema.string(
            description:
                'Optional local-day window end hour in 24h format (default 22)'),
      },
    );

    final getEventColorsTool = FunctionDeclaration(
      'getEventColors',
      'Get available event colors (color ID and hex values). Use for adding/updating event colors.',
      parameters: {},
    );

    _model = ai.generativeModel(
      model: _currentModel,
      systemInstruction: Content.system(
        SystemPrompt.build(),
      ),
      tools: [
        Tool.functionDeclarations([
          addEventTool,
          listEventsTool,
          getEventByIdTool,
          deleteEventTool,
          updateEventTool,
          getFreeBusyTool,
          findFreeSlotsTool,
          getEventColorsTool,
        ]),
      ],
    );

    final conversationHistory = history.map((message) {
      return Content.text('${message.role}: ${message.content}');
    }).toList();

    _chat = _model!.startChat(history: conversationHistory);
    _isInitialized = true;
    print('$_TAG Chat session started with function calling');
  }

  Future<void> changeModel(String modelName, List<ChatMessage> history) async {
    _currentModel = modelName;
    await initialize(history);
  }

  Future<String> sendMessage(String prompt) async {
    print('===========================================');
    print('$_TAG SEND_MESSAGE');
    print('===========================================');

    if (!_isInitialized || _chat == null) {
      return "Error: Chat is not initialized.";
    }

    final formattedPrompt = 'User query: $prompt';

    _lastPrompt = formattedPrompt;
    _lastTrace = null;
    _lastFunctionCalls = null;
    _lastResponse = null;
    _startTrace(prompt);
    _interrupted = false;

    try {
      _appendTrace('Sending user query to model with tools enabled');
      final content = Content.text(formattedPrompt);
      var response = await _chat!.sendMessage(content);
      var cycles = 0;
      final requiresFreeSlotLookup = _requiresFreeSlotLookup(prompt);
      var usedFindFreeSlots = false;

      while (cycles < AppConstants.maxAgentCycles) {
        if (_interrupted) {
          _appendTrace('Request interrupted; stopping execution loop');
          _lastTrace = _toTraceText();
          return 'Operation interrupted by user.';
        }

        final cycle = cycles + 1;
        _appendTrace('Cycle $cycle/${AppConstants.maxAgentCycles} started');
        final functionCalls = response.functionCalls.toList();
        final responseText = response.text?.trim();

        if (responseText != null && responseText.isNotEmpty) {
          _appendTrace(
              'Model text in cycle $cycle: ${_truncate(responseText)}');
        }

        if (functionCalls.isEmpty) {
          if (responseText != null && responseText.isNotEmpty) {
            if (requiresFreeSlotLookup && !usedFindFreeSlots) {
              _appendTrace(
                'Availability query ended without findFreeSlots; forcing verification cycle',
              );
              response = await _chat!.sendMessage(
                Content.text(
                  'Before finalizing availability, call findFreeSlots with the requested range '
                  'and minimum duration, then answer only from those slots.',
                ),
              );
              cycles++;
              continue;
            }

            _lastResponse = responseText;
            _appendTrace('Final response produced without further tool calls');
            _lastTrace = _toTraceText();
            return responseText;
          }

          _appendTrace('Empty model output; sending continue nudge');
          response = await _chat!.sendMessage(
            Content.text(
              'Continue working on the request. If complete, provide a final answer. '
              'If blocked, ask one concise clarification question.',
            ),
          );
          cycles++;
          continue;
        }

        _lastFunctionCalls = _formatFunctionCalls(functionCalls);
        final functionCall = functionCalls.first;
        if (functionCall.name == 'findFreeSlots') {
          usedFindFreeSlots = true;
        }
        _appendTrace(
          'Model requested tool `${functionCall.name}` with args: ${_truncate(functionCall.args)}',
        );

        if (_interrupted) {
          _appendTrace('Interrupted before tool execution');
          _lastTrace = _toTraceText();
          return 'Operation interrupted by user.';
        }

        final result = await _executeWithGuardrails(functionCall);
        _appendTrace(
          'Tool `${functionCall.name}` result: ${_truncate(result)}',
        );

        response = await _chat!.sendMessage(
          Content.functionResponse(functionCall.name, result),
        );
        _appendTrace(
          'Tool result sent back to model for next reasoning cycle',
        );
        cycles++;
      }

      final fallback = response.text?.trim();
      if (fallback != null && fallback.isNotEmpty) {
        _lastResponse = fallback;
        _appendTrace(
          'Cycle limit reached; returning latest model response as fallback',
        );
        _lastTrace = _toTraceText();
        return fallback;
      }
      _appendTrace('Cycle limit reached with no final response');
      _lastTrace = _toTraceText();
      return 'I could not complete that within the current tool cycle limit. '
          'Please confirm if you want me to continue from here.';
    } catch (e) {
      print('EXCEPTION: $e');
      _appendTrace('Exception: $e');
      _lastTrace = _toTraceText();
      return "Error: $e";
    }
  }

  String _formatFunctionCalls(List<FunctionCall> functionCalls) {
    return functionCalls.map((call) => '${call.name}: ${call.args}').join('\n');
  }

  bool _requiresFreeSlotLookup(String prompt) {
    final text = prompt.toLowerCase();
    final asksAvailability = text.contains('free') ||
        text.contains('available') ||
        text.contains('availability') ||
        text.contains('slot');
    return asksAvailability;
  }

  void _startTrace(String prompt) {
    _traceEntries.clear();
    _appendTrace('Request received: $prompt');
    _appendTrace('Model: $_currentModel');
  }

  void _appendTrace(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _traceEntries.add('[$timestamp] $message');
  }

  String _toTraceText() {
    if (_traceEntries.isEmpty) {
      return '';
    }
    return _traceEntries.join('\n');
  }

  String _truncate(dynamic value, {int maxLength = 1200}) {
    String encoded;
    if (value is String) {
      encoded = value;
    } else {
      try {
        encoded = jsonEncode(value);
      } catch (_) {
        encoded = value.toString();
      }
    }
    if (encoded.length <= maxLength) {
      return encoded;
    }
    return '${encoded.substring(0, maxLength)}... [truncated]';
  }

  int _parseIntArg(dynamic value, int fallback) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? fallback;
  }

  bool? _parseBoolArg(dynamic value, bool? fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return fallback;
  }

  List<String> _parseStringList(String? value) {
    if (value == null || value.trim().isEmpty) return const <String>[];
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<int> _parseIntList(String? value) {
    if (value == null || value.trim().isEmpty) return const <int>[];
    final results = <int>[];
    for (final token in value.split(',')) {
      final parsed = int.tryParse(token.trim());
      if (parsed != null) {
        results.add(parsed);
      }
    }
    return results;
  }

  Map<String, dynamic>? _parseJsonObject(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _eventToMap(calendar.Event event) {
    return {
      'id': event.id,
      'title': event.summary,
      'startTime': event.start?.dateTime?.toIso8601String(),
      'startDate': event.start?.date?.toIso8601String(),
      'endTime': event.end?.dateTime?.toIso8601String(),
      'endDate': event.end?.date?.toIso8601String(),
      'recurringEventId': event.recurringEventId,
      'originalStartTime': event.originalStartTime?.dateTime?.toIso8601String(),
      'originalStartDate': event.originalStartTime?.date?.toIso8601String(),
      'isRecurringInstance':
          event.recurringEventId != null && event.originalStartTime != null,
      'description': event.description,
      'location': event.location,
      'colorId': event.colorId,
      'status': event.status,
      'visibility': event.visibility,
      'transparency': event.transparency,
      'recurrence': event.recurrence,
      'attendees': event.attendees
          ?.map((a) => {
                'email': a.email,
                'displayName': a.displayName,
                'responseStatus': a.responseStatus,
                'optional': a.optional,
                'organizer': a.organizer,
                'self': a.self,
                'resource': a.resource,
              })
          .toList(),
      'reminders': event.reminders == null
          ? null
          : {
              'useDefault': event.reminders!.useDefault,
              'overrides': event.reminders!.overrides
                  ?.map((r) => {'method': r.method, 'minutes': r.minutes})
                  .toList(),
            },
      'source': event.source == null
          ? null
          : {
              'title': event.source!.title,
              'url': event.source!.url,
            },
      'htmlLink': event.htmlLink,
      'hangoutLink': event.hangoutLink,
      'calendarId': event.organizer?.email,
      'raw': event.toJson(),
    };
  }

  Future<String?> _resolveColorId(String? rawColor) async {
    if (rawColor == null || rawColor.trim().isEmpty) {
      return null;
    }

    final normalized = rawColor.trim().toLowerCase();
    final directId = int.tryParse(normalized);
    if (directId != null && directId >= 1 && directId <= 11) {
      _appendTrace('Resolved color "$rawColor" as direct color ID $directId');
      return directId.toString();
    }

    final aliasId = _colorAliases[normalized];
    if (aliasId != null) {
      _appendTrace(
          'Resolved color "$rawColor" via alias mapping to ID $aliasId');
      return aliasId;
    }

    if (normalized.startsWith('#')) {
      final colors = await _calendarService!.fetchEventColors();
      for (final entry in colors.entries) {
        final bg = entry.value['background']?.toLowerCase();
        if (bg == normalized) {
          _appendTrace('Resolved hex color "$rawColor" to ID ${entry.key}');
          return entry.key;
        }
      }
    }

    // Return the original token to allow backend/API validation feedback.
    _appendTrace(
        'Color "$rawColor" could not be mapped locally; passing raw value');
    return rawColor;
  }

  Future<Map<String, dynamic>> _executeWithGuardrails(
    FunctionCall functionCall,
  ) async {
    _appendTrace('Executing tool with guardrails: ${functionCall.name}');
    if (_interrupted) {
      return {'error': 'Operation interrupted by user'};
    }

    var result = await _executeFunction(functionCall);

    final isRetryableError =
        result.containsKey('error') && _isRetryableError(result['error']);
    if (isRetryableError) {
      _appendTrace(
        'Retryable tool error detected, triggering retry flow: ${_truncate(result['error'])}',
      );
      result = await _executeWithRetry(functionCall);
      _appendTrace('Retry flow completed with: ${_truncate(result)}');
    }

    if (!_isMutationTool(functionCall.name) || result['success'] != true) {
      return result;
    }

    final verified = await _verifyMutation(functionCall, result);
    if (verified) {
      _appendTrace('Mutation verification succeeded for ${functionCall.name}');
      return <String, dynamic>{
        ...result,
        'verified': true,
      };
    }

    _appendTrace('Mutation verification failed; retrying mutation flow');
    result = await _retryMutationWithVerification(functionCall, result);
    return result;
  }

  Future<Map<String, dynamic>> _executeFunction(
      FunctionCall functionCall) async {
    final name = functionCall.name;
    final args = functionCall.args;

    _appendTrace('Running tool handler: $name');

    if (_calendarService == null) {
      _appendTrace('Calendar service unavailable');
      return {'error': 'Calendar service not initialized'};
    }

    try {
      switch (name) {
        case 'addEvent':
          final title = args['title'] as String?;
          final startTimeStr = args['startTime'] as String?;
          final endTimeStr = args['endTime'] as String?;
          final description = args['description'] as String?;
          final location = args['location'] as String?;
          final rawColorId = args['colorId'] as String?;
          final visibility = args['visibility'] as String?;
          final transparency = args['transparency'] as String?;
          final status = args['status'] as String?;
          final recurrenceRulesRaw = args['recurrenceRules'] as String?;
          final attendeeEmailsRaw = args['attendeeEmails'] as String?;
          final remindersUseDefaultRaw = args['remindersUseDefault'];
          final reminderMinutesRaw = args['reminderMinutes'] as String?;
          final sourceTitle = args['sourceTitle'] as String?;
          final sourceUrl = args['sourceUrl'] as String?;
          final allDayRaw = args['allDay'];
          final calendarId = args['calendarId'] as String?;
          final advancedFieldsRaw = args['advancedFieldsJson'] as String?;

          if (title == null || startTimeStr == null) {
            return {'error': 'title and startTime required'};
          }

          final startTime = DateTime.parse(startTimeStr);
          final endTime =
              endTimeStr != null ? DateTime.parse(endTimeStr) : null;
          final colorId = await _resolveColorId(rawColorId);
          final recurrenceRules = _parseStringList(recurrenceRulesRaw);
          final attendeeEmails = _parseStringList(attendeeEmailsRaw);
          final remindersUseDefault =
              _parseBoolArg(remindersUseDefaultRaw, null);
          final reminderMinutes = _parseIntList(reminderMinutesRaw);
          final allDay = _parseBoolArg(allDayRaw, null);
          final advancedFields = _parseJsonObject(advancedFieldsRaw);

          _appendTrace(
            'addEvent with title="$title", start="$startTime", end="${endTime?.toIso8601String()}", '
            'colorId="$colorId", description="${_truncate(description ?? '')}", '
            'location="${_truncate(location ?? '')}", visibility="$visibility", transparency="$transparency", '
            'status="$status", recurrenceRules="${recurrenceRules.join(',')}", attendees="${attendeeEmails.join(',')}"',
          );
          final event = await _calendarService!.addEvent(
            title: title,
            startTime: startTime,
            endTime: endTime,
            description: description,
            location: location,
            colorId: colorId,
            visibility: visibility,
            transparency: transparency,
            status: status,
            recurrence: recurrenceRules.isEmpty ? null : recurrenceRules,
            attendeeEmails: attendeeEmails.isEmpty ? null : attendeeEmails,
            remindersUseDefault: remindersUseDefault,
            reminderMinutes: reminderMinutes.isEmpty ? null : reminderMinutes,
            sourceTitle: sourceTitle,
            sourceUrl: sourceUrl,
            allDay: allDay,
            calendarId: calendarId,
            advancedFields: advancedFields,
          );

          return {
            'success': true,
            'message': 'Event "${event.summary}" created',
            'event': _eventToMap(event),
            'eventId': event.id,
            'colorId': colorId,
            'requestedColor': rawColorId,
          };

        case 'listEvents':
          final startDateStr = args['startDate'] as String?;
          final endDateStr = args['endDate'] as String?;
          final query = args['query'] as String?;
          final calendarId = args['calendarId'] as String?;
          final includeDeleted =
              _parseBoolArg(args['includeDeleted'], false) ?? false;

          if (startDateStr == null) {
            return {'error': 'startDate required'};
          }

          final startDate = DateTime.parse(startDateStr);
          final endDate = endDateStr != null
              ? DateTime.parse(endDateStr)
              : startDate.add(const Duration(days: 7));
          _appendTrace(
            'listEvents for range ${startDate.toIso8601String()} to ${endDate.toIso8601String()}, '
            'query="$query", calendarId="$calendarId", includeDeleted=$includeDeleted',
          );

          final events = await _calendarService!.fetchEventsByDateRange(
            startDate,
            endDate,
            query: query,
            calendarId: calendarId,
            includeDeleted: includeDeleted,
          );

          return {
            'success': true,
            'events': events.map(_eventToMap).toList(),
            'count': events.length
          };

        case 'getEventById':
          final eventId = args['eventId'] as String?;
          if (eventId == null || eventId.trim().isEmpty) {
            return {'error': 'eventId required'};
          }
          _appendTrace('getEventById for eventId="$eventId"');
          final event = await _calendarService!.getEventById(eventId);
          if (event == null) {
            return {
              'success': false,
              'found': false,
              'eventId': eventId,
              'message': 'Event not found'
            };
          }
          return {
            'success': true,
            'found': true,
            'event': _eventToMap(event),
          };

        case 'deleteEvent':
          final eventId = args['eventId'] as String?;
          if (eventId == null) return {'error': 'eventId required'};

          _appendTrace('deleteEvent for eventId="$eventId"');
          await _calendarService!.deleteEvent(eventId);

          return {
            'success': true,
            'message': 'Event deleted',
            'eventId': eventId,
          };

        case 'updateEvent':
          final eventId = args['eventId'] as String?;
          final title = args['title'] as String?;
          final startTimeStr = args['startTime'] as String?;
          final endTimeStr = args['endTime'] as String?;
          final description = args['description'] as String?;
          final location = args['location'] as String?;
          final rawColorId = args['colorId'] as String?;
          final visibility = args['visibility'] as String?;
          final transparency = args['transparency'] as String?;
          final status = args['status'] as String?;
          final recurrenceRulesRaw = args['recurrenceRules'] as String?;
          final attendeeEmailsRaw = args['attendeeEmails'] as String?;
          final remindersUseDefaultRaw = args['remindersUseDefault'];
          final reminderMinutesRaw = args['reminderMinutes'] as String?;
          final sourceTitle = args['sourceTitle'] as String?;
          final sourceUrl = args['sourceUrl'] as String?;
          final allDayRaw = args['allDay'];
          final calendarId = args['calendarId'] as String?;
          final advancedFieldsRaw = args['advancedFieldsJson'] as String?;

          if (eventId == null) return {'error': 'eventId required'};

          final startTime =
              startTimeStr != null ? DateTime.parse(startTimeStr) : null;
          final endTime =
              endTimeStr != null ? DateTime.parse(endTimeStr) : null;
          final colorId = await _resolveColorId(rawColorId);
          final recurrenceRules = _parseStringList(recurrenceRulesRaw);
          final attendeeEmails = _parseStringList(attendeeEmailsRaw);
          final remindersUseDefault =
              _parseBoolArg(remindersUseDefaultRaw, null);
          final reminderMinutes = _parseIntList(reminderMinutesRaw);
          final allDay = _parseBoolArg(allDayRaw, null);
          final advancedFields = _parseJsonObject(advancedFieldsRaw);

          _appendTrace(
            'updateEvent for eventId="$eventId", title="$title", start="${startTime?.toIso8601String()}", '
            'end="${endTime?.toIso8601String()}", colorId="$colorId", description="${_truncate(description ?? '')}", '
            'location="${_truncate(location ?? '')}", visibility="$visibility", transparency="$transparency", '
            'status="$status", recurrenceRules="${recurrenceRules.join(',')}", attendees="${attendeeEmails.join(',')}"',
          );
          final event = await _calendarService!.updateEvent(
            eventId,
            title: title,
            startTime: startTime,
            endTime: endTime,
            description: description,
            location: location,
            colorId: colorId,
            visibility: visibility,
            transparency: transparency,
            status: status,
            recurrence: recurrenceRules.isEmpty ? null : recurrenceRules,
            attendeeEmails: attendeeEmails.isEmpty ? null : attendeeEmails,
            remindersUseDefault: remindersUseDefault,
            reminderMinutes: reminderMinutes.isEmpty ? null : reminderMinutes,
            sourceTitle: sourceTitle,
            sourceUrl: sourceUrl,
            allDay: allDay,
            calendarId: calendarId,
            advancedFields: advancedFields,
          );

          return {
            'success': true,
            'message': 'Event updated to "${event.summary}"',
            'event': _eventToMap(event),
            'eventId': event.id ?? eventId,
            'colorId': colorId,
            'requestedColor': rawColorId,
          };

        case 'getFreeBusy':
          final startDateStr = args['startDate'] as String?;
          final endDateStr = args['endDate'] as String?;

          if (startDateStr == null || endDateStr == null) {
            return {'error': 'startDate and endDate required'};
          }

          final startDate = DateTime.parse(startDateStr);
          final endDate = DateTime.parse(endDateStr);
          _appendTrace(
            'getFreeBusy for range ${startDate.toIso8601String()} to ${endDate.toIso8601String()}',
          );
          final busyPeriods =
              await _calendarService!.fetchFreeBusy(startDate, endDate);

          return {
            'success': true,
            'busyPeriods': busyPeriods,
            'count': busyPeriods.length,
          };

        case 'findFreeSlots':
          final startDateStr = args['startDate'] as String?;
          final endDateStr = args['endDate'] as String?;
          final minDurationRaw = args['minDurationMinutes'];
          final dayStartHourRaw = args['dayStartHour'];
          final dayEndHourRaw = args['dayEndHour'];

          if (startDateStr == null || endDateStr == null) {
            return {'error': 'startDate and endDate required'};
          }

          final startDate = DateTime.parse(startDateStr);
          final endDate = DateTime.parse(endDateStr);
          final minDurationMinutes = _parseIntArg(minDurationRaw, 60);
          final dayStartHour = _parseIntArg(dayStartHourRaw, 8);
          final dayEndHour = _parseIntArg(dayEndHourRaw, 22);
          _appendTrace(
            'findFreeSlots for range ${startDate.toIso8601String()} to ${endDate.toIso8601String()}, '
            'minDurationMinutes=$minDurationMinutes, dayStartHour=$dayStartHour, dayEndHour=$dayEndHour',
          );

          final freeSlots = await _calendarService!.findFreeSlots(
            start: startDate,
            end: endDate,
            minDurationMinutes: minDurationMinutes,
            dayStartHour: dayStartHour,
            dayEndHour: dayEndHour,
          );

          return {
            'success': true,
            'freeSlots': freeSlots,
            'count': freeSlots.length,
            'minDurationMinutes': minDurationMinutes,
            'dayWindow': {
              'startHour': dayStartHour,
              'endHour': dayEndHour,
            },
          };

        case 'getEventColors':
          _appendTrace('getEventColors requested');
          final colors = await _calendarService!.fetchEventColors();
          return {
            'success': true,
            'colors': colors,
            'nameAliases': _colorAliases,
            'count': colors.length,
          };

        default:
          return {'error': 'Unknown function: $name'};
      }
    } catch (e) {
      _appendTrace('Tool execution error in "$name": $e');
      return {'error': e.toString()};
    }
  }

  bool _isRetryableError(dynamic error) {
    if (error == null) return false;
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('not found') ||
        errorStr.contains('404') ||
        errorStr.contains('400') ||
        errorStr.contains('invalid') ||
        errorStr.contains('the event') ||
        errorStr.contains('required');
  }

  Future<Map<String, dynamic>> _executeWithRetry(
      FunctionCall functionCall) async {
    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      _appendTrace(
        'Retry attempt $attempt/$maxRetries for ${functionCall.name}',
      );
      final result = await _executeFunction(functionCall);
      if (!result.containsKey('error')) {
        _appendTrace('Retry attempt $attempt succeeded');
        return result;
      }
      if (!_isRetryableError(result['error'])) {
        _appendTrace(
          'Retry stopped due to non-retryable error: ${_truncate(result['error'])}',
        );
        return result;
      }
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
    _appendTrace('Retry attempts exhausted for ${functionCall.name}');
    return {'error': 'Max retries exceeded'};
  }

  bool _isMutationTool(String toolName) {
    return toolName == 'addEvent' ||
        toolName == 'updateEvent' ||
        toolName == 'deleteEvent';
  }

  Future<Map<String, dynamic>> _retryMutationWithVerification(
    FunctionCall functionCall,
    Map<String, dynamic> successfulResult,
  ) async {
    const maxVerificationRetries = 2;

    for (int attempt = 1; attempt <= maxVerificationRetries; attempt++) {
      if (_interrupted) {
        return {
          ...successfulResult,
          'verified': false,
          'verificationWarning':
              'Operation interrupted before verification finished',
        };
      }

      _appendTrace(
        'Mutation verification retry $attempt/$maxVerificationRetries for ${functionCall.name}',
      );

      final verified = await _verifyMutation(functionCall, successfulResult);
      if (verified) {
        _appendTrace(
          'Mutation verification retry $attempt succeeded',
        );
        return {
          ...successfulResult,
          'verified': true,
          'verificationRetries': attempt + 1,
        };
      }

      _appendTrace(
        'Mutation verification retry $attempt failed',
      );
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }

    _appendTrace('Mutation verification retries exhausted');
    return {
      ...successfulResult,
      'verified': false,
      'verificationWarning':
          'Operation succeeded but post-verification was inconclusive.',
    };
  }

  Future<bool> _verifyMutation(
    FunctionCall functionCall,
    Map<String, dynamic> result,
  ) async {
    final eventId =
        (result['eventId'] ?? functionCall.args['eventId']) as String?;
    if (eventId == null || eventId.isEmpty) {
      _appendTrace('Verification skipped: missing eventId');
      return false;
    }

    const checks = 3;
    for (int i = 1; i <= checks; i++) {
      _appendTrace('Verification check $i/$checks for eventId="$eventId"');
      final event = await _calendarService!.getEventById(eventId);
      final verified = _validatePostCondition(functionCall, event, result);
      if (verified) {
        _appendTrace('Verification check $i passed');
        return true;
      }
      _appendTrace('Verification check $i failed');
      await Future.delayed(Duration(milliseconds: 250 * i));
    }

    _appendTrace('Verification failed after $checks checks');
    return false;
  }

  bool _validatePostCondition(
    FunctionCall functionCall,
    calendar.Event? event,
    Map<String, dynamic> executionResult,
  ) {
    switch (functionCall.name) {
      case 'deleteEvent':
        if (event == null) {
          return true;
        }
        final status = (event.status ?? '').toLowerCase();
        return status == 'cancelled';
      case 'addEvent':
      case 'updateEvent':
        if (event == null) return false;

        final allDayExpected = _parseBoolArg(functionCall.args['allDay'], null);
        final isAllDayEvent =
            event.start?.date != null && event.start?.dateTime == null;

        if (allDayExpected == true && !isAllDayEvent) {
          return false;
        }
        if (allDayExpected == false && isAllDayEvent) {
          return false;
        }

        final expectedTitle = functionCall.args['title'] as String?;
        if (expectedTitle != null &&
            event.summary != null &&
            event.summary != expectedTitle) {
          return false;
        }

        final expectedStartText = functionCall.args['startTime'] as String?;
        if (expectedStartText != null) {
          final expectedStart = DateTime.parse(expectedStartText);
          if (allDayExpected == true || isAllDayEvent) {
            final actualStartDate = event.start?.date;
            if (actualStartDate == null ||
                actualStartDate.year != expectedStart.year ||
                actualStartDate.month != expectedStart.month ||
                actualStartDate.day != expectedStart.day) {
              return false;
            }
          } else {
            final actualStart = event.start?.dateTime;
            if (!_isNearInstant(actualStart, expectedStart)) {
              return false;
            }
          }
        }

        final expectedEndText = functionCall.args['endTime'] as String?;
        if (expectedEndText != null) {
          final expectedEnd = DateTime.parse(expectedEndText);
          if (allDayExpected == true || isAllDayEvent) {
            final actualEndDate = event.end?.date;
            final expectedEndDateOnly = DateTime(
              expectedEnd.year,
              expectedEnd.month,
              expectedEnd.day,
            );
            if (actualEndDate == null ||
                actualEndDate.isBefore(expectedEndDateOnly)) {
              return false;
            }
          } else {
            final actualEnd = event.end?.dateTime;
            if (!_isNearInstant(actualEnd, expectedEnd)) {
              return false;
            }
          }
        }

        final executionEvent = executionResult['event'];
        final expectedColorId = executionResult['colorId'] as String? ??
            (executionEvent is Map
                ? executionEvent['colorId']?.toString()
                : null) ??
            functionCall.args['colorId'] as String?;
        if (expectedColorId != null && event.colorId != expectedColorId) {
          return false;
        }

        final expectedDescription = functionCall.args['description'] as String?;
        if (expectedDescription != null &&
            event.description != expectedDescription) {
          return false;
        }

        final expectedLocation = functionCall.args['location'] as String?;
        if (expectedLocation != null && event.location != expectedLocation) {
          return false;
        }

        final expectedVisibility = functionCall.args['visibility'] as String?;
        if (expectedVisibility != null &&
            event.visibility != expectedVisibility) {
          return false;
        }

        final expectedTransparency =
            functionCall.args['transparency'] as String?;
        if (expectedTransparency != null &&
            event.transparency != expectedTransparency) {
          return false;
        }

        final expectedStatus = functionCall.args['status'] as String?;
        if (expectedStatus != null && event.status != expectedStatus) {
          return false;
        }

        final recurrenceRules =
            _parseStringList(functionCall.args['recurrenceRules'] as String?);
        if (recurrenceRules.isNotEmpty) {
          final actualRules = event.recurrence ?? const <String>[];
          for (final rule in recurrenceRules) {
            if (!actualRules.contains(rule)) {
              return false;
            }
          }
        }

        final attendeeEmails =
            _parseStringList(functionCall.args['attendeeEmails'] as String?);
        if (attendeeEmails.isNotEmpty) {
          final actualAttendees =
              (event.attendees ?? const <calendar.EventAttendee>[])
                  .map((a) => (a.email ?? '').toLowerCase())
                  .where((email) => email.isNotEmpty)
                  .toSet();
          for (final attendee in attendeeEmails) {
            if (!actualAttendees.contains(attendee.toLowerCase())) {
              return false;
            }
          }
        }

        final expectedUseDefault =
            _parseBoolArg(functionCall.args['remindersUseDefault'], null);
        if (expectedUseDefault != null &&
            event.reminders?.useDefault != expectedUseDefault) {
          return false;
        }

        final expectedReminderMinutes =
            _parseIntList(functionCall.args['reminderMinutes'] as String?);
        if (expectedReminderMinutes.isNotEmpty) {
          final actualReminderMinutes =
              (event.reminders?.overrides ?? const <calendar.EventReminder>[])
                  .map((r) => r.minutes)
                  .whereType<int>()
                  .toSet();
          for (final reminder in expectedReminderMinutes) {
            if (!actualReminderMinutes.contains(reminder)) {
              return false;
            }
          }
        }

        final expectedSourceTitle = functionCall.args['sourceTitle'] as String?;
        if (expectedSourceTitle != null &&
            event.source?.title != expectedSourceTitle) {
          return false;
        }

        final expectedSourceUrl = functionCall.args['sourceUrl'] as String?;
        if (expectedSourceUrl != null &&
            event.source?.url != expectedSourceUrl) {
          return false;
        }

        final advancedExpected = _parseJsonObject(
          functionCall.args['advancedFieldsJson'] as String?,
        );
        if (advancedExpected != null &&
            !_containsSubset(event.toJson(), advancedExpected)) {
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  bool _containsSubset(dynamic actual, dynamic expected) {
    if (expected is Map<String, dynamic>) {
      if (actual is! Map) return false;
      for (final entry in expected.entries) {
        if (!actual.containsKey(entry.key)) {
          return false;
        }
        if (!_containsSubset(actual[entry.key], entry.value)) {
          return false;
        }
      }
      return true;
    }

    if (expected is List) {
      if (actual is! List) return false;
      if (expected.isEmpty) return true;
      for (final expectedItem in expected) {
        final matched = actual
            .any((actualItem) => _containsSubset(actualItem, expectedItem));
        if (!matched) {
          return false;
        }
      }
      return true;
    }

    return actual == expected;
  }

  bool _isNearInstant(DateTime? a, DateTime? b, {int toleranceMinutes = 1}) {
    if (a == null || b == null) return false;
    final diff = a.toUtc().difference(b.toUtc()).abs();
    return diff.inMinutes <= toleranceMinutes;
  }
}
