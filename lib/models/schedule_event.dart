/// 사용자가 등록한 일정 하나.
class ScheduleEvent {
  const ScheduleEvent({
    required this.title,
    required this.start,
    this.place,
    this.remind = true,
    this.remindDaysBefore,
    this.remindTime,
  });

  factory ScheduleEvent.fromJson(Map<String, dynamic> json) => ScheduleEvent(
        title: json['title'] as String,
        start: DateTime.parse(json['start'] as String).toLocal(),
        place: json['place'] as String?,
        remind: json['remind'] as bool? ?? true,
        remindDaysBefore: (json['remindDaysBefore'] as num?)?.toInt(),
        remindTime: parseRemindTime(json['remindTime'] as String?),
      );

  /// "면접", "친구 결혼식"처럼 사용자가 말한 일정 이름.
  final String title;
  final DateTime start;
  final String? place;

  /// 폰 알림을 받을지. 일정을 넣을 때 "일정 전에 알림을 드릴까요?"에 "아니"라고 하면 false.
  final bool remind;

  /// 며칠 전 아침 8시에 미리 알릴지. 0이면 당일 아침만. null이면 아직 안 정함(전날 아침 + 당일 아침).
  final int? remindDaysBefore;

  /// 미리 알림을 띄울 시각(서울). null이면 아침 8시. [remindDaysBefore]가 0이면 당일 알림 시각.
  /// "약속 2일 전 오후 4시에 알려 줘"면 2일·16:00(2026-11-20 정지원).
  final ({int hour, int minute})? remindTime;

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': start.toIso8601String(),
        'place': place,
        'remind': remind,
        'remindDaysBefore': remindDaysBefore,
        'remindTime': remindTime == null
            ? null
            : '${remindTime!.hour.toString().padLeft(2, '0')}:'
                '${remindTime!.minute.toString().padLeft(2, '0')}',
      };
}

/// 서버가 준 "16:00"(또는 "16:00:00")을 시·분으로. 비었거나 못 읽으면 null(아침 8시).
({int hour, int minute})? parseRemindTime(String? text) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(text ?? '');
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return (hour: hour, minute: minute);
}

/// "오후 2시", "오전 10시 30분".
String spokenTime(DateTime t) {
  final ampm = t.hour < 12 ? '오전' : '오후';
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$ampm $hour시${t.minute == 0 ? '' : ' ${t.minute}분'}';
}
