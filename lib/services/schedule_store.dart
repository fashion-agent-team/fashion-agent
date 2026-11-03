import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_event.dart';

/// 일정 저장소. 일정 기능(말로 등록)이 채우고, 옷 검사가 오늘 일정을 읽는다.
abstract class ScheduleStore {
  Future<List<ScheduleEvent>> all();
  Future<void> add(ScheduleEvent event);

  /// [day]와 같은 날짜의 일정을 시간순으로.
  Future<List<ScheduleEvent>> on(DateTime day) async {
    final events = (await all())
        .where((e) =>
            e.start.year == day.year &&
            e.start.month == day.month &&
            e.start.day == day.day)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return events;
  }
}

class LocalScheduleStore extends ScheduleStore {
  static const _key = 'schedule.events';

  @override
  Future<List<ScheduleEvent>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ScheduleEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> add(ScheduleEvent event) async {
    final events = [...await all(), event];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final e in events) e.toJson()]));
  }
}

class InMemoryScheduleStore extends ScheduleStore {
  InMemoryScheduleStore([List<ScheduleEvent>? events]) : events = events ?? [];

  final List<ScheduleEvent> events;

  @override
  Future<List<ScheduleEvent>> all() async => events;

  @override
  Future<void> add(ScheduleEvent event) async => events.add(event);
}
