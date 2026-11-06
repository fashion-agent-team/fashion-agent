import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'capture_service.dart';

/// 카메라 프레임을 [cells]×[cells] 칸으로 나눠 칸마다 평균 밝기(0~255)를 구한다.
///
/// [bytesPerPixel]이 1이면 Y(밝기) 평면(안드로이드 YUV420), 4면 BGRA(아이폰)로 읽는다.
/// 칸마다 네 점만 읽어서 빠르다. 움직임과 어두움만 보면 되니까 이걸로 충분하다.
List<double> lumaGrid(
  Uint8List bytes, {
  required int width,
  required int height,
  required int bytesPerRow,
  int bytesPerPixel = 1,
  int cells = 16,
}) {
  final grid = List<double>.filled(cells * cells, 0);
  double at(int x, int y) {
    final i = y * bytesPerRow + x * bytesPerPixel;
    if (i + bytesPerPixel > bytes.length) return 0;
    if (bytesPerPixel == 1) return bytes[i].toDouble();
    // BGRA → 밝기
    return 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
  }

  for (var cy = 0; cy < cells; cy++) {
    for (var cx = 0; cx < cells; cx++) {
      var sum = 0.0;
      for (final (fx, fy) in const [(1, 1), (3, 1), (1, 3), (3, 3)]) {
        final x = ((cx * 4 + fx) * width) ~/ (cells * 4);
        final y = ((cy * 4 + fy) * height) ~/ (cells * 4);
        sum += at(x, y);
      }
      grid[cy * cells + cx] = sum / 4;
    }
  }
  return grid;
}

/// 프레임이 지금 어떤지.
enum FrameState {
  /// 너무 어둡다.
  dark,

  /// 폰이나 옷이 움직이고 있다.
  moving,

  /// 멈췄지만 아직 [StillnessDetector.hold]만큼은 아니다.
  settling,

  /// 충분히 멈췄다. 지금 찍으면 된다.
  ready,
}

/// 프레임이 [hold] 동안 거의 바뀌지 않으면 [FrameState.ready]를 준다. 사진 찍기 버튼 대신이다.
///
/// 기준값은 실기기에서 조정한다. 폰과 옷을 손에 들고 있으면 조금씩 흔들려서 [motionLimit]을 너무 낮추면 안 찍힌다.
class StillnessDetector {
  StillnessDetector({
    this.hold = const Duration(seconds: 1),
    this.motionLimit = 6,
    this.darkLimit = 50,
  });

  final Duration hold;

  /// 이전 프레임과 칸별 밝기 차이의 평균이 이보다 작으면 멈춘 것으로 본다.
  final double motionLimit;

  /// 평균 밝기가 이보다 낮으면 어둡다.
  final double darkLimit;

  List<double>? _last;
  Duration? _stillSince;

  void reset() {
    _last = null;
    _stillSince = null;
  }

  FrameState feed(List<double> grid, Duration at) {
    final last = _last;
    _last = grid;
    final mean = grid.reduce((a, b) => a + b) / grid.length;
    if (mean < darkLimit) {
      _stillSince = null;
      return FrameState.dark;
    }
    if (last == null || last.length != grid.length) {
      _stillSince = null;
      return FrameState.moving;
    }
    var diff = 0.0;
    for (var i = 0; i < grid.length; i++) {
      diff += (grid[i] - last[i]).abs();
    }
    if (diff / grid.length > motionLimit) {
      _stillSince = null;
      return FrameState.moving;
    }
    final since = _stillSince ??= at;
    return at - since >= hold ? FrameState.ready : FrameState.settling;
  }
}

/// 사진을 셀카 화면처럼 좌우로 뒤집는다(사진 왼쪽 = 사용자 왼쪽). 방향(EXIF)도 픽셀에 반영한다.
Uint8List mirrorJpeg(Uint8List jpeg) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) return jpeg;
  final upright = img.bakeOrientation(decoded);
  return img.encodeJpg(img.flipHorizontal(upright), quality: 85);
}

/// 켜 둔 카메라. 사용자가 버튼을 누르지 않아도 프레임이 멈추면 한 장을 찍는다.
abstract class AutoCaptureCamera {
  /// 화면에 미리 보기를 그릴 컨트롤러. 테스트용 구현은 null.
  ValueListenable<CameraController?> get preview;

  /// [front]면 앞쪽(셀카) 카메라. 이미 같은 카메라가 켜져 있으면 그대로 둔다.
  Future<void> open({required bool front});

  /// 프레임이 멈출 때까지 기다렸다가 한 장 찍는다. [timeout]이 지나거나 [cancel]하면 null.
  /// 앞쪽 카메라 사진은 셀카 방향으로 뒤집어서 준다.
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
  });

  /// 기다리던 [nextStill]을 멈춘다. 말하기를 누르거나 그만둘 때.
  Future<void> cancel();

  Future<void> close();
}

class DeviceAutoCaptureCamera implements AutoCaptureCamera {
  DeviceAutoCaptureCamera({
    StillnessDetector? detector,
    this.mirrorFront = true,
  }) : _detector = detector ?? StillnessDetector();

  final StillnessDetector _detector;

  /// 앞쪽 카메라 사진을 좌우로 뒤집을지. 아이폰·안드로이드 카메라 플러그인 모두 찍은 사진은
  /// 거울처럼 뒤집혀 있지 않아서(남이 보는 방향) 뒤집는다. 실기기에서 오른손을 들고 확인한다.
  final bool mirrorFront;

  final _preview = ValueNotifier<CameraController?>(null);
  bool? _front;
  Completer<Uint8List?>? _waiting;
  Timer? _timer;

  /// 프레임을 전부 보지 않고 이 간격마다 하나씩 본다.
  static const _every = Duration(milliseconds: 120);

  @override
  ValueListenable<CameraController?> get preview => _preview;

  @override
  Future<void> open({required bool front}) async {
    final current = _preview.value;
    if (current != null && current.value.isInitialized && _front == front) {
      return;
    }
    await close();
    final cameras = await availableCameras();
    final want = front ? CameraLensDirection.front : CameraLensDirection.back;
    final camera = cameras.firstWhere((c) => c.lensDirection == want,
        orElse: () => cameras.first);
    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _front = front;
    _preview.value = controller;
  }

  @override
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
  }) async {
    final controller = _preview.value;
    if (controller == null) return null;
    await cancel();

    final done = _waiting = Completer<Uint8List?>();
    _detector.reset();
    final clock = Stopwatch()..start();
    var lastLook = -_every.inMilliseconds;
    Duration? darkSince;
    Duration? movingSince;
    var saidDark = false;
    var saidMoving = false;
    var shooting = false;

    _timer = Timer(timeout, () => unawaited(_finish(null)));
    await controller.startImageStream((frame) {
      if (done.isCompleted || shooting) return;
      final now = clock.elapsed;
      if (now.inMilliseconds - lastLook < _every.inMilliseconds) return;
      lastLook = now.inMilliseconds;

      final plane = frame.planes.first;
      final state = _detector.feed(
        lumaGrid(plane.bytes,
            width: frame.width,
            height: frame.height,
            bytesPerRow: plane.bytesPerRow,
            bytesPerPixel: plane.bytesPerPixel ?? 1),
        now,
      );

      darkSince = state == FrameState.dark ? (darkSince ?? now) : null;
      movingSince = state == FrameState.moving ? (movingSince ?? now) : null;
      if (!saidDark && darkSince != null && now - darkSince! > _darkHint) {
        saidDark = true;
        onHint?.call(CaptureHint.tooDark);
      }
      if (!saidMoving &&
          movingSince != null &&
          now - movingSince! > _movingHint) {
        saidMoving = true;
        onHint?.call(CaptureHint.shaking);
      }
      if (state == FrameState.ready) {
        shooting = true;
        unawaited(_shoot(controller));
      }
    });
    return done.future;
  }

  static const _darkHint = Duration(seconds: 2);
  static const _movingHint = Duration(seconds: 8);

  Future<void> _shoot(CameraController controller) async {
    try {
      await _stopStream(controller);
      final file = await controller.takePicture();
      var bytes = await file.readAsBytes();
      if (_front == true && mirrorFront) {
        bytes = await compute(mirrorJpeg, bytes);
      }
      await _finish(bytes);
    } on Object catch (e) {
      debugPrint('자동 촬영 실패: $e');
      await _finish(null);
    }
  }

  Future<void> _finish(Uint8List? bytes) async {
    _timer?.cancel();
    _timer = null;
    final controller = _preview.value;
    if (controller != null) await _stopStream(controller);
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete(bytes);
  }

  Future<void> _stopStream(CameraController controller) async {
    if (!controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
    } on Object catch (e) {
      debugPrint('프레임 멈추기 실패: $e');
    }
  }

  @override
  Future<void> cancel() => _finish(null);

  @override
  Future<void> close() async {
    await cancel();
    final controller = _preview.value;
    _preview.value = null;
    _front = null;
    await controller?.dispose();
  }
}

/// 테스트·시뮬레이터용. 정해 둔 사진을 차례로 "찍는다". null은 시간이 지나도 안 멈춘 경우다.
class FakeAutoCaptureCamera implements AutoCaptureCamera {
  FakeAutoCaptureCamera([List<Uint8List?>? shots]) : shots = shots ?? [];

  final List<Uint8List?> shots;
  final opened = <bool>[];
  bool closed = false;
  Completer<Uint8List?>? _waiting;

  /// 남은 사진이 없으면 [cancel]될 때까지 기다린다.
  @override
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
  }) {
    if (shots.isNotEmpty) return Future.value(shots.removeAt(0));
    return (_waiting = Completer<Uint8List?>()).future;
  }

  bool get waiting => _waiting != null && !_waiting!.isCompleted;

  @override
  ValueListenable<CameraController?> get preview => ValueNotifier(null);

  @override
  Future<void> open({required bool front}) async => opened.add(front);

  @override
  Future<void> cancel() async {
    final w = _waiting;
    if (w != null && !w.isCompleted) w.complete(null);
  }

  @override
  Future<void> close() async {
    closed = true;
    await cancel();
  }
}
