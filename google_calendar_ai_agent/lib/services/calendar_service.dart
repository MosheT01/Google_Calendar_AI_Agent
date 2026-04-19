import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';

class CalendarService {
  late calendar.CalendarApi _api;

  Future<void> initialize() async {
    final credentials = jsonDecode(
      await rootBundle.loadString('assets/service_account.json'),
    );
    final accountCredentials = ServiceAccountCredentials.fromJson(credentials);
    final authClient = await clientViaServiceAccount(
      accountCredentials,
      [calendar.CalendarApi.calendarScope],
    );
    _api = calendar.CalendarApi(authClient);
  }

  Future<List<calendar.Event>> fetchEvents({int? days}) async {
    final now = DateTime.now().toUtc();
    final startOfRange = now.subtract(const Duration(days: 1));
    final endOfRange = startOfRange.add(Duration(days: days ?? AppConstants.daysOfAccess));

    final result = await _api.events.list(
      AppConstants.calendarEmail,
      timeMin: startOfRange,
      timeMax: endOfRange,
      singleEvents: true,
      orderBy: 'startTime',
    );

    return result.items?.map((e) {
          e.start?.dateTime = e.start?.dateTime?.toLocal();
          e.end?.dateTime = e.end?.dateTime?.toLocal();
          return e;
        }).toList() ??
        [];
  }

  String formatEventsForAi(List<calendar.Event> events) {
    final buffer = StringBuffer();
    for (var event in events) {
      final start = event.start?.dateTime ?? event.start?.date;
      final end = event.end?.dateTime ?? event.end?.date;
      buffer.writeln("Event ID: ${event.id ?? 'No ID'}");
      buffer.writeln("Event: ${event.summary ?? 'No Title'}");
      buffer.writeln("  Start: ${start?.toIso8601String() ?? 'Unknown'}");
      buffer.writeln("  End: ${end?.toIso8601String() ?? 'Unknown'}");
      if (event.description != null) {
        buffer.writeln("  Description: ${event.description}");
      }
      if (event.location != null) {
        buffer.writeln("  Location: ${event.location}");
      }
      buffer.writeln("------");
    }
    return buffer.toString();
  }

  Future<calendar.Event> addEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
  }) async {
    final event = calendar.Event(
      summary: title,
      start: calendar.EventDateTime(
        dateTime: startTime.toUtc(),
        timeZone: AppConstants.timeZone,
      ),
      end: calendar.EventDateTime(
        dateTime: (endTime ?? startTime.add(const Duration(hours: 1))).toUtc(),
        timeZone: AppConstants.timeZone,
      ),
      description: description,
      location: location,
      colorId: colorId,
    );
    return await _api.events.insert(event, AppConstants.calendarEmail);
  }

  Future<calendar.Event> updateEvent(
    String eventId, {
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
  }) async {
    final event = await _api.events.get(AppConstants.calendarEmail, eventId);
    if (title != null) event.summary = title;
    if (startTime != null) {
      event.start = calendar.EventDateTime(
        dateTime: startTime.toUtc(),
        timeZone: AppConstants.timeZone,
      );
    }
    if (endTime != null) {
      event.end = calendar.EventDateTime(
        dateTime: endTime.toUtc(),
        timeZone: AppConstants.timeZone,
      );
    }
    if (description != null) event.description = description;
    if (location != null) event.location = location;
    if (colorId != null) event.colorId = colorId;
    return await _api.events.update(event, AppConstants.calendarEmail, eventId);
  }

  Future<void> deleteEvent(String eventId) async {
    await _api.events.delete(AppConstants.calendarEmail, eventId);
  }

  Future<List<Map<String, dynamic>>> fetchFreeBusy(DateTime start, DateTime end) async {
    final request = calendar.FreeBusyRequest(
      timeMin: start.toUtc(),
      timeMax: end.toUtc(),
      items: [calendar.FreeBusyRequestItem(id: AppConstants.calendarEmail)],
    );
    final response = await _api.freebusy.query(request);
    final busyTimes = response.calendars?[AppConstants.calendarEmail]?.busy ?? [];
    return busyTimes.map((period) {
      return {
        'start': period.start?.toIso8601String(),
        'end': period.end?.toIso8601String(),
      };
    }).toList();
  }

  String formatFreeBusy(List<Map<String, dynamic>> busyPeriods) {
    final buffer = StringBuffer();
    buffer.writeln("Busy periods:");
    for (var period in busyPeriods) {
      final startStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(period['start'] as String).toLocal());
      final endStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(period['end'] as String).toLocal());
      buffer.writeln("- $startStr to $endStr");
    }
    return buffer.toString();
  }
}