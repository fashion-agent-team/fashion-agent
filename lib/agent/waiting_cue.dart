import 'dart:async';

import '../services/gateway_auth.dart' show GatewayException;

/// 오래 걸리는 일을 기다리는 동안 소리 없이 멈춘 것처럼 느끼지 않게 한다(2026-11-13 점검).
///
/// [firstAfter]가 지나도 [pending]이 안 끝나면 [tick](짧은 진동)을 하고, 그 뒤 [every]마다 다시 한다.
/// [stillAfter]가 지나면 한 번은 진동 대신 [still]("아직 보고 있어요")을 한다. 끝나면 바로 멈춘다.
Future<T> withWaitingCue<T>(
  Future<T> pending, {
  required void Function() tick,
  void Function()? still,
  Duration firstAfter = const Duration(seconds: 2),
  Duration every = const Duration(milliseconds: 2500),
  Duration stillAfter = const Duration(seconds: 6),
}) async {
  final watch = Stopwatch()..start();
  var saidStill = false;
  var done = false;
  Timer? periodic;
  void beat() {
    if (done) return;
    if (!saidStill && still != null && watch.elapsed >= stillAfter) {
      saidStill = true;
      still();
    } else {
      tick();
    }
  }

  final first = Timer(firstAfter, () {
    beat();
    if (!done) periodic = Timer.periodic(every, (_) => beat());
  });
  try {
    return await pending;
  } finally {
    done = true;
    first.cancel();
    periodic?.cancel();
  }
}

/// 기다림이 길 때 한 번 하는 말.
const stillWorkingSpeech = '아직 보고 있어요. 조금만 기다려 주세요.';

/// 오류가 난 뒤 하던 대화가 남아 있을 때 덧붙이는 말.
const resumeHint = '다시 말씀하시면 하던 데서 이어 갈게요.';

/// [send]가 연결 오류로 실패하면 0.8초 쉬고 한 번 더 보낸다.
///
/// 서버가 답한 오류(GatewayException)나 시간 초과는 다시 보내지 않는다. 서버가 이미 받아서 처리했을 수 있어서
/// (일정이 두 번 들어가는 일) 요청이 서버에 닿지 않은 경우만 다시 보낸다.
Future<T> retryOnceIfUnsent<T>(Future<T> Function() send,
    {Duration wait = const Duration(milliseconds: 800)}) async {
  try {
    return await send();
  } on GatewayException {
    rethrow;
  } on TimeoutException {
    rethrow;
  } on Object {
    await Future<void>.delayed(wait);
    return send();
  }
}
