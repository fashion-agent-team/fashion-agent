import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_speech.dart' show isHomeCommand;
import 'command_listener.dart';
import '../services/auto_capture.dart';
import '../services/capture_service.dart';
import '../services/framing.dart';
import '../services/listen_service.dart';
import '../services/face_landmark_finder.dart';
import '../services/mouth_finder.dart';
import '../services/speech_service.dart';
import '../services/turn_api.dart';

/// 얼굴 사진에서 눈·눈썹·입술 윤곽을 다 못 찾았을 때 폰이 바로 하는 안내.
/// 가까이 대서 눈썹·턱이 화면 밖으로 나가는 일이 가장 흔하다.
const faceRetrySpeech = '얼굴이 다 안 보여요. 폰을 조금 멀리 들어서 이마부터 턱까지 화면에 다 들어오게 해 주세요.';

/// agent가 `camera_*`를 주면 도는 카메라 대화. 카메라를 켜 둔 채로 멈추면 한 장씩 보낸다.
///
/// - 옷(얼굴, 입)이 1초 멈추면 자동으로 찍어 보낸다. 사용자는 찍기 버튼을 누르지 않는다.
/// - 답이 다시 `camera_*`면 읽어 주고 계속 본다. 다른 카메라(`camera_face` 등)면 바꿔 켠다.
/// - 답이 `listen`·`done`이면 카메라를 끄고 그 답을 읽지 않은 채로 돌려준다. 에이전트가 이어서 읽는다.
/// - 카메라가 켜진 동안 [talk]로 말할 수 있다("이걸로 할게", "어디야?"). [stop]이면 null로 끝난다.
/// - [handsFree]면 카메라가 켜진 동안 계속 들어서, 버튼이나 이름 없이 바로 말해도 된다.
///   안내를 읽는 동안은 듣기를 멈춰서 폰이 자기 목소리를 듣지 않게 한다.
class CameraTurnController extends ChangeNotifier {
  CameraTurnController({
    required this.speech,
    required this.listen,
    required this.turns,
    required this.camera,
    LocationProvider? location,
    this.mouths,
    this.faces,
    this.stillTimeout = const Duration(seconds: 30),
    this.maxTimeouts = 3,
    this.handsFree = false,
  }) : location = location ?? LocationProvider();

  final SpeechService speech;
  final ListenService listen;
  final TurnApi turns;
  final AutoCaptureCamera camera;
  final LocationProvider location;

  /// 이 사진에서 입 박스(`mouthBox`)를 찾는다. null이거나 못 찾으면 박스 없이 보낸다.
  final MouthFinder? mouths;

  /// 얼굴 사진에서 ML Kit 윤곽점(`faceLandmarks`)을 찾는다. 화장 좌우 확인(face_makeup_check)은 이게 있어야
  /// 판단하고, 없으면 서버가 "얼굴을 찾지 못했어요"로 답한다. null이거나 못 찾으면 윤곽점 없이 보낸다.
  final FaceLandmarkFinder? faces;

  /// 이만큼 기다려도 멈추지 않으면 다시 안내한다.
  final Duration stillTimeout;

  /// 안내를 이만큼 해도 못 찍으면 카메라를 끈다.
  final int maxTimeouts;

  /// 카메라가 켜진 동안 버튼 없이 계속 듣기.
  final bool handsFree;

  /// 읽고 있는 안내 수. 0보다 크면 듣지 않는다.
  int _speaking = 0;

  /// 화면에 크게 보여 줄 마지막 안내.
  String message = '';

  /// 사진을 보내거나 말을 듣는 중이면 true. 그동안 말하기 버튼을 막는다.
  bool busy = false;

  ImageKind kind = ImageKind.outfit;

  /// 이번에 카메라를 켜고 보낸 사진 수. 화면 진행 막대(세 칸)에 쓴다.
  int shots = 0;

  String? _sessionId;
  Completer<TurnReply?>? _done;
  int _round = 0;
  int _timeouts = 0;

  /// 얼굴 사진에서 윤곽점을 연달아 못 찾은 수. [maxFaceMisses]까지는 보내지 않고 다시 비추게 한다.
  int _faceMisses = 0;

  /// 윤곽점 없이는 서버가 판단하지 못해서(no_landmarks), 이만큼은 폰에서 바로 다시 안내한다.
  static const maxFaceMisses = 2;

  bool _closing = false;

  bool get running => _done != null && !_done!.isCompleted && !_closing;

  /// [kind] 카메라를 켜고, 카메라가 끝나는 답(또는 그만두면 null)을 돌려준다.
  Future<TurnReply?> run(String sessionId, ImageKind kind) async {
    _sessionId = sessionId;
    this.kind = kind;
    shots = 0;
    message = '';
    _timeouts = 0;
    _faceMisses = 0;
    _closing = false;
    final done = _done = Completer<TurnReply?>();
    try {
      await camera.open(front: kind.selfie);
    } on Object catch (e) {
      debugPrint('카메라를 켜지 못함: $e');
      await _say('미안해요, 카메라를 못 켰어요. 설정 앱에서 카메라 권한이 켜져 있는지 봐 주실래요?');
      await _end(null);
      return done.future;
    }
    _watch();
    if (handsFree) unawaited(_listenLoop());
    return done.future;
  }

  /// 카메라가 켜진 동안 계속 듣는다. 들은 말은 사진을 기다리던 것을 멈추고 보낸다.
  Future<void> _listenLoop() async {
    var quickMisses = 0;
    while (running) {
      if (busy || _speaking > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final started = DateTime.now();
      // 명령으로 끝난 말은 바로, 아니면 1.6초 조용하면 끝낸다(2026-11-09 피드백: 텀이 길다. 예전 3초).
      final heard = await CommandListener.once(listen,
          listenFor: const Duration(seconds: 30),
          pause: const Duration(milliseconds: 1600));
      if (!running) break;
      if (heard == null || heard.trim().length < 2) {
        final quick =
            DateTime.now().difference(started) < const Duration(seconds: 1);
        quickMisses = quick ? quickMisses + 1 : 0;
        if (quickMisses >= 3) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        continue;
      }
      quickMisses = 0;
      // 그사이 사진이 찍혀 보내는 중이면 그 답을 먼저 듣게 한다.
      if (busy) continue;
      if (isHomeCommand(heard)) {
        await _goHome();
        break;
      }
      _round++;
      await camera.cancel();
      _setBusy(true);
      try {
        await _handle(() => turns.say(_sessionId, heard));
      } finally {
        _setBusy(false);
      }
    }
  }

  /// 말하기 버튼. 자동 촬영을 잠깐 멈추고 한 번 듣는다.
  Future<void> talk() async {
    if (running && busy && speech.speaking) {
      // 말하는 중에 누르면 끊는다.
      await speech.stop();
      return;
    }
    if (!running || busy) return;
    _round++;
    await camera.cancel();
    _setBusy(true);
    try {
      await _say('말씀해 주세요.');
      await speech.listeningCue();
      final heard = await CommandListener.once(listen);
      if (!running) return;
      if (heard == null) {
        await _say('제가 잘 못 들었어요. 괜찮아요, 옷은 계속 보여 주셔도 돼요.');
        _watch();
        return;
      }
      if (isHomeCommand(heard)) {
        await _goHome();
        return;
      }
      await _handle(() => turns.say(_sessionId, heard));
    } finally {
      _setBusy(false);
    }
  }

  /// "첫 화면": 카메라를 끄고 첫 화면으로 돌아간다(그만하기와 같다).
  Future<void> _goHome() async {
    _round++;
    await camera.cancel();
    await _say('처음으로 돌아갈게요.');
    await _end(null);
  }

  /// 그만하기 버튼.
  Future<void> stop() async {
    if (!running) return;
    _round++;
    await _end(null);
  }

  void _watch() {
    if (!running) return;
    final round = ++_round;
    unawaited(() async {
      final still = await camera.nextStill(
        timeout: stillTimeout,
        onHint: _hint,
        subject: switch (kind) {
          ImageKind.outfit => Subject.garment,
          ImageKind.worn => Subject.body,
          _ => Subject.any,
        },
        onGuide: (speech) => unawaited(_say(speech)),
      );
      if (round != _round || !running) return;
      if (still == null) {
        if (++_timeouts >= maxTimeouts) {
          await _say('잘 안 보여서 카메라는 잠깐 끌게요. 다시 하고 싶으면 말씀해 주세요.');
          await _end(null);
          return;
        }
        await _say(_timeoutHint());
        _watch();
        return;
      }
      _timeouts = 0;
      _setBusy(true);
      try {
        // 젯슨까지 올리는 구간이 느려서 보내기 전에 줄인다. 입 박스·윤곽점도 줄인 사진에서 찾는다.
        final shot = await compute(shrinkJpeg, (
          jpeg: still,
          maxSide: switch (kind) {
            ImageKind.teeth => sendMaxSideTeeth,
            ImageKind.outfit || ImageKind.worn => sendMaxSideClothes,
            ImageKind.face => sendMaxSide,
          },
        ));
        if (round != _round || !running) return;
        final marks = kind == ImageKind.face ? await _findFace(shot) : null;
        if (round != _round || !running) return;
        // 윤곽점이 없으면 서버는 보지도 않고 "얼굴을 찾지 못했어요"로 답한다(몇 초 낭비).
        // 폰에서 바로 다시 비추게 하고, 그래도 계속 못 찾으면 그냥 보내 agent 안내를 따른다.
        if (kind == ImageKind.face &&
            marks == null &&
            faces != null &&
            _faceMisses < maxFaceMisses) {
          _faceMisses++;
          await _say(faceRetrySpeech);
          _watch();
          return;
        }
        _faceMisses = 0;
        shots++;
        // 찍혔다는 걸 바로 알린다. 답을 기다리는 동안 읽는다.
        final saying = _say('찍었어요. 잘 볼게요.');
        final loc = await location.current();
        final box = kind == ImageKind.teeth ? await _findMouth(shot) : null;
        await _handle(
            () => turns.show(_sessionId, kind, shot,
                location: loc, mouthBox: box, faceLandmarks: marks),
            before: saying);
      } finally {
        _setBusy(false);
      }
    }());
  }

  Future<MouthBox?> _findMouth(Uint8List shot) async {
    final finder = mouths;
    if (finder == null) return null;
    try {
      return await finder.find(shot);
    } on Object catch (e) {
      debugPrint('입 찾기 실패: $e');
      return null;
    }
  }

  Future<Map<String, Object>?> _findFace(Uint8List shot) async {
    final finder = faces;
    if (finder == null) return null;
    try {
      return await finder.find(shot);
    } on Object catch (e) {
      debugPrint('얼굴 윤곽 찾기 실패: $e');
      return null;
    }
  }

  Future<void> _handle(Future<TurnReply> Function() send,
      {Future<void>? before}) async {
    TurnReply reply;
    try {
      reply = await send();
    } on Object catch (e) {
      debugPrint('turn 실패: $e');
      await before;
      await _say(turnErrorSpeech(e));
      _watch();
      return;
    }
    await before;
    if (!running) return;
    _sessionId = reply.sessionId;
    final next = reply.next.camera;
    if (next == null) {
      await _end(reply);
      return;
    }
    if (next.selfie != kind.selfie) {
      try {
        await camera.open(front: next.selfie);
      } on Object catch (e) {
        debugPrint('카메라 바꾸기 실패: $e');
      }
    }
    kind = next;
    await _say(reply.speech);
    _watch();
  }

  void _hint(CaptureHint hint) => unawaited(_say(switch (hint) {
        CaptureHint.tooDark => '조금 어두워요. 불을 켜 주실래요?',
        CaptureHint.shaking => switch (kind) {
            ImageKind.worn => '잠깐 멈춰 주세요.',
            ImageKind.outfit => '잠깐 멈춰 주세요.',
            _ => '잠깐 멈춰 주세요.',
          },
        CaptureHint.ok => '좋아요, 그대로 있어 주세요.',
      }));

  String _timeoutHint() => switch (kind) {
        ImageKind.outfit => '옷이 잘 안 보여요. 폰을 조금 떨어뜨려 비춰 주세요.',
        ImageKind.worn => '몸이 잘 안 보여요. 두 걸음 뒤로 가 주세요.',
        ImageKind.face => '얼굴이 잘 안 보여요. 폰을 얼굴 앞에 들어 주세요.',
        ImageKind.teeth => '입이 잘 안 보여요. 이를 보이게 해 주세요.',
      };

  Future<void> _end(TurnReply? reply) async {
    _round++;
    _closing = true;
    if (handsFree) await listen.cancel();
    try {
      await camera.close();
    } on Object catch (e) {
      debugPrint('카메라 끄기 실패: $e');
    }
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(reply);
    notifyListeners();
  }

  void _setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  Future<void> _say(String text) async {
    message = text;
    notifyListeners();
    _speaking++;
    try {
      if (handsFree) await listen.cancel();
      await speech.speak(text);
    } finally {
      _speaking--;
    }
  }
}
