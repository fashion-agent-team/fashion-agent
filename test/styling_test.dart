import 'package:fashion_agent/models/garment.dart';
import 'package:fashion_agent/models/outfit_feedback.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/styling/color_rules.dart';
import 'package:fashion_agent/styling/feedback_engine.dart';
import 'package:fashion_agent/styling/korean.dart';
import 'package:fashion_agent/styling/position_speech.dart';
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
      box: box,
      confidence: confidence,
    );

Weather weatherAt(double apparent, {int rain = 0}) => Weather(
      temperature: apparent,
      apparentTemperature: apparent,
      minTemperature: apparent - 3,
      maxTemperature: apparent + 3,
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

  group('피드백', () {
    test('상의와 하의를 판단하고 이유를 붙인다', () {
      final f = evaluateOutfit([navyShirt, beigePants]);
      expect(f.verdict, Verdict.good);
      expect(f.toSpeech(), startsWith('잘 어울리는 조합이에요.'));
    });

    test('확신이 낮으면 판단하지 않고 다시 비춰 달라고 한다', () {
      final blurry =
          g('x', GarmentCategory.top, '회색', ColorFamily.gray, confidence: 0.3);
      final f = evaluateOutfit([blurry, beigePants]);
      expect(f.verdict, Verdict.unsure);
      expect(f.reasons.single, contains('다시 비춰'));
    });

    test('하의가 없으면 함께 펼쳐 달라고 한다', () {
      final f = evaluateOutfit([navyShirt]);
      expect(f.verdict, Verdict.unsure);
      expect(f.reasons.first, '하의를 찾지 못했어요.');
    });

    test('더운 날 니트는 주의를 준다', () {
      final knit = g('k', GarmentCategory.top, '회색', ColorFamily.gray,
          name: '니트', material: '니트 같음');
      final f = evaluateOutfit([knit, beigePants], weather: weatherAt(27));
      expect(f.warnings, contains('니트가 따뜻한 소재 같아서 오늘은 더울 수 있어요.'));
    });
  });

  group('겉옷', () {
    test('체감 온도로 겉옷을 고르고 이유를 말한다', () {
      expect(outerAdvice(weatherAt(24)), isNull);
      expect(outerAdvice(weatherAt(12)), '체감 온도가 12도라서 자켓이나 가디건을 걸치세요.');
      expect(outerAdvice(weatherAt(-3)), contains('영하 3도라서 패딩'));
    });
  });

  group('옷장 대안', () {
    test('남겨 둘 옷과 어울리는 같은 종류만 고른다', () {
      final closet = [
        g('c1', GarmentCategory.bottom, '초록색', ColorFamily.green),
        g('c2', GarmentCategory.bottom, '베이지', ColorFamily.beige),
        g('c3', GarmentCategory.top, '회색', ColorFamily.gray),
      ];
      final alts =
          findAlternatives(keep: redTop, replace: greenPants, closet: closet);
      expect(alts.map((a) => a.id), ['c2']);
    });

    test('위치를 왼쪽부터 순서로 말한다', () {
      final a = g('a', GarmentCategory.bottom, '파란색', ColorFamily.blue,
          box: const GarmentBox(0.05, 0.5, 0.2, 0.4));
      final b = g('b', GarmentCategory.bottom, '베이지', ColorFamily.beige,
          box: const GarmentBox(0.3, 0.5, 0.2, 0.4));
      expect(describePosition(b, [a, b]), '가운데 아래, 왼쪽에서 두 번째');
    });

    test('꺼낸 옷이 안내한 옷인지 확인한다', () {
      expect(isSameGarment(beigePants, beigePants), isTrue);
      expect(isSameGarment(beigePants, greenPants), isFalse);
      expect(
          isSameGarment(
              beigePants,
              g('x', GarmentCategory.bottom, '베이지', ColorFamily.beige,
                  confidence: 0.2)),
          isNull);
    });
  });
}
