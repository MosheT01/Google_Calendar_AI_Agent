import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:http/http.dart' as http;

import 'support/target_calendar.dart';

const String _requiredTitlePrefix = 'test_event_in_llm_e2e_';
const String _apiKeyPath = 'assets/gemini_api_key.json';
const String _serviceAccountPath = 'assets/service_account.json';
const String _defaultModel = 'gemini-2.5-flash';
const String _agentSystemInstruction = '''
You are a precise calendar execution agent.

Rules:
1) Use tools for all calendar actions.
2) Never claim success unless the tool succeeded.
3) For update/delete, resolve target event via listEvents first when needed.
4) Keep times in ISO 8601.
5) Be concise in final response.
''';

final DateTime _january2027Start = DateTime(2027, 1, 1);
final DateTime _january2027EndExclusive = DateTime(2027, 2, 1);
final bool _runRealLlmE2e =
    Platform.environment['RUN_REAL_LLM_E2E'] == 'true' ||
    Platform.environment['RUN_PRODUCTION_LLM_E2E'] == 'true';
final String _targetCalendarId = resolveTargetCalendarIdFromEnvironment();
final String _modelName =
    Platform.environment['LLM_E2E_MODEL']?.trim().isNotEmpty == true
        ? Platform.environment['LLM_E2E_MODEL']!.trim()
        : _defaultModel;

bool _isInJanuary2027(DateTime value) {
  return !value.isBefore(_january2027Start) &&
      value.isBefore(_january2027EndExclusive);
}

DateTime? _eventStartLocal(calendar.Event event) {
  return event.start?.dateTime?.toLocal() ?? event.start?.date;
}

Map<String, dynamic> _eventToMap(calendar.Event event) {
  return {
    'id': event.id,
    'title': event.summary,
    'startTime': event.start?.dateTime?.toIso8601String(),
    'startDate': event.start?.date?.toIso8601String(),
    'endTime': event.end?.dateTime?.toIso8601String(),
    'endDate': event.end?.date?.toIso8601String(),
    'status': event.status,
    'recurringEventId': event.recurringEventId,
    'originalStartTime': event.originalStartTime?.dateTime?.toIso8601String(),
  };
}

Future<void> _cleanupTaggedJanuaryEvents(CalendarService service) async {
  final events = await service.fetchEventsByDateRange(
    _january2027Start,
    _january2027EndExclusive,
    calendarId: _targetCalendarId,
    includeDeleted: false,
  );

  for (final event in events) {
    final eventId = event.id;
    final title = event.summary ?? '';
    final start = _eventStartLocal(event);
    if (eventId == null ||
        eventId.isEmpty ||
        start == null ||
        !_isInJanuary2027(start) ||
        !title.contains(_requiredTitlePrefix)) {
      continue;
    }
    await service.deleteEvent(eventId);
  }
}

Future<String> _loadGeminiApiKey() async {
  final raw = await File(_apiKeyPath).readAsString();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final apiKey = (decoded['api_key'] ?? '').toString().trim();
  if (apiKey.isEmpty) {
    throw StateError('Missing api_key in $_apiKeyPath');
  }
  return apiKey;
}

List<Map<String, dynamic>> _toolDeclarations() {
  return <Map<String, dynamic>>[
    {
      'name': 'addEvent',
      'description': 'Create a calendar event',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING'},
          'startTime': {'type': 'STRING'},
          'endTime': {'type': 'STRING'},
          'description': {'type': 'STRING'},
        },
        'required': ['title', 'startTime']
      },
    },
    {
      'name': 'listEvents',
      'description': 'List events in a date range',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'startDate': {'type': 'STRING'},
          'endDate': {'type': 'STRING'},
          'query': {'type': 'STRING'},
        },
        'required': ['startDate', 'endDate']
      },
    },
    {
      'name': 'getEventById',
      'description': 'Get one event by ID',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'eventId': {'type': 'STRING'},
        },
        'required': ['eventId']
      },
    },
    {
      'name': 'updateEvent',
      'description': 'Update an event',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'eventId': {'type': 'STRING'},
          'title': {'type': 'STRING'},
          'startTime': {'type': 'STRING'},
          'endTime': {'type': 'STRING'},
          'description': {'type': 'STRING'},
        },
        'required': ['eventId']
      },
    },
    {
      'name': 'deleteEvent',
      'description': 'Delete an event',
      'parameters': {
        'type': 'OBJECT',
        'properties': {
          'eventId': {'type': 'STRING'},
        },
        'required': ['eventId']
      },
    },
  ];
}

class _AgentRunResult {
  final String finalText;
  final List<String> toolCalls;

  const _AgentRunResult({
    required this.finalText,
    required this.toolCalls,
  });
}

Future<Map<String, dynamic>> _executeToolCall(
  CalendarService service,
  String name,
  Map<String, dynamic> args,
) async {
  DateTime? parseDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.parse(value);
  }

  Future<Map<String, dynamic>> guardDelete(String eventId) async {
    final event = await service.getEventById(eventId);
    if (event == null) {
      return {
        'success': false,
        'error': 'Event not found for guarded delete',
      };
    }
    final title = event.summary ?? '';
    final start = _eventStartLocal(event);
    if (!title.contains(_requiredTitlePrefix) ||
        start == null ||
        !_isInJanuary2027(start)) {
      return {
        'success': false,
        'error':
            'Guard rejected delete. Event must be tagged and inside January 2027.',
      };
    }

    await service.deleteEvent(eventId);
    return {
      'success': true,
      'eventId': eventId,
    };
  }

  switch (name) {
    case 'addEvent':
      final title = (args['title'] ?? '').toString().trim();
      final start = parseDateTime(args['startTime']?.toString());
      final end = parseDateTime(args['endTime']?.toString());
      final description = args['description']?.toString();

      if (title.isEmpty || start == null) {
        return {
          'success': false,
          'error': 'title and startTime are required',
        };
      }
      if (!title.contains(_requiredTitlePrefix)) {
        return {
          'success': false,
          'error':
              'Guard rejected addEvent. Title must include $_requiredTitlePrefix',
        };
      }
      if (!_isInJanuary2027(start) || (end != null && !_isInJanuary2027(end))) {
        return {
          'success': false,
          'error': 'Guard rejected addEvent. Time must be inside January 2027.',
        };
      }
      if (end != null && !end.isAfter(start)) {
        return {
          'success': false,
          'error': 'endTime must be after startTime',
        };
      }

      final created = await service.addEvent(
        title: title,
        startTime: start,
        endTime: end,
        description: description,
        calendarId: _targetCalendarId,
      );
      return {
        'success': true,
        'event': _eventToMap(created),
        'eventId': created.id,
      };

    case 'listEvents':
      final start = parseDateTime(args['startDate']?.toString());
      final end = parseDateTime(args['endDate']?.toString());
      final query = args['query']?.toString();

      if (start == null || end == null) {
        return {
          'success': false,
          'error': 'startDate and endDate are required',
        };
      }
      if (!end.isAfter(start)) {
        return {
          'success': false,
          'error': 'endDate must be after startDate',
        };
      }

      final safeStart =
          start.isBefore(_january2027Start) ? _january2027Start : start;
      final safeEnd = end.isAfter(_january2027EndExclusive)
          ? _january2027EndExclusive
          : end;
      if (!safeEnd.isAfter(safeStart)) {
        return {
          'success': true,
          'events': <Map<String, dynamic>>[],
          'count': 0,
        };
      }

      final events = await service.fetchEventsByDateRange(
        safeStart,
        safeEnd,
        query: query,
        calendarId: _targetCalendarId,
        includeDeleted: false,
      );

      return {
        'success': true,
        'events': events.map(_eventToMap).toList(),
        'count': events.length,
      };

    case 'getEventById':
      final eventId = (args['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) {
        return {
          'success': false,
          'error': 'eventId required',
        };
      }
      final event = await service.getEventById(eventId);
      if (event == null) {
        return {
          'success': true,
          'found': false,
        };
      }
      return {
        'success': true,
        'found': true,
        'event': _eventToMap(event),
      };

    case 'updateEvent':
      final eventId = (args['eventId'] ?? '').toString().trim();
      final title = args['title']?.toString();
      final start = parseDateTime(args['startTime']?.toString());
      final end = parseDateTime(args['endTime']?.toString());
      final description = args['description']?.toString();

      if (eventId.isEmpty) {
        return {
          'success': false,
          'error': 'eventId required',
        };
      }
      if (title != null &&
          title.trim().isNotEmpty &&
          !title.contains(_requiredTitlePrefix)) {
        return {
          'success': false,
          'error':
              'Guard rejected updateEvent title. Must include $_requiredTitlePrefix',
        };
      }
      if (start != null && !_isInJanuary2027(start)) {
        return {
          'success': false,
          'error': 'Guard rejected updateEvent startTime outside January 2027',
        };
      }
      if (end != null && !_isInJanuary2027(end)) {
        return {
          'success': false,
          'error': 'Guard rejected updateEvent endTime outside January 2027',
        };
      }
      if (start != null && end != null && !end.isAfter(start)) {
        return {
          'success': false,
          'error': 'endTime must be after startTime',
        };
      }

      final updated = await service.updateEvent(
        eventId,
        title: title,
        startTime: start,
        endTime: end,
        description: description,
        calendarId: _targetCalendarId,
      );
      return {
        'success': true,
        'event': _eventToMap(updated),
        'eventId': updated.id ?? eventId,
      };

    case 'deleteEvent':
      final eventId = (args['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) {
        return {
          'success': false,
          'error': 'eventId required',
        };
      }
      return guardDelete(eventId);

    default:
      return {
        'success': false,
        'error': 'Unknown tool: $name',
      };
  }
}

List<Map<String, dynamic>> _extractFunctionCalls(Map<String, dynamic> content) {
  final parts = content['parts'];
  if (parts is! List) return const <Map<String, dynamic>>[];

  final calls = <Map<String, dynamic>>[];
  for (final part in parts) {
    if (part is! Map) continue;
    final functionCall = part['functionCall'];
    if (functionCall is! Map) continue;

    final name = functionCall['name']?.toString();
    final argsRaw = functionCall['args'];
    Map<String, dynamic> args = <String, dynamic>{};
    if (argsRaw is Map) {
      args = argsRaw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (name != null && name.isNotEmpty) {
      calls.add({
        'name': name,
        'args': args,
      });
    }
  }
  return calls;
}

String _extractText(Map<String, dynamic> content) {
  final parts = content['parts'];
  if (parts is! List) return '';
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is! Map) continue;
    final text = part['text'];
    if (text is String && text.trim().isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(text.trim());
    }
  }
  return buffer.toString().trim();
}

Future<_AgentRunResult> _runGoalWithGeminiTools({
  required CalendarService calendarService,
  required String apiKey,
  required String userGoal,
  int maxCycles = 12,
}) async {
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '$_modelName:generateContent?key=$apiKey',
  );

  final contents = <Map<String, dynamic>>[
    {
      'role': 'user',
      'parts': [
        {'text': userGoal},
      ],
    },
  ];
  final toolCalls = <String>[];

  for (var i = 0; i < maxCycles; i++) {
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': _agentSystemInstruction},
        ],
      },
      'tools': [
        {
          'functionDeclarations': _toolDeclarations(),
        }
      ],
      'contents': contents,
      'generationConfig': {
        'temperature': 0.1,
      },
    };

    final response = await http.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      throw StateError(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw StateError('Gemini returned no candidates: ${response.body}');
    }

    final first = candidates.first;
    if (first is! Map) {
      throw StateError('Invalid candidate payload: ${response.body}');
    }

    final contentRaw = first['content'];
    if (contentRaw is! Map) {
      throw StateError('Candidate content missing: ${response.body}');
    }
    final content = contentRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final modelContent = <String, dynamic>{
      'role': (content['role'] ?? 'model').toString(),
      'parts':
          (content['parts'] is List) ? content['parts'] : const <dynamic>[],
    };
    contents.add(modelContent);

    final functionCalls = _extractFunctionCalls(content);
    if (functionCalls.isEmpty) {
      final text = _extractText(content);
      if (text.isNotEmpty) {
        return _AgentRunResult(finalText: text, toolCalls: toolCalls);
      }

      contents.add({
        'role': 'user',
        'parts': [
          {
            'text': 'Continue. If done, provide a concise final confirmation.',
          }
        ],
      });
      continue;
    }

    for (final functionCall in functionCalls) {
      final name = functionCall['name'] as String;
      final args = (functionCall['args'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      toolCalls.add(name);

      final executionResult = await _executeToolCall(
        calendarService,
        name,
        args,
      );

      contents.add(
        {
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': name,
                'response': executionResult,
              }
            }
          ],
        },
      );
    }
  }

  throw StateError('Agent exceeded maxCycles=$maxCycles without final text');
}

Future<calendar.Event?> _findEventByTitleWithRetry({
  required CalendarService service,
  required String title,
  required DateTime day,
  int maxAttempts = 6,
  bool includeDeleted = false,
}) async {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  for (var i = 0; i < maxAttempts; i++) {
    final events = await service.fetchEventsByDateRange(
      dayStart,
      dayEnd,
      calendarId: _targetCalendarId,
      includeDeleted: includeDeleted,
    );
    for (final event in events) {
      if ((event.summary ?? '').trim() == title.trim()) {
        return event;
      }
    }
    if (i < maxAttempts - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  return null;
}

void main() {
  group(
    'Playground LLM goal E2E (live model + live calendar)',
    () {
      late CalendarService calendarService;
      late String apiKey;
      var initialized = false;
      final createdEventIds = <String>{};
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch.toString();
      final eventTitle = '${_requiredTitlePrefix}goal_$uniqueSuffix';
      const targetDay = 18;
      const targetDayPadded = '18';

      setUpAll(() async {
        calendarService = CalendarService(
          serviceAccountLoader: () => File(_serviceAccountPath).readAsString(),
        );
        await calendarService.initialize();
        apiKey = await _loadGeminiApiKey();
        initialized = true;
        print('Using locked playground calendar: $_targetCalendarId');
        await _cleanupTaggedJanuaryEvents(calendarService);
      });

      tearDownAll(() async {
        if (!initialized) return;
        for (final eventId in createdEventIds) {
          try {
            await calendarService.deleteEvent(eventId);
          } catch (_) {
            // Ignore best-effort cleanup failures.
          }
        }
        await _cleanupTaggedJanuaryEvents(calendarService);
      });

      test(
        'LLM can execute create -> update -> delete goals and calendar state matches',
        () async {
          final createGoal = '''
Create one calendar event with:
- title: $eventTitle
- start: 2027-01-${targetDayPadded}T10:00:00
- end: 2027-01-${targetDayPadded}T11:00:00
- description: playground llm e2e create
Use tools and then confirm completion.
''';

          final createRun = await _runGoalWithGeminiTools(
            calendarService: calendarService,
            apiKey: apiKey,
            userGoal: createGoal,
          );

          expect(
            createRun.toolCalls.contains('addEvent'),
            isTrue,
            reason: 'Create goal should call addEvent',
          );

          final createdEvent = await _findEventByTitleWithRetry(
            service: calendarService,
            title: eventTitle,
            day: DateTime(2027, 1, targetDay),
          );
          expect(createdEvent, isNotNull);
          expect(createdEvent!.id, isNotNull);
          createdEventIds.add(createdEvent.id!);

          final createdStart = _eventStartLocal(createdEvent);
          expect(createdStart, isNotNull);
          expect(_isInJanuary2027(createdStart!), isTrue);
          expect(createdStart.hour, 10);
          expect(createdStart.minute, 0);

          final updateGoal = '''
Update the existing event titled "$eventTitle":
- move start to 2027-01-${targetDayPadded}T12:00:00
- move end to 2027-01-${targetDayPadded}T13:00:00
- set description to: playground llm e2e updated
Use tools and confirm completion.
''';

          final updateRun = await _runGoalWithGeminiTools(
            calendarService: calendarService,
            apiKey: apiKey,
            userGoal: updateGoal,
          );

          expect(
            updateRun.toolCalls.contains('updateEvent'),
            isTrue,
            reason: 'Update goal should call updateEvent',
          );

          final updatedEvent = await _findEventByTitleWithRetry(
            service: calendarService,
            title: eventTitle,
            day: DateTime(2027, 1, targetDay),
          );
          expect(updatedEvent, isNotNull);
          final updatedStart = _eventStartLocal(updatedEvent!);
          expect(updatedStart, isNotNull);
          expect(updatedStart!.hour, 12);
          expect(updatedStart.minute, 0);
          expect(updatedEvent.description, 'playground llm e2e updated');

          final deleteGoal = '''
Delete the event titled "$eventTitle" on 2027-01-$targetDay.
Use tools and confirm deletion.
''';

          final deleteRun = await _runGoalWithGeminiTools(
            calendarService: calendarService,
            apiKey: apiKey,
            userGoal: deleteGoal,
          );

          expect(
            deleteRun.toolCalls.contains('deleteEvent'),
            isTrue,
            reason: 'Delete goal should call deleteEvent',
          );

          final deletedCheck = await _findEventByTitleWithRetry(
            service: calendarService,
            title: eventTitle,
            day: DateTime(2027, 1, targetDay),
            includeDeleted: false,
          );
          expect(
            deletedCheck == null ||
                (deletedCheck.status != null &&
                    deletedCheck.status!.toLowerCase() == 'cancelled'),
            isTrue,
            reason: 'Deleted event should be absent or cancelled',
          );

          expect(createRun.finalText.trim().isNotEmpty, isTrue);
          expect(updateRun.finalText.trim().isNotEmpty, isTrue);
          expect(deleteRun.finalText.trim().isNotEmpty, isTrue);
        },
        timeout: const Timeout(Duration(minutes: 8)),
      );
    },
    skip: !_runRealLlmE2e,
  );
}
