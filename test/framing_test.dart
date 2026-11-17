import 'dart:typed_data';
import 'dart:ui';

import 'package:fashion_agent/services/framing.dart';
import 'package:flutter_test/flutter_test.dart';

BodyPoint p(double x, double y, [double l = 0.9]) =>
    (x: x, y: y, likelihood: l);

void main() {
  group('내려놓은 옷', () {
    test('옷이 없으면 비춰 달라고 한다', () {
      expect(frameGarment([]).speech, contains('안 보여요'));
    });

    test('가운데에 적당한 크기면 찍는다', () {
      expect(frameGarment([const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8)]).ready,
          isTrue);
    });

    test('치우치거나 잘리면 그쪽으로 옮기게 한다', () {
      expect(frameGarment([const Rect.fromLTRB(0.0, 0.3, 0.5, 0.7)]).speech,
          contains('왼쪽'));
      expect(frameGarment([const Rect.fromLTRB(0.55, 0.3, 0.95, 0.7)]).speech,
          contains('오른쪽'));
      expect(frameGarment([const Rect.fromLTRB(0.3, 0.0, 0.7, 0.5)]).speech,
          contains('위로'));
    });

    test('너무 크면 높이 들고, 너무 작으면 가까이', () {
      expect(frameGarment([const Rect.fromLTRB(0, 0.1, 1, 0.9)]).speech,
          contains('높이'));
      expect(frameGarment([const Rect.fromLTRB(0.45, 0.45, 0.55, 0.55)]).speech,
          contains('가까이'));
    });

    test('두 벌이면 둘 다 감싸서 본다', () {
      expect(
          frameGarment([
            const Rect.fromLTRB(0.15, 0.3, 0.45, 0.7),
            const Rect.fromLTRB(0.55, 0.3, 0.85, 0.7),
          ]).ready,
          isTrue);
    });
  });

  group('입은 옷', () {
    Map<String, List<BodyPoint>> body(
            {double footY = 0.92,
            double x = 0.5,
            double kneeY = 0.72,
            double footL = 0.9,
            double scale = 1}) =>
        {
          'head': [p(x, 0.08 * scale)],
          'shoulder': [p(x - 0.1, 0.2 * scale), p(x + 0.1, 0.2 * scale)],
          'hip': [p(x - 0.08, 0.5 * scale), p(x + 0.08, 0.5 * scale)],
          'knee': [p(x - 0.07, kneeY * scale), p(x + 0.07, kneeY * scale)],
          'foot': [
            p(x - 0.06, footY * scale, footL),
            p(x + 0.06, footY * scale, footL)
          ],
        };

    test('머리부터 발까지 가운데면 찍는다', () {
      expect(frameBody(body()).ready, isTrue);
    });

    test('발과 무릎 아래가 안 보이면 뒤로', () {
      expect(frameBody(body(footY: 1.2, kneeY: 0.95, scale: 1.3)).speech,
          contains('뒤로'));
    });

    test('발목이 흐릿해도 무릎이 아래쪽에 보이면 찍는다(리허설: 앞뒤로 왔다 갔다)', () {
      expect(frameBody(body(footL: 0.2)).ready, isTrue);
    });

    test('조금 멀어도 앞으로 오라고 하지 않는다', () {
      // 몸이 화면 세로의 40% 정도. 예전에는 45% 미만이면 앞으로 오라고 해서 뒤로·앞으로를 번갈아 말했다.
      expect(frameBody(body(scale: 0.45)).ready, isTrue);
    });

    test('아주 멀면 앞으로', () {
      expect(frameBody(body(scale: 0.2)).speech, contains('앞으로'));
    });

    test('얼굴이 안 나와도 어깨부터 발까지 보이면 찍는다', () {
      final points = body()..remove('head');
      expect(frameBody(points).ready, isTrue);
    });

    test('몸이 없으면 서 달라고 한다', () {
      expect(frameBody({}).speech, contains('몸이 안 보여요'));
    });

    test('한쪽으로 치우치면 가운데로', () {
      // 뒤쪽 카메라: 사진 왼쪽에 있으면 그 사람은 자기 오른쪽으로 치우친 것이라 왼쪽으로 가야 한다.
      expect(frameBody(body(x: 0.15)).speech, contains('왼쪽'));
      expect(frameBody(body(x: 0.85)).speech, contains('오른쪽'));
    });
  });

  test('같은 장면은 차이가 작다', () {
    final a = List<double>.filled(256, 100);
    final b = List<double>.filled(256, 102);
    final c = List<double>.filled(256, 160);
    expect(sceneDifference(a, b), lessThan(5));
    expect(sceneDifference(a, c), greaterThan(30));
  });

  test('누운 프레임을 시계 방향으로 세운다', () {
    // 2×1 그림: 왼쪽 빨강(BGRA 0,0,255), 오른쪽 파랑
    final src = Uint8List.fromList([0, 0, 255, 255, 255, 0, 0, 255]);
    final r = uprightBgra(src,
        width: 2, height: 1, bytesPerRow: 8, rotation: 90, step: 1);
    expect((r.width, r.height), (1, 2));
    // 시계 방향 90도: 왼쪽(빨강)이 위로
    expect(r.bytes.sublist(0, 3), [0, 0, 255]);
    expect(r.bytes.sublist(4, 7), [255, 0, 0]);
  });

  group('셀카 얼굴 각도·밝기(2026-11-17)', () {
    const face = Rect.fromLTRB(0.2, 0.2, 0.8, 0.75);
    const bright = (mean: 140.0, left: 140.0, right: 135.0);

    test('똑바로 보고 밝으면 찍는다', () {
      expect(frameFace([face], yaw: 3, roll: -4, light: bright).ready, isTrue);
    });

    test('고개를 돌리거나 기울이면 똑바로 하라고 한다', () {
      expect(frameFace([face], yaw: -20).speech, contains('똑바로 봐'));
      expect(frameFace([face], roll: 28).speech, contains('기울었어요'));
    });

    test('어둡거나 한쪽이 그늘지면 조명이 필요하다고 표시한다', () {
      final dark = frameFace([face], light: (mean: 40, left: 40, right: 40));
      expect(dark.dark, isTrue);
      expect(dark.speech, contains('어두워요'));
      final uneven =
          frameFace([face], light: (mean: 110, left: 150, right: 70));
      expect(uneven.dark, isTrue);
      expect(uneven.speech, contains('그늘'));
    });

    test('이마·턱이 잘리면 위아래로 옮기게 한다', () {
      expect(frameFace([const Rect.fromLTRB(0.2, 0.0, 0.8, 0.5)]).speech,
          contains('위로'));
      expect(frameFace([const Rect.fromLTRB(0.2, 0.5, 0.8, 1.0)]).speech,
          contains('아래로'));
    });
  });

  group('치아(입) 구도', () {
    MouthView mouth(
            {double cx = 0.5,
            double cy = 0.6,
            double width = 0.4,
            double open = 0.3,
            double? luma = 150}) =>
        (
          inner: Rect.fromCenter(
              center: Offset(cx, cy), width: width, height: width * open),
          lips: Rect.fromCenter(
              center: Offset(cx, cy),
              width: width * 1.15,
              height: width * open + 0.08),
          luma: luma,
        );

    test('얼굴을 못 찾으면 얼굴 전체가 들어오게 떨어뜨리라고 한다', () {
      final f = frameMouth(null);
      expect(f.ready, isFalse);
      expect(f.speech, contains('얼굴 전체'));
      expect(f.closeness, 0);
      expect(frameMouth(null, faceSeen: true).speech, contains('입이 잘 안 보여요'));
    });

    test('입술 윤곽 없이 입 끝 점만 찾아도 크기·자리는 본다', () {
      MouthView corners(double width) => (
            inner: null,
            lips: Rect.fromCenter(
                center: const Offset(0.5, 0.6), width: width, height: 0.1),
            luma: 150,
          );
      expect(frameMouth(corners(0.4)).ready, isTrue);
      expect(frameMouth(corners(0.12)).speech, contains('가까이'));
    });

    test('가운데에서 크게, 벌리고, 밝으면 찍는다', () {
      final f = frameMouth(mouth());
      expect(f.ready, isTrue);
      expect(f.closeness, 1);
    });

    test('입이 작으면 가까이, 너무 크면 멀리', () {
      expect(frameMouth(mouth(width: 0.12)).speech, contains('가까이'));
      expect(frameMouth(mouth(width: 0.75)).speech, contains('멀리'));
    });

    test('입이 잘리면 위·아래·정면으로 옮기게 한다', () {
      expect(frameMouth(mouth(cy: 0.05)).speech, contains('위로'));
      expect(frameMouth(mouth(cy: 0.97)).speech, contains('아래로'));
      expect(frameMouth(mouth(cx: 0.1)).speech, contains('정면'));
    });

    test('덜 벌렸으면 "이~" 하라고 한다', () {
      expect(frameMouth(mouth(open: 0.05)).speech, contains('이~'));
    });

    test('입 안이 어두우면 조명이 필요하다고 표시한다', () {
      final f = frameMouth(mouth(luma: 30));
      expect(f.ready, isFalse);
      expect(f.dark, isTrue);
      expect(f.speech, contains('어두워요'));
    });

    test('가운데로 오고 벌릴수록 소리가 빨라진다', () {
      final lips = mouth().lips;
      expect(
          mouthCloseness(lips, 0.3), greaterThan(mouthCloseness(lips, 0.02)));
      expect(mouthCloseness(lips, 0.3),
          greaterThan(mouthCloseness(lips.shift(const Offset(0.3, 0)), 0.3)));
    });
  });

  group('세운 화면 기준 밝기', () {
    // 4×2 원본(가로로 누움, Y 평면): 왼쪽 두 칸 0, 오른쪽 두 칸 200
    final raw = Uint8List.fromList([0, 0, 200, 200, 0, 0, 200, 200]);

    test('돌리지 않으면 그대로 읽는다', () {
      expect(
          uprightRegionLuma(raw,
              width: 4,
              height: 2,
              bytesPerRow: 4,
              rotation: 0,
              region: const Rect.fromLTRB(0.5, 0, 1, 1)),
          200);
    });

    test('90도 세우면 원본 오른쪽이 아래로 간다', () {
      double at(Rect r) => uprightRegionLuma(raw,
          width: 4, height: 2, bytesPerRow: 4, rotation: 90, region: r);
      expect(at(const Rect.fromLTRB(0, 0.5, 1, 1)), 200);
      expect(at(const Rect.fromLTRB(0, 0, 1, 0.5)), 0);
    });

    test('BGRA도 읽는다', () {
      final bgra = Uint8List.fromList([100, 100, 100, 255]);
      expect(
          uprightRegionLuma(bgra,
              width: 1,
              height: 1,
              bytesPerRow: 4,
              bytesPerPixel: 4,
              rotation: 0,
              region: const Rect.fromLTRB(0, 0, 1, 1)),
          closeTo(100, 1e-6));
    });
  });
}
