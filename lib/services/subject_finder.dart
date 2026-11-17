import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:math' show Point;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'framing.dart';

/// 카메라 프레임 한 장에서 옷·몸을 찾아 구도를 판단한다. 폰 안에서만 돌고 사진을 밖으로 보내지 않는다.
abstract class SubjectFinder {
  /// [subject]를 찾아 안내를 돌려준다. 볼 수 없는 프레임이면 null.
  Future<Framing?> look(
      CameraImage frame, CameraDescription camera, Subject subject);

  Future<void> close();
}

/// ML Kit(폰 안 모델): 옷은 물체 찾기(Fashion good), 입은 옷은 몸 자세 찾기.
class MlKitSubjectFinder implements SubjectFinder {
  ObjectDetector? _objects;
  PoseDetector? _poses;

  ObjectDetector get _objectDetector => _objects ??= ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );

  FaceDetector? _faces;

  /// 구도 안내용이라 빠른 모드로 찾는다. 입 위치를 보려고 윤곽(가장 큰 얼굴 하나)도 켠다.
  /// 정밀한 윤곽점은 찍은 뒤 [MlKitFaceLandmarkFinder]·[MlKitMouthFinder]가 다시 찾는다.
  FaceDetector get _faceDetector => _faces ??= FaceDetector(
      options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast, enableContours: true));

  PoseDetector get _poseDetector => _poses ??= PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream));

  @override
  Future<Framing?> look(
      CameraImage frame, CameraDescription camera, Subject subject) async {
    if (subject == Subject.any) return const Framing.ready();
    final input = _input(frame, camera);
    if (input == null) return null;
    final (image, w, h) = input;
    try {
      if (subject == Subject.face || subject == Subject.mouth) {
        final found = await _faceDetector.processImage(image);
        Rect norm(Rect r) => Rect.fromLTRB(
            (r.left / w).clamp(0, 1),
            (r.top / h).clamp(0, 1),
            (r.right / w).clamp(0, 1),
            (r.bottom / h).clamp(0, 1));
        final biggest = found.isEmpty
            ? null
            : found.reduce((a, b) =>
                a.boundingBox.width * a.boundingBox.height >=
                        b.boundingBox.width * b.boundingBox.height
                    ? a
                    : b);
        double luma(Rect region) => _luma(frame, camera, region);
        if (subject == Subject.mouth) {
          return frameMouth(
              biggest == null ? null : mouthView(biggest, w, h, luma: luma));
        }
        final faces = [for (final f in found) norm(f.boundingBox)];
        if (biggest == null) return frameFace(faces);
        final box = norm(biggest.boundingBox);
        return frameFace(faces,
            yaw: biggest.headEulerAngleY,
            roll: biggest.headEulerAngleZ,
            light: faceLight(box, luma));
      }
      if (subject == Subject.garment) {
        final found = await _objectDetector.processImage(image);
        return frameGarment(garmentBoxes(found, w, h));
      }
      final poses = await _poseDetector.processImage(image);
      if (poses.isEmpty) return frameBody(const {});
      return frameBody(bodyPoints(poses.first, w, h));
    } on Object catch (e) {
      debugPrint('옷·몸 찾기 실패: $e');
      return null;
    }
  }

  /// 똑바로 세운 화면 기준 [region]의 밝기. 서버로 보내지 않고 폰 안에서 숫자만 쓴다.
  double _luma(CameraImage frame, CameraDescription camera, Rect region) {
    final plane = frame.planes.first;
    return uprightRegionLuma(plane.bytes,
        width: frame.width,
        height: frame.height,
        bytesPerRow: plane.bytesPerRow,
        bytesPerPixel: Platform.isIOS ? 4 : 1,
        rotation: camera.sensorOrientation,
        region: region);
  }

  /// 프레임을 똑바로 선 그림으로. 돌려준 크기는 화면(세로) 기준이다.
  (InputImage, double, double)? _input(
      CameraImage frame, CameraDescription camera) {
    if (frame.planes.isEmpty) return null;
    if (Platform.isIOS) {
      final plane = frame.planes.first;
      final up = uprightBgra(plane.bytes,
          width: frame.width,
          height: frame.height,
          bytesPerRow: plane.bytesPerRow,
          rotation: camera.sensorOrientation);
      return (
        InputImage.fromBytes(
          bytes: up.bytes,
          metadata: InputImageMetadata(
            size: Size(up.width.toDouble(), up.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.bgra8888,
            bytesPerRow: up.width * 4,
          ),
        ),
        up.width.toDouble(),
        up.height.toDouble(),
      );
    }
    // 안드로이드: NV21 그대로 넣고 돌릴 각도를 알려 준다. 결과 좌표는 돌린 뒤 기준이다.
    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;
    final plane = frame.planes.first;
    final turned = camera.sensorOrientation % 180 != 0;
    return (
      InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
      (turned ? frame.height : frame.width).toDouble(),
      (turned ? frame.width : frame.height).toDouble(),
    );
  }

  @override
  Future<void> close() async {
    await _objects?.close();
    await _poses?.close();
    await _faces?.close();
    _faces = null;
    _objects = null;
    _poses = null;
  }
}

/// 옷으로 볼 상자(0~1). "Fashion good"으로 분류된 것. 분류된 게 하나도 없으면 분류 안 된 물체도 옷 후보로 본다.
/// 책상·침대처럼 "Home good"으로 분류된 것은 뺀다. 기준은 실기기에서 조정한다.
List<Rect> garmentBoxes(List<DetectedObject> found, double w, double h) {
  Rect norm(Rect r) => Rect.fromLTRB(
      (r.left / w).clamp(0, 1),
      (r.top / h).clamp(0, 1),
      (r.right / w).clamp(0, 1),
      (r.bottom / h).clamp(0, 1));
  final fashion = found
      .where((o) => o.labels.any((l) =>
          l.text.toLowerCase().contains('fashion') && l.confidence >= 0.3))
      .map((o) => norm(o.boundingBox))
      .toList();
  if (fashion.isNotEmpty) return fashion;
  return found
      .where((o) => o.labels.isEmpty)
      .map((o) => norm(o.boundingBox))
      .toList();
}

/// 몸 자세에서 머리·어깨·엉덩이·무릎·발 점(0~1).
Map<String, List<BodyPoint>> bodyPoints(Pose pose, double w, double h) {
  List<BodyPoint> pick(List<PoseLandmarkType> types) => [
        for (final t in types)
          if (pose.landmarks[t] case final l?)
            (x: l.x / w, y: l.y / h, likelihood: l.likelihood),
      ];
  return {
    'head': pick([
      PoseLandmarkType.nose,
      PoseLandmarkType.leftEar,
      PoseLandmarkType.rightEar
    ]),
    'shoulder':
        pick([PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder]),
    'hip': pick([PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]),
    'knee': pick([PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee]),
    'foot': pick([
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.leftHeel,
      PoseLandmarkType.rightHeel,
    ]),
  };
}

/// 얼굴 상자(0~1)에서 밝기를 잰다. 뺨 높이(상자 가운데 띠)의 왼쪽·오른쪽 반을 따로 잰다.
FaceLight faceLight(Rect box, double Function(Rect region) luma) {
  final top = box.top + box.height * 0.3, bottom = box.top + box.height * 0.75;
  final inset = box.width * 0.12;
  return (
    mean: luma(box.deflate(box.width * 0.1)),
    left: luma(Rect.fromLTRB(box.left + inset, top, box.center.dx, bottom)),
    right: luma(Rect.fromLTRB(box.center.dx, top, box.right - inset, bottom)),
  );
}

/// 얼굴 윤곽에서 입(0~1)을 꺼낸다. 입술 윤곽이 없으면 null.
MouthView? mouthView(Face face, double w, double h,
    {double Function(Rect region)? luma}) {
  List<Point<int>>? pts(FaceContourType t) => face.contours[t]?.points;
  final upperBottom = pts(FaceContourType.upperLipBottom),
      lowerTop = pts(FaceContourType.lowerLipTop),
      upperTop = pts(FaceContourType.upperLipTop),
      lowerBottom = pts(FaceContourType.lowerLipBottom);
  if (upperBottom == null || lowerTop == null) return null;
  final inner = boundsOf([...upperBottom, ...lowerTop], w, h);
  final lips = boundsOf(
      [...upperBottom, ...lowerTop, ...?upperTop, ...?lowerBottom], w, h);
  if (inner == null || lips == null) return null;
  return (
    inner: inner,
    lips: lips,
    luma: luma?.call(mouthCropRegion(inner, w, h))
  );
}

/// 점들(픽셀)을 감싸는 상자를 0~1로. 화면 밖 점은 잘라 낸다.
Rect? boundsOf(List<Point<num>> points, double w, double h) {
  if (points.isEmpty || w <= 0 || h <= 0) return null;
  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final p in points) {
    l = math.min(l, p.x.toDouble());
    t = math.min(t, p.y.toDouble());
    r = math.max(r, p.x.toDouble());
    b = math.max(b, p.y.toDouble());
  }
  return Rect.fromLTRB((l / w).clamp(0.0, 1.0), (t / h).clamp(0.0, 1.0),
      (r / w).clamp(0.0, 1.0), (b / h).clamp(0.0, 1.0));
}

/// 서버가 치아 모델에 넣으려고 잘라 보는 자리: 입 안쪽 상자의 긴 변(픽셀) × 1.36 정사각형(0~1).
Rect mouthCropRegion(Rect inner, double w, double h) {
  final side = math.max(inner.width * w, inner.height * h) * 1.36;
  return Rect.fromCenter(
      center: inner.center, width: side / w, height: side / h);
}
