import 'package:flutter_test/flutter_test.dart';
import 'package:google_calendar_ai_agent/domain/entities/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('should create from constructor', () {
      final message = ChatMessage(role: 'user', content: 'Hello');
      expect(message.role, 'user');
      expect(message.content, 'Hello');
    });

    test('should convert to map', () {
      final message = ChatMessage(role: 'user', content: 'Hello');
      final map = message.toMap();
      expect(map['role'], 'user');
      expect(map['content'], 'Hello');
    });

    test('should create from map', () {
      final map = {'role': 'model', 'content': 'Hi there'};
      final message = ChatMessage.fromMap(map);
      expect(message.role, 'model');
      expect(message.content, 'Hi there');
    });

    test('should handle null values in fromMap', () {
      final map = <String, String>{};
      final message = ChatMessage.fromMap(map);
      expect(message.role, '');
      expect(message.content, '');
    });
  });
}