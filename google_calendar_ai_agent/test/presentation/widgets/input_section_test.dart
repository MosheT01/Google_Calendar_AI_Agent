import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/presentation/widgets/input_section.dart';

void main() {
  group('InputSection', () {
    testWidgets('should display text field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputSection(
              controller: TextEditingController(),
              isListening: false,
              onSend: () {},
              onMic: () {},
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should show mic icon when not listening', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputSection(
              controller: TextEditingController(),
              isListening: false,
              onSend: () {},
              onMic: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('should show send icon when text entered', (tester) async {
      final controller = TextEditingController(text: 'Hello');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputSection(
              controller: controller,
              isListening: false,
              onSend: () {},
              onMic: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('should call onSend when send tapped', (tester) async {
      bool called = false;
      final controller = TextEditingController(text: 'Hello');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputSection(
              controller: controller,
              isListening: false,
              onSend: () => called = true,
              onMic: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.send));
      expect(called, true);
    });

    testWidgets('should call onMic when mic tapped', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InputSection(
              controller: TextEditingController(),
              isListening: false,
              onSend: () {},
              onMic: () => called = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.mic));
      expect(called, true);
    });
  });
}