import 'package:fashion_agent/services/cloud_tts.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/voices.dart';

/// 시험용 SpeechService에 목소리 고르기·신호음을 채운다. 미리 듣기([speakWith])도 [speak]로 남긴다.
mixin FakeSpeechExtras implements SpeechService {
  @override
  TtsApi? cloud;

  Voice? chosen;
  int cues = 0;

  /// 미리 들려준 목소리(문장마다).
  final sampled = <Voice?>[];

  @override
  List<Voice> get voices => const [...cloudVoices, deviceVoice];

  @override
  Future<Voice> get voice async => chosen ?? cloudVoices.first;

  @override
  Future<void> setVoice(Voice v) async => chosen = v;

  @override
  Future<void> speakWith(String text, {Voice? voice}) async {
    sampled.add(voice);
    await speak(text);
  }

  @override
  Future<void> loadDeviceVoices() async {}

  @override
  Future<void> prefetch(Iterable<String> texts) async {}

  @override
  Future<void> listeningCue() async => cues++;

  @override
  double rate = SpeechService.speechRate;

  @override
  Future<bool> changeRate(int steps) async {
    final next = (rate + steps * SpeechService.rateStep)
        .clamp(SpeechService.minRate, SpeechService.maxRate);
    if (next == rate) return false;
    rate = next;
    return true;
  }
}
