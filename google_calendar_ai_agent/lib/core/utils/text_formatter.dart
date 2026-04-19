class TextFormatter {
  static String formatForSpeech(String text) {
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
    return modifiedText.toString();
  }

  static String cleanResponse(String response) {
    var toReturn = response.replaceAll(RegExp(r'(\n)+'), '\n');
    toReturn = toReturn.replaceAll(RegExp(r'\*'), '');
    toReturn = toReturn.replaceAll(RegExp(r'(?<!\n)\.\s'), '.\n\n');
    toReturn = toReturn.replaceAll(RegExp(r'(?<!\n),\s'), ',\n');
    return toReturn.replaceFirst(RegExp(r'^mode=\w+\s*'), '').trim();
  }
}