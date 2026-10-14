import 'dart:convert';

const bool runPlaygroundE2E =
    bool.fromEnvironment(
      'RUN_PLAYGROUND_E2E',
      defaultValue: false,
    ) ||
    bool.fromEnvironment(
      'RUN_PRODUCTION_PLAYGROUND_E2E',
      defaultValue: false,
    );

const String lockedPlaygroundCalendarId =
    '58c4b0ccda887d9a1c0c2231af395b70a302c1d332e67189aebf3c4b941d6b37@group.calendar.google.com';

const String _targetCalendarIdDefine = String.fromEnvironment(
  'TEST_TARGET_CALENDAR_ID',
  defaultValue: '',
);
const String _targetCalendarUrlDefine = String.fromEnvironment(
  'TEST_TARGET_CALENDAR_URL',
  defaultValue: '',
);

const String _modelOverrideDefine = String.fromEnvironment(
  'LLM_E2E_MODEL',
  defaultValue: '',
);
const String _passThresholdDefine = String.fromEnvironment(
  'E2E_PASS_THRESHOLD',
  defaultValue: '1.0',
);

final DateTime january2027Start = DateTime(2027, 1, 1);
final DateTime january2027EndExclusive = DateTime(2027, 2, 1);

String resolvePlaygroundTargetCalendarId() {
  final raw = (_targetCalendarIdDefine.trim().isNotEmpty
          ? _targetCalendarIdDefine
          : _targetCalendarUrlDefine)
      .trim();

  if (raw.isEmpty) {
    return lockedPlaygroundCalendarId;
  }

  final provided = _normalizeCalendarId(raw);
  if (provided != lockedPlaygroundCalendarId) {
    throw StateError(
      'Playground E2E is locked to test calendar '
      '$lockedPlaygroundCalendarId and cannot run against "$provided".',
    );
  }

  return lockedPlaygroundCalendarId;
}

String resolveModelForPlayground(String fallback) {
  final override = _modelOverrideDefine.trim();
  return override.isEmpty ? fallback : override;
}

double resolvePassThreshold() {
  final parsed = double.tryParse(_passThresholdDefine.trim()) ?? 1.0;
  if (parsed.isNaN) {
    return 1.0;
  }
  if (parsed < 0.0) {
    return 0.0;
  }
  if (parsed > 1.0) {
    return 1.0;
  }
  return parsed;
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
