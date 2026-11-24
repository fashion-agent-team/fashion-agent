import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:fashion_agent/services/framing.dart';
import 'package:fashion_agent/services/subject_finder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 카메라 구도 안내에서 ML Kit 결과를 0~1 좌표로 바꾸는 순수 함수들. ML Kit 자체는 폰에서만 돌아서
/// 여기서는 ML Kit가 돌려줄 모양(DetectedObject, Pose, Face)을 직접 만들어 넣는다.
void main() {
  DetectedObject obj(Rect box, List<(String, double)> labels) => DetectedObject(
      boundingBox: box,
      labels: [
        for (final (i, l) in labels.indexed)
          Label(text: l.$1, confidence: l.$2, index: i)
      ],
      trackingId: null);

  group('garmentBoxes', () {
    test('Fashion good(확신 0.3 이상)만 옷으로 보고 0~1로 바꾼다', () {
      final boxes = garmentBoxes([
        obj(const Rect.fromLTRB(100, 200, 300, 600), [('Fashion good', 0.8)]),
        obj(const Rect.fromLTRB(0, 0, 50, 50), [('Home good', 0.9)]),
        obj(const Rect.fromLTRB(0, 0, 400, 800), [('Fashion good', 0.2)]),
      ], 400, 800);
      expect(boxes, [const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75)]);
    });

    test('분류된 옷이 없으면 분류 안 된 물체를 옷 후보로 본다(Home good은 빼고)', () {
      final boxes = garmentBoxes([
        obj(const Rect.fromLTRB(0, 0, 200, 400), []),
        obj(const Rect.fromLTRB(0, 0, 400, 800), [('Home good', 0.9)]),
      ], 400, 800);
      expect(boxes, [const Rect.fromLTRB(0, 0, 0.5, 0.5)]);
    });

    test('Fashion이 하나라도 있으면 분류 안 된 물체는 넣지 않는다', () {
      final boxes = garmentBoxes([
        obj(const Rect.fromLTRB(0, 0, 200, 400), []),
        obj(const Rect.fromLTRB(200, 400, 400, 800), [('fashion GOOD', 0.5)]),
      ], 400, 800);
      expect(boxes, [const Rect.fromLTRB(0.5, 0.5, 1, 1)]);
    });

    test('화면 밖으로 나간 상자는 0~1로 잘라 낸다', () {
      final boxes = garmentBoxes([
        obj(const Rect.fromLTRB(-40, -80, 480, 900), [('Fashion good', 0.9)]),
      ], 400, 800);
      expect(boxes, [const Rect.fromLTRB(0, 0, 1, 1)]);
    });

    test('아무것도 없으면 빈 목록', () {
      expect(garmentBoxes([], 400, 800), isEmpty);
    });
  });

  group('bodyPoints', () {
    PoseLandmark lm(PoseLandmarkType t, double x, double y, double p) =>
        PoseLandmark(type: t, x: x, y: y, z: 0, likelihood: p);

    test('머리·어깨·엉덩이·무릎·발로 묶고 0~1로 바꾼다', () {
      final pose = Pose(landmarks: {
        PoseLandmarkType.nose: lm(PoseLandmarkType.nose, 200, 80, 0.99),
        PoseLandmarkType.leftShoulder:
            lm(PoseLandmarkType.leftShoulder, 100, 200, 0.9),
        PoseLandmarkType.rightShoulder:
            lm(PoseLandmarkType.rightShoulder, 300, 200, 0.8),
        PoseLandmarkType.leftHeel: lm(PoseLandmarkType.leftHeel, 120, 760, 0.4),
        PoseLandmarkType.leftWrist:
            lm(PoseLandmarkType.leftWrist, 10, 10, 0.9), // 쓰지 않는 점
      });

      final p = bodyPoints(pose, 400, 800);

      expect(p.keys, ['head', 'shoulder', 'hip', 'knee', 'foot']);
      expect(p['head'], [(x: 0.5, y: 0.1, likelihood: 0.99)]);
      expect(p['shoulder'], [
        (x: 0.25, y: 0.25, likelihood: 0.9),
        (x: 0.75, y: 0.25, likelihood: 0.8),
      ]);
      expect(p['hip'], isEmpty);
      expect(p['knee'], isEmpty);
      expect(p['foot'], [(x: 0.3, y: 0.95, likelihood: 0.4)]);
    });

    test('점이 하나도 없으면 다섯 묶음 모두 빈 목록', () {
      final p = bodyPoints(Pose(landmarks: {}), 400, 800);
      expect(p.values.every((v) => v.isEmpty), isTrue);
    });
  });

  group('faceLight', () {
    test('전체(안쪽 80%), 뺨 높이 왼쪽 반, 오른쪽 반을 따로 잰다', () {
      final asked = <Rect>[];
      double luma(Rect r) {
        asked.add(r);
        return asked.length * 10.0;
      }

      const box = Rect.fromLTWH(0.2, 0.1, 0.5, 0.6);
      final light = faceLight(box, luma);

      expect(light, (mean: 10.0, left: 20.0, right: 30.0));
      // 안쪽 80%(상자 너비의 10%씩 줄임)
      expect(asked[0].left, closeTo(0.25, 1e-9));
      expect(asked[0].top, closeTo(0.15, 1e-9));
      expect(asked[0].right, closeTo(0.65, 1e-9));
      expect(asked[0].bottom, closeTo(0.65, 1e-9));
      // 뺨: 위 30% ~ 75%, 양옆 12% 안쪽, 가운데에서 나눔
      expect(asked[1].top, closeTo(0.28, 1e-9));
      expect(asked[1].bottom, closeTo(0.55, 1e-9));
      expect(asked[1].left, closeTo(0.26, 1e-9));
      expect(asked[1].right, closeTo(0.45, 1e-9));
      expect(asked[2].left, closeTo(0.45, 1e-9));
      expect(asked[2].right, closeTo(0.64, 1e-9));
    });
  });

  group('boundsOf', () {
    test('점들을 감싸는 상자를 0~1로', () {
      expect(boundsOf(const [Point(100, 200), Point(300, 100)], 400, 400),
          const Rect.fromLTRB(0.25, 0.25, 0.75, 0.5));
    });

    test('화면 밖 점은 잘라 낸다', () {
      expect(boundsOf(const [Point(-50, -50), Point(500, 900)], 400, 800),
          const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('점이 없거나 크기가 0이면 null', () {
      expect(boundsOf(const [], 400, 400), isNull);
      expect(boundsOf(const [Point(1, 1)], 0, 400), isNull);
    });
  });

  group('mouthCropRegion', () {
    test('입 안쪽 긴 변(픽셀) × 1.36 정사각형, 가운데는 같다', () {
      const inner = Rect.fromLTWH(0.4, 0.5, 0.2, 0.05); // 1000×2000: 200×100px
      final r = mouthCropRegion(inner, 1000, 2000);
      expect(r.center.dx, closeTo(inner.center.dx, 1e-9));
      expect(r.center.dy, closeTo(inner.center.dy, 1e-9));
      expect(r.width * 1000, closeTo(272, 1e-6));
      expect(r.height * 2000, closeTo(272, 1e-6));
    });
  });

  group('mouthView', () {
    Face face({
      Map<FaceContourType, List<Point<int>>> contours = const {},
      Map<FaceLandmarkType, Point<int>> landmarks = const {},
    }) =>
        Face(
          boundingBox: const Rect.fromLTWH(0, 0, 400, 400),
          contours: {
            for (final e in contours.entries)
              e.key: FaceContour(type: e.key, points: e.value)
          },
          landmarks: {
            for (final e in landmarks.entries)
              e.key: FaceLandmark(type: e.key, position: e.value)
          },
        );

    test('입술 윤곽이 있으면 안쪽(윗입술 아래·아랫입술 위)과 입술 전체 상자, 치아 자리 밝기', () {
      final asked = <Rect>[];
      final v = mouthView(
        face(contours: {
          FaceContourType.upperLipTop: const [Point(100, 180), Point(300, 180)],
          FaceContourType.upperLipBottom: const [
            Point(120, 200),
            Point(280, 200)
          ],
          FaceContourType.lowerLipTop: const [Point(120, 240), Point(280, 240)],
          FaceContourType.lowerLipBottom: const [
            Point(100, 260),
            Point(300, 260)
          ],
        }),
        400,
        400,
        luma: (r) {
          asked.add(r);
          return 0.42;
        },
      )!;

      expect(v.inner, const Rect.fromLTRB(0.3, 0.5, 0.7, 0.6));
      expect(v.lips, const Rect.fromLTRB(0.25, 0.45, 0.75, 0.65));
      expect(v.luma, 0.42);
      expect(asked.single, mouthCropRegion(v.inner!, 400, 400));
    });

    test('윤곽이 없으면 입 끝 점으로 입술 상자만 어림한다(위로 입 너비의 30%)', () {
      final v = mouthView(
        face(landmarks: {
          FaceLandmarkType.leftMouth: const Point(100, 240),
          FaceLandmarkType.rightMouth: const Point(300, 240),
          FaceLandmarkType.bottomMouth: const Point(200, 280),
        }),
        400,
        400,
      )!;

      expect(v.inner, isNull);
      expect(v.luma, isNull); // luma를 안 넘기면 재지 않는다
      expect(v.lips.left, closeTo(0.25, 1e-9));
      expect(v.lips.right, closeTo(0.75, 1e-9));
      expect(v.lips.top, closeTo(0.6 - 0.5 * 0.3, 1e-9));
      expect(v.lips.bottom, closeTo(0.7, 1e-9));
    });

    test('입 끝 점이 하나뿐이거나 아무것도 없으면 null', () {
      expect(
          mouthView(
              face(landmarks: {
                FaceLandmarkType.bottomMouth: const Point(200, 280)
              }),
              400,
              400),
          isNull);
      expect(mouthView(face(), 400, 400), isNull);
    });

    test('윤곽 목록이 비어 있으면 입 끝 점으로 넘어간다', () {
      final v = mouthView(
        face(contours: {
          FaceContourType.upperLipBottom: const [],
          FaceContourType.lowerLipTop: const [],
        }, landmarks: {
          FaceLandmarkType.leftMouth: const Point(100, 240),
          FaceLandmarkType.rightMouth: const Point(300, 240),
        }),
        400,
        400,
      );
      expect(v, isNotNull);
      expect(v!.inner, isNull);
    });
  });

  test('Subject.any는 ML Kit를 부르지 않고 바로 준비됨', () async {
    final f = MlKitSubjectFinder();
    // 프레임을 읽지 않으므로 아무 값이나 넘겨도 된다(ML Kit 플러그인은 테스트에서 없음).
    expect((await f.look(_NoFrame(), _NoCamera(), Subject.any))?.ready, isTrue);
    await f.close();
  });
}

class _NoFrame implements CameraImage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCamera implements CameraDescription {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
