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
    if (_isIOS) {
      _tts.setSharedInstance(true);
    }
    _tts.setVolume(1.0);
  }

  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 읽기 직전에 iOS 오디오를 "재생 전용"으로 바꾼다.
  ///
  /// 음성 인식이 켜졌던 녹음+재생(playAndRecord) 모드로 읽으면, 스피커로 나와도 통화용 음량이라
  /// 최대로 키워도 작게 들린다. 읽는 동안에는 녹음할 일이 없으므로 재생 전용(playback)으로 크게 읽고,
  /// 음성 인식은 들을 때 스스로 녹음 모드로 바꿨다가 끝나면 이 모드로 되돌린다.
  Future<void> _loudPlayback() async {
    if (!_isIOS) return;
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );
  }

  /// 지금 읽고 있는지.
  bool get speaking => _speaking;

  /// 읽던 안내를 멈춘다. 말하는 중에 말하기 버튼을 누르면 끊고 바로 듣게 할 때 쓴다.
  Future<void> stop() async {
    if (!_speaking) return;
    await _tts.stop();
    _speaking = false;
  }

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
    await _loudPlayback();
    await _tts.speak(text);
  }
}
