import 'package:fashion_agent/agent/voice_picker.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/voices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_test.dart' show FakeSpeech, ScriptedListen;

/// 목소리 고르기를 [heard] 대답으로 끝까지 돌린다. 안내 문장과 고른 목소리를 돌려준다.
Future<(List<String>, Voice?, FakeSpeech)> _pick(List<String?> heard,
    {int maxMisses = 3}) async {
  final speech = FakeSpeech();
  final said = <String>[];
  final picked = await VoicePicker(
          speech: speech, listen: ScriptedListen(heard), maxMisses: maxMisses)
      .run((s) async => said.add(s));
  return (said, picked, speech);
}

void main() {
  group('말로 목소리 고르기', () {
    test('다음, 이전으로 옮겨 가며 들려주고 "이 목소리 좋아"로 고른다', () async {
      final (_, picked, speech) = await _pick(['다음', '다음', '이전', '이 목소리 좋아']);
      // 1번 → 2번 → 3번 → 2번에서 고름
      expect(picked, cloudVoices[1]);
      expect(speech.chosen, cloudVoices[1]);
      expect(speech.sampled.take(4),
          [cloudVoices[0], cloudVoices[1], cloudVoices[2], cloudVoices[1]]);
      expect(speech.spoken.last, '좋아요. 이제부터 2번 목소리로 말할게요.');
    });

    test('"4번 들려줘"로 건너뛰고 "처음부터"로 돌아가 번호로 고른다', () async {
      final (_, picked, speech) =
          await _pick(['4번 들려줘', '처음부터', '세 번째 목소리로 할게']);
      expect(speech.sampled.take(3),
          [cloudVoices[0], cloudVoices[3], cloudVoices[0]]);
      expect(picked, cloudVoices[2]);
    });

    test('마지막에서 "다음"이면 처음부터 다시 들려준다', () async {
      final all = FakeSpeech().voices;
      final (said, picked, speech) =
          await _pick([...List.filled(all.length - 1, '다음'), '다음', '그만']);
      expect(said, contains('마지막 목소리였어요. 처음부터 다시 들려 드릴게요.'));
      expect(speech.sampled.last, all.first);
      expect(said.last, '알겠어요. 지금 목소리 그대로 쓸게요.');
      expect(picked, isNull);
    });

    test('첫 목소리에서 "이전"이면 마지막 목소리로 간다', () async {
      final all = FakeSpeech().voices;
      final (_, _, speech) = await _pick(['앞에 거', '그만할래']);
      expect(speech.sampled[1], all.last);
    });

    test('"다시"면 같은 목소리를 한 번 더 들려준다', () async {
      final (_, _, speech) = await _pick(['다시 들려줘', '취소']);
      expect(speech.sampled.take(2), [cloudVoices[0], cloudVoices[0]]);
    });

    test('못 알아들으면 말하는 법을 알려 주고, 계속 못 알아들으면 그만둔다', () async {
      final (said, picked, speech) =
          await _pick(['음', null, '어'], maxMisses: 3);
      expect(said.where((s) => s.startsWith('"다음", "처음부터"')), hasLength(2));
      expect(said.last, startsWith('목소리 고르기를 마칠게요.'));
      expect(picked, isNull);
      // 못 알아들은 뒤에는 같은 목소리를 다시 틀지 않는다
      expect(speech.sampled, hasLength(1));
    });

    test('대답 읽기: 싫다는 말은 다음, 번호만 말하면 들어 보기', () {
      expect(parseVoiceAnswer('별로야', 7)!.kind, VoiceAnswerKind.next);
      expect(parseVoiceAnswer('5번', 7)!.kind, VoiceAnswerKind.listen);
      expect(parseVoiceAnswer('5번', 7)!.number, 5);
      expect(parseVoiceAnswer('9번 좋아', 7)!.number, isNull);
      expect(voiceNumber('일곱째', 7), 7);
      expect(voiceNumber('여덟 번', 7), isNull);
    });
  });

  group('내 정보 폰에 저장', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('모든 항목을 저장했다가 그대로 불러온다', () async {
      final store = LocalProfileStore();
      expect(await store.load(), isNull);

      final profile = UserProfile(
        name: '박창근',
        birthDate: DateTime(1999, 4, 1),
        gender: '남자',
        job: '학생',
        heightCm: 175,
        weightKg: 70,
        agentName: '심청이',
        callName: '창근',
        accountId: 'uid-9',
        consent: consentVersion,
        speechRate: 0.36,
      );
      await store.save(profile);

      final back = (await LocalProfileStore().load())!;
      expect(back.name, '박창근');
      expect(back.birthDate, DateTime(1999, 4, 1));
      expect(back.gender, '남자');
      expect(back.job, '학생');
      expect(back.heightCm, 175);
      expect(back.weightKg, 70);
      expect(back.agentName, '심청이');
      expect(back.callName, '창근');
      expect(back.accountId, 'uid-9');
      expect(back.consent, consentVersion);
      expect(back.speechRate, 0.36);
      expect(back.isOnboarded, isTrue);
    });
  });
}
