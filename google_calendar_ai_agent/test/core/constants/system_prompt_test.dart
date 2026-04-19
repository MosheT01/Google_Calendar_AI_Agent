import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/constants/system_prompt.dart';

void main() {
  group('SystemPrompt', () {
    test('should build prompt with correct days', () {
      final prompt = SystemPrompt.build(60);
      expect(prompt.contains('60 calendar days'), true);
    });

    test('should contain response mode instructions', () {
      final prompt = SystemPrompt.build(60);
      expect(prompt.contains('Clarifying Mode'), true);
      expect(prompt.contains('Code Output Mode'), true);
      expect(prompt.contains('Generic Response Mode'), true);
    });

    test('should contain calendar function instructions', () {
      final prompt = SystemPrompt.build(60);
      expect(prompt.contains('addEvent'), true);
      expect(prompt.contains('updateEvent'), true);
      expect(prompt.contains('deleteEvent'), true);
    });

    test('should contain color options', () {
      final prompt = SystemPrompt.build(60);
      expect(prompt.contains('colorOptions'), true);
    });
  });
}