import 'dart:typed_data';

import 'package:camera/camera.dart';

/// 찍기 전에 사용자에게 줄 안내.
enum CaptureHint {
  ok,
  tooDark,
  shaking,
}

/// 카메라 프레임의 평균 밝기(0~255)와 흔들림 정도로 안내를 정한다.
///
/// 실시간 안내(`startImageStream` + 가속도 센서)에서 0.5초마다 부른다. 기준값은 실기기 테스트로 조정한다.
CaptureHint assessFrame({required double meanLuma, double motion = 0}) {
  if (meanLuma < 50) return CaptureHint.tooDark;
  if (motion > 1.5) return CaptureHint.shaking;
  return CaptureHint.ok;
}

String hintSpeech(CaptureHint hint) => switch (hint) {
      CaptureHint.ok => '좋아요, 그대로 있어 주세요.',
      CaptureHint.tooDark => '너무 어두워요. 불을 켜 주세요.',
      CaptureHint.shaking => '폰이 흔들려요. 잠시 멈춰 주세요.',
    };

/// 사진 한 장을 찍는다.
abstract class CaptureService {
  Future<void> open();
  Future<Uint8List> capture();
  Future<void> close();
}

/// 후면 카메라로 찍는다.
///
/// TODO(촬영 담당): 프레임 밝기·흔들림을 [assessFrame]으로 확인해 조건이 맞으면 자동으로 찍기.
class CameraCaptureService implements CaptureService {
  CameraController? _controller;

  @override
  Future<void> open() async {
    if (_controller?.value.isInitialized ?? false) return;
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller =
        CameraController(back, ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    _controller = controller;
  }

  @override
  Future<Uint8List> capture() async {
    await open();
    final file = await _controller!.takePicture();
    return file.readAsBytes();
  }

  @override
  Future<void> close() async {
    await _controller?.dispose();
    _controller = null;
  }
}

/// 카메라가 없는 시뮬레이터나 테스트용. 빈 사진을 돌려준다.
class FakeCaptureService implements CaptureService {
  int captures = 0;

  @override
  Future<void> open() async {}

  @override
  Future<Uint8List> capture() async {
    captures++;
    return Uint8List(0);
  }

  @override
  Future<void> close() async {}
}
