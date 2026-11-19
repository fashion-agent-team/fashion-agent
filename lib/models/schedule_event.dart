/// 사용자가 등록한 일정 하나.
class ScheduleEvent {
  const ScheduleEvent({
    required this.title,
    required this.start,
    this.place,
    this.remind = true,
    this.remindDaysBefore,
  });

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) => ScheduleEvent(
        title: json['title'] as String,
        start: DateTime.parse(json['start'] as String).toLocal(),
        place: json['place'] as String?,
        remind: json['remind'] as bool? ?? true,
        remindDaysBefore: (json['remindDaysBefore'] as num?)?.toInt(),
      );

  /// "면접", "친구 결혼식"처럼 사용자가 말한 일정 이름.
  final String title;
  final DateTime start;
  final String? place;

  /// 폰 알림을 받을지. 일정을 넣을 때 "일정 전에 알림을 드릴까요?"에 "아니"라고 하면 false.
  final bool remind;

  /// 며칠 전 저녁 8시에 미리 알릴지. 0이면 당일 아침만. null이면 아직 안 정함(전날 저녁 + 당일 아침).
  final int? remindDaysBefore;

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': start.toIso8601String(),
        'place': place,
        'remind': remind,
        'remindDaysBefore': remindDaysBefore,
      };
}

/// "오후 2시", "오전 10시 30분".
String spokenTime(DateTime t) {
  final ampm = t.hour < 12 ? '오전' : '오후';
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$ampm $hour시${t.minute == 0 ? '' : ' ${t.minute}분'}';
}
