import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/small_talk.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_test.dart'
    show
        FakeAccount,
        FakeSpeech,
        FakeWeatherService,
        ScriptedListen,
        onboardingWith;

/// 온보딩을 마친 사용자로 시작한 agent(서버 없음).
Future<(AgentController, FakeSpeech, InMemoryProfileStore, FakeAccount)>
    _started({List<String?> heard = const [], String? accountId}) async {
  final speech = FakeSpeech();
  final profile = UserProfile(
      name: '이진행',
      agentName: '하늘',
      consent: consentVersion,
      accountId: accountId);
  final store = InMemoryProfileStore(profile);
  final account = FakeAccount(id: accountId);
  final agent = AgentController(
    speech: speech,
    listen: ScriptedListen(heard),
    profiles: store,
    weatherService: FakeWeatherService(),
    onboarding:
        onboardingWith(speech, const [], account: account, consentFirst: false),
  );
  await agent.start();
  speech.spoken.clear();
  return (agent, speech, store, account);
}

void main() {
  group('말 빠르기 바꾸기', () {
    test('"천천히 말해 줘"면 느리게 바꾸고 정보와 계정에 저장한다', () async {
      final (agent, speech, store, account) =
          await _started(accountId: 'uid-1');

      await agent.handle('조금 천천히 말해 줘');
      await pumpEventQueue();

      expect(speech.spoken.first, '네, 이제 조금 더 천천히 말할게요.');
      expect(speech.spoken.last, tapToTalk);
      expect(speech.rate, lessThan(SpeechService.speechRate));
      expect(store.profile!.speechRate, speech.rate);
      expect(account.uploaded!.speechRate, speech.rate);
    });

    test('"빠르게 말해 줘"를 끝까지 하면 가장 빠른 빠르기라고 알려 준다', () async {
      final (agent, speech, _, account) = await _started();
      speech.rate = SpeechService.maxRate;

      await agent.handle('더 빠르게 말해 줘');

      expect(speech.spoken.first, '지금이 제가 낼 수 있는 가장 빠른 빠르기예요.');
      expect(account.uploaded, isNull, reason: '안 바뀌었으면 저장하지 않는다');
    });
  });

  group('다시 말해 줘', () {
    test('방금 한 안내를 그대로 다시 읽는다', () async {
      final (agent, speech, _, _) = await _started();

      await agent.handle('오늘 날씨 어때');
      final weather = speech.spoken.first;
      speech.spoken.clear();

      await agent.handle('뭐라고? 다시 말해 줘');
      expect(speech.spoken, [weather, tapToTalk]);
    });
  });

  group('서버 없이 폰이 답하는 말', () {
    test('"잠깐 쉬어"면 쉬고 이름 듣기를 멈춘다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('잠깐 쉬어');
      expect(agent.resting, isTrue);
      expect(speech.spoken, ['네, 잠깐 쉴게요.']);
    });

    test('일정은 서버가 필요하다고 말한다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('내일 일정 알려 줘');
      expect(speech.spoken, [noServerScheduleSpeech, tapToTalk]);
    });

    test('할 줄 아는 걸 물으면 기능을 소개한다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('너는 뭘 할 수 있어');
      expect(speech.spoken.first, featureIntro);
    });

    test('못 하는 일은 아쉽다고 하고 할 수 있는 일을 알려 준다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('비행기 표 예매해 줘');
      expect(speech.spoken.first, unknownSpeech);
    });

    test('"내 정보 알려 줘"면 저장된 정보를 읽어 준다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('내 정보 알려 줘');
      expect(speech.spoken.first, contains('이진행'));
      expect(speech.spoken.first, contains('"내 키 바꿔 줘"처럼'));
    });

    test('듣지 못하면 다시 말해 달라고 한다', () async {
      final (agent, speech, _, _) = await _started();
      await agent.handle('처음으로');
      expect(speech.spoken, [homeScreen, '앗, 제가 잘 못 들었어요. $tapToTalk']);
    });
  });
}
