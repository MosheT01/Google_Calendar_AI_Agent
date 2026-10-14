import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import '../core/constants/app_constants.dart';
import 'calendar_conflicts.dart';

class CalendarService {
  static const String _TAG = '[CalendarService]';
  late calendar.CalendarApi _api;
  final Future<String> Function() _serviceAccountLoader;
  final String? _defaultCalendarIdOverride;
  final Map<String, String> _eventCalendarIndex = {};
  List<String>? _cachedCalendarIds;
  DateTime? _calendarIdsCachedAt;

  CalendarService({
    Future<String> Function()? serviceAccountLoader,
    String? defaultCalendarIdOverride,
  })  : _serviceAccountLoader = serviceAccountLoader ??
            (() => rootBundle.loadString('assets/service_account.json')),
        _defaultCalendarIdOverride = defaultCalendarIdOverride;

  String get _defaultCalendarId {
    final override = _defaultCalendarIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return AppConstants.calendarEmail;
  }

  Future<void> initialize() async {
    print('$_TAG Initializing...');
    try {
      final credentials = jsonDecode(await _serviceAccountLoader());
      print('$_TAG Credentials loaded: ${credentials.keys}');

      final accountCredentials =
          ServiceAccountCredentials.fromJson(credentials);
      print('$_TAG Service account created');

      final authClient = await clientViaServiceAccount(
        accountCredentials,
        [calendar.CalendarApi.calendarScope],
      );
      print('$_TAG Auth client created');

      _api = calendar.CalendarApi(authClient);
      print('$_TAG Calendar API initialized');
    } catch (e) {
      print('$_TAG ERROR during init: $e');
      rethrow;
    }
  }

  Future<List<String>> _getAccessibleCalendarIds({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final hasFreshCache = !forceRefresh &&
        _cachedCalendarIds != null &&
        _calendarIdsCachedAt != null &&
        now.difference(_calendarIdsCachedAt!).inMinutes < 10;

    if (hasFreshCache) {
      return _cachedCalendarIds!;
    }

    final ids = <String>{};
    String? pageToken;

    do {
      final listResponse = await _api.calendarList.list(
        pageToken: pageToken,
        showDeleted: false,
        showHidden: false,
      );

      for (final entry
          in listResponse.items ?? <calendar.CalendarListEntry>[]) {
        final id = entry.id;
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }

      pageToken = listResponse.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    ids.add(_defaultCalendarId);
    _cachedCalendarIds = ids.toList();
    _calendarIdsCachedAt = now;

    print('$_TAG Accessible calendars: ${_cachedCalendarIds!.length}');
    return _cachedCalendarIds!;
  }

  void _rememberEventCalendar(calendar.Event event, String calendarId) {
    final eventId = event.id;
    if (eventId != null && eventId.isNotEmpty) {
      _eventCalendarIndex[eventId] = calendarId;
    }
  }

  DateTime _eventStartAsLocal(calendar.Event event) {
    return event.start?.dateTime?.toLocal() ??
        event.start?.date ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _rejectOverlaps({
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
    required bool confirmDespiteConflicts,
  }) async {
    final dayStart = DateTime(start.year, start.month, start.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final events = await fetchEventsByDateRange(dayStart, dayEnd);
    final spans = <CalendarSpan>[];
    for (final event in events) {
      final span = _spanFromEvent(event);
      if (span != null) {
        spans.add(span);
      }
    }
    rejectIfOverlapping(
      confirmDespiteConflicts: confirmDespiteConflicts,
      existing: spans,
      start: start,
      end: end,
      excludeEventId: excludeEventId,
    );
  }

  CalendarSpan? _spanFromEvent(calendar.Event event) {
    final id = event.id;
    if (id == null || id.isEmpty) {
      return null;
    }
    final start = _eventStartAsLocal(event);
    final end = event.end?.dateTime?.toLocal() ??
        (event.end?.date == null
            ? start.add(const Duration(hours: 1))
            : DateTime(
                event.end!.date!.year,
                event.end!.date!.month,
                event.end!.date!.day,
              ));
    return CalendarSpan(
      id: id,
      title: event.summary ?? '',
      start: start,
      end: end,
      location: event.location,
    );
  }

  String _calendarIdForEventId(String eventId) {
    return _eventCalendarIndex[eventId] ?? _defaultCalendarId;
  }

  Future<List<calendar.Event>> fetchEventsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String? query,
    String? calendarId,
    bool includeDeleted = false,
  }) async {
    print('$_TAG fetchEventsByDateRange called');
    print(
        '$_TAG Start: ${startDate.toIso8601String()}, End: ${endDate.toIso8601String()}');

    final calendarIds = calendarId != null && calendarId.trim().isNotEmpty
        ? <String>[calendarId.trim()]
        : await _getAccessibleCalendarIds();
    final events = <calendar.Event>[];

    for (final calendarId in calendarIds) {
      String? pageToken;
      do {
        final result = await _api.events.list(
          calendarId,
          timeMin: startDate.toUtc(),
          timeMax: endDate.toUtc(),
          q: query,
          showDeleted: includeDeleted,
          singleEvents: true,
          orderBy: 'startTime',
          maxResults: 2500,
          pageToken: pageToken,
        );

        for (final event in result.items ?? <calendar.Event>[]) {
          event.start?.dateTime = event.start?.dateTime?.toLocal();
          event.end?.dateTime = event.end?.dateTime?.toLocal();
          _rememberEventCalendar(event, calendarId);
          events.add(event);
        }

        pageToken = result.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);
    }

    events
        .sort((a, b) => _eventStartAsLocal(a).compareTo(_eventStartAsLocal(b)));

    print('$_TAG Found ${events.length} events in range');
    return events;
  }

  Future<calendar.Event> addEvent({
    required String title,
    required DateTime startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
    String? visibility,
    String? transparency,
    String? status,
    List<String>? recurrence,
    List<String>? attendeeEmails,
    bool? remindersUseDefault,
    List<int>? reminderMinutes,
    String? sourceTitle,
    String? sourceUrl,
    bool? allDay,
    String? calendarId,
    Map<String, dynamic>? advancedFields,
    bool confirmDespiteConflicts = false,
  }) async {
    print('$_TAG addEvent called');
    print('$_TAG Title: $title');
    print('$_TAG Start: ${startTime.toIso8601String()}');
    print('$_TAG End: ${endTime?.toIso8601String()}');

    final targetCalendarId = calendarId ?? _defaultCalendarId;
    final resolvedEndTime = endTime ?? startTime.add(const Duration(hours: 1));

    final isAllDay = allDay == true;
    final startDateTime = isAllDay
        ? calendar.EventDateTime(
            date: DateTime(startTime.year, startTime.month, startTime.day),
          )
        : calendar.EventDateTime(
            dateTime: startTime.toUtc(),
            timeZone: AppConstants.timeZone,
          );

    DateTime allDayEndDate = DateTime(
        resolvedEndTime.year, resolvedEndTime.month, resolvedEndTime.day);
    final allDayStartDate =
        DateTime(startTime.year, startTime.month, startTime.day);
    if (!allDayEndDate.isAfter(allDayStartDate)) {
      allDayEndDate = allDayStartDate.add(const Duration(days: 1));
    }

    final endDateTime = isAllDay
        ? calendar.EventDateTime(date: allDayEndDate)
        : calendar.EventDateTime(
            dateTime: resolvedEndTime.toUtc(),
            timeZone: AppConstants.timeZone,
          );

    calendar.Event event = calendar.Event(
      summary: title,
      start: startDateTime,
      end: endDateTime,
      description: description,
      location: location,
      colorId: colorId,
      visibility: visibility,
      transparency: transparency,
      status: status,
      recurrence: recurrence,
      attendees: _buildAttendees(attendeeEmails),
      reminders: _buildReminders(remindersUseDefault, reminderMinutes),
      source: _buildSource(sourceTitle, sourceUrl),
    );

    event = _applyAdvancedFields(event, advancedFields);

    await _rejectOverlaps(
      start: isAllDay
          ? DateTime(startTime.year, startTime.month, startTime.day)
          : startTime,
      end: isAllDay ? allDayEndDate : resolvedEndTime,
      confirmDespiteConflicts: confirmDespiteConflicts,
    );

    print('$_TAG Event object created, inserting...');
    final result = await _api.events.insert(event, targetCalendarId);
    _rememberEventCalendar(result, targetCalendarId);
    print('$_TAG Event created with ID: ${result.id}');
    return result;
  }

  Future<calendar.Event> updateEvent(
    String eventId, {
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? description,
    String? location,
    String? colorId,
    String? visibility,
    String? transparency,
    String? status,
    List<String>? recurrence,
    List<String>? attendeeEmails,
    bool? remindersUseDefault,
    List<int>? reminderMinutes,
    String? sourceTitle,
    String? sourceUrl,
    bool? allDay,
    String? calendarId,
    Map<String, dynamic>? advancedFields,
    bool confirmDespiteConflicts = false,
  }) async {
    print('$_TAG updateEvent called');
    print('$_TAG Event ID: $eventId');
    print('$_TAG New title: $title');
    print('$_TAG New start: ${startTime?.toIso8601String()}');

    final targetCalendarId = calendarId ?? _calendarIdForEventId(eventId);
    calendar.Event event = await _api.events.get(targetCalendarId, eventId);
    print('$_TAG Current event: ${event.summary}');

    if (title != null) event.summary = title;
    if (startTime != null) {
      if (allDay == true) {
        event.start = calendar.EventDateTime(
          date: DateTime(startTime.year, startTime.month, startTime.day),
        );
      } else {
        event.start = calendar.EventDateTime(
          dateTime: startTime.toUtc(),
          timeZone: AppConstants.timeZone,
        );
      }
    }
    if (endTime != null) {
      if (allDay == true) {
        var allDayEndDate = DateTime(endTime.year, endTime.month, endTime.day);
        final allDayStartDate = DateTime(
            (startTime ?? event.start?.date ?? DateTime.now()).year,
            (startTime ?? event.start?.date ?? DateTime.now()).month,
            (startTime ?? event.start?.date ?? DateTime.now()).day);
        if (!allDayEndDate.isAfter(allDayStartDate)) {
          allDayEndDate = allDayStartDate.add(const Duration(days: 1));
        }
        event.end = calendar.EventDateTime(date: allDayEndDate);
      } else {
        event.end = calendar.EventDateTime(
          dateTime: endTime.toUtc(),
          timeZone: AppConstants.timeZone,
        );
      }
    }
    if (allDay == true && startTime == null && event.start?.dateTime != null) {
      final currentStart = event.start!.dateTime!.toLocal();
      event.start = calendar.EventDateTime(
        date: DateTime(currentStart.year, currentStart.month, currentStart.day),
      );
      final currentEnd =
          (event.end?.dateTime ?? currentStart.add(const Duration(hours: 1)))
              .toLocal();
      var allDayEndDate =
          DateTime(currentEnd.year, currentEnd.month, currentEnd.day);
      final allDayStartDate =
          DateTime(currentStart.year, currentStart.month, currentStart.day);
      if (!allDayEndDate.isAfter(allDayStartDate)) {
        allDayEndDate = allDayStartDate.add(const Duration(days: 1));
      }
      event.end = calendar.EventDateTime(date: allDayEndDate);
    }
    if (description != null) event.description = description;
    if (location != null) event.location = location;
    if (colorId != null) event.colorId = colorId;
    if (visibility != null) event.visibility = visibility;
    if (transparency != null) event.transparency = transparency;
    if (status != null) event.status = status;
    if (recurrence != null) event.recurrence = recurrence;
    if (attendeeEmails != null) {
      event.attendees = _buildAttendees(attendeeEmails);
    }
    if (remindersUseDefault != null || reminderMinutes != null) {
      event.reminders = _buildReminders(remindersUseDefault, reminderMinutes);
    }
    if (sourceTitle != null || sourceUrl != null) {
      event.source = _buildSource(sourceTitle, sourceUrl);
    }

    event = _applyAdvancedFields(event, advancedFields);

    if (startTime != null || endTime != null) {
      final nextStart = startTime ??
          event.start?.dateTime?.toLocal() ??
          event.start?.date ??
          DateTime.now();
      final nextEnd = endTime ??
          event.end?.dateTime?.toLocal() ??
          event.end?.date ??
          nextStart.add(const Duration(hours: 1));
      await _rejectOverlaps(
        start: nextStart,
        end: nextEnd,
        excludeEventId: eventId,
        confirmDespiteConflicts: confirmDespiteConflicts,
      );
    }

    print('$_TAG Updating event...');
    final result = await _api.events.update(event, targetCalendarId, eventId);
    _rememberEventCalendar(result, targetCalendarId);
    print('$_TAG Event updated: ${result.summary}');
    return result;
  }

  Future<void> deleteEvent(String eventId) async {
    print('$_TAG deleteEvent called');
    print('$_TAG Event ID: $eventId');
    final existingEvent = await getEventById(eventId);
    if (existingEvent == null) {
      print('$_TAG Event already absent: $eventId');
      _eventCalendarIndex.remove(eventId);
      return;
    }

    final calendarId = _calendarIdForEventId(eventId);
    final isRecurringInstance = existingEvent.recurringEventId != null &&
        existingEvent.originalStartTime != null;

    if (isRecurringInstance) {
      existingEvent.status = 'cancelled';
      await _api.events.update(existingEvent, calendarId, eventId);
      print('$_TAG Recurring instance cancelled');
    } else {
      await _api.events.delete(calendarId, eventId);
    }

    _eventCalendarIndex.remove(eventId);
    print('$_TAG Event deleted');
  }

  Future<calendar.Event?> getEventById(String eventId) async {
    print('$_TAG getEventById called: $eventId');
    try {
      final preferredCalendarId = _calendarIdForEventId(eventId);
      final event = await _api.events.get(preferredCalendarId, eventId);
      event.start?.dateTime = event.start?.dateTime?.toLocal();
      event.end?.dateTime = event.end?.dateTime?.toLocal();
      _rememberEventCalendar(event, preferredCalendarId);
      return event;
    } catch (e) {
      final errorText = e.toString().toLowerCase();
      if (errorText.contains('404') || errorText.contains('not found')) {
        final calendarIds = await _getAccessibleCalendarIds();
        for (final calendarId in calendarIds) {
          if (calendarId == _calendarIdForEventId(eventId)) continue;
          try {
            final event = await _api.events.get(calendarId, eventId);
            event.start?.dateTime = event.start?.dateTime?.toLocal();
            event.end?.dateTime = event.end?.dateTime?.toLocal();
            _rememberEventCalendar(event, calendarId);
            return event;
          } catch (_) {
            // Try next calendar.
          }
        }
        print('$_TAG Event not found across accessible calendars: $eventId');
        return null;
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFreeBusy(
      DateTime start, DateTime end) async {
    print('$_TAG fetchFreeBusy called');
    print(
        '$_TAG Start: ${start.toIso8601String()}, End: ${end.toIso8601String()}');

    final calendarIds = await _getAccessibleCalendarIds();
    final request = calendar.FreeBusyRequest(
      timeMin: start.toUtc(),
      timeMax: end.toUtc(),
      items: calendarIds
          .map((id) => calendar.FreeBusyRequestItem(id: id))
          .toList(),
    );
    final response = await _api.freebusy.query(request);
    final allBusyPeriods = <Map<String, dynamic>>[];

    (response.calendars ?? {}).forEach((calendarId, calendarInfo) {
      for (final period in calendarInfo.busy ?? <calendar.TimePeriod>[]) {
        allBusyPeriods.add({
          'calendarId': calendarId,
          'start': period.start?.toIso8601String(),
          'end': period.end?.toIso8601String(),
        });
      }
    });

    print('$_TAG Found ${allBusyPeriods.length} busy periods across calendars');
    return allBusyPeriods;
  }

  Future<List<Map<String, dynamic>>> findFreeSlots({
    required DateTime start,
    required DateTime end,
    required int minDurationMinutes,
    int dayStartHour = 8,
    int dayEndHour = 22,
    int maxResults = 10,
  }) async {
    print('$_TAG findFreeSlots called');
    print(
      '$_TAG Range: ${start.toIso8601String()} -> ${end.toIso8601String()}, '
      'minDurationMinutes=$minDurationMinutes, dayStartHour=$dayStartHour, dayEndHour=$dayEndHour',
    );

    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    var effectiveStart = localStart;
    final now = DateTime.now();
    if (localEnd.isAfter(now) && effectiveStart.isBefore(now)) {
      effectiveStart = now;
    }

    if (!localEnd.isAfter(effectiveStart)) {
      return [];
    }

    final safeMinDuration = minDurationMinutes <= 0 ? 1 : minDurationMinutes;
    final safeDayStart = dayStartHour.clamp(0, 23);
    final safeDayEnd = dayEndHour.clamp(safeDayStart + 1, 24);
    final safeMaxResults = maxResults <= 0 ? 10 : maxResults;

    final busyPeriods = await fetchFreeBusy(localStart, localEnd);
    final busyRanges = <_TimeRange>[];

    for (final period in busyPeriods) {
      final startRaw = period['start'] as String?;
      final endRaw = period['end'] as String?;
      if (startRaw == null || endRaw == null) continue;

      final busyStart = DateTime.parse(startRaw).toLocal();
      final busyEnd = DateTime.parse(endRaw).toLocal();
      if (!busyEnd.isAfter(busyStart)) continue;

      if (busyEnd.isBefore(effectiveStart) || busyStart.isAfter(localEnd)) {
        continue;
      }

      busyRanges.add(
        _TimeRange(
          start: _maxDateTime(busyStart, effectiveStart),
          end: _minDateTime(busyEnd, localEnd),
        ),
      );
    }

    busyRanges.sort((a, b) => a.start.compareTo(b.start));
    final mergedBusy = _mergeRanges(busyRanges);

    final slots = <Map<String, dynamic>>[];
    var dayCursor = DateTime(
      effectiveStart.year,
      effectiveStart.month,
      effectiveStart.day,
    );
    final endDay = DateTime(localEnd.year, localEnd.month, localEnd.day);

    while (!dayCursor.isAfter(endDay)) {
      final dayWindowStart = DateTime(
        dayCursor.year,
        dayCursor.month,
        dayCursor.day,
        safeDayStart,
      );
      final dayWindowEnd = DateTime(
        dayCursor.year,
        dayCursor.month,
        dayCursor.day,
        safeDayEnd,
      );

      var windowStart = _maxDateTime(dayWindowStart, effectiveStart);
      final windowEnd = _minDateTime(dayWindowEnd, localEnd);

      if (windowEnd.isAfter(windowStart)) {
        for (final busy in mergedBusy) {
          if (!busy.end.isAfter(windowStart) ||
              !busy.start.isBefore(windowEnd)) {
            continue;
          }

          final blockStart = _maxDateTime(busy.start, windowStart);
          final blockEnd = _minDateTime(busy.end, windowEnd);
          if (blockStart.isAfter(windowStart)) {
            final duration = blockStart.difference(windowStart).inMinutes;
            if (duration >= safeMinDuration) {
              slots.add({
                'start': windowStart.toIso8601String(),
                'end': blockStart.toIso8601String(),
                'durationMinutes': duration,
              });
            }
          }

          if (blockEnd.isAfter(windowStart)) {
            windowStart = blockEnd;
          }

          if (!windowEnd.isAfter(windowStart)) {
            break;
          }
        }

        if (windowEnd.isAfter(windowStart)) {
          final duration = windowEnd.difference(windowStart).inMinutes;
          if (duration >= safeMinDuration) {
            slots.add({
              'start': windowStart.toIso8601String(),
              'end': windowEnd.toIso8601String(),
              'durationMinutes': duration,
            });
          }
        }
      }

      if (slots.length >= safeMaxResults) {
        break;
      }

      dayCursor = dayCursor.add(const Duration(days: 1));
    }

    final trimmed = slots.take(safeMaxResults).toList();
    print('$_TAG Found ${trimmed.length} free slots');
    return trimmed;
  }

  List<_TimeRange> _mergeRanges(List<_TimeRange> ranges) {
    if (ranges.isEmpty) return [];

    final merged = <_TimeRange>[ranges.first];
    for (final range in ranges.skip(1)) {
      final last = merged.last;
      if (!range.start.isAfter(last.end)) {
        merged[merged.length - 1] = _TimeRange(
          start: last.start,
          end: _maxDateTime(last.end, range.end),
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  DateTime _maxDateTime(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  DateTime _minDateTime(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  Future<Map<String, Map<String, String?>>> fetchEventColors() async {
    print('$_TAG fetchEventColors called');
    final colors = await _api.colors.get();
    final eventColors = colors.event ?? {};
    final mapped = <String, Map<String, String?>>{};

    eventColors.forEach((id, colorDef) {
      mapped[id] = {
        'background': colorDef.background,
        'foreground': colorDef.foreground,
      };
    });

    print('$_TAG Found ${mapped.length} event colors');
    return mapped;
  }

  List<calendar.EventAttendee>? _buildAttendees(List<String>? attendeeEmails) {
    if (attendeeEmails == null) return null;
    final emails = attendeeEmails
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    return emails.map((email) => calendar.EventAttendee(email: email)).toList();
  }

  calendar.EventReminders? _buildReminders(
    bool? useDefault,
    List<int>? reminderMinutes,
  ) {
    if (useDefault == null && reminderMinutes == null) {
      return null;
    }

    final overrides = (reminderMinutes ?? <int>[])
        .where((m) => m >= 0)
        .map((m) => calendar.EventReminder(method: 'popup', minutes: m))
        .toList();

    return calendar.EventReminders(
      useDefault: useDefault ?? overrides.isEmpty,
      overrides: overrides.isEmpty ? null : overrides,
    );
  }

  calendar.EventSource? _buildSource(String? title, String? url) {
    if ((title == null || title.trim().isEmpty) &&
        (url == null || url.trim().isEmpty)) {
      return null;
    }
    return calendar.EventSource(
      title: title?.trim().isEmpty == true ? null : title?.trim(),
      url: url?.trim().isEmpty == true ? null : url?.trim(),
    );
  }

  calendar.Event _applyAdvancedFields(
    calendar.Event baseEvent,
    Map<String, dynamic>? advancedFields,
  ) {
    if (advancedFields == null || advancedFields.isEmpty) {
      return baseEvent;
    }

    final merged = Map<String, dynamic>.from(baseEvent.toJson());
    _deepMerge(merged, advancedFields);
    return calendar.Event.fromJson(merged);
  }

  void _deepMerge(Map<String, dynamic> target, Map<String, dynamic> patch) {
    for (final entry in patch.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map && target[key] is Map) {
        final nestedTarget =
            (target[key] as Map).map((k, v) => MapEntry(k.toString(), v));
        final nestedPatch = value.map((k, v) => MapEntry(k.toString(), v));
        _deepMerge(nestedTarget, nestedPatch);
        target[key] = nestedTarget;
      } else {
        target[key] = value;
      }
    }
  }
}

class _TimeRange {
  final DateTime start;
  final DateTime end;

  const _TimeRange({
    required this.start,
    required this.end,
  });
}
