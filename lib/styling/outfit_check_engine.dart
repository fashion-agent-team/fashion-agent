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

/// 음성으로 읽을 결과. 보이는 옷 → 얼룩·찢어짐 → 날씨·일정에 맞는지 순서다(2026-11-09 진행 님 요청).
///
/// 날씨와 일정에 잘 맞으면 "오늘 날씨와 일정에 잘 어울려요."만 말하고,
/// 맞지 않으면 오늘 날씨와 일정을 먼저 알려 준 뒤 무엇을 바꾸면 좋을지 말한다.
String checkSpeech(OutfitCheck c, {Weather? weather}) {
  if (c.unsure != null) return c.unsure!;
  final fits = c.scheduleOk && c.weatherOk;
  final umbrella = c.weatherNotes.where((n) => n.contains('우산'));
  final advice = [
    ...c.scheduleNotes,
    ...c.weatherNotes.where((n) => !n.contains('알맞은 옷차림') && !n.contains('우산')),
  ];
  final parts = <String>[
    '보이는 옷은 ${ieyo(c.garments.map((g) => g.spokenName).join(', '))}.',
    c.damageNotes.join(' '),
    if (fits) ...[
      if (c.weatherNotes.isNotEmpty && c.event != null)
        '오늘 날씨와 일정에 잘 어울려요.'
      else if (c.weatherNotes.isNotEmpty)
        '오늘 날씨에 잘 어울려요. 등록된 일정은 없어요.'
      else if (c.event != null)
        '오늘 일정에 잘 어울려요.',
    ] else ...[
      if (weather != null) weatherSummary(weather),
      if (c.event != null)
        '${spokenTime(c.event!.start)} ${iGa(c.event!.title)} 있어요.',
      ...advice,
    ],
    ...umbrella,
    if (c.weatherNotes.isEmpty) '날씨를 가져오지 못해서 날씨는 확인하지 못했어요.',
    if (c.allGood) '이대로 나가셔도 좋아요.',
  ];
  return parts.where((p) => p.isNotEmpty).join(' ');
}

/// "오늘은 체감 온도 12도, 최저 8도 최고 16도예요."
String weatherSummary(Weather w) =>
    '오늘은 체감 온도 ${spokenDegrees(w.apparentTemperature)}, '
    '최저 ${spokenDegrees(w.minTemperature)} 최고 ${ieyo(spokenDegrees(w.maxTemperature))}.';
