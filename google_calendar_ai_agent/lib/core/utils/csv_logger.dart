import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class CsvLogger {
  static const String _TAG = '[CsvLogger]';
  
  static Future<void> log(String prompt, String response) async {
    print('$_TAG log() called');
    try {
      if (await Permission.storage.isDenied ||
          await Permission.manageExternalStorage.isDenied) {
        print('$_TAG Requesting storage permission');
        var status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          print('$_TAG Permission denied, skipping log');
          return;
        }
      }

      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        print('$_TAG Download directory not found');
        return;
      }

      final filePath = '${directory.path}/ai_logs.csv';
      print('$_TAG File path: $filePath');
      final file = File(filePath);

      if (!await file.exists()) {
        print('$_TAG Creating new CSV file');
        await file.writeAsString("Timestamp,Prompt,Response\n");
      }

      final timestamp = DateTime.now().toIso8601String();
      
      // Escape quotes for CSV
      final escapedPrompt = prompt.replaceAll('"', '""');
      final escapedResponse = response.replaceAll('"', '""');
      
      final csvLine = '"$timestamp","$escapedPrompt","$escapedResponse"\n';
      
      print('$_TAG Writing line: ${csvLine.length} chars');
      await file.writeAsString(csvLine, mode: FileMode.append, flush: true);
      print('$_TAG ✓ Log written successfully');
    } catch (e) {
      print('$_TAG ERROR: $e');
    }
  }
}