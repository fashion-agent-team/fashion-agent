import 'package:fashion_agent/services/cloud_tts.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/voices.dart';
import 'package:flutter_test/flutter_test.dart';

/// 소리를 내지 않는 [SpeechService]. 앱이 소리 내어 말한 문장을 [said]에 차례로 모은다.
///
/// 검사는 아래 매처로 쓴다. 숨은 그림 찾기처럼 `contains(startsWith(...))`를 직접 쓰지 않는다.
/// ```dart
/// expect(speech, saidLineStartingWith('좋아요, 이제 제 이름은'));
/// expect(speech, neverSaidLineStartingWith('앗'));
/// expect(speech.said, ['문장1', '문장2']); // 말한 순서 전체가 중요할 때
/// ```
class FakeSpeech with FakeSpeechExtras implements SpeechService {
  /// 앱이 소리 내어 말한 문장(말한 순서대로).
  final said = <String>[];

  /// [said] 중 [part]가 들어간 문장 수. 같은 질문을 몇 번 했는지 셀 때.
  int countLinesContaining(String part) =>
      said.where((line) => line.contains(part)).length;

  @override
  Future<void> speak(String text) async => said.add(text);

  int stops = 0;

  @override
  bool get speaking => false;

  @override
  Future<void> stop() async => stops++;
}

/// 앱이 [line]과 똑같은 문장을 한 번이라도 말했다.
Matcher saidLine(String line) => _saidLines('"$line"을(를) 말함', contains(line));

/// 앱이 [prefix]로 시작하는 문장을 한 번이라도 말했다.
Matcher saidLineStartingWith(String prefix) =>
    _saidLines('"$prefix…"로 시작하는 문장을 말함', contains(startsWith(prefix)));

/// 앱이 [part]가 들어간 문장을 한 번이라도 말했다.
Matcher saidLineContaining(String part) =>
    _saidLines('"…$part…"가 들어간 문장을 말함', contains(contains(part)));

/// 앱이 [line]과 똑같은 문장을 한 번도 말하지 않았다.
Matcher neverSaidLine(String line) =>
    _saidLines('"$line"을(를) 말하지 않음', isNot(contains(line)));

/// 앱이 [prefix]로 시작하는 문장을 한 번도 말하지 않았다.
Matcher neverSaidLineStartingWith(String prefix) => _saidLines(
    '"$prefix…"로 시작하는 문장을 말하지 않음', isNot(contains(startsWith(prefix))));

/// 앱이 [part]가 들어간 문장을 한 번도 말하지 않았다.
Matcher neverSaidLineContaining(String part) =>
    _saidLines('"…$part…"가 들어간 문장을 말하지 않음', isNot(contains(contains(part))));

Matcher _saidLines(String description, Matcher lines) =>
    isA<FakeSpeech>().having((s) => s.said, description, lines);

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
  Future<void> warmUp() async {}

  @override
  Future<void> listeningCue() async => cues++;

  int ticks = 0;

  @override
  Future<void> waitingTick() async => ticks++;

  @override
  double rate = SpeechService.speechRate;

  @override
  Future<void> setRate(double value) async =>
      rate = value.clamp(SpeechService.minRate, SpeechService.maxRate);

  @override
  Future<bool> changeRate(int steps) async {
    final next = (rate + steps * SpeechService.rateStep)
        .clamp(SpeechService.minRate, SpeechService.maxRate);
    if (next == rate) return false;
    rate = next;
    return true;
  }
}
