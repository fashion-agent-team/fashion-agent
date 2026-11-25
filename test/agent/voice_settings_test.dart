import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/agent_fakes.dart';

/// 앱을 쓰다가 말로 에이전트 이름·호칭·내 정보를 바꾼다.
void main() {
  /// [heard]는 앱이 듣는 말, [answers]는 설정을 바꾸며 되묻는 말에 대한 대답이다.
  AgentController agentWith(FakeSpeech speech, List<String?> heard,
          {required UserProfile profile,
          List<String?> answers = const [],
          ProfileStore? store,
          FakeAccount? account}) =>
      AgentController(
        speech: speech,
        listen: ScriptedListen(heard),
        profiles: store ?? InMemoryProfileStore(profile),
        weatherService: FakeWeatherService(),
        onboarding: onboardingWith(speech, answers,
            account: account, consentFirst: false),
      );

  test('에이전트 이름을 바꾸고 저장·업로드한다', () async {
    final speech = FakeSpeech();
    const before = UserProfile(
        name: '이진행',
        agentName: '박창근',
        consent: consentVersion,
        accountId: 'uid-1');
    final store = InMemoryProfileStore(before);
    final account = FakeAccount(id: 'uid-1');
    final agent = agentWith(speech, ['네 이름 바꿔 줘'],
        profile: before, answers: ['코디', '네'], store: store, account: account);
    await agent.start();

    expect(speech.spoken, contains('새 이름을 말씀해 주세요.'));
    expect(speech.spoken, contains('좋아요, 이제 제 이름은 코디예요.'));
    expect(agent.wakeName, '코디');
    expect(store.profile?.agentName, '코디');
    expect(store.profile?.name, '이진행');
    expect(account.uploaded?.agentName, '코디');
  });

  test('호칭을 말과 함께 정하면 확인만 하고, 인사에 넣는다', () async {
    final speech = FakeSpeech();
    const before = UserProfile(agentName: '하늘', consent: consentVersion);
    final store = InMemoryProfileStore(before);
    final agent = agentWith(speech, ['나를 진행 님이라고 불러 줘'],
        profile: before, answers: ['응'], store: store);
    await agent.start();

    expect(speech.spoken, contains('앞으로 진행 님, 이렇게 불러 드릴까요?'));
    expect(store.profile?.callName, '진행 님');

    final again = FakeSpeech();
    await agentWith(again, const [], profile: store.profile!, store: store)
        .start();
    expect(again.spoken.first, startsWith('반가워요, 진행 님. 저 하늘이에요.'));
  });

  test('사용자 정보 한 항목만 바꾼다', () async {
    final speech = FakeSpeech();
    const before = UserProfile(
        name: '김민수', heightCm: 170, agentName: '하늘', consent: consentVersion);
    final store = InMemoryProfileStore(before);
    final agent = agentWith(speech, ['내 키 바꿔 줘'],
        profile: before, answers: ['175'], store: store);
    await agent.start();

    expect(store.profile?.heightCm, 175);
    expect(store.profile?.name, '김민수');
    expect(speech.spoken, contains(startsWith('바꿨어요. 이름 김민수')));
  });

  test('정보를 고쳐도 동의와 말 빠르기는 그대로 둔다', () async {
    // 2026-11-13 점검: 예전에는 고칠 때 동의·말 빠르기가 지워져서 다음 실행에 동의 안내가 다시 나왔다.
    final speech = FakeSpeech();
    const before = UserProfile(
        heightCm: 170,
        agentName: '하늘',
        consent: consentVersion,
        speechRate: 0.48);
    final store = InMemoryProfileStore(before);
    final agent = agentWith(speech, ['내 키 바꿔 줘'],
        profile: before, answers: ['175'], store: store);
    await agent.start();

    expect(store.profile?.heightCm, 175);
    expect(store.profile?.consent, consentVersion);
    expect(store.profile?.speechRate, 0.48);
  });

  test('못 알아들으면 정보를 지우지 않고 그대로 둔다', () async {
    final speech = FakeSpeech();
    const before =
        UserProfile(heightCm: 170, agentName: '하늘', consent: consentVersion);
    final store = InMemoryProfileStore(before);
    final agent = agentWith(speech, ['내 키 바꿔 줘'],
        profile: before, answers: [null, null, null], store: store);
    await agent.start();

    expect(store.profile?.heightCm, 170);
    expect(speech.spoken, contains('키는 그대로 둘게요.'));
  });
}
