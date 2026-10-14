import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/presentation/providers/app_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('initializes with injected fakes and no production side effects',
        () async {
      final fakeCalendar = FakeCalendarService();
      final fakeAi = FakeAiService();
      final fakeTts = FakeTtsService();
      final fakeStt = FakeSttService();
      final fakeTranslation = FakeTranslationService();

      final provider = AppProvider(
        calendarService: fakeCalendar,
        aiService: fakeAi,
        ttsService: fakeTts,
        sttService: fakeStt,
        translationService: fakeTranslation,
        autoStartListeningOnInit: false,
        enableCsvLogging: false,
      );

      await provider.initialize();

      expect(provider.isLoading, false);
      expect(fakeCalendar.initializeCalls, 1);
      expect(fakeAi.initializeCalls, 1);
      expect(identical(fakeAi.boundCalendarService, fakeCalendar), true);
      expect(fakeTts.initializeCalls, 1);
      expect(fakeStt.initializeCalls, 1);
      expect(fakeTranslation.initializeCalls, 1);
    });

    test('renders markdown-friendly chat while keeping speech markdown-free',
        () async {
      final fakeAi = FakeAiService(
        responsesByPrompt: const <String, String>{
          'Create a summary':
              'mode=generic Hello **team**. See [agenda](https://example.com) at 2026-04-23T09:00:00'
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
      await provider.handleUserQuery('Create a summary');

      expect(provider.chatMessages.length, 2);
      expect(provider.chatMessages[0].role, 'user');
      expect(provider.chatMessages[1].role, 'model');
      expect(provider.chatMessages[1].content.contains('**team**'), true);
      expect(
          provider.chatMessages[1].content.contains('April 23, 2026 9:00 AM'),
          true);

      expect(fakeTts.spokenTexts.length, 1);
      final spoken = fakeTts.spokenTexts.single;
      expect(spoken.contains('**'), false);
      expect(spoken.contains('['), false);
      expect(spoken.contains(']('), false);
      expect(spoken.contains('https://example.com'), false);
    });

    test('interrupt stops active request and appends interruption message',
        () async {
      final fakeAi = FakeAiService(
        defaultResponse: 'mode=generic this should be ignored',
        responseDelay: const Duration(milliseconds: 200),
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
      final pending = provider.handleUserQuery('Long request');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      provider.interrupt();
      await pending;

      expect(fakeAi.wasInterrupted, true);
      expect(provider.isThinking, false);
      expect(provider.chatMessages.last.content, '(Interrupted by user)');
      expect(fakeTts.stopCalls > 0, true);
    });

    test('persists and applies TTS engine selection', () async {
      final fakeTts = FakeTtsService();
      final provider = AppProvider(
        calendarService: FakeCalendarService(),
        aiService: FakeAiService(),
        ttsService: fakeTts,
        sttService: FakeSttService(),
        translationService: FakeTranslationService(),
        autoStartListeningOnInit: false,
        enableCsvLogging: false,
      );

      await provider.initialize();
      await provider.saveTtsEngine('cloud');

      expect(provider.currentTtsEngine, 'cloud');
      expect(fakeTts.selectedEngines.isNotEmpty, true);
      expect(fakeTts.selectedEngines.last.name, 'cloud');
    });
  });
}
