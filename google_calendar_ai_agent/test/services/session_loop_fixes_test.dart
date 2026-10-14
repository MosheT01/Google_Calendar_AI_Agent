import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/constants/system_prompt.dart';
import 'package:google_calendar_ai_agent/services/agent_loop_policy.dart';
import 'package:google_calendar_ai_agent/services/calendar_conflicts.dart';
import 'package:google_calendar_ai_agent/services/jerusalem_time.dart';

void main() {
  group('AgentLoopPolicy', () {
    test('runs every tool call in a cycle', () async {
      final calls = [
        FunctionCall.forTest('listEvents', const {'startDate': '2026-10-15'}),
        FunctionCall.forTest('listEvents', const {'startDate': '2026-10-22'}),
      ];
      final executed = <String>[];

      final results = await AgentLoopPolicy.runAll(calls, (call) async {
        executed.add(call.name);
        return call.args['startDate'];
      });

      expect(executed, ['listEvents', 'listEvents']);
      expect(results, ['2026-10-15', '2026-10-22']);
    });

    test('treats a progress sentence as unfinished', () {
      expect(
        AgentLoopPolicy.looksUnfinished(
          'I have updated the first event. I will now update the remaining events.',
        ),
        isTrue,
      );
      expect(
        AgentLoopPolicy.looksUnfinished('All 11 sessions are on the calendar.'),
        isFalse,
      );
    });

    test('blocks mutations on a lookup and allows an explicit delete', () {
      expect(AgentLoopPolicy.allowMutations('there are dups'), isFalse);
      expect(
        AgentLoopPolicy.allowMutations('check each date for all of its events'),
        isFalse,
      );
      expect(AgentLoopPolicy.allowMutations('delete them all'), isTrue);
      expect(AgentLoopPolicy.allowMutations('fix the titles'), isTrue);
    });

    test('keeps only the last 12 pairs of history', () {
      final history = List<int>.generate(40, (index) => index);
      expect(AgentLoopPolicy.recentPairs(history),
          List<int>.generate(24, (index) => index + 16));
      expect(AgentLoopPolicy.recentPairs([1, 2, 3]), [1, 2, 3]);
    });

    test('retries connection aborts and caps quota waits at 90 seconds', () {
      expect(
        AgentLoopPolicy.isConnectionAbort(
          Exception('ClientException: Software caused connection abort'),
        ),
        isTrue,
      );
      expect(
        AgentLoopPolicy.quotaRetryDelaySeconds(
          Exception('Quota exceeded. Please retry in 57.7s.'),
        ),
        58,
      );
      expect(
        AgentLoopPolicy.quotaRetryDelaySeconds(
          Exception('Quota exceeded. Please retry in 180s.'),
        ),
        90,
      );
    });
  });

  group('Jerusalem wall time', () {
    test('stores 18:00Z as 18:00 wall time', () {
      final parsed = JerusalemTime.parseWallTime('2026-10-22T18:00:00Z');
      expect(parsed, DateTime(2026, 10, 22, 18, 0, 0));
      expect(parsed.isUtc, isFalse);
    });

    test('formats a local time with a numeric offset', () {
      final formatted = JerusalemTime.formatWithOffset(
        DateTime(2026, 10, 22, 18, 0, 0),
      );
      expect(formatted.startsWith('2026-10-22T18:00:00'), isTrue);
      expect(formatted.contains('Z'), isFalse);
      expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(formatted), isTrue);
    });
  });

  group('Calendar conflicts', () {
    final competition = CalendarSpan(
      id: 'competition',
      title: 'Competition',
      start: DateTime(2026, 10, 22, 8),
      end: DateTime(2026, 10, 22, 21),
    );
    final course = CalendarSpan(
      id: 'course-a',
      title: 'helel private October (2 of 3)',
      start: DateTime(2026, 10, 22, 18),
      end: DateTime(2026, 10, 22, 21, 15),
    );
    final sameTitleLater = CalendarSpan(
      id: 'course-b',
      title: 'helel private October (2 of 3)',
      start: DateTime(2026, 10, 19, 18),
      end: DateTime(2026, 10, 19, 21, 15),
    );

    test('blocks an overlapping add until conflicts are confirmed', () {
      expect(
        () => rejectIfOverlapping(
          confirmDespiteConflicts: false,
          existing: [competition],
          start: course.start,
          end: course.end,
        ),
        throwsA(isA<CalendarConflictException>()),
      );

      expect(
        () => rejectIfOverlapping(
          confirmDespiteConflicts: true,
          existing: [competition],
          start: course.start,
          end: course.end,
        ),
        returnsNormally,
      );
    });

    test('reports the same title on different days as a collision', () {
      final groups =
          titleCollisionGroups([course, sameTitleLater, competition]);
      expect(groups, hasLength(1));
      expect(groups.single['title'], 'helel private October (2 of 3)');
      expect((groups.single['events'] as List), hasLength(2));
    });
  });

  group('SystemPrompt batch rules', () {
    test('tells the model to scan a range once and name each course', () {
      final prompt = SystemPrompt.build();
      expect(prompt.contains('earliest 00:00:00'), isTrue);
      expect(prompt.contains('Do not append Z'), isTrue);
      expect(prompt.contains('Course 2 (1 of 3)'), isTrue);
      expect(prompt.contains('confirmDespiteConflicts'), isTrue);
    });
  });
}
