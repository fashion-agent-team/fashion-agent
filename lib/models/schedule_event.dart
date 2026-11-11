/// 사용자가 등록한 일정 하나.
class ScheduleEvent {
  const ScheduleEvent({required this.title, required this.start, this.place});

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) => ScheduleEvent(
        title: json['title'] as String,
        start: DateTime.parse(json['start'] as String).toLocal(),
        place: json['place'] as String?,
      );

  /// "면접", "친구 결혼식"처럼 사용자가 말한 일정 이름.
  final String title;
  final DateTime start;
  final String? place;

  Map<String, dynamic> toJson() =>
      {'title': title, 'start': start.toIso8601String(), 'place': place};
}

/// "오후 2시", "오전 10시 30분".
String spokenTime(DateTime t) {
  final ampm = t.hour < 12 ? '오전' : '오후';
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$ampm $hour시${t.minute == 0 ? '' : ' ${t.minute}분'}';
}
