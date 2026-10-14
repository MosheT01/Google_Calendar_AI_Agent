import 'package:intl/intl.dart';

class TextFormatter {
  static const String _TAG = '[TextFormatter]';

  static String formatForSpeech(String text) {
    print('$_TAG formatForSpeech() input length: ${text.length}');
    StringBuffer modifiedText = StringBuffer();
    int charCount = 0;
    bool hasPeriod = false;

    for (int i = 0; i < text.length; i++) {
      charCount++;
      if (text[i] == '.') hasPeriod = true;

      if (charCount >= 100 && !hasPeriod && text[i] == ' ') {
        modifiedText.write('.');
        modifiedText.write(' ');
        hasPeriod = true;
      }

      modifiedText.write(text[i]);

      if (charCount >= 100 && (text[i] == '.' || text[i] == ' ')) {
        charCount = 0;
        hasPeriod = false;
      }
    }
    final result = modifiedText.toString();
    print(
        '$_TAG Output length: ${result.length} (added ${result.length - text.length} chars)');
    return result;
  }

  static String cleanResponse(String response) {
    print('$_TAG cleanResponse() input length: ${response.length}');
    print(
        '$_TAG Raw input: ${response.substring(0, response.length > 100 ? 100 : response.length)}');

    var toReturn = response.replaceAll(RegExp(r'(\n)+'), '\n');
    toReturn = toReturn.replaceAll(RegExp(r'\*'), '');
    toReturn = toReturn.replaceAll(RegExp(r'(?<!\n)\.\s'), '.\n\n');
    toReturn = toReturn.replaceAll(RegExp(r'(?<!\n),\s'), ',\n');

    // Remove mode prefix
    final modeRegex = RegExp(r'^mode=\w+\s*');
    if (modeRegex.hasMatch(toReturn)) {
      print('$_TAG Removed mode prefix');
    }
    toReturn = toReturn.replaceFirst(modeRegex, '').trim();

    print('$_TAG Output length: ${toReturn.length}');
    return toReturn;
  }

  static String cleanResponseForDisplay(String response) {
    print('$_TAG cleanResponseForDisplay() input length: ${response.length}');
    var toReturn = response.replaceAll(RegExp(r'\r\n?'), '\n');
    toReturn = toReturn.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final modeRegex = RegExp(r'^mode=\w+\s*');
    toReturn = toReturn.replaceFirst(modeRegex, '').trim();

    print('$_TAG cleanResponseForDisplay() output length: ${toReturn.length}');
    return toReturn;
  }

  static String cleanResponseForSpeech(String response) {
    print('$_TAG cleanResponseForSpeech() input length: ${response.length}');
    var toReturn = cleanResponseForDisplay(response);

    toReturn = toReturn.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    toReturn = toReturn.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => match.group(1) ?? '',
    );
    toReturn = toReturn.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
      (match) => match.group(1) ?? '',
    );

    toReturn = toReturn.replaceAll(
      RegExp(r'^\s{0,3}(#{1,6})\s+', multiLine: true),
      '',
    );
    toReturn = toReturn.replaceAll(
      RegExp(r'^\s{0,3}>\s?', multiLine: true),
      '',
    );
    toReturn = toReturn.replaceAll(
      RegExp(r'^\s*[-+*]\s+', multiLine: true),
      '',
    );
    toReturn = toReturn.replaceAll(
      RegExp(r'^\s*\d+\.\s+', multiLine: true),
      '',
    );
    toReturn = toReturn.replaceAll(RegExp(r'[*_~]'), '');
    toReturn = toReturn.replaceAll('|', ' ');

    toReturn = toReturn.replaceAll(RegExp(r'\n+'), ' ');
    toReturn = toReturn.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    print('$_TAG cleanResponseForSpeech() output length: ${toReturn.length}');
    return toReturn;
  }

  static String humanizeDateTimes(String text) {
    var output = text;

    // Convert combined date/time first.
    final dateTimePattern = RegExp(
      r'\b(\d{4})-(\d{2})-(\d{2})[T ]([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b',
    );
    output = output.replaceAllMapped(dateTimePattern, (match) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final dt = DateTime(year, month, day, hour, minute);
      return DateFormat('MMMM d, yyyy h:mm a').format(dt);
    });

    // Convert date-only values.
    final datePattern = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
    output = output.replaceAllMapped(datePattern, (match) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final dt = DateTime(year, month, day);
      return DateFormat('MMMM d, yyyy').format(dt);
    });

    // Convert standalone 24h times, only when followed by word boundary
    // to avoid touching already-formatted "a.m./p.m." text.
    final timePattern = RegExp(
      r'\b([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b(?!\s*[AaPp]\.?[Mm]\.?)',
    );
    output = output.replaceAllMapped(timePattern, (match) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final dt = DateTime(2000, 1, 1, hour, minute);
      return DateFormat('h:mm a').format(dt);
    });

    return output;
  }
}
