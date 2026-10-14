import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/presentation/providers/app_provider.dart';
import 'package:google_calendar_ai_agent/presentation/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'safe chat flow works end-to-end with fakes only',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final fakeAi = FakeAiService(
        responsesByPrompt: const <String, String>{
          'Plan tomorrow':
              'mode=generic Sure. **Tomorrow** has no conflicts, and I can suggest 9:00 AM.'
        },
      );
      final fakeTts = FakeTtsService();

      final provider = AppProvider(
        calendarService: FakeCalendarService(),
        aiService: fakeAi,
        ttsService: fakeTts,
        sttService: FakeSttService(),
        translationService: FakeTranslationService(),
        autoStartListeningOnInit: false,
        enableCsvLogging: false,
      );
      await provider.initialize();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      await tester.enterText(inputFinder, 'Plan tomorrow');
      await tester.pump(const Duration(milliseconds: 150));

      final sendIconFinder = find.byIcon(Icons.send);
      expect(sendIconFinder, findsOneWidget);
      await tester.tap(sendIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(provider.chatMessages.length, 2);
      expect(provider.chatMessages.first.content, 'Plan tomorrow');
      expect(provider.chatMessages.last.content.contains('**Tomorrow**'), true);
      expect(fakeTts.spokenTexts.isNotEmpty, true);
      expect(fakeAi.initializeCalls, 1);
    },
  );
}
