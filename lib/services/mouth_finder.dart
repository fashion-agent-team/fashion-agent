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

/// 찍은 사진의 입 박스가 서버(mcp-face-check `TeethCheckService.framing`) 기준을 넘는지 폰에서 먼저 본다.
/// 넘으면 null, 아니면 다시 찍기 안내. 서버까지 사진을 올렸다가 "입을 더 벌려 주세요"를 듣는 왕복(느린 업로드로
/// 10초 넘게)을 줄인다(2026-11-17 정지원). 박스가 없으면(입을 못 찾음) 다시 비추게 한다.
String? mouthRetakeSpeech(MouthBox? box) {
  if (box == null) return '입이 잘 안 보여요. 폰을 입 앞에 들고 "이~" 해 주세요.';
  const edge = 0.005;
  if (box.y <= edge) return '입이 화면 위쪽으로 잘렸어요. 폰을 조금 위로 올려 주세요.';
  if (box.y + box.h >= 1 - edge) return '입이 화면 아래쪽으로 잘렸어요. 폰을 조금 아래로 내려 주세요.';
  if (box.x <= edge || box.x + box.w >= 1 - edge) {
    return '입이 화면 옆으로 잘렸어요. 폰을 입 정면으로 옮겨 주세요.';
  }
  if (box.w < teethMinMouthWidth) return '입이 작게 보여요. 폰을 입에 조금 더 가까이 대 주세요.';
  if (box.h / box.w < teethMinOpenRatio) {
    return '이가 잘 안 보여요. 입을 조금 더 벌리고 "이~" 해 주세요.';
  }
  return null;
}

/// 서버 기준(mcp-face-check `FaceCheckProperties.Teeth`)과 같은 값.
const double teethMinMouthWidth = 0.15;
const double teethMinOpenRatio = 0.10;

/// 입 주변만 잘라 보낼 때 입 박스 긴 변의 몇 배로 자를지. 서버가 보는 가장 넓은 여백(1.5배)보다 넉넉하다.
const double teethCropScale = 2.0;

/// 잘라 보내는 입 사진의 긴 변 최대 픽셀. 서버 치아 모델 입력(384px, 입 긴 변 × 1.36)보다 조금 크게 남는다.
const int teethCropMaxSide = 640;

/// 이 사진에서 입 주변만 잘라 낸다. 얼굴 전체가 서버로 가지 않고(개인정보), 보낼 크기도 크게 준다(2026-11-17 정지원).
///
/// 입 박스 중심에서 긴 변(픽셀) × [teethCropScale] 정사각형을 자르고(사진 밖으로 나가면 사진 안으로 민다)
/// 긴 변 [teethCropMaxSide] 이하로 줄인다. 입 박스는 잘라 낸 사진 기준 비율로 다시 계산한다.
/// 사진을 읽지 못하면 원본과 원래 박스를 그대로 준다.
({Uint8List jpeg, MouthBox box}) cropMouth(
    ({Uint8List jpeg, MouthBox box}) input) {
  final img.Image? decoded;
  try {
    decoded = img.decodeJpg(input.jpeg);
  } on Object catch (_) {
    return input;
  }
  if (decoded == null) return input;
  final photo = img.bakeOrientation(decoded);
  final w = photo.width, h = photo.height;
  final b = input.box;
  final side = (max(b.w * w, b.h * h) * teethCropScale).round();
  final cw = min(side, w), ch = min(side, h);
  final cx = (b.x + b.w / 2) * w, cy = (b.y + b.h / 2) * h;
  final left = (cx - cw / 2).round().clamp(0, w - cw);
  final top = (cy - ch / 2).round().clamp(0, h - ch);
  var crop = img.copyCrop(photo, x: left, y: top, width: cw, height: ch);
  if (max(cw, ch) > teethCropMaxSide) {
    crop = cw >= ch
        ? img.copyResize(crop,
            width: teethCropMaxSide, interpolation: img.Interpolation.average)
        : img.copyResize(crop,
            height: teethCropMaxSide, interpolation: img.Interpolation.average);
  }
  final box = MouthBox(
    (b.x * w - left) / cw,
    (b.y * h - top) / ch,
    b.w * w / cw,
    b.h * h / ch,
  );
  return (jpeg: img.encodeJpg(crop, quality: 85), box: box);
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
