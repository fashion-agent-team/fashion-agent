import 'dart:io' show Platform;
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

  /// 구도 안내용이라 윤곽점 없이 빠르게 얼굴 상자만 찾는다(윤곽점은 찍은 뒤 [MlKitFaceLandmarkFinder]가 찾는다).
  FaceDetector get _faceDetector => _faces ??= FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast));

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
      if (subject == Subject.face) {
        final found = await _faceDetector.processImage(image);
        return frameFace([
          for (final f in found)
            Rect.fromLTRB(
                (f.boundingBox.left / w).clamp(0, 1),
                (f.boundingBox.top / h).clamp(0, 1),
                (f.boundingBox.right / w).clamp(0, 1),
                (f.boundingBox.bottom / h).clamp(0, 1)),
        ]);
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
