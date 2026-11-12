import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// 계약의 `faceLandmarks`(docs/contracts/mcp-tools.md `face_makeup_check`의 `landmarks`).
///
/// ML Kit 얼굴 윤곽(contour) 이름을 camelCase로(`FaceContourType.leftEyebrowTop` → `leftEyebrowTop`),
/// 점은 사진 너비·높이를 1로 본 비율 `[x, y]`. 고개 돌림·기울임은 `yaw`(headEulerAngleY), `roll`(headEulerAngleZ).
/// 화장 좌우 확인(mcp-face-check)은 이 점으로 눈썹·입술 자리를 잡고, 모양·색은 사진 픽셀에서 잰다.
/// 윤곽점이 없으면 서버가 매번 "얼굴을 찾지 못했어요"(no_landmarks)로 답한다.
Map<String, Object>? faceLandmarksFromContours(
  Map<String, List<Point<num>>> contours, {
  required int width,
  required int height,
  double? yaw,
  double? roll,
}) {
  if (width <= 0 || height <= 0) return null;
  double rx(num v) => (v / width).clamp(0.0, 1.0);
  double ry(num v) => (v / height).clamp(0.0, 1.0);
  final out = <String, Object>{};
  contours.forEach((name, points) {
    if (points.isEmpty) return;
    out[name] = [
      for (final p in points) [rx(p.x), ry(p.y)]
    ];
  });
  // 서버가 꼭 쓰는 윤곽이 하나라도 없으면 보내지 않는다(서버도 다시 찍기로 답함)
  const needed = [
    'leftEye',
    'rightEye',
    'leftEyebrowTop',
    'rightEyebrowTop',
    'upperLipTop',
    'lowerLipBottom',
  ];
  if (!needed.every(out.containsKey)) return null;
  if (yaw != null) out['yaw'] = yaw;
  if (roll != null) out['roll'] = roll;
  return out;
}

/// 찍은 얼굴 사진에서 윤곽점을 찾는다. 못 찾으면 null을 주고, 앱은 윤곽점 없이 보낸다.
abstract class FaceLandmarkFinder {
  Future<Map<String, Object>?> find(Uint8List jpeg);

  Future<void> close();
}

/// 폰 안 ML Kit 얼굴 윤곽으로 찾는다. 사진은 폰 밖으로 나가지 않는다.
///
/// 사진은 셀카 방향으로 이미 뒤집혀 있고 방향(EXIF)도 픽셀에 반영돼 있어서([mirrorJpeg]),
/// 그 사진을 그대로 읽으면 점 좌표를 따로 뒤집지 않아도 된다(입 박스와 같은 방식).
class MlKitFaceLandmarkFinder implements FaceLandmarkFinder {
  MlKitFaceLandmarkFinder()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  final FaceDetector _detector;

  @override
  Future<Map<String, Object>?> find(Uint8List jpeg) async {
    final size = img.JpegDecoder().startDecode(jpeg);
    if (size == null) return null;
    // ML Kit은 파일 경로로 받을 때 사진 크기·방향을 스스로 읽는다. 다 쓰면 바로 지운다.
    final dir = await Directory.systemTemp.createTemp('face');
    final file = File('${dir.path}/still.jpg');
    try {
      await file.writeAsBytes(jpeg, flush: true);
      final faces =
          await _detector.processImage(InputImage.fromFilePath(file.path));
      if (faces.isEmpty) return null;
      // 여러 명이면 가장 큰 얼굴(폰에 가장 가까운 사람)
      final face = faces.reduce((a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b);
      return faceLandmarksFromContours(
        {
          for (final e in face.contours.entries)
            if (e.value != null) e.key.name: e.value!.points,
        },
        width: size.width,
        height: size.height,
        yaw: face.headEulerAngleY,
        roll: face.headEulerAngleZ,
      );
    } on Object catch (e) {
      debugPrint('얼굴 윤곽 찾기 실패, 윤곽점 없이 보냅니다: $e');
      return null;
    } finally {
      try {
        await dir.delete(recursive: true);
      } on Object catch (_) {}
    }
  }

  @override
  Future<void> close() => _detector.close();
}

/// 테스트용. 정해 둔 윤곽점을 준다.
class FakeFaceLandmarkFinder implements FaceLandmarkFinder {
  FakeFaceLandmarkFinder([this.landmarks]);

  final Map<String, Object>? landmarks;
  int calls = 0;

  @override
  Future<Map<String, Object>?> find(Uint8List jpeg) async {
    calls++;
    return landmarks;
  }

  @override
  Future<void> close() async {}
}
