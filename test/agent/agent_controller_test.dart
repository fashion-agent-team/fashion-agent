import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/agent_fakes.dart';

/// 온보딩을 마친 뒤 앱을 열었을 때(lib/agent/agent_controller.dart).
void main() {
  const onboarded = UserProfile(agentName: '하늘', consent: consentVersion);

  AgentController agentWith(FakeSpeech speech, List<String?> heard,
          {UserProfile? profile}) =>
      AgentController(
        speech: speech,
        listen: ScriptedListen(heard),
        profiles: InMemoryProfileStore(profile),
        weatherService: FakeWeatherService(),
        onboarding: onboardingWith(speech, const [], consentFirst: false),
      );

  test('다시 실행하면 이름을 넣어 인사하고, 날씨를 물으면 일교차도 알려 준다', () async {
    final speech = FakeSpeech();
    final agent = agentWith(speech, ['오늘 날씨 어때'], profile: onboarded);
    await agent.start();

    expect(
        speech.spoken.first,
        '반가워요. 저 하늘이에요. 오늘도 같이 준비해 봐요. '
        '필요한 게 있으면 편하게 말씀해 주세요.');
    expect(speech.spoken[1], contains('일교차가 13도로 커요'));
    expect(speech.spoken.last, '다른 기능이 필요하면 화면 위쪽을 누르고 말씀해 주세요.');
  });

  // specs/001-account-profile/spec.md US2-2
  test('US2-2 Given 에이전트 이름이 비어 있는 사용자 When 앱을 열면 Then 온보딩을 다시 안내한다', () async {
    // given: 이름·키는 저장됐지만 에이전트 이름은 아직 정하지 않았다
    final speech = FakeSpeech();
    final agent = agentWith(speech, const [],
        profile: const UserProfile(
            name: '김민수', heightCm: 175, consent: consentVersion));

    // when
    await agent.start();

    // then: 다시 온 인사 대신 온보딩 첫 질문(말 빠르기)부터 묻는다
    expect(
        speech.spoken,
        contains(
            '제 말 빠르기 괜찮으세요? 괜찮으면 "괜찮아", 더 천천히 들으시려면 "천천히", 조금 빠르게 들으시려면 "빠르게"라고 해 주세요.'));
    expect(speech.spoken, isNot(contains(startsWith('반가워요. 저 '))));
  });

  test('US2-2 Given 에이전트 이름이 있는 사용자 When 앱을 열면 Then 온보딩 없이 인사한다', () async {
    // given
    final speech = FakeSpeech();
    final agent = agentWith(speech, const [], profile: onboarded);

    // when
    await agent.start();

    // then
    expect(
        speech.spoken,
        isNot(contains(
            '제 말 빠르기 괜찮으세요? 괜찮으면 "괜찮아", 더 천천히 들으시려면 "천천히", 조금 빠르게 들으시려면 "빠르게"라고 해 주세요.')));
    expect(speech.spoken.first, startsWith('반가워요. 저 하늘이에요.'));
  });

  test('"첫 화면"이라고 하면 처음 화면 안내 뒤 처음부터 듣는다', () async {
    final speech = FakeSpeech();
    final agent = agentWith(speech, ['첫 화면', '날씨 어때'], profile: onboarded);
    await agent.start();

    expect(speech.spoken,
        contains('원하시는 기능을 말씀하시면 도와드려요. 어떤 기능이 있는지 궁금하시면 "기능 설명"이라고 말씀해주세요.'));
    expect(speech.spoken, contains(contains('일교차')));
  });

  group('옷 검사·얼굴 확인', () {
    test('옷 검사를 말하면 옷 검사 화면을 연다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['옷 검사해 줘'], profile: onboarded);
      var opened = false;
      agent.openOutfitCheck = () async => opened = true;
      await agent.start();

      expect(opened, isTrue);
      expect(speech.spoken.last, startsWith('옷 다 봤어요.'));
    });

    test('서버 없이 옷 검사를 말하면 예전 프록시로 보내지 않고 서버가 필요하다고 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['옷 검사해 줘'], profile: onboarded);
      await agent.start();

      expect(
          speech.spoken,
          contains(
              '지금은 서버에 연결되지 않아서 옷을 볼 수가 없어요. 와이파이나 데이터가 켜져 있는지 봐 주시고, 조금 뒤에 다시 말씀해 주세요.'));
    });

    test('서버 없이 얼굴 확인을 말하면 준비 중이 아니라 서버 연결이 필요하다고 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['얼굴 좀 봐 줘'], profile: onboarded);
      await agent.start();

      expect(
          speech.spoken,
          contains(
              '지금은 서버에 연결되지 않아서 얼굴을 볼 수가 없어요. 와이파이나 데이터가 켜져 있는지 봐 주시고, 조금 뒤에 다시 말씀해 주세요.'));
      expect(speech.spoken.any((s) => s.contains('준비 중')), isFalse);
    });
  });
}
