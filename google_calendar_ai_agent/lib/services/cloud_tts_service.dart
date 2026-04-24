import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class CloudTtsService {
  static const String _TAG = '[CloudTtsService]';
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    if (_isInitialized) return;
    print('$_TAG Initializing cloud audio player...');
    await _player.setReleaseMode(ReleaseMode.stop);
    _isInitialized = true;
    print('$_TAG ✓ Cloud audio player initialized');
  }

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

  Future<void> speak(String message) async {
    if (!_isInitialized) {
      await initialize();
    }

    print('$_TAG speak() called');
    final audioContent = await getSpeechAudio(message);
    final bytes = _decodeAudio(audioContent);
    if (bytes.isEmpty) {
      throw Exception('Cloud TTS returned empty audio payload');
    }

    await _player.stop();
    _isSpeaking = true;
    print('$_TAG Playing cloud TTS audio (${bytes.length} bytes)');

    final onComplete = _player.onPlayerComplete.first;
    await _player.play(BytesSource(bytes));

    try {
      await onComplete.timeout(
        const Duration(minutes: 2),
        onTimeout: () =>
            throw Exception('Cloud TTS playback timed out before completion'),
      );
    } finally {
      _isSpeaking = false;
      print('$_TAG ✓ Cloud TTS playback complete');
    }
  }

  Uint8List _decodeAudio(String raw) {
    final trimmed = raw.trim();
    final payload = trimmed.contains(',')
        ? trimmed.substring(trimmed.indexOf(',') + 1).trim()
        : trimmed;
    return base64Decode(payload);
  }

  Future<void> stop() async {
    print('$_TAG stop() called');
    await _player.stop();
    _isSpeaking = false;
  }

  Future<void> dispose() async {
    print('$_TAG dispose() called');
    await _player.dispose();
    _isInitialized = false;
    _isSpeaking = false;
  }
}
