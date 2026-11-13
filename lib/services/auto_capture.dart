import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'capture_service.dart';
import 'framing.dart';
import 'subject_finder.dart';

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

/// 서버로 보내는 사진의 긴 변 최대 픽셀. 젯슨까지 올리는 구간이 느려서(약 40KB/s)
/// 1920×1080 원본(1~1.5MB)은 30~60초 걸린다. 1280·품질 80이면 200~300KB.
const int sendMaxSide = 1280;

/// 옷 사진(내려놓은 옷·입은 모습)은 더 줄인다. 옷 상태 서버 모델 입력이 512px이라 960이면 충분하고,
/// 1280보다 보낼 크기가 약 45% 작다(2026-11-13 응답 시간 줄이기). 얼굴 사진은 [sendMaxSide] 그대로.
const int sendMaxSideClothes = 960;

/// 이 사진은 입 안쪽만 잘라 보므로(서버 치아 모델 입력 320px) 조금 더 크게 둔다.
const int sendMaxSideTeeth = 1600;
const int sendQuality = 80;

/// 보낼 사진을 줄인다. 긴 변이 [maxSide] 이하면 원본 그대로, 크면 방향(EXIF)을 픽셀에 반영한 뒤
/// 비율을 지켜 줄이고 품질 [sendQuality] JPEG로 다시 만든다. 셀카 좌우 뒤집기는 그대로 남는다.
/// 입 박스·얼굴 윤곽점은 줄인 사진에서 비율(0~1)로 구하므로 따로 바꿀 것이 없다.
Uint8List shrinkJpeg(({Uint8List jpeg, int maxSide}) input) {
  final img.Image? decoded;
  try {
    decoded = img.decodeJpg(input.jpeg);
  } on Object catch (_) {
    return input.jpeg; // 읽을 수 없으면 원본을 보내고 서버 판단에 맡긴다
  }
  if (decoded == null) return input.jpeg;
  final photo = img.bakeOrientation(decoded);
  final wide = photo.width >= photo.height;
  if ((wide ? photo.width : photo.height) <= input.maxSide) return input.jpeg;
  final small = wide
      ? img.copyResize(photo,
          width: input.maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(photo,
          height: input.maxSide, interpolation: img.Interpolation.average);
  return img.encodeJpg(small, quality: sendQuality);
}

/// 켜 둔 카메라. 사용자가 버튼을 누르지 않아도 프레임이 멈추면 한 장을 찍는다.
abstract class AutoCaptureCamera {
  /// 화면에 미리 보기를 그릴 컨트롤러. 테스트용 구현은 null.
  ValueListenable<CameraController?> get preview;

  /// [front]면 앞쪽(셀카) 카메라. 이미 같은 카메라가 켜져 있으면 그대로 둔다.
  Future<void> open({required bool front});

  /// 프레임이 멈출 때까지 기다렸다가 한 장 찍는다. [timeout]이 지나거나 [cancel]하면 null.
  /// 앞쪽 카메라 사진은 셀카 방향으로 뒤집어서 준다.
  ///
  /// [subject]가 옷·몸이면 폰 안에서 그걸 찾아 화면에 잘 들어왔을 때만 찍고, 그전까지는
  /// "폰을 조금 왼쪽으로"처럼 [onGuide]로 위치를 안내한다. 방금 찍은 것과 같은 장면은 다시 찍지 않는다.
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
    Subject subject = Subject.any,
    void Function(String speech)? onGuide,
  });

  /// 기다리던 [nextStill]을 멈춘다. 말하기를 누르거나 그만둘 때.
  Future<void> cancel();

  /// 구도에 따라 톡톡 소리를 내는지([FramingBeeper]). 내면 카메라를 처음 켤 때 소리 뜻을 알려 준다.
  bool get beeps;

  Future<void> close();
}

class DeviceAutoCaptureCamera implements AutoCaptureCamera {
  DeviceAutoCaptureCamera({
    StillnessDetector? detector,
    SubjectFinder? finder,
    this.mirrorFront = true,
  })  : _detector = detector ?? StillnessDetector(),
        _finder = finder ?? MlKitSubjectFinder();

  final StillnessDetector _detector;
  final SubjectFinder _finder;
  CameraDescription? _camera;

  /// 방금 찍은 장면(밝기 칸). 같은 옷을 계속 찍지 않으려고 둔다. 카메라를 다시 켜면 비운다.
  List<double>? _lastShot;

  /// 앞쪽 카메라 사진을 좌우로 뒤집을지. 아이폰·안드로이드 카메라 플러그인 모두 찍은 사진은
  /// 거울처럼 뒤집혀 있지 않아서(남이 보는 방향) 뒤집는다. 실기기에서 오른손을 들고 확인한다.
  final bool mirrorFront;

  final _preview = ValueNotifier<CameraController?>(null);
  bool? _front;
  Completer<Uint8List?>? _waiting;
  Timer? _timer;
  FramingBeeper? _beeper;

  /// 프레임을 전부 보지 않고 이 간격마다 하나씩 본다.
  static const _every = Duration(milliseconds: 120);

  @override
  ValueListenable<CameraController?> get preview => _preview;

  @override
  bool get beeps => true;

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
          // ML Kit(안드로이드)은 NV21을 받는다. 첫 평면 앞부분이 밝기(Y)라 lumaGrid도 그대로 된다.
          : ImageFormatGroup.nv21,
    );
    await controller.initialize();
    _front = front;
    _camera = camera;
    _lastShot = null;
    _preview.value = controller;
  }

  @override
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
    Subject subject = Subject.any,
    void Function(String speech)? onGuide,
  }) async {
    final controller = _preview.value;
    final camera = _camera;
    if (controller == null || camera == null) return null;
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
    // 구도(옷·몸 위치)
    var finding = false;
    var lastFind = -_findEvery.inMilliseconds;
    Framing? framing;
    var framingAt = Duration.zero;
    String? lastGuide;
    var lastGuideAt = -_guideGap;
    var saidSame = false;

    void guide(Framing f, Duration now) {
      if (f.ready) {
        if (lastGuide != f.speech) onGuide?.call(f.speech);
        lastGuide = f.speech;
        lastGuideAt = now;
        return;
      }
      final gap = now - lastGuideAt;
      if ((f.speech != lastGuide && gap >= _guideGap) || gap >= _guideRepeat) {
        onGuide?.call(f.speech);
        lastGuide = f.speech;
        lastGuideAt = now;
      }
    }

    // 소리 구도 안내: 옷(몸, 얼굴)이 가운데에 알맞게 올수록 톡톡 소리가 빨라진다(2026-11-13 진행 님).
    final beeper = _beeper = FramingBeeper()..start();
    if (subject == Subject.any) beeper.stop();
    _timer = Timer(timeout, () => unawaited(_finish(null)));
    await controller.startImageStream((frame) {
      if (done.isCompleted || shooting) return;
      final now = clock.elapsed;
      if (now.inMilliseconds - lastLook < _every.inMilliseconds) return;
      lastLook = now.inMilliseconds;

      final plane = frame.planes.first;
      final grid = lumaGrid(plane.bytes,
          width: frame.width,
          height: frame.height,
          bytesPerRow: plane.bytesPerRow,
          bytesPerPixel: plane.bytesPerPixel ?? 1);
      final state = _detector.feed(grid, now);

      // 옷·몸 찾기는 무거워서 조금씩만 한다. 결과는 다음 프레임들이 쓴다.
      if (subject != Subject.any &&
          !finding &&
          state != FrameState.dark &&
          now.inMilliseconds - lastFind >= _findEvery.inMilliseconds) {
        finding = true;
        lastFind = now.inMilliseconds;
        unawaited(_finder.look(frame, camera, subject).then((f) {
          finding = false;
          if (f == null || done.isCompleted) return;
          framing = f;
          framingAt = clock.elapsed;
          beeper.closeness = f.closeness;
          guide(f, clock.elapsed);
        }));
      }

      darkSince = state == FrameState.dark ? (darkSince ?? now) : null;
      movingSince = state == FrameState.moving ? (movingSince ?? now) : null;
      if (!saidDark && darkSince != null && now - darkSince! > _darkHint) {
        saidDark = true;
        onHint?.call(CaptureHint.tooDark);
      }
      // 옷·몸을 찾을 때는 위치 안내가 대신한다.
      if (subject == Subject.any &&
          !saidMoving &&
          movingSince != null &&
          now - movingSince! > _movingHint) {
        saidMoving = true;
        onHint?.call(CaptureHint.shaking);
      }
      if (state != FrameState.ready) return;
      // 얼굴은 폰마다 앞쪽 카메라 방향이 달라 못 찾을 수도 있다. 그래도 [_faceGate]가 지나면 예전처럼 멈추면 찍는다
      // (찍은 뒤 윤곽점 확인이 한 번 더 있다). 안내 때문에 아예 못 찍게 되지는 않게.
      final gated = subject != Subject.any &&
          !(subject == Subject.face && now > _faceGate);
      if (gated) {
        final f = framing;
        if (f == null || !f.ready || now - framingAt > _framingFresh) return;
      }
      final last = _lastShot;
      if (subject == Subject.garment &&
          last != null &&
          sceneDifference(grid, last) < _sameScene) {
        if (!saidSame) {
          saidSame = true;
          onGuide?.call('방금 본 옷과 같아요. 다른 옷을 보여 주시거나 "이걸로 할게"라고 말씀해 주세요.');
        }
        return;
      }
      shooting = true;
      _lastShot = grid;
      unawaited(_shoot(controller));
    });
    return done.future;
  }

  /// 얼굴을 이만큼 못 맞추면 구도 안내 없이 찍는다.
  static const _faceGate = Duration(seconds: 8);

  static const _darkHint = Duration(seconds: 2);
  static const _movingHint = Duration(seconds: 8);

  /// 옷·몸 찾기 간격, 찾은 결과를 믿는 시간.
  static const _findEvery = Duration(milliseconds: 400);
  static const _framingFresh = Duration(milliseconds: 900);

  /// 같은 안내는 이 간격 안에 다시 하지 않고, 바뀐 안내도 이만큼은 띄운다.
  static const _guideGap = Duration(milliseconds: 2500);
  static const _guideRepeat = Duration(seconds: 6);

  /// 방금 찍은 장면과 밝기 차이가 이보다 작으면 같은 옷으로 본다. 실기기에서 조정한다.
  static const _sameScene = 6.0;

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
    _beeper?.stop();
    _beeper = null;
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
    _camera = null;
    _lastShot = null;
    await controller?.dispose();
  }
}

/// 구도에 따라 빨라지는 톡톡 소리.
///
/// [closeness]가 0이면(옷을 못 찾음) 조용하고, 찾으면 느리게, 찍기 좋은 자리(1)에 가까울수록 빠르게 낸다.
/// 시스템 "딸깍" 소리와 가벼운 진동을 쓴다. 소리 파일을 틀면(audioplayers) iOS 오디오 세션이 꺼져서
/// 켜 둔 마이크가 아무것도 못 듣는다(2026-11-09 폰 확인). 시스템 소리와 진동은 세션을 건드리지 않는다.
class FramingBeeper {
  FramingBeeper({void Function()? beep}) : _beep = beep ?? _systemBeep;

  final void Function() _beep;
  Timer? _timer;
  final _clock = Stopwatch();
  Duration _last = Duration.zero;

  /// 0~1. 구도를 새로 볼 때마다 바뀐다.
  double closeness = 0;

  /// 가장 느린 간격과 가장 빠른 간격.
  static const slowest = Duration(milliseconds: 1100);
  static const fastest = Duration(milliseconds: 150);

  /// [closeness]일 때 소리 사이 간격. 0이면 null(소리 없음).
  static Duration? gapFor(double closeness) {
    if (closeness <= 0) return null;
    final c = closeness.clamp(0.0, 1.0);
    final ms = slowest.inMilliseconds -
        (slowest.inMilliseconds - fastest.inMilliseconds) * c;
    return Duration(milliseconds: ms.round());
  }

  void start() {
    _clock.start();
    _timer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      final gap = gapFor(closeness);
      if (gap == null) return;
      if (_clock.elapsed - _last >= gap) {
        _last = _clock.elapsed;
        _beep();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _systemBeep() {
    unawaited(
        SystemSound.play(SystemSoundType.click).catchError((Object _) {}));
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  }
}

/// 테스트·시뮬레이터용. 정해 둔 사진을 차례로 "찍는다". null은 시간이 지나도 안 멈춘 경우다.
class FakeAutoCaptureCamera implements AutoCaptureCamera {
  FakeAutoCaptureCamera([List<Uint8List?>? shots, this.beeps = false])
      : shots = shots ?? [];

  @override
  final bool beeps;

  final List<Uint8List?> shots;
  final opened = <bool>[];
  final subjects = <Subject>[];
  bool closed = false;
  Completer<Uint8List?>? _waiting;

  /// 남은 사진이 없으면 [cancel]될 때까지 기다린다.
  @override
  Future<Uint8List?> nextStill({
    Duration timeout = const Duration(seconds: 30),
    void Function(CaptureHint hint)? onHint,
    Subject subject = Subject.any,
    void Function(String speech)? onGuide,
  }) {
    subjects.add(subject);
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
