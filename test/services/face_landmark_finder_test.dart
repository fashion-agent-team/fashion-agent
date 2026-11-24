import 'dart:math';

import 'package:fashion_agent/services/face_landmark_finder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('faceLandmarksFromContours', () {
    final full = {
      for (final n in [
        'leftEye',
        'rightEye',
        'leftEyebrowTop',
        'rightEyebrowTop',
        'upperLipTop',
        'lowerLipBottom',
      ])
        n: const [Point(100, 200), Point(300, 400), Point(500, 800)],
    };

    test('점을 사진 크기에 대한 비율로, 이름은 그대로, yaw·roll을 같이', () {
      final m = faceLandmarksFromContours(full,
          width: 1000, height: 1000, yaw: 3.5, roll: -1.0)!;
      expect(m['leftEye'], [
        [0.1, 0.2],
        [0.3, 0.4],
        [0.5, 0.8],
      ]);
      expect(m['yaw'], 3.5);
      expect(m['roll'], -1.0);
    });

    test('사진 밖으로 나간 점은 잘라 낸다', () {
      final m = faceLandmarksFromContours({
        ...full,
        'face': const [Point(-10, 1200)]
      }, width: 1000, height: 1000)!;
      expect(m['face'], [
        [0.0, 1.0]
      ]);
      expect(m.containsKey('yaw'), isFalse);
    });

    test('꼭 필요한 윤곽(눈·눈썹 위·입술 위아래)이 하나라도 없으면 null', () {
      final missing = Map.of(full)..remove('upperLipTop');
      expect(faceLandmarksFromContours(missing, width: 10, height: 10), isNull);
      expect(
          faceLandmarksFromContours({...full, 'leftEye': const []},
              width: 10, height: 10),
          isNull);
    });

    test('사진 크기가 0이면 null', () {
      expect(faceLandmarksFromContours(full, width: 0, height: 10), isNull);
    });
  });
}
