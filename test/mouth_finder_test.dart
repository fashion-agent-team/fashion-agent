import 'dart:math';

import 'package:fashion_agent/services/mouth_finder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('입 박스', () {
    test('입술 안쪽 점을 감싸는 박스를 사진 크기 비율로 준다', () {
      final box = mouthBoxFromLips(
        const [Point(300, 550), Point(500, 540), Point(700, 552)],
        const [Point(300, 552), Point(500, 640), Point(700, 550)],
        width: 1000,
        height: 1000,
      );
      expect(box!.x, closeTo(0.30, 1e-9));
      expect(box.y, closeTo(0.54, 1e-9));
      expect(box.w, closeTo(0.40, 1e-9));
      expect(box.h, closeTo(0.10, 1e-9));
    });

    test('가로세로가 다른 사진은 각 변으로 나눈다', () {
      final box = mouthBoxFromLips(
        const [Point(100, 300)],
        const [Point(300, 400)],
        width: 400,
        height: 800,
      );
      expect(box, const MouthBox(0.25, 0.375, 0.5, 0.125));
    });

    test('사진 밖으로 나간 점은 잘라 낸다', () {
      final box = mouthBoxFromLips(
        const [Point(-50, 900)],
        const [Point(200, 1100)],
        width: 1000,
        height: 1000,
      );
      expect(box!.x, 0);
      expect(box.y, closeTo(0.9, 1e-9));
      expect(box.w, closeTo(0.2, 1e-9));
      expect(box.h, closeTo(0.1, 1e-9));
    });

    test('점이 없거나 사진 크기가 0이면 null', () {
      expect(
          mouthBoxFromLips(const [], const [], width: 10, height: 10), isNull);
      expect(
          mouthBoxFromLips(const [Point(1, 1)], const [], width: 0, height: 10),
          isNull);
    });

    test('계약 모양으로 바꾼다', () {
      expect(const MouthBox(0.3, 0.55, 0.4, 0.2).toJson(),
          {'x': 0.3, 'y': 0.55, 'w': 0.4, 'h': 0.2});
    });
  });
}
