import '../models/garment.dart';
import '../models/outfit_check.dart';
import '../models/schedule_event.dart';
import '../models/weather.dart';
import 'damage_rules.dart';
import 'korean.dart';
import 'schedule_rules.dart';
import 'weather_rules.dart';

/// 이 값보다 확신이 낮은 옷은 판단에 쓰지 않고 다시 비춰 달라고 한다.
const minConfidence = 0.6;

/// 입은(입으려는) 옷을 일정·날씨·손상 세 가지로 검사한다.
///
/// AI가 준 사실([Garment])만 받아서 규칙으로 판단하므로, 같은 입력이면 늘 같은 결과가 나온다.
OutfitCheck checkOutfit(
  List<Garment> garments, {
  Weather? weather,
  List<ScheduleEvent> todayEvents = const [],
  required DateTime now,
}) {
  final unsure = garments.where((g) => g.confidence < minConfidence).toList();
  if (unsure.isNotEmpty) {
    return OutfitCheck.unsure(
        '${josa(unsure.first.name, '을', '를')} 잘 알아보지 못했어요. '
        '불을 켜고 다시 비춰 주세요.');
  }

  final event = eventToDressFor(todayEvents, now);
  final schedule = event == null ? null : scheduleFit(event, garments);
  final fit = weather == null ? null : weatherFit(weather, garments);

  return OutfitCheck(
    garments: garments,
    event: event,
    scheduleOk: schedule?.ok ?? true,
    scheduleNotes: schedule?.notes ?? const [],
    weatherOk: fit?.ok ?? true,
    weatherNotes: fit?.notes ?? const [],
    damaged: hasDamage(garments),
    damageNotes: damageNotes(garments),
  );
}

/// 음성으로 읽을 결과. 입은 옷 → 일정 → 날씨 → 얼룩·찢어짐 순서로, 항목마다 이유를 붙인다.
String checkSpeech(OutfitCheck c) {
  if (c.unsure != null) return c.unsure!;
  final parts = <String>[
    '보이는 옷은 ${ieyo(c.garments.map((g) => g.spokenName).join(', '))}.',
    if (c.event == null)
      '오늘 등록된 일정은 없어요.'
    else
      '${spokenTime(c.event!.start)} ${c.event!.title} 일정 기준으로 볼게요. '
          '${c.scheduleNotes.join(' ')}',
    if (c.weatherNotes.isEmpty)
      '날씨를 가져오지 못해서 날씨는 확인하지 못했어요.'
    else
      c.weatherNotes.join(' '),
    c.damageNotes.join(' '),
    if (c.allGood) '이대로 나가셔도 좋아요.',
  ];
  return parts.join(' ');
}
