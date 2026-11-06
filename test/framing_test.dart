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
          contains('위쪽'));
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
    Map<String, List<BodyPoint>> body({double footY = 0.92, double x = 0.5}) =>
        {
          'head': [p(x, 0.08)],
          'shoulder': [p(x - 0.1, 0.2), p(x + 0.1, 0.2)],
          'hip': [p(x - 0.08, 0.5), p(x + 0.08, 0.5)],
          'foot': [p(x - 0.06, footY), p(x + 0.06, footY)],
        };

    test('머리부터 발까지 가운데면 찍는다', () {
      expect(frameBody(body()).ready, isTrue);
    });

    test('발이 안 보이면 뒤로', () {
      expect(frameBody(body(footY: 1.2)).speech, contains('발까지'));
    });

    test('몸이 없으면 서 달라고 한다', () {
      expect(frameBody({}).speech, contains('몸이 안 보여요'));
    });

    test('한쪽으로 치우치면 가운데로', () {
      expect(frameBody(body(x: 0.15)).speech, contains('가운데'));
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
}
