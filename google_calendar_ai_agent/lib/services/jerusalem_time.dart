class JerusalemTime {
  JerusalemTime._();

  static const String schemaDescription =
      'Asia/Jerusalem wall time, YYYY-MM-DDTHH:MM:SS. '
      '18:00 means 6:00 PM. Do not append Z.';

  static DateTime parseWallTime(String raw) {
    final trimmed = raw.trim();
    final dateTime = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(trimmed);
    if (dateTime != null) {
      return DateTime(
        int.parse(dateTime.group(1)!),
        int.parse(dateTime.group(2)!),
        int.parse(dateTime.group(3)!),
        int.parse(dateTime.group(4)!),
        int.parse(dateTime.group(5)!),
        int.parse(dateTime.group(6) ?? '0'),
      );
    }

    final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (dateOnly != null) {
      return DateTime(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }

    throw FormatException('Unrecognized wall time: $raw');
  }

  static String formatWithOffset(DateTime value) {
    final local = value.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final clock = local.toIso8601String().split('.').first;
    return '$clock$sign$hours:$minutes';
  }
}
