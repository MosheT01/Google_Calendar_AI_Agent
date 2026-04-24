import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/constants/system_prompt.dart';

void main() {
  group('SystemPrompt', () {
    test('should build prompt', () {
      final prompt = SystemPrompt.build();
      expect(prompt.isNotEmpty, true);
    });

    test('should mention calendar', () {
      final prompt = SystemPrompt.build();
      expect(prompt.toLowerCase().contains('calendar'), true);
    });

    test('should mention today and workflow constraints', () {
      final prompt = SystemPrompt.build();
      expect(prompt.contains('Today is'), true);
      expect(prompt.contains('Current local time is'), true);
      expect(prompt.contains('Work in cycles'), true);
    });
  });
}
