import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/constants/app_colors.dart';

void main() {
  group('AppColors', () {
    test('should have primary color', () {
      expect(AppColors.primary, const Color(0xFFFF7F9C));
    });

    test('should have primary light color', () {
      expect(AppColors.primaryLight, const Color(0xFFFFDEE2));
    });

    test('should have background color', () {
      expect(AppColors.background, const Color(0xFFFFF8F8));
    });

    test('should have surface color', () {
      expect(AppColors.surface, Colors.white);
    });

    test('should have user bubble color', () {
      expect(AppColors.userBubble, const Color(0xFFFFDEE2));
    });

    test('should have assistant bubble color', () {
      expect(AppColors.assistantBubble, const Color(0xFFEEEEEE));
    });
  });
}