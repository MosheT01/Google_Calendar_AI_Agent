import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class CsvLogger {
  static Future<void> log(String prompt, String response) async {
    try {
      if (await Permission.storage.isDenied ||
          await Permission.manageExternalStorage.isDenied) {
        var status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) return;
      }

      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) return;

      final filePath = '${directory.path}/ai_logs.csv';
      final file = File(filePath);

      if (!await file.exists()) {
        await file.writeAsString("Timestamp,Prompt,Response\n");
      }

      final timestamp = DateTime.now().toIso8601String();
      final csvLine = '"$timestamp","${prompt.replaceAll('"', '""')}","${response.replaceAll('"', '""')}"\n';

      await file.writeAsString(csvLine, mode: FileMode.append, flush: true);
    } catch (e) {
      // Silently fail
    }
  }
}