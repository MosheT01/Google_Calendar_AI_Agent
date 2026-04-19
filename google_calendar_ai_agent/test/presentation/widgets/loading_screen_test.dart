import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/presentation/widgets/loading_screen.dart';

void main() {
  group('LoadingScreen', () {
    testWidgets('should display loading message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoadingScreen(message: 'Loading...'),
        ),
      );
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('should display circular progress indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoadingScreen(message: 'Please wait'),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should have primary background color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoadingScreen(message: 'Wait'),
        ),
      );
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFFF7F9C));
    });
  });
}