import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 앱의 모든 음성 안내를 담당한다.
class SpeechService {
  SpeechService() {
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
    // 안내가 끝난 뒤 다음 안내로 넘어가도록 speak가 읽기를 마칠 때까지 기다리게 한다.
    _tts.awaitSpeakCompletion(true);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // 말한 뒤 바로 음성 인식을 켜므로, 재생과 녹음을 함께 쓰는 오디오 모드로 둔다.
      // 이렇게 하지 않으면 마이크를 켠 뒤 안내 음성이 수화기 쪽으로 작게 나온다.
      _tts.setSharedInstance(true);
      _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playAndRecord,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
  }

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  /// 읽고 있던 안내를 끊고 [text]를 읽는다. 다 읽을 때까지 기다린다.
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
