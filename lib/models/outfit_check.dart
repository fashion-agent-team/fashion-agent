import 'garment.dart';
import 'schedule_event.dart';

/// 옷 검사 결과. 일정, 날씨, 손상 세 가지를 따로 담고, 판단마다 이유를 붙인다.
class OutfitCheck {
  const OutfitCheck({
    required this.garments,
    this.event,
    this.scheduleOk = true,
    this.scheduleNotes = const [],
    this.weatherOk = true,
    this.weatherNotes = const [],
    this.damaged = false,
    this.damageNotes = const [],
    this.unsure,
  });

  /// 판단할 수 없을 때. 다시 비춰 달라는 안내를 담는다.
  const OutfitCheck.unsure(String reason)
      : this(garments: const [], unsure: reason);

  final List<Garment> garments;

  /// 맞춰 본 일정. 오늘 일정이 없으면 null.
  final ScheduleEvent? event;
  final bool scheduleOk;
  final List<String> scheduleNotes;

  /// 날씨를 못 가져오면 [weatherNotes]가 빈다.
  final bool weatherOk;
  final List<String> weatherNotes;

  final bool damaged;
  final List<String> damageNotes;

  final String? unsure;

  bool get allGood => unsure == null && scheduleOk && weatherOk && !damaged;
}
