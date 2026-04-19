class CommandParser {
  static Map<String, String> parseArguments(String command) {
    final args = <String, String>{};
    final regex = RegExp(r'\((.*)\)');
    final match = regex.firstMatch(command);
    if (match == null) return args;

    final arguments = match.group(1);
    if (arguments == null) return args;

    final keyValueRegex = RegExp(r'(\w+)\s*:\s*(".*?"|[^,]+)');
    for (final match in keyValueRegex.allMatches(arguments)) {
      final key = match.group(1)?.trim();
      var value = match.group(2)?.trim();

      if (key != null && value != null) {
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        args[key] = value;
      }
    }
    return args;
  }

  static List<String> extractCommandStack(String response) {
    final startIndex = response.indexOf('{');
    final endIndex = response.indexOf('}');
    if (startIndex != -1 && endIndex != -1) {
      final commandsString = response.substring(startIndex + 1, endIndex);
      return commandsString.split('|||').map((cmd) => cmd.trim()).toList();
    }
    return [];
  }
}