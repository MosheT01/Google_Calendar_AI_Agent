import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/system_prompt.dart';
import '../domain/entities/chat_message.dart';

class AiService {
  GenerativeModel? _model;
  ChatSession? _chat;
  String _currentModel = AppConstants.defaultModel;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  String get currentModel => _currentModel;

  Future<void> initialize(List<ChatMessage> history) async {
    final apiKey = jsonDecode(
      await rootBundle.loadString('assets/gemini_api_key.json'),
    )['api_key'];

    _model = GenerativeModel(
      model: _currentModel,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 2,
        maxOutputTokens: 1000,
      ),
      systemInstruction: Content.system(
        SystemPrompt.build(AppConstants.daysOfAccess),
      ),
    );

    final conversationHistory = history.map((message) {
      return Content.text('${message.role}: ${message.content}');
    }).toList();

    _chat = _model!.startChat(history: conversationHistory);
    _isInitialized = true;
  }

  Future<void> changeModel(String modelName, List<ChatMessage> history) async {
    _currentModel = modelName;
    await initialize(history);
  }

  Future<String> sendMessage(String prompt, String calendarContext) async {
    if (!_isInitialized || _chat == null) {
      return "Error: Chat is not initialized.";
    }

    final formattedPrompt = '''
You are an AI assistant with access to the user's calendar and free/busy data for the next ${AppConstants.daysOfAccess} calendar days in israel.
adhere to the system instruction and respond strictly as instructed.

Today is ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} (${DateFormat('EEEE').format(DateTime.now())}).

$calendarContext

The user query: $prompt
''';

    try {
      final content = Content.text(formattedPrompt);
      final response = await _chat!.sendMessage(content);
      var result = response.text ?? "Error: No response received.";
      result = result.replaceAll('```', '');
      return result;
    } catch (e) {
      return "Error: $e";
    }
  }
}