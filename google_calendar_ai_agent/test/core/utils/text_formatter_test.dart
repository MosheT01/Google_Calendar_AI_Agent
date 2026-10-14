import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/utils/text_formatter.dart';

void main() {
  group('TextFormatter', () {
    group('formatForSpeech', () {
      test('should return empty string for empty input', () {
        final result = TextFormatter.formatForSpeech('');
        expect(result, '');
      });

      test('should add period if no period in 100 characters', () {
        final text = 'a' * 99 + ' b';
        final result = TextFormatter.formatForSpeech(text);
        expect(result.contains('.'), true);
      });

      test('should not add extra period if text already has period', () {
        const text = 'Hello world. This is a test.';
        final result = TextFormatter.formatForSpeech(text);
        expect(result.contains('Hello world.'), true);
      });
    });

    group('cleanResponse', () {
      test('should remove mode prefix', () {
        final result = TextFormatter.cleanResponse('mode=generic Hello world');
        expect(result, 'Hello world');
      });

      test('should remove multiple newlines', () {
        final result = TextFormatter.cleanResponse('Hello\n\n\nWorld');
        expect(result, 'Hello\nWorld');
      });

      test('should remove asterisks', () {
        final result = TextFormatter.cleanResponse('Hello *world* test');
        expect(result.contains('*'), false);
      });
    });

    group('cleanResponseForDisplay', () {
      test('should preserve markdown emphasis', () {
        final result =
            TextFormatter.cleanResponseForDisplay('mode=generic Hello *world*');
        expect(result, 'Hello *world*');
      });
    });

    group('cleanResponseForSpeech', () {
      test('should strip markdown links and code formatting', () {
        final result = TextFormatter.cleanResponseForSpeech(
          'Use [`listEvents`](https://example.com) and `deleteEvent`.',
        );
        expect(result.contains('listEvents'), true);
        expect(result.contains('https://example.com'), false);
        expect(result.contains('`'), false);
        expect(result.contains('['), false);
      });
    });

    group('humanizeDateTimes', () {
      test('should convert ISO date and time to readable format', () {
        final result = TextFormatter.humanizeDateTimes(
          'Event at 2026-04-23 09:00:00',
        );
        expect(result.contains('April 23, 2026 9:00 AM'), true);
      });

      test('should convert standalone 24h time to am/pm', () {
        final result = TextFormatter.humanizeDateTimes('From 14:30 to 15:45');
        expect(result.contains('2:30 PM'), true);
        expect(result.contains('3:45 PM'), true);
      });
    });
  });
}
