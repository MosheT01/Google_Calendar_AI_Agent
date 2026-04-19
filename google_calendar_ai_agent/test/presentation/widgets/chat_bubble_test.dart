import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/presentation/widgets/chat_bubble.dart';

void main() {
  group('ChatBubble', () {
    testWidgets('should display user message aligned right', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: 'Hello',
              isUser: true,
            ),
          ),
        ),
      );
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('should display assistant message aligned left', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: 'Hi there',
              isUser: false,
            ),
          ),
        ),
      );
      expect(find.text('Hi there'), findsOneWidget);
    });

    testWidgets('should make message selectable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: 'Select me',
              isUser: true,
            ),
          ),
        ),
      );
      expect(find.byType(SelectableText), findsOneWidget);
    });
  });
}