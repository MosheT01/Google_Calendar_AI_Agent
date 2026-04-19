import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/domain/entities/ai_response.dart';

void main() {
  group('AiResponse', () {
    group('parse', () {
      test('should parse clarifying mode', () {
        final response = AiResponse.parse('mode=clarifying What is the title?');
        expect(response.mode, ResponseMode.clarifying);
        expect(response.content, 'What is the title?');
      });

      test('should parse code_output mode', () {
        final response = AiResponse.parse('mode=code_output commandsToBeExecutedStack={addEvent(title: "Test")}');
        expect(response.mode, ResponseMode.codeOutput);
        expect(response.commands?.length, 1);
      });

      test('should parse generic mode', () {
        final response = AiResponse.parse('mode=generic Hello world');
        expect(response.mode, ResponseMode.generic);
        expect(response.content, 'Hello world');
      });

      test('should default to generic for unknown mode', () {
        final response = AiResponse.parse('Hello world');
        expect(response.mode, ResponseMode.generic);
      });

      test('should return empty commands for non-code mode', () {
        final response = AiResponse.parse('mode=generic Hello');
        expect(response.commands, null);
      });
    });
  });
}