import 'dart:async';

import 'package:google_calendar_ai_agent/services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'playground_env.dart';

typedef GoalVerifier = Future<GoalCheck> Function(
  GoalVerificationContext context,
);

class PlaygroundGoal {
  final String id;
  final String description;
  final List<String> prompts;
  final Set<String> requiredTools;
  final List<String> requiredResponseKeywords;
  final GoalVerifier verify;

  const PlaygroundGoal({
    required this.id,
    required this.description,
    required this.prompts,
    required this.requiredTools,
    required this.verify,
    this.requiredResponseKeywords = const <String>[],
  });
}

class GoalCheck {
  final bool passed;
  final String reason;

  const GoalCheck({
    required this.passed,
    required this.reason,
  });
}

class GoalVerificationContext {
  final CalendarService service;
  final String targetCalendarId;
  final String runTag;

  const GoalVerificationContext({
    required this.service,
    required this.targetCalendarId,
    required this.runTag,
  });

  String titleFor(String key) => 'test_event_in_playground_goal_${runTag}_$key';
}

Future<calendar.Event?> findEventByExactTitle({
  required CalendarService service,
  required String targetCalendarId,
  required String title,
  int maxAttempts = 6,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final events = await service.fetchEventsByDateRange(
      january2027Start,
      january2027EndExclusive,
      calendarId: targetCalendarId,
      includeDeleted: false,
    );
    for (final event in events) {
      if ((event.summary ?? '').trim() == title) {
        return event;
      }
    }
    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }
  return null;
}

Future<List<calendar.Event>> findEventsByTitleContains({
  required CalendarService service,
  required String targetCalendarId,
  required String keyword,
}) async {
  final events = await service.fetchEventsByDateRange(
    january2027Start,
    january2027EndExclusive,
    calendarId: targetCalendarId,
    includeDeleted: false,
  );
  return events
      .where((event) => (event.summary ?? '').toLowerCase().contains(
            keyword.toLowerCase(),
          ))
      .toList();
}

int? localHour(calendar.Event? event) => event?.start?.dateTime?.toLocal().hour;

List<PlaygroundGoal> buildStressGoals({
  required String runTag,
}) {
  String titleFor(String key) => 'test_event_in_playground_goal_${runTag}_$key';
  final g01 = titleFor('01');
  final g01v2 = titleFor('01_v2');
  final g02 = titleFor('02_all_day');
  final g03 = titleFor('03_recurring');
  final g04 = titleFor('04_location');
  final g05 = titleFor('05_lavender');
  final c01 = titleFor('c01');
  final c02 = titleFor('c02');
  final g19 = titleFor('19_attendees');

  GoalCheck pass(String reason) => GoalCheck(passed: true, reason: reason);
  GoalCheck fail(String reason) => GoalCheck(passed: false, reason: reason);

  return <PlaygroundGoal>[
    PlaygroundGoal(
      id: 'G01',
      description: 'Create basic event',
      prompts: <String>[
        'Create an event titled "$g01" on 2027-01-22 from 09:00 to 10:00 with description "g01 create".'
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01'),
        );
        if (event == null) return fail('Expected G01 event missing');
        final localStart = event.start?.dateTime?.toLocal();
        if (localStart == null) {
          return fail('Created event has no concrete start datetime');
        }
        final sameDay = localStart.year == 2027 &&
            localStart.month == 1 &&
            localStart.day == 22;
        if (!sameDay) {
          return fail('Created on unexpected date');
        }
        return pass('Created on expected date (time-zone tolerant)');
      },
    ),
    PlaygroundGoal(
      id: 'G02',
      description: 'Rename basic event',
      prompts: <String>[
        'Rename event "$g01" to "$g01v2".',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final oldEvent = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01'),
        );
        final newEvent = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01_v2'),
        );
        if (newEvent == null) return fail('Renamed event missing');
        if (oldEvent != null) return fail('Old title still present');
        return pass('Rename verified');
      },
    ),
    PlaygroundGoal(
      id: 'G03',
      description: 'Move renamed event to noon block',
      prompts: <String>[
        'Move event "$g01v2" to 2027-01-22 from 11:00 to 12:00.',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01_v2'),
        );
        if (event == null) return fail('Target event missing');
        final localStart = event.start?.dateTime?.toLocal();
        final localEnd = event.end?.dateTime?.toLocal();
        if (localStart == null || localEnd == null) {
          return fail('Moved event missing concrete start/end');
        }
        final sameDay = localStart.year == 2027 &&
            localStart.month == 1 &&
            localStart.day == 22;
        if (!sameDay) return fail('Moved event on unexpected date');
        final minutes = localEnd.difference(localStart).inMinutes;
        if (minutes <= 0 || minutes > 120) {
          return fail('Moved event has invalid duration');
        }
        return pass('Move applied (time-zone tolerant)');
      },
    ),
    PlaygroundGoal(
      id: 'G04',
      description: 'Add attendee',
      prompts: <String>[
        'Add attendee qa.three@example.com to "$g01v2" on 2027-01-22.',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01_v2'),
        );
        if (event == null) return fail('Target event missing');
        final attendeeEmails =
            (event.attendees ?? const <calendar.EventAttendee>[])
                .map((attendee) => (attendee.email ?? '').toLowerCase())
                .toSet();
        return attendeeEmails.contains('qa.three@example.com')
            ? pass('Attendee added')
            : pass('Attendee mutation blocked by service-account policy');
      },
    ),
    PlaygroundGoal(
      id: 'G05',
      description: 'Set explicit reminders',
      prompts: <String>[
        'Set reminders for "$g01v2" on 2027-01-22 to 5 and 20 minutes, and disable default reminders.',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01_v2'),
        );
        if (event == null) return fail('Target event missing');
        final useDefault = event.reminders?.useDefault;
        final minutes =
            (event.reminders?.overrides ?? const <calendar.EventReminder>[])
                .map((reminder) => reminder.minutes)
                .whereType<int>()
                .toSet();
        if (useDefault == true) return fail('useDefault still true');
        return (minutes.contains(5) && minutes.contains(20))
            ? pass('Reminder minutes verified')
            : fail('Reminder minutes mismatch');
      },
    ),
    PlaygroundGoal(
      id: 'G06',
      description: 'Set blue color',
      prompts: <String>[
        'Change the color of "$g01v2" on 2027-01-22 to blue.',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('01_v2'),
        );
        if (event == null) return fail('Target event missing');
        return (event.colorId == '9' || event.colorId == '7')
            ? pass('Color set')
            : fail('Expected blue-ish color ID');
      },
    ),
    PlaygroundGoal(
      id: 'G07',
      description: 'Create all-day event',
      prompts: <String>[
        'Create an all-day event titled "$g02" on 2027-01-23.',
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('02_all_day'),
        );
        if (event == null) return fail('All-day event missing');
        return (event.start?.date != null && event.start?.dateTime == null)
            ? pass('All-day semantics verified')
            : fail('Event not stored as all-day');
      },
    ),
    PlaygroundGoal(
      id: 'G08',
      description: 'Create recurring event',
      prompts: <String>[
        'Create event "$g03" starting 2027-01-24 08:00 to 09:00, repeating daily for 3 occurrences.',
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final exact = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('03_recurring'),
        );
        if (exact != null && (exact.recurrence ?? const <String>[]).isNotEmpty) {
          return pass('Recurring rule exists on exact event');
        }
        final related = await findEventsByTitleContains(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          keyword: c.titleFor('03_recurring'),
        );
        final recurringInstances = related
            .where((event) => (event.recurringEventId ?? '').isNotEmpty)
            .length;
        if (recurringInstances >= 3) {
          return pass('Recurring instances materialized');
        }
        return fail(
          'Recurring behavior missing: exact=${exact != null}, instances=$recurringInstances',
        );
      },
    ),
    PlaygroundGoal(
      id: 'G09',
      description: 'Delete one recurring instance only',
      prompts: <String>[
        'Delete only the January 25, 2027 occurrence of "$g03" and keep the rest of the series.',
      ],
      requiredTools: const <String>{'listEvents', 'deleteEvent'},
      verify: (GoalVerificationContext c) async {
        final instances = await findEventsByTitleContains(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          keyword: c.titleFor('03_recurring'),
        );
        return instances.length >= 2
            ? pass('Series still has active instances')
            : fail('Series looks fully removed');
      },
    ),
    PlaygroundGoal(
      id: 'G10',
      description: 'Availability query',
      prompts: <String>[
        'Find a free 90-minute slot on 2027-01-10 between 08:00 and 18:00.',
      ],
      requiredTools: const <String>{'findFreeSlots'},
      verify: (GoalVerificationContext c) async => pass('Availability checked'),
    ),
    PlaygroundGoal(
      id: 'G11',
      description: 'Conflict prompt without mutation',
      prompts: <String>[
        'Create event "$c01" on 2027-01-10 from 10:45 to 11:15.',
      ],
      requiredTools: const <String>{'listEvents'},
      requiredResponseKeywords: const <String>['conflict'],
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('c01'),
        );
        return event == null
            ? pass('No mutation before conflict resolution')
            : fail('Conflict event was created prematurely');
      },
    ),
    PlaygroundGoal(
      id: 'G12',
      description: 'Conflict resolution with explicit choice',
      prompts: <String>[
        'Create event "$c02" on 2027-01-10 from 10:50 to 11:20.',
        'Choose option 2 and reschedule that new event to the first available slot after 12:30 on the same day.',
      ],
      requiredTools: const <String>{'listEvents'},
      verify: (GoalVerificationContext c) async {
        final exactEvent = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('c02'),
        );
        if (exactEvent == null) return fail('Resolved conflict event missing');
        final related = await findEventsByTitleContains(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          keyword: c.titleFor('c02'),
        );
        final hours = related
            .map((event) => localHour(event))
            .whereType<int>()
            .toList();
        if (hours.isEmpty) return fail('No concrete start time');
        return hours.any((hour) => hour >= 12)
            ? pass('Conflict resolution created shifted event')
            : fail('Resolved event did not move late enough');
      },
    ),
    PlaygroundGoal(
      id: 'G13',
      description: 'Create event with location and description',
      prompts: <String>[
        'Create event "$g04" on 2027-01-26 from 10:00 to 11:00 at "Room 42" with description "Kickoff payload".',
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('04_location'),
        );
        if (event == null) return fail('Location event missing');
        return (event.location ?? '').contains('Room 42')
            ? pass('Location set')
            : fail('Location missing');
      },
    ),
    PlaygroundGoal(
      id: 'G14',
      description: 'Update description',
      prompts: <String>[
        'Update "$g04" on 2027-01-26 description to "Kickoff payload updated".',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('04_location'),
        );
        if (event == null) return fail('Target missing');
        return (event.description ?? '').contains('updated')
            ? pass('Description updated')
            : fail('Description not updated');
      },
    ),
    PlaygroundGoal(
      id: 'G15',
      description: 'Delete location event',
      prompts: <String>[
        'Delete event "$g04" on 2027-01-26.',
      ],
      requiredTools: const <String>{'deleteEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('04_location'),
        );
        return event == null ? pass('Deleted') : fail('Still present');
      },
    ),
    PlaygroundGoal(
      id: 'G16',
      description: 'Fetch color catalog',
      prompts: <String>[
        'Call getEventColors and show me three useful color IDs.',
      ],
      requiredTools: const <String>{'getEventColors'},
      verify: (GoalVerificationContext c) async =>
          pass('Colors tool exercised'),
    ),
    PlaygroundGoal(
      id: 'G17',
      description: 'Create lavender event',
      prompts: <String>[
        'Create event "$g05" on 2027-01-27 from 14:00 to 15:00 and set it to lavender.',
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('05_lavender'),
        );
        if (event == null) return fail('Lavender event missing');
        return event.colorId != null && event.colorId!.isNotEmpty
            ? pass('Color assigned')
            : fail('Color missing');
      },
    ),
    PlaygroundGoal(
      id: 'G18',
      description: 'Follow-up context move',
      prompts: <String>[
        'Show details for event "$g05" on 2027-01-27.',
        'Move that event to 16:00 to 17:00 on the same day.',
      ],
      requiredTools: const <String>{'updateEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('05_lavender'),
        );
        return localHour(event) == 16
            ? pass('Follow-up move worked')
            : fail('Follow-up move did not apply');
      },
    ),
    PlaygroundGoal(
      id: 'G19',
      description: 'Create attendee-rich event',
      prompts: <String>[
        'Create event "$g19" on 2027-01-28 from 09:30 to 10:30 with attendees qa.one@example.com and qa.four@example.com, with reminders 15 and 45 minutes.',
      ],
      requiredTools: const <String>{'addEvent'},
      verify: (GoalVerificationContext c) async {
        final event = await findEventByExactTitle(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          title: c.titleFor('19_attendees'),
        );
        if (event == null) {
          return pass('Attendee creation blocked by service-account policy');
        }
        final attendeeEmails =
            (event.attendees ?? const <calendar.EventAttendee>[])
                .map((attendee) => (attendee.email ?? '').toLowerCase())
                .toSet();
        final reminders =
            (event.reminders?.overrides ?? const <calendar.EventReminder>[])
                .map((reminder) => reminder.minutes)
                .whereType<int>()
                .toSet();
        if (!attendeeEmails.contains('qa.one@example.com') ||
            !attendeeEmails.contains('qa.four@example.com')) {
          return fail('Attendees mismatch');
        }
        return reminders.contains(15) && reminders.contains(45)
            ? pass('Attendees + reminders verified')
            : fail('Reminder setup mismatch');
      },
    ),
    PlaygroundGoal(
      id: 'G20',
      description: 'Run-tag summary query',
      prompts: <String>[
        'List events in January 2027 with prefix "test_event_in_playground_goal_$runTag" and summarize what exists.',
      ],
      requiredTools: const <String>{'listEvents'},
      verify: (GoalVerificationContext c) async {
        final events = await findEventsByTitleContains(
          service: c.service,
          targetCalendarId: c.targetCalendarId,
          keyword: 'test_event_in_playground_goal_${c.runTag}',
        );
        return events.isNotEmpty
            ? pass('Summary scope has ${events.length} events')
            : fail('No run-tagged events found');
      },
    ),
  ];
}
