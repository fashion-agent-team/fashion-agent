import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// 사용자의 말을 한 번 듣고 글자로 돌려준다.
abstract class ListenService {
  /// 아무 말도 듣지 못하면 null. [cancel]해도 null.
  ///
  /// [listenFor]는 한 번에 듣는 가장 긴 시간, [pauseFor]는 말이 끊긴 뒤 끝낼 때까지 기다리는 시간.
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 15),
    Duration pauseFor = const Duration(seconds: 3),
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
    Duration listenFor = const Duration(seconds: 15),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!await prepare()) return null;
    await cancel();

    _heard = '';
    final done = _pending = Completer<String?>();
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        listenFor: listenFor,
        pauseFor: pauseFor,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        _heard = result.recognizedWords;
        if (result.finalResult) _finish();
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
