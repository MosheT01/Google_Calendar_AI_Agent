import 'package:googleapis/calendar/v3.dart' as calendar;

class CalendarEvent {
  final String? id;
  final String summary;
  final DateTime startTime;
  final DateTime endTime;
  final String? description;
  final String? location;
  final String? colorId;

  CalendarEvent({
    this.id,
    required this.summary,
    required this.startTime,
    required this.endTime,
    this.description,
    this.location,
    this.colorId,
  });

  factory CalendarEvent.fromApiEvent(calendar.Event event) {
    return CalendarEvent(
      id: event.id,
      summary: event.summary ?? 'No Title',
      startTime: event.start?.dateTime?.toLocal() ?? DateTime.now(),
      endTime: event.end?.dateTime?.toLocal() ?? DateTime.now(),
      description: event.description,
      location: event.location,
      colorId: event.colorId,
    );
  }

  calendar.Event toApiEvent() => calendar.Event(
        summary: summary,
        start: calendar.EventDateTime(
          dateTime: startTime.toUtc(),
          timeZone: 'Asia/Jerusalem',
        ),
        end: calendar.EventDateTime(
          dateTime: endTime.toUtc(),
          timeZone: 'Asia/Jerusalem',
        ),
        description: description,
        location: location,
        colorId: colorId,
      );
}