import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class CloudTtsService {
  Future<String> _getUrl() async {
    final config =
        jsonDecode(await rootBundle.loadString('assets/config.json'));
    return config['cloud_tts_url'] as String;
  }

  Future<String> getSpeechAudio(String message) async {
    final url = await _getUrl();
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'message': message});

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      return responseData['audioContent'];
    } else {
      throw Exception('Failed to synthesize speech');
    }
  }
}