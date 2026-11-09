import '../services/listen_service.dart';
import '../services/speech_service.dart';
import '../services/voices.dart';
import 'command_listener.dart';

/// 말로 목소리 고르기. 2026-11-09 발표 피드백:
/// "목소리 순서대로 들려줘" → 1번부터 들려주고 "다음", "다음", … "처음부터", "3번 목소리가 좋아",
/// 또는 듣다가 "지금 목소리 좋아"라고 하면 그 목소리로 바꾼다.
class VoicePicker {
  VoicePicker({required this.speech, required this.listen, this.maxMisses = 3});

  final SpeechService speech;
  final ListenService listen;

  /// 못 알아들은 답이 이만큼 이어지면 그만둔다.
  final int maxMisses;

  static const intro = '목소리를 하나씩 들려 드릴게요. 다음 목소리는 "다음", 처음부터는 "처음부터", '
      '마음에 들면 "이 목소리 좋아" 또는 "몇 번 목소리 좋아"라고 말씀해 주세요.';

  static String sample(int number, Voice v) =>
      '$number번 목소리예요. ${v.description}이에요. 안녕하세요, 오늘도 멋진 하루 보내세요.';

  /// 목소리를 고른다. 바꿨으면 고른 목소리, 그만두면 null. 안내는 [say]로 한다.
  Future<Voice?> run(Future<void> Function(String) say) async {
    await speech.loadDeviceVoices();
    final all = speech.voices;
    if (all.length < 2) {
      await say(
          '지금 폰에는 한국어 목소리가 하나뿐이에요. 설정의 손쉬운 사용, 읽기 및 말하기, 음성, 한국어에서 목소리를 더 받아 두시면 여기서 골라 쓸 수 있어요.');
      return null;
    }
    await say(intro);
    var i = 0;
    var misses = 0;
    var replay = true;
    while (true) {
      if (replay) await speech.speakWith(sample(i + 1, all[i]), voice: all[i]);
      replay = true;
      final heard = await CommandListener.once(listen);
      final pick = heard == null ? null : parseVoiceAnswer(heard, all.length);
      switch (pick) {
        case VoiceAnswer(kind: VoiceAnswerKind.choose, :final number):
          final chosen = all[(number ?? i + 1) - 1];
          await speech.setVoice(chosen);
          await speech.speakWith(
              '좋아요. 이제부터 ${all.indexOf(chosen) + 1}번 목소리로 말할게요.',
              voice: chosen);
          return chosen;
        case VoiceAnswer(kind: VoiceAnswerKind.next):
          if (i + 1 >= all.length) {
            await say('마지막 목소리였어요. 처음부터 다시 들려 드릴게요.');
            i = 0;
          } else {
            i++;
          }
          misses = 0;
        case VoiceAnswer(kind: VoiceAnswerKind.previous):
          i = i == 0 ? all.length - 1 : i - 1;
          misses = 0;
        case VoiceAnswer(kind: VoiceAnswerKind.first):
          i = 0;
          misses = 0;
        case VoiceAnswer(kind: VoiceAnswerKind.listen, :final number):
          i = (number ?? i + 1) - 1;
          misses = 0;
        case VoiceAnswer(kind: VoiceAnswerKind.again):
          misses = 0;
        case VoiceAnswer(kind: VoiceAnswerKind.cancel):
          await say('알겠어요. 지금 목소리 그대로 쓸게요.');
          return null;
        case null:
          misses++;
          if (misses >= maxMisses) {
            await say('목소리 고르기를 마칠게요. 다시 고르려면 "목소리 바꿔 줘"라고 말씀해 주세요.');
            return null;
          }
          await say('"다음", "처음부터", 또는 "몇 번 목소리 좋아"라고 말씀해 주세요.');
          replay = false;
      }
    }
  }
}

enum VoiceAnswerKind { choose, next, previous, first, listen, again, cancel }

class VoiceAnswer {
  const VoiceAnswer(this.kind, [this.number]);

  final VoiceAnswerKind kind;

  /// 말한 번호(1부터). 없으면 지금 듣던 목소리.
  final int? number;
}

const _numberWords = {
  '일': 1, '하나': 1, '한': 1, '첫': 1, '첫째': 1, //
  '이': 2, '둘': 2, '두': 2, '둘째': 2,
  '삼': 3, '셋': 3, '세': 3, '셋째': 3,
  '사': 4, '넷': 4, '네': 4, '넷째': 4,
  '오': 5, '다섯': 5, '다섯째': 5,
  '육': 6, '여섯': 6, '여섯째': 6,
  '칠': 7, '일곱': 7, '일곱째': 7,
};

/// 말 속의 목소리 번호("3번", "삼 번", "세 번째"). 없거나 범위 밖이면 null.
int? voiceNumber(String text, int count) {
  final s = text.replaceAll(RegExp(r'\s+'), '');
  final digit = RegExp(r'(\d+)번').firstMatch(s);
  int? n = digit == null ? null : int.tryParse(digit.group(1)!);
  if (n == null) {
    final word = RegExp(
            r'(첫째|둘째|셋째|넷째|다섯째|여섯째|일곱째|하나|다섯|여섯|일곱|첫|둘|두|셋|세|넷|네|일|삼|사|오|육|칠)(번|째)')
        .firstMatch(s);
    if (word != null) n = _numberWords[word.group(1)!];
  }
  if (n == null || n < 1 || n > count) return null;
  return n;
}

/// 목소리를 들으며 한 말을 뜻으로 바꾼다. 모르는 말이면 null.
VoiceAnswer? parseVoiceAnswer(String text, int count) {
  final s = text.replaceAll(RegExp(r'[\s?.!,~]+'), '');
  final n = voiceNumber(text, count);
  if (RegExp(r'안좋|별로|싫|맘에안|마음에안').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.next);
  }
  final like = RegExp(
          r'좋아|좋다|좋네|좋을|좋겠|마음에|맘에|이걸로|이거로|이것으로|그걸로|이목소리로|로할게|로해|로바꿔|선택|골라|정할게|쓸게|할게')
      .hasMatch(s);
  if (n != null && like) return VoiceAnswer(VoiceAnswerKind.choose, n);
  if (RegExp(r'^(그만|취소|됐어|안바꿀|바꾸지마|원래대로|그대로)').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.cancel);
  }
  if (like) return const VoiceAnswer(VoiceAnswerKind.choose);
  if (RegExp(r'처음부터|처음으로|첫번째부터|맨처음|일번부터').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.first);
  }
  if (n != null) return VoiceAnswer(VoiceAnswerKind.listen, n);
  if (RegExp(r'이전|앞에|앞으로|전꺼|전거|뒤로').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.previous);
  }
  if (RegExp(r'다음|넘겨|다른거|다른목소리|별로|싫어|패스|넘어가').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.next);
  }
  if (RegExp(r'다시|한번더|못들었|뭐라고').hasMatch(s)) {
    return const VoiceAnswer(VoiceAnswerKind.again);
  }
  return null;
}
