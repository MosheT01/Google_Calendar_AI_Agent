class ChatMessage {
  final String role;
  final String content;
  final String? debugPrompt;
  final String? debugTrace;
  final String? debugFunctionCalls;
  final String? debugResponse;

  ChatMessage({
    required this.role,
    required this.content,
    this.debugPrompt,
    this.debugTrace,
    this.debugFunctionCalls,
    this.debugResponse,
  });

  ChatMessage copyWith({
    String? role,
    String? content,
    String? debugPrompt,
    String? debugTrace,
    String? debugFunctionCalls,
    String? debugResponse,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      debugPrompt: debugPrompt ?? this.debugPrompt,
      debugTrace: debugTrace ?? this.debugTrace,
      debugFunctionCalls: debugFunctionCalls ?? this.debugFunctionCalls,
      debugResponse: debugResponse ?? this.debugResponse,
    );
  }

  Map<String, String> toMap() => {'role': role, 'content': content};

  factory ChatMessage.fromMap(Map<String, String> map) =>
      ChatMessage(role: map['role'] ?? '', content: map['content'] ?? '');
}
