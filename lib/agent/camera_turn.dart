import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auto_capture.dart';
import '../services/capture_service.dart';
import '../services/listen_service.dart';
import '../services/speech_service.dart';
import '../services/turn_api.dart';

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
    this.stillTimeout = const Duration(seconds: 30),
    this.maxTimeouts = 3,
    this.handsFree = false,
  }) : location = location ?? LocationProvider();

  final SpeechService speech;
  final ListenService listen;
  final TurnApi turns;
  final AutoCaptureCamera camera;
  final LocationProvider location;

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
  String? _sessionId;
  Completer<TurnReply?>? _done;
  int _round = 0;
  int _timeouts = 0;

  bool _closing = false;

  bool get running => _done != null && !_done!.isCompleted && !_closing;

  /// [kind] 카메라를 켜고, 카메라가 끝나는 답(또는 그만두면 null)을 돌려준다.
  Future<TurnReply?> run(String sessionId, ImageKind kind) async {
    _sessionId = sessionId;
    this.kind = kind;
    _timeouts = 0;
    _closing = false;
    final done = _done = Completer<TurnReply?>();
    try {
      await camera.open(front: kind.selfie);
    } on Object catch (e) {
      debugPrint('카메라를 켜지 못함: $e');
      await _say('카메라를 켜지 못했어요. 설정 앱에서 카메라 권한을 확인해 주세요.');
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
      final heard = await listen.listen(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 2),
      );
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
    if (!running || busy) return;
    _round++;
    await camera.cancel();
    _setBusy(true);
    try {
      await _say('말씀해 주세요.');
      final heard = await listen.listen();
      if (!running) return;
      if (heard == null) {
        await _say('잘 듣지 못했어요. 옷을 계속 보여 주셔도 돼요.');
        _watch();
        return;
      }
      await _handle(() => turns.say(_sessionId, heard));
    } finally {
      _setBusy(false);
    }
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
      final shot = await camera.nextStill(timeout: stillTimeout, onHint: _hint);
      if (round != _round || !running) return;
      if (shot == null) {
        if (++_timeouts >= maxTimeouts) {
          await _say('잘 보이지 않아서 카메라를 끌게요.');
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
        // 찍혔다는 걸 바로 알린다. 답을 기다리는 동안 읽는다.
        final saying = _say('찍었어요. 확인하고 있어요.');
        final loc = await location.current();
        await _handle(() => turns.show(_sessionId, kind, shot, location: loc),
            before: saying);
      } finally {
        _setBusy(false);
      }
    }());
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
        CaptureHint.tooDark => '너무 어두워요. 불을 켜 주세요.',
        CaptureHint.shaking =>
          kind.selfie ? '폰을 얼굴 앞에 두고 잠시 멈춰 주세요.' : '옷을 폰 앞에 두고 잠시 멈춰 주세요.',
        CaptureHint.ok => '좋아요, 그대로 있어 주세요.',
      }));

  String _timeoutHint() => switch (kind) {
        ImageKind.outfit => '옷이 잘 보이지 않아요. 폰을 옷에서 한 걸음 떨어뜨려 비추고 잠시 멈춰 주세요.',
        ImageKind.face => '얼굴이 잘 보이지 않아요. 폰을 얼굴 앞 한 뼘 거리에 두고 잠시 멈춰 주세요.',
        ImageKind.teeth => '입이 잘 보이지 않아요. 폰을 입 앞에 두고 이를 보이게 한 채 잠시 멈춰 주세요.',
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
