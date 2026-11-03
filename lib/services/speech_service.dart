import 'package:flutter_tts/flutter_tts.dart';

/// 앱의 모든 음성 안내를 담당한다.
class SpeechService {
  SpeechService() {
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
  }

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  /// 읽고 있던 안내를 끊고 [text]를 읽는다.
  Future<void> speak(String text) async {
    await _tts.setLanguage('ko-KR');
    if (_speaking) {
      await _tts.stop();
      // 웹 TTS는 멈춤이 끝났다는 이벤트가 오기 전에 speak를 부르면 무시한다.
      // 그래서 이전 안내가 완전히 멈출 때까지 잠깐 기다린다.
      for (var i = 0; i < 20 && _speaking; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _speaking = false;
    }
    await _tts.speak(text);
  }
}
