enum ResponseMode { clarifying, codeOutput, generic }

class AiResponse {
  final ResponseMode mode;
  final String content;
  final List<String>? commands;

  AiResponse({
    required this.mode,
    required this.content,
    this.commands,
  });

  factory AiResponse.parse(String response) {
    if (response.startsWith('mode=clarifying')) {
      return AiResponse(
        mode: ResponseMode.clarifying,
        content: response.replaceFirst('mode=clarifying', '').trim(),
      );
    } else if (response.startsWith('mode=code_output')) {
      final commands = _extractCommands(response);
      return AiResponse(
        mode: ResponseMode.codeOutput,
        content: 'Executing ${commands.length} commands',
        commands: commands,
      );
    } else {
      return AiResponse(
        mode: ResponseMode.generic,
        content: response.replaceFirst('mode=generic', '').trim(),
      );
    }
  }

  static List<String> _extractCommands(String response) {
    final startIndex = response.indexOf('{');
    final endIndex = response.indexOf('}');
    if (startIndex != -1 && endIndex != -1) {
      final commandsString = response.substring(startIndex + 1, endIndex);
      return commandsString.split('|||').map((cmd) => cmd.trim()).toList();
    }
    return [];
  }
}