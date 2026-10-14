import 'package:google_calendar_ai_agent/services/calendar_service.dart';

import 'playground_env.dart';

const String playgroundSeedPrefix = 'test_event_in_playground_seed_';

class PlaygroundSeedResult {
  final Map<String, String> eventIdsByKey;
  final int totalSeeded;

  const PlaygroundSeedResult({
    required this.eventIdsByKey,
    required this.totalSeeded,
  });
}

Future<void> hardResetJanuary2027({
  required CalendarService service,
  required String targetCalendarId,
  int maxPasses = 8,
}) async {
  for (var pass = 1; pass <= maxPasses; pass++) {
    final events = await service.fetchEventsByDateRange(
      january2027Start,
      january2027EndExclusive,
      calendarId: targetCalendarId,
      includeDeleted: false,
    );

    if (events.isEmpty) {
      return;
    }

    for (final event in events) {
      final eventId = event.id;
      if (eventId == null || eventId.isEmpty) {
        continue;
      }
      await service.deleteEvent(eventId);
    }
  }

  final remaining = await service.fetchEventsByDateRange(
    january2027Start,
    january2027EndExclusive,
    calendarId: targetCalendarId,
    includeDeleted: false,
  );
  if (remaining.isNotEmpty) {
    throw StateError(
      'Hard reset failed: January 2027 still has ${remaining.length} events on target calendar.',
    );
  }
}

Future<PlaygroundSeedResult> seedPlaygroundMatrix({
  required CalendarService service,
  required String targetCalendarId,
}) async {
  final seededIds = <String, String>{};

  Future<void> addSeed({
    required String key,
    required String title,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
    String? colorId,
    List<String>? recurrence,
    List<String>? attendeeEmails,
    bool? remindersUseDefault,
    List<int>? reminderMinutes,
    bool? allDay,
  }) async {
    try {
      final created = await service.addEvent(
        title: '$playgroundSeedPrefix$title',
        startTime: start,
        endTime: end,
        description: description,
        location: location,
        colorId: colorId,
        recurrence: recurrence,
        attendeeEmails: attendeeEmails,
        remindersUseDefault: remindersUseDefault,
        reminderMinutes: reminderMinutes,
        allDay: allDay,
        calendarId: targetCalendarId,
      );
      if (created.id != null && created.id!.isNotEmpty) {
        seededIds[key] = created.id!;
      }
    } catch (e) {
      final lower = e.toString().toLowerCase();
      final attendeeInviteBlocked = attendeeEmails != null &&
          lower.contains('service accounts cannot invite attendees');
      if (attendeeInviteBlocked) {
        print(
          '[PlaygroundSeed] Skipping attendee fixture "$key" due to service-account attendee restriction.',
        );
        return;
      }
      rethrow;
    }
  }

  await addSeed(
    key: 'overlap_a',
    title: 'overlap_a',
    start: DateTime(2027, 1, 10, 9, 0),
    end: DateTime(2027, 1, 10, 11, 0),
    description: 'Busy block A for conflict tests',
  );
  await addSeed(
    key: 'overlap_b',
    title: 'overlap_b',
    start: DateTime(2027, 1, 10, 10, 30),
    end: DateTime(2027, 1, 10, 12, 30),
    description: 'Busy block B for overlap tests',
  );
  await addSeed(
    key: 'afternoon_anchor',
    title: 'afternoon_anchor',
    start: DateTime(2027, 1, 10, 14, 0),
    end: DateTime(2027, 1, 10, 15, 0),
    description: 'Anchor event to leave free windows around it',
  );
  await addSeed(
    key: 'all_day',
    title: 'all_day',
    start: DateTime(2027, 1, 11),
    end: DateTime(2027, 1, 12),
    allDay: true,
    description: 'All-day scenario fixture',
  );
  await addSeed(
    key: 'recurring_core',
    title: 'recurring_core',
    start: DateTime(2027, 1, 12, 9, 0),
    end: DateTime(2027, 1, 12, 10, 0),
    recurrence: const <String>['RRULE:FREQ=DAILY;COUNT=4'],
    description: 'Recurring fixture for instance-level operations',
  );
  await addSeed(
    key: 'attendees_fixture',
    title: 'attendees_fixture',
    start: DateTime(2027, 1, 13, 16, 0),
    end: DateTime(2027, 1, 13, 17, 0),
    attendeeEmails: const <String>['qa.one@example.com', 'qa.two@example.com'],
    description: 'Fixture with attendees',
  );
  await addSeed(
    key: 'reminders_fixture',
    title: 'reminders_fixture',
    start: DateTime(2027, 1, 14, 11, 0),
    end: DateTime(2027, 1, 14, 12, 0),
    remindersUseDefault: false,
    reminderMinutes: const <int>[10, 30],
    description: 'Fixture with explicit reminders',
  );
  await addSeed(
    key: 'color_fixture',
    title: 'color_fixture_blue',
    start: DateTime(2027, 1, 15, 13, 0),
    end: DateTime(2027, 1, 15, 14, 0),
    colorId: '9',
    description: 'Fixture with explicit color',
  );
  await addSeed(
    key: 'location_fixture',
    title: 'location_desc_fixture',
    start: DateTime(2027, 1, 16, 10, 0),
    end: DateTime(2027, 1, 16, 11, 0),
    location: 'Seed Room 16A',
    description: 'Location and description fixture',
  );
  await addSeed(
    key: 'conflict_target',
    title: 'conflict_target',
    start: DateTime(2027, 1, 18, 12, 0),
    end: DateTime(2027, 1, 18, 13, 0),
    description: 'Known conflict target window',
  );
  await addSeed(
    key: 'freebusy_busy1',
    title: 'freebusy_busy1',
    start: DateTime(2027, 1, 20, 9, 0),
    end: DateTime(2027, 1, 20, 10, 0),
    description: 'Busy block for availability checks',
  );
  await addSeed(
    key: 'freebusy_busy2',
    title: 'freebusy_busy2',
    start: DateTime(2027, 1, 20, 11, 0),
    end: DateTime(2027, 1, 20, 12, 0),
    description: 'Second busy block for availability checks',
  );

  final januaryEvents = await service.fetchEventsByDateRange(
    january2027Start,
    january2027EndExclusive,
    calendarId: targetCalendarId,
    includeDeleted: false,
  );
  final seededEvents = januaryEvents.where((event) {
    final summary = (event.summary ?? '').trim();
    return summary.startsWith(playgroundSeedPrefix);
  }).toList();

  if (seededEvents.length < seededIds.length) {
    throw StateError(
      'Seed verification failed. Expected at least ${seededIds.length} fixtures, found ${seededEvents.length}.',
    );
  }

  return PlaygroundSeedResult(
    eventIdsByKey: seededIds,
    totalSeeded: seededEvents.length,
  );
}

class SnapshotEvent {
  final String id;
  final String title;
  final String start;
  final String end;
  final String status;

  const SnapshotEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.status,
  });
}

class CalendarSnapshot {
  final Map<String, SnapshotEvent> byId;

  const CalendarSnapshot(this.byId);
}

Future<CalendarSnapshot> captureJanuarySnapshot({
  required CalendarService service,
  required String targetCalendarId,
}) async {
  final events = await service.fetchEventsByDateRange(
    january2027Start,
    january2027EndExclusive,
    calendarId: targetCalendarId,
    includeDeleted: false,
  );

  final byId = <String, SnapshotEvent>{};
  for (final event in events) {
    final id = event.id;
    if (id == null || id.isEmpty) continue;
    byId[id] = SnapshotEvent(
      id: id,
      title: event.summary ?? '',
      start: event.start?.dateTime?.toIso8601String() ??
          event.start?.date?.toIso8601String() ??
          '',
      end: event.end?.dateTime?.toIso8601String() ??
          event.end?.date?.toIso8601String() ??
          '',
      status: event.status ?? '',
    );
  }
  return CalendarSnapshot(byId);
}
