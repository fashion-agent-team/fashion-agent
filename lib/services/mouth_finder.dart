import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// 계약의 `mouthBox`(docs/contracts/mcp-tools.md `teeth_check`). 사진 크기에 대한 비율(0~1).
///
/// ML Kit 입술 윤곽 `UPPER_LIP_BOTTOM`과 `LOWER_LIP_TOP` 점을 감싸는 박스, 곧 입 안쪽이다.
/// 서버(mcp-face-check)는 이 박스의 긴 변 × 1.36 정사각형으로 잘라 치아 모델에 넣는다.
/// 학습 사진을 자른 규칙과 같으니 다른 점을 섞지 않는다.
@immutable
class MouthBox {
  const MouthBox(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, double> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  @override
  bool operator ==(Object other) =>
      other is MouthBox &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'MouthBox($x, $y, $w, $h)';
}

/// 입술 안쪽 윤곽점(픽셀)으로 [MouthBox]를 만든다. 점이 없거나 사진 크기가 0이면 null.
///
/// 점은 보내는 사진과 같은 방향(셀카처럼 뒤집은 뒤)이어야 한다. 사진 밖으로 나간 점은 잘라 낸다.
/// 입을 다물어 높이가 0에 가까워도 그대로 보낸다. 서버가 "입을 더 벌려 주세요"라고 안내한다.
MouthBox? mouthBoxFromLips(
  List<Point<num>> upperLipBottom,
  List<Point<num>> lowerLipTop, {
  required int width,
  required int height,
}) {
  final points = [...upperLipBottom, ...lowerLipTop];
  if (points.isEmpty || width <= 0 || height <= 0) return null;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in points) {
    minX = min(minX, p.x.toDouble());
    minY = min(minY, p.y.toDouble());
    maxX = max(maxX, p.x.toDouble());
    maxY = max(maxY, p.y.toDouble());
  }
  double rx(double v) => (v / width).clamp(0.0, 1.0);
  double ry(double v) => (v / height).clamp(0.0, 1.0);
  final x = rx(minX), y = ry(minY);
  return MouthBox(x, y, rx(maxX) - x, ry(maxY) - y);
}

/// 찍은 사진에서 입을 찾는다. 못 찾으면 null을 주고, 앱은 `mouthBox` 없이 보낸다(서버가 사진 가운데를 본다).
abstract class MouthFinder {
  Future<MouthBox?> find(Uint8List jpeg);

  Future<void> close();
}

/// 폰 안 ML Kit 얼굴 검출로 입을 찾는다. 사진은 폰 밖으로 나가지 않는다.
///
/// 사진은 셀카 방향으로 이미 뒤집혀 있고 방향(EXIF)도 픽셀에 반영돼 있어서([mirrorJpeg]),
/// 그 사진을 그대로 읽으면 점 좌표를 따로 뒤집지 않아도 된다.
class MlKitMouthFinder implements MouthFinder {
  MlKitMouthFinder()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

  final FaceDetector _detector;

  @override
  Future<MouthBox?> find(Uint8List jpeg) async {
    final size = img.JpegDecoder().startDecode(jpeg);
    if (size == null) return null;
    // ML Kit은 파일 경로로 받을 때 사진 크기·방향을 스스로 읽는다. 다 쓰면 바로 지운다.
    final dir = await Directory.systemTemp.createTemp('mouth');
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
      final upper = face.contours[FaceContourType.upperLipBottom]?.points;
      final lower = face.contours[FaceContourType.lowerLipTop]?.points;
      if (upper == null || lower == null) return null;
      return mouthBoxFromLips(upper, lower,
          width: size.width, height: size.height);
    } on Object catch (e) {
      debugPrint('입 찾기 실패, mouthBox 없이 보냅니다: $e');
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

/// 테스트용. 정해 둔 박스를 준다.
class FakeMouthFinder implements MouthFinder {
  FakeMouthFinder([this.box]);

  final MouthBox? box;
  int calls = 0;

  @override
  Future<MouthBox?> find(Uint8List jpeg) async {
    calls++;
    return box;
  }

  @override
  Future<void> close() async {}
}
