import 'package:fashion_agent/models/garment.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/styling/color_rules.dart';
import 'package:fashion_agent/styling/damage_rules.dart';
import 'package:fashion_agent/styling/korean.dart';
import 'package:fashion_agent/styling/outfit_check_engine.dart';
import 'package:fashion_agent/styling/schedule_rules.dart';
import 'package:fashion_agent/styling/weather_rules.dart';
import 'package:flutter_test/flutter_test.dart';

Garment g(
  String id,
  GarmentCategory category,
  String colorName,
  ColorFamily family, {
  String name = '옷',
  Tone tone = Tone.mid,
  String? pattern,
  String? material,
  Formality formality = Formality.unknown,
  List<GarmentDefect> defects = const [],
  GarmentBox? box,
  double confidence = 0.9,
}) =>
    Garment(
      id: id,
      category: category,
      name: name,
      colorName: colorName,
      colorFamily: family,
      tone: tone,
      pattern: pattern,
      material: material,
      formality: formality,
      defects: defects,
      box: box,
      confidence: confidence,
    );

Weather weatherAt(double apparent, {int rain = 0, double range = 6}) => Weather(
      temperature: apparent,
      apparentTemperature: apparent,
      minTemperature: apparent - range / 2,
      maxTemperature: apparent + range / 2,
      weatherCode: 0,
      precipitationProbability: rain,
    );

void main() {
  final navyShirt =
      g('t', GarmentCategory.top, '남색', ColorFamily.navy, name: '셔츠');
  final beigePants =
      g('b', GarmentCategory.bottom, '베이지', ColorFamily.beige, name: '면바지');
  final redTop = g('r', GarmentCategory.top, '빨간색', ColorFamily.red);
  final greenPants = g('gr', GarmentCategory.bottom, '초록색', ColorFamily.green);

  group('조사', () {
    test('받침에 맞춰 붙인다', () {
      expect(gwaWa('남색'), '남색과');
      expect(gwaWa('베이지'), '베이지와');
      expect(eunNeun('베이지'), '베이지는');
      expect(ira('12도'), '12도라');
      expect(euro('체크'), '체크로');
      expect(euro('줄무늬'), '줄무늬로');
    });
  });

  group('색 조합', () {
    test('기본색끼리는 잘 어울린다', () {
      final m = matchColors(navyShirt, beigePants);
      expect(m.verdict, Verdict.good);
      expect(m.reason, '남색과 베이지는 기본색끼리라 무난하게 잘 어울려요.');
    });

    test('빨강과 초록은 부딪힌다고 경고한다', () {
      final m = matchColors(redTop, greenPants);
      expect(m.verdict, Verdict.clash);
      expect(m.reason, contains('부딪혀'));
    });

    test('기본색 하나가 있으면 어울린다', () {
      expect(matchColors(redTop, beigePants).verdict, Verdict.good);
    });

    test('무늬가 둘 다 있으면 주의를 준다', () {
      final striped =
          g('s', GarmentCategory.top, '흰색', ColorFamily.white, pattern: '줄무늬');
      final checked =
          g('c', GarmentCategory.bottom, '회색', ColorFamily.gray, pattern: '체크');
      expect(overlapWarnings(striped, checked).single, contains('줄무늬와 체크로'));
    });
  });

  group('겉옷', () {
    test('체감 온도로 겉옷을 고르고 이유를 말한다', () {
      expect(outerAdvice(weatherAt(24)), isNull);
      expect(outerAdvice(weatherAt(12)), '체감 온도가 12도라서 자켓이나 가디건을 걸치세요.');
      expect(outerAdvice(weatherAt(-3)), contains('영하 3도라서 패딩'));
    });
  });

  final today = DateTime(2026, 11, 3, 9);
  ScheduleEvent event(String title, {int hour = 14}) =>
      ScheduleEvent(title: title, start: DateTime(2026, 11, 3, hour));

  final shirt = g('t', GarmentCategory.top, '남색', ColorFamily.navy,
      name: '셔츠', formality: Formality.smart);
  final jeans = g('j', GarmentCategory.bottom, '파란색', ColorFamily.blue,
      name: '청바지', formality: Formality.casual);
  final slacks = g('s', GarmentCategory.bottom, '검은색', ColorFamily.black,
      name: '슬랙스', formality: Formality.smart, tone: Tone.dark);

  group('일정', () {
    test('일정 이름으로 성격을 고른다', () {
      expect(occasionOf(event('오후 면접')), Occasion.formal);
      expect(occasionOf(event('친구 결혼식')), Occasion.wedding);
      expect(occasionOf(event('헬스')), Occasion.active);
      expect(occasionOf(event('카페')), Occasion.casual);
    });

    test('여러 일정이면 가장 격식 있는 자리에 맞추고, 끝난 일정은 뺀다', () {
      final events = [event('카페', hour: 11), event('면접', hour: 15)];
      expect(eventToDressFor(events, today)?.title, '면접');
      expect(eventToDressFor([event('회의', hour: 6)], today), isNull);
    });

    test('면접에 청바지면 이유와 대신 입을 옷을 말한다', () {
      final fit = scheduleFit(event('면접'), [shirt, jeans]);
      expect(fit.ok, isFalse);
      expect(fit.notes.single, '파란색 청바지는 편한 옷이라 면접에는 슬랙스나 정장 바지, 단정한 치마가 좋아요.');
      expect(scheduleFit(event('면접'), [shirt, slacks]).ok, isTrue);
    });

    test('장례식에는 밝은 색을 알려 준다', () {
      final pink = g('p', GarmentCategory.top, '분홍색', ColorFamily.pink,
          name: '니트', formality: Formality.smart);
      final fit = scheduleFit(event('장례식 조문'), [pink, slacks]);
      expect(fit.ok, isFalse);
      expect(fit.notes.single, contains('밝아 보일 수 있어요'));
    });
  });

  group('날씨', () {
    test('겉옷 없이 쌀쌀하면 겉옷을 챙기라고 한다', () {
      final fit = weatherFit(weatherAt(12), [shirt, jeans]);
      expect(fit.ok, isFalse);
      expect(fit.notes.single, '겉옷은 보이지 않아요. 체감 온도가 12도라서 자켓이나 가디건을 걸치세요.');
    });

    test('따뜻해도 일교차가 크면 겉옷을 챙기라고 한다', () {
      final fit = weatherFit(weatherAt(22, range: 12), [shirt, jeans]);
      expect(fit.ok, isFalse);
      expect(fit.notes.single, contains('일교차가 12도로 커요'));
    });

    test('알맞으면 이유를 붙여 알맞다고 한다', () {
      final fit = weatherFit(weatherAt(24), [shirt, jeans]);
      expect(fit.ok, isTrue);
      expect(fit.notes.single, '체감 온도가 24도라서 오늘 날씨에 알맞은 옷차림이에요.');
    });

    test('더운 날 니트는 주의를 준다', () {
      final knit = g('k', GarmentCategory.top, '회색', ColorFamily.gray,
          name: '니트', material: '니트 같음');
      expect(weatherFit(weatherAt(27), [knit, jeans]).notes,
          contains('니트가 따뜻한 소재 같아서 오늘은 더울 수 있어요.'));
    });
  });

  group('얼룩·찢어짐', () {
    test('위치와 함께 알려 주고, 확실하지 않으면 손으로 확인하라고 한다', () {
      final stained = g('t', GarmentCategory.top, '흰색', ColorFamily.white,
          name: '셔츠',
          defects: const [
            GarmentDefect(
                kind: DefectKind.stain, where: '왼쪽 가슴', confidence: 0.9),
            GarmentDefect(kind: DefectKind.tear, where: '밑단', confidence: 0.4),
          ]);
      expect(damageNotes([stained]), [
        '흰색 셔츠 왼쪽 가슴에 얼룩이 있어요.',
        '흰색 셔츠 밑단에 찢어진 곳 같은 게 보여요. 손으로 한번 확인해 보세요.',
      ]);
      expect(hasDamage([stained]), isTrue);
    });

    test('없으면 없다고 말한다', () {
      expect(damageNotes([shirt]), ['얼룩이나 찢어진 곳은 보이지 않아요.']);
    });
  });

  group('옷 검사', () {
    test('일정·날씨·손상 순서로 이유를 붙여 말한다', () {
      final c = checkOutfit([shirt, jeans],
          weather: weatherAt(24), todayEvents: [event('면접')], now: today);
      expect(c.allGood, isFalse);
      expect(
          checkSpeech(c),
          '보이는 옷은 남색 셔츠, 파란색 청바지예요. '
          '오후 2시 면접 일정 기준으로 볼게요. '
          '파란색 청바지는 편한 옷이라 면접에는 슬랙스나 정장 바지, 단정한 치마가 좋아요. '
          '체감 온도가 24도라서 오늘 날씨에 알맞은 옷차림이에요. '
          '얼룩이나 찢어진 곳은 보이지 않아요.');
    });

    test('일정이 없고 다 괜찮으면 그대로 나가도 좋다고 한다', () {
      final c =
          checkOutfit([shirt, slacks], weather: weatherAt(24), now: today);
      expect(c.allGood, isTrue);
      expect(checkSpeech(c), contains('오늘 등록된 일정은 없어요.'));
      expect(checkSpeech(c), endsWith('이대로 나가셔도 좋아요.'));
    });

    test('확신이 낮으면 판단하지 않고 다시 비춰 달라고 한다', () {
      final blurry =
          g('x', GarmentCategory.top, '회색', ColorFamily.gray, confidence: 0.3);
      final c = checkOutfit([blurry, jeans], now: today);
      expect(c.unsure, contains('다시 비춰'));
    });
  });
}
