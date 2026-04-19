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
  });
}