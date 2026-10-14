import 'dart:convert';
import 'dart:io';

const String lockedPlaygroundCalendarId =
    '58c4b0ccda887d9a1c0c2231af395b70a302c1d332e67189aebf3c4b941d6b37@group.calendar.google.com';

String resolveTargetCalendarIdFromEnvironment() {
  final raw = (Platform.environment['TEST_TARGET_CALENDAR_ID'] ??
          Platform.environment['TEST_TARGET_CALENDAR_URL'] ??
          '')
      .trim();

  if (raw.isEmpty) {
    return lockedPlaygroundCalendarId;
  }

  final provided = _normalizeCalendarId(raw);
  if (provided != lockedPlaygroundCalendarId) {
    throw StateError(
      'Guarded real-calendar tests are locked to test calendar '
      '$lockedPlaygroundCalendarId and cannot run against "$provided".',
    );
  }

  return lockedPlaygroundCalendarId;
}

String _extractCandidate(String input) {
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasScheme) {
    return input;
  }

  final segments = uri.pathSegments;
  if (segments.isEmpty) {
    return input;
  }

  final calendarIndex = segments.lastIndexOf('calendar');
  if (calendarIndex != -1 && calendarIndex + 1 < segments.length) {
    return segments[calendarIndex + 1];
  }

  return segments.last;
}

String _tryDecodeBase64(String input) {
  try {
    final normalized = base64.normalize(input);
    final decoded = utf8.decode(base64.decode(normalized));
    return decoded.trim();
  } catch (_) {
    try {
      final normalized = base64Url.normalize(input);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return decoded.trim();
    } catch (_) {
      return input;
    }
  }
}

bool _looksLikeCalendarId(String value) {
  return value.contains('@') &&
      value.contains('.') &&
      !value.contains('/') &&
      !value.contains(' ');
}
String _normalizeCalendarId(String raw) {
  final candidate = _extractCandidate(raw);
  final decodedUri = Uri.decodeComponent(candidate).trim();
  if (_looksLikeCalendarId(decodedUri)) {
    return decodedUri;
  }

  final decodedBase64 = _tryDecodeBase64(decodedUri);
  if (_looksLikeCalendarId(decodedBase64)) {
    return decodedBase64;
  }

  return decodedUri;
}
