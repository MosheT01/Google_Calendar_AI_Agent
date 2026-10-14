import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'support/target_calendar.dart';

const String _requiredTitlePrefix = 'test_event_in_';
final DateTime _january2027Start = DateTime(2027, 1, 1);
final DateTime _january2027EndExclusive = DateTime(2027, 2, 1);
final bool _runRealCalendarTests =
    Platform.environment['RUN_REAL_CALENDAR_TESTS'] == 'true' ||
    Platform.environment['RUN_PRODUCTION_CALENDAR_TESTS'] == 'true';
final String _targetCalendarId = resolveTargetCalendarIdFromEnvironment();

String _buildTaggedTitle(String suffix) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return '$_requiredTitlePrefix${suffix}_$timestamp';
}

DateTime? _eventStartLocal(calendar.Event event) {
  return event.start?.dateTime?.toLocal() ?? event.start?.date;
}

bool _isInJanuary2027(DateTime dateTime) {
  return !dateTime.isBefore(_january2027Start) &&
      dateTime.isBefore(_january2027EndExclusive);
}

void _expectInJanuary2027(DateTime value, String context) {
  expect(
    _isInJanuary2027(value),
    isTrue,
    reason:
        '$context must stay inside January 2027. Found: ${value.toIso8601String()}',
  );
}

void _expectTaggedTitle(String title) {
  expect(
    title.contains(_requiredTitlePrefix),
    isTrue,
    reason:
        'All real-calendar test events must include "$_requiredTitlePrefix" in title',
  );
}

Future<void> _cleanupTaggedJanuaryEvents(CalendarService service) async {
  final candidates = await service.fetchEventsByDateRange(
    _january2027Start,
    _january2027EndExclusive,
    calendarId: _targetCalendarId,
    includeDeleted: false,
  );

  for (final event in candidates) {
    final eventId = event.id;
    final summary = event.summary ?? '';
    final start = _eventStartLocal(event);
    if (eventId == null || eventId.isEmpty) {
      continue;
    }
    if (start == null || !_isInJanuary2027(start)) {
      continue;
    }
    if (!summary.contains(_requiredTitlePrefix)) {
      continue;
    }
    await service.deleteEvent(eventId);
  }
}

Future<List<calendar.Event>> _fetchUntilContainsEventIds(
  CalendarService service,
  Set<String> expectedIds, {
  int maxAttempts = 6,
}) async {
  var attempts = 0;
  var last = <calendar.Event>[];
  while (attempts < maxAttempts) {
    attempts++;
    last = await service.fetchEventsByDateRange(
      _january2027Start,
      _january2027EndExclusive,
      calendarId: _targetCalendarId,
      includeDeleted: false,
    );
    final ids = last.map((event) => event.id).whereType<String>().toSet();
    if (expectedIds.difference(ids).isEmpty) {
      return last;
    }
    if (attempts < maxAttempts) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  return last;
}

void main() {
  group(
    'Playground calendar integration (January 2027 + tagged titles only)',
    () {
      late CalendarService service;
      var serviceInitialized = false;
      final createdEventIds = <String>{};

      setUpAll(() async {
        service = CalendarService(
          serviceAccountLoader: () =>
              File('assets/service_account.json').readAsString(),
        );
        await service.initialize();
        serviceInitialized = true;
        print('Using locked playground calendar: $_targetCalendarId');
        await _cleanupTaggedJanuaryEvents(service);
      });

      tearDownAll(() async {
        if (!serviceInitialized) {
          return;
        }
        for (final eventId in createdEventIds) {
          try {
            await service.deleteEvent(eventId);
          } catch (_) {
            // Best-effort cleanup; the event may already be deleted.
          }
        }
        await _cleanupTaggedJanuaryEvents(service);
      });

      test('create -> read -> update -> delete single event safely', () async {
        final start = DateTime(2027, 1, 15, 10, 0);
        final end = DateTime(2027, 1, 15, 11, 0);
        _expectInJanuary2027(start, 'Create start');
        _expectInJanuary2027(end, 'Create end');

        final originalTitle = _buildTaggedTitle('crud');
        _expectTaggedTitle(originalTitle);

        final created = await service.addEvent(
          title: originalTitle,
          startTime: start,
          endTime: end,
          description: 'Playground integration test event',
          calendarId: _targetCalendarId,
        );
        expect(created.id?.isNotEmpty, isTrue);
        createdEventIds.add(created.id!);

        final fetched = await service.getEventById(created.id!);
        expect(fetched, isNotNull);
        expect(fetched!.summary, contains(_requiredTitlePrefix));
        final fetchedStart = _eventStartLocal(fetched);
        expect(fetchedStart, isNotNull);
        _expectInJanuary2027(fetchedStart!, 'Fetched event start');

        final updatedTitle = _buildTaggedTitle('crud_updated');
        _expectTaggedTitle(updatedTitle);
        final updatedStart = DateTime(2027, 1, 15, 12, 0);
        final updatedEnd = DateTime(2027, 1, 15, 13, 0);
        _expectInJanuary2027(updatedStart, 'Update start');
        _expectInJanuary2027(updatedEnd, 'Update end');

        final updated = await service.updateEvent(
          created.id!,
          title: updatedTitle,
          startTime: updatedStart,
          endTime: updatedEnd,
          calendarId: _targetCalendarId,
        );
        expect(updated.summary, contains(_requiredTitlePrefix));
        final updatedFetched = await service.getEventById(created.id!);
        expect(updatedFetched, isNotNull);
        expect(updatedFetched!.summary, updatedTitle);

        await service.deleteEvent(created.id!);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final deleted = await service.getEventById(created.id!);
        expect(
          deleted == null || deleted.status == 'cancelled',
          isTrue,
          reason: 'Deleted event should be absent or cancelled',
        );
        createdEventIds.remove(created.id!);
      });

      test('list returns tagged events in January 2027 window', () async {
        final titleA = _buildTaggedTitle('list_a');
        final titleB = _buildTaggedTitle('list_b');
        _expectTaggedTitle(titleA);
        _expectTaggedTitle(titleB);

        final eventA = await service.addEvent(
          title: titleA,
          startTime: DateTime(2027, 1, 20, 9, 0),
          endTime: DateTime(2027, 1, 20, 10, 0),
          calendarId: _targetCalendarId,
        );
        final eventB = await service.addEvent(
          title: titleB,
          startTime: DateTime(2027, 1, 21, 14, 0),
          endTime: DateTime(2027, 1, 21, 15, 0),
          calendarId: _targetCalendarId,
        );
        createdEventIds.addAll(<String>[eventA.id!, eventB.id!]);

        final listed = await _fetchUntilContainsEventIds(
          service,
          <String>{eventA.id!, eventB.id!},
        );

        final listedIds =
            listed.map((event) => event.id).whereType<String>().toSet();
        expect(listedIds.contains(eventA.id!), isTrue);
        expect(listedIds.contains(eventB.id!), isTrue);

        for (final event in listed) {
          final summary = event.summary ?? '';
          final start = _eventStartLocal(event);
          if (summary.contains(_requiredTitlePrefix) && start != null) {
            _expectInJanuary2027(start, 'Listed tagged event start');
          }
        }
      });

      test('delete one recurring instance without deleting whole series',
          () async {
        final recurringTitle = _buildTaggedTitle('recurring');
        _expectTaggedTitle(recurringTitle);

        final master = await service.addEvent(
          title: recurringTitle,
          startTime: DateTime(2027, 1, 24, 9, 0),
          endTime: DateTime(2027, 1, 24, 10, 0),
          recurrence: <String>['RRULE:FREQ=DAILY;COUNT=3'],
          calendarId: _targetCalendarId,
        );
        createdEventIds.add(master.id!);

        final instances = await service.fetchEventsByDateRange(
          DateTime(2027, 1, 24),
          DateTime(2027, 1, 28),
          query: recurringTitle,
          calendarId: _targetCalendarId,
        );

        final targetInstance = instances.firstWhere(
          (event) =>
              event.id != null &&
              event.recurringEventId != null &&
              event.originalStartTime != null,
          orElse: () => throw TestFailure(
            'No recurring instance found for recurring series test',
          ),
        );

        final targetInstanceId = targetInstance.id!;
        await service.deleteEvent(targetInstanceId);
        await Future<void>.delayed(const Duration(milliseconds: 700));

        final afterDelete = await service.getEventById(targetInstanceId);
        if (afterDelete != null) {
          expect(
            afterDelete.status,
            'cancelled',
            reason: 'Deleted recurring instance should become cancelled',
          );
        }

        final afterList = await service.fetchEventsByDateRange(
          DateTime(2027, 1, 24),
          DateTime(2027, 1, 28),
          query: recurringTitle,
          calendarId: _targetCalendarId,
          includeDeleted: false,
        );
        final remainingActiveInstances = afterList.where((event) {
          return event.recurringEventId == master.id &&
              (event.status == null || event.status != 'cancelled');
        }).toList();

        expect(
          remainingActiveInstances.isNotEmpty,
          isTrue,
          reason: 'Deleting one instance should not remove the entire series',
        );
      });

      test('freeBusy, freeSlots, and colors endpoints are callable', () async {
        final dayStart = DateTime(2027, 1, 12, 8, 0);
        final dayEnd = DateTime(2027, 1, 12, 18, 0);
        _expectInJanuary2027(dayStart, 'freeBusy start');
        _expectInJanuary2027(dayEnd, 'freeBusy end');

        final busy = await service.fetchFreeBusy(dayStart, dayEnd);
        expect(busy, isA<List<Map<String, dynamic>>>());

        final slots = await service.findFreeSlots(
          start: dayStart,
          end: dayEnd,
          minDurationMinutes: 30,
          dayStartHour: 8,
          dayEndHour: 18,
          maxResults: 5,
        );
        expect(slots, isA<List<Map<String, dynamic>>>());
        for (final slot in slots) {
          final slotStart = DateTime.parse(slot['start'] as String).toLocal();
          final slotEnd = DateTime.parse(slot['end'] as String).toLocal();
          final durationMinutes = slot['durationMinutes'] as int;
          _expectInJanuary2027(slotStart, 'Free slot start');
          _expectInJanuary2027(slotEnd, 'Free slot end');
          expect(durationMinutes >= 30, isTrue);
        }

        final colors = await service.fetchEventColors();
        expect(colors.isNotEmpty, isTrue);
      });
    },
    skip: !_runRealCalendarTests,
  );
}
