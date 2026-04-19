import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/core/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('should have correct app name', () {
      expect(AppConstants.appName, 'Bella');
    });

    test('should have correct calendar email', () {
      expect(AppConstants.calendarEmail, 'mousatams@gmail.com');
    });

    test('should have default model', () {
      expect(AppConstants.defaultModel, 'gemini-2.5-flash');
    });

    test('should have days of access', () {
      expect(AppConstants.daysOfAccess, 60);
    });

    test('should have timezone', () {
      expect(AppConstants.timeZone, 'Asia/Jerusalem');
    });
  });
}