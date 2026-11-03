import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// 사용자의 말을 한 번 듣고 글자로 돌려준다.
abstract class ListenService {
  /// 아무 말도 듣지 못하면 null.
  Future<String?> listen();
}

/// 기기의 음성 인식(iOS Speech, Android SpeechRecognizer)으로 한국어를 듣는다.
class DeviceListenService implements ListenService {
  final _stt = SpeechToText();
  bool? _ready;
  Completer<String?>? _pending;
  String _heard = '';

  @override
  Future<String?> listen() async {
    _ready ??=
        await _stt.initialize(onStatus: _onStatus, onError: (_) => _finish());
    if (!_ready!) return null;

    _heard = '';
    final done = _pending = Completer<String?>();
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'ko_KR',
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        _heard = result.recognizedWords;
        if (result.finalResult) _finish();
      },
    );
    return done.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _stt.stop();
      return _heard.isEmpty ? null : _heard;
    });
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
