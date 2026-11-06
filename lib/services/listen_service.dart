import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// 한 번에 듣는 가장 긴 시간.
const defaultListenFor = Duration(seconds: 30);

/// 말이 끊긴 뒤 끝낼 때까지 기다리는 시간. 2026-11-06 진행 님 폰 확인: 3초는 생각할 틈 없이 끊겨서 5초로.
const defaultPauseFor = Duration(seconds: 5);

/// 사용자의 말을 한 번 듣고 글자로 돌려준다.
abstract class ListenService {
  /// 아무 말도 듣지 못하면 null. [cancel]해도 null.
  ///
  /// [listenFor]는 한 번에 듣는 가장 긴 시간, [pauseFor]는 말이 끊긴 뒤 끝낼 때까지 기다리는 시간.
  ///
  /// [stopWhen]이 있으면 중간에 들린 말이 조건에 맞고 [settle] 동안 더 바뀌지 않을 때 바로 끝낸다.
  /// 이름 부르기에서 "코디야"만 듣고 3초 조용하기를 기다리지 않으려고 쓴다.
  Future<String?> listen({
    Duration listenFor = defaultListenFor,
    Duration pauseFor = defaultPauseFor,
    bool Function(String partial)? stopWhen,
    Duration settle = const Duration(milliseconds: 700),
  });

  /// 듣던 것을 멈춘다. 안내를 읽기 전에 불러서, 폰이 자기 목소리를 듣지 않게 한다.
  Future<void> cancel();
}

/// 기기의 음성 인식(iOS Speech, Android SpeechRecognizer)으로 한국어를 듣는다.
class DeviceListenService implements ListenService {
  final _stt = SpeechToText();
  bool? _ready;
  Completer<String?>? _pending;
  String _heard = '';

  /// 음성 인식을 준비한다. 처음 부르면 iOS가 마이크·음성 인식 허용 창을 띄운다. 들을 수 있으면 true.
  Future<bool> prepare() async => _ready ??=
      await _stt.initialize(onStatus: _onStatus, onError: (_) => _finish());

  @override
  Future<String?> listen({
    Duration listenFor = defaultListenFor,
    Duration pauseFor = defaultPauseFor,
    bool Function(String partial)? stopWhen,
    Duration settle = const Duration(milliseconds: 700),
  }) async {
    if (!await prepare()) return null;
    await cancel();

    _heard = '';
    final done = _pending = Completer<String?>();
    Timer? early;
    unawaited(done.future.whenComplete(() => early?.cancel()));
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        _heard = result.recognizedWords;
        if (result.finalResult) {
          _finish();
          return;
        }
        early?.cancel();
        if (stopWhen != null && stopWhen(_heard)) {
          early = Timer(settle, () {
            if (done.isCompleted) return;
            _finish();
            unawaited(_stt.stop());
          });
        }
      },
    );
    return done.future.timeout(listenFor + const Duration(seconds: 5),
        onTimeout: () {
      _stt.stop();
      return _heard.isEmpty ? null : _heard;
    });
  }

  @override
  Future<void> cancel() async {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _heard = '';
    _finish();
    await _stt.cancel();
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _finish();
    }
  }

  void _finish() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.complete(_heard.trim().isEmpty ? null : _heard.trim());
  }
}
