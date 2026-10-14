import 'jerusalem_time.dart';

class CalendarSpan {
  const CalendarSpan({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? location;

  Map<String, Object?> toJson() {
    return {
      'eventId': id,
      'title': title,
      'startTime': JerusalemTime.formatWithOffset(start),
      'endTime': JerusalemTime.formatWithOffset(end),
      if (location != null && location!.trim().isNotEmpty) 'location': location,
    };
  }
}

class CalendarConflictException implements Exception {
  CalendarConflictException(this.conflicts);

  final List<CalendarSpan> conflicts;

  @override
  String toString() =>
      'Calendar write blocked by ${conflicts.length} overlapping event(s)';
}

void rejectIfOverlapping({
  required bool confirmDespiteConflicts,
  required List<CalendarSpan> existing,
  required DateTime start,
  required DateTime end,
  String? excludeEventId,
}) {
  if (confirmDespiteConflicts) {
    return;
  }
  final conflicts = overlappingSpans(
    existing: existing,
    start: start,
    end: end,
    excludeEventId: excludeEventId,
  );
  if (conflicts.isNotEmpty) {
    throw CalendarConflictException(conflicts);
  }
}

List<CalendarSpan> overlappingSpans({
  required List<CalendarSpan> existing,
  required DateTime start,
  required DateTime end,
  String? excludeEventId,
}) {
  return existing.where((span) {
    if (excludeEventId != null && span.id == excludeEventId) {
      return false;
    }
    return start.isBefore(span.end) && end.isAfter(span.start);
  }).toList();
}

List<Map<String, Object?>> titleCollisionGroups(List<CalendarSpan> events) {
  final groups = <String, List<CalendarSpan>>{};
  for (final event in events) {
    final key = event.title.trim().toLowerCase();
    if (key.isEmpty) {
      continue;
    }
    groups.putIfAbsent(key, () => <CalendarSpan>[]).add(event);
  }

  return groups.entries
      .where((entry) => entry.value.length >= 2)
      .map(
        (entry) => <String, Object?>{
          'title': entry.value.first.title,
          'events': entry.value.map((event) => event.toJson()).toList(),
        },
      )
      .toList();
}
