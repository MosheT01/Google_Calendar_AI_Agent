import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/utils/command_parser.dart';

void main() {
  group('CommandParser', () {
    group('parseArguments', () {
      test('should parse simple arguments', () {
        final result = CommandParser.parseArguments('addEvent(title: "Test")');
        expect(result['title'], 'Test');
      });

      test('should parse multiple arguments', () {
        final result = CommandParser.parseArguments(
            'addEvent(title: "Test", startTime: "2025-01-01T10:00:00.000")');
        expect(result['title'], 'Test');
        expect(result['startTime'], '2025-01-01T10:00:00.000');
      });

      test('should remove quotes from values', () {
        final result = CommandParser.parseArguments('addEvent(title: "Test Event")');
        expect(result['title'], 'Test Event');
      });

      test('should return empty map for no arguments', () {
        final result = CommandParser.parseArguments('addEvent()');
        expect(result.isEmpty, true);
      });

      test('should return empty map for malformed input', () {
        final result = CommandParser.parseArguments('notACommand');
        expect(result.isEmpty, true);
      });
    });

    group('extractCommandStack', () {
      test('should extract commands from braces', () {
        final result = CommandParser.extractCommandStack('mode=code_output commandsToBeExecutedStack={cmd1|||cmd2}');
        expect(result.length, 2);
        expect(result[0], 'cmd1');
        expect(result[1], 'cmd2');
      });

      test('should return empty list for no braces', () {
        final result = CommandParser.extractCommandStack('mode=generic Hello');
        expect(result.isEmpty, true);
      });
    });
  });
}