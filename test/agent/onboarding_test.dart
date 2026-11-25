import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/permission_service.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

const speedQuestion =
    '제 말 빠르기 괜찮으세요? 괜찮으면 "괜찮아", 더 천천히 들으시려면 "천천히", 조금 빠르게 들으시려면 "빠르게"라고 해 주세요.';
const featureGuide =
    '제가 할 수 있는 것들 알려드릴게요. 저는 일정 추가, 날씨 정보, 옷 추천, 원하는 옷 확인, 옷 색 확인, 화장 상태와 이에 낀 이물질 확인을 도와드려요. "처음으로"라고 하시면 언제든 처음으로 돌아와요. 편하게 말씀해 주세요.';

/// 처음 켤 때 묻는 흐름(lib/agent/onboarding_flow.dart).
void main() {
  group('순서와 저장', () {
    test('인사 → 이름 짓기 → 정보 → 재확인 → 기능 설명 순서로 묻고 저장한다', () async {
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();
      final profile =
          await onboardingWith(speech, [...sampleAnswers, '네'], store: store)
              .run();

      expect(speech.said.first, '안녕하세요, 저는 당신의 곁에서 패션을 책임질 에이전트 심청이예요.');
      expect(speech, saidLineStartingWith('좋아요, 이제 제 이름은 하늘이에요.'));
      expect(
          speech,
          saidLine('말씀해주신 정보를 읽어 드릴게요. 이름 김민수, 생년월일 1990년 3월 5일, '
              '성별 남성, 직업 회사원, 키 170센티미터, 몸무게 건너뜀. 말씀해주신 정보와 일치할까요?'));
      expect(speech, saidLine('지금은 계정 연결 없이 이 폰에만 저장할게요.'));
      expect(speech.said.last, featureGuide);

      expect(profile.agentName, '하늘');
      expect(profile.birthDate, DateTime(1990, 3, 5));
      expect(profile.weightKg, isNull);
      expect(store.profile?.name, '김민수');
    });

    test('허용하면 동의로 보고, 음성으로 동의를 묻지 않는다', () async {
      final speech = FakeSpeech();
      final permissions = FakePermissionService();
      final profile = await onboardingWith(speech, [...sampleAnswers, '네'],
              permissions: permissions)
          .run();

      expect(permissions.requests, 1);
      expect(profile.consented, isTrue);
      expect(speech.said.take(9), [
        '안녕하세요, 저는 당신의 곁에서 패션을 책임질 에이전트 심청이예요.',
        '시작하기 전에 알려 드릴게요. 말씀과 옷 사진은 옷 추천을 위해 서버에서만 살펴보고, 다른 곳에는 쓰지 않아요.',
        "이제 허용 창이 몇 개 떠요. 오른쪽으로 쓸어 넘기다 보면 '허용 안 함'이 먼저 들려요. 그건 지나치고, '허용'이나 '확인'이 들리면 두 번 탭해 주세요. 위치는 '앱을 사용하는 동안 허용'을 골라 주세요.",
        '허용해 주셔서 고마워요.',
        '폰을 바꿔도 이어서 쓸 수 있게 구글 계정으로 로그인할게요. 곧 로그인 창이 떠요. 화면을 오른쪽으로 한 번씩 쓸어 넘기다가 \'계속\'이 들리면 두 번 탭해 주세요. 그다음 쓰실 구글 계정을 고르시면 돼요.',
        '지금은 계정 연결 없이 이 폰에만 저장할게요.',
        speedQuestion,
        '목소리는 맘에 드시나요? "괜찮아", "바꾸고 싶어"로 알려주세요.',
        '제 이름은 심청이예요. 다른 이름으로 부르고 싶으시면 지금 말씀해 주시고, 이대로 좋으시면 "좋아"라고 해 주세요.',
      ]);
      expect(speech, neverSaidLineStartingWith('혹시 다른 폰에서'));
    });

    test('마이크를 막으면 들을 수 없다고 알려 준다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(speech, [...sampleAnswers, '네'],
              permissions: FakePermissionService(canListen: false))
          .run();

      expect(speech.said.last,
          '마이크나 음성 인식이 꺼져 있어서 말씀을 들을 수가 없어요. 설정 앱에서 켜고 다시 열어 주세요.');
      expect(profile.isOnboarded, isFalse);
    });
  });

  group('말 빠르기·목소리', () {
    test('"천천히"라고 하면 느리게 바꾸고 다시 묻는다', () async {
      final speech = FakeSpeech();
      await onboardingWith(
              speech, ['너무 빨라 천천히', '괜찮아', '괜찮아', ...sampleAnswers, '네'],
              consentFirst: false)
          .run();

      expect(speech.rate, lessThan(SpeechService.speechRate));
      expect(speech, saidLine('네, 이제 이 속도로 말할게요. 괜찮으세요?'));
    });

    test('목소리를 바꾸고 싶다고 하면 하나씩 들려준다', () async {
      final speech = FakeSpeech();
      await onboardingWith(
              speech, ['괜찮아', '바꾸고 싶어', '좋아', ...sampleAnswers, '네'],
              consentFirst: false)
          .run();

      expect(speech, saidLine('목소리는 맘에 드시나요? "괜찮아", "바꾸고 싶어"로 알려주세요.'));
      expect(speech, saidLine('목소리를 하나씩 들려 드릴게요. 원하는 목소리면 "좋아"라고 해주세요.'));
    });
  });

  group('에이전트 이름', () {
    test('이름에 대답이 없으면 심청이로 정한다', () async {
      final speech = FakeSpeech();
      final profile =
          await onboardingWith(speech, [null, ...sampleAnswers.skip(2), '네'])
              .run();

      expect(speech,
          saidLine('좋아요, 심청이라고 불러 주세요. 나중에라도 "네 이름 바꿔 줘"라고 하시면 바꿀 수 있어요.'));
      expect(profile.agentName, '심청이');
    });

    test('"좋아"라고 하면 심청이 그대로, 비슷한 이름은 맞는지 묻는다', () async {
      final keep = await onboardingWith(
          FakeSpeech(), ['좋아', ...sampleAnswers.skip(2), '네']).run();
      expect(keep.agentName, '심청이');

      final speech = FakeSpeech();
      final guessed = await onboardingWith(
          speech, ['신청이', '네', ...sampleAnswers.skip(2), '네']).run();
      expect(speech, saidLine('제 이름이 심청이, 맞나요?'));
      expect(guessed.agentName, '심청이');
    });
  });

  // specs/001-account-profile/spec.md US2-1, US2-3
  group('내 정보', () {
    test('US2-1 Given 온보딩 중 When 키만 말하고 나머지를 건너뛰면 Then 키만 저장되고 나머지는 비어 있다',
        () async {
      // given
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();

      // when
      final profile = await onboardingWith(
              speech,
              [
                '하늘', '네', // 에이전트 이름
                '건너뛰기', '건너뛰기', '건너뛰기', '건너뛰기', '170', '건너뛰기', '네',
              ],
              store: store)
          .run();

      // then
      expect(profile.heightCm, 170);
      expect(profile.name, isNull);
      expect(profile.birthDate, isNull);
      expect(profile.gender, isNull);
      expect(profile.job, isNull);
      expect(profile.weightKg, isNull);
      expect(store.profile?.heightCm, 170);
    });

    test('US2-3 Given 키를 300센티로 잘못 말함 When 저장하면 Then 받지 않고 키를 다시 묻는다',
        () async {
      // given
      final speech = FakeSpeech();

      // when
      final profile = await onboardingWith(speech, [
        '하늘',
        '네',
        '김민수예요',
        '1990년 3월 5일',
        '남자',
        '회사원이에요',
        '키 300센티',
        '170',
        '건너뛰기',
        '네',
      ]).run();

      // then
      expect(profile.heightCm, 170);
      expect(speech.countLinesContaining('키는 몇 센티미터인가요?'),
          greaterThanOrEqualTo(2));
    });

    test(
        'US2-3 Given 키·몸무게를 경계값으로 말함 When 저장하면 Then 키 50~250cm·몸무게 10~300kg만 받고 넘으면 다시 묻는다',
        () async {
      // given
      final speech = FakeSpeech();

      // when: 키 251(거절) → 250, 몸무게 9(거절) → 300
      final tall = await onboardingWith(speech, [
        '하늘',
        '네',
        '김민수예요',
        '1990년 3월 5일',
        '남자',
        '회사원이에요',
        '251',
        '250',
        '9',
        '300',
        '네',
      ]).run();
      // when: 가장 작은 값 키 50, 몸무게 10
      final small = await onboardingWith(FakeSpeech(), [
        '하늘',
        '네',
        '김민수예요',
        '1990년 3월 5일',
        '남자',
        '회사원이에요',
        '50',
        '10',
        '네',
      ]).run();

      // then
      expect(tall.heightCm, 250);
      expect(tall.weightKg, 300);
      expect(speech.countLinesContaining('키는 몇 센티미터인가요?'),
          greaterThanOrEqualTo(2));
      expect(speech.countLinesContaining('몸무게는 몇 킬로그램인가요?'),
          greaterThanOrEqualTo(2));
      expect(small.heightCm, 50);
      expect(small.weightKg, 10);
    });

    test('"나중에 할게"라고 하면 내 정보를 한 번에 넘긴다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(speech, [
        '하늘', '네', //
        '나중에 할게', '건너뛰기',
      ]).run();

      expect(profile.agentName, '하늘');
      expect(profile.name, isNull);
      expect(speech,
          saidLine('알겠어요, 내 정보는 나중에 여쭤볼게요. "내 키 바꿔 줘"처럼 말씀하시면 언제든 넣을 수 있어요.'));
      expect(speech, neverSaidLineStartingWith('말씀해주신 정보를 읽어 드릴게요'));
      expect(speech, neverSaidLine('생년월일을 말씀해 주세요. 예를 들면 1990년 3월 5일처럼요.'));
    });
  });

  group('재확인', () {
    test('틀렸다고 하면 고칠 항목만 다시 묻는다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(
          speech, [...sampleAnswers, '아니요', '키가 틀렸어', '175', '네']).run();

      expect(profile.heightCm, 175);
      expect(profile.name, '김민수');
      expect(speech.countLinesContaining('일치할까요'), 2);
    });

    test('대답을 못 알아들으면 맞다고 치지 않고 다시 묻는다', () async {
      final speech = FakeSpeech();
      await onboardingWith(speech, [...sampleAnswers, '음', '음', '음', '네'])
          .run();
      expect(speech.countLinesContaining('일치할까요'), 4);
    });
  });

  group('호칭', () {
    const withName = [
      '하늘', '네', //
      '이진행이요', '건너뛰기', '건너뛰기', '건너뛰기', '건너뛰기', '건너뛰기', '네',
    ];

    test('이름을 말하면 호칭을 제안해서 묻는다', () async {
      final speech = FakeSpeech();
      final profile =
          await onboardingWith(speech, [...withName, '진행 님', '네']).run();

      expect(
          speech,
          saidLine(
              '제가 어떻게 불러 드릴까요? 진행 님으로 불러드리면 될까요? 아니라면 불리고 싶은 호칭을 말씀해 주세요.'));
      expect(profile.callName, '진행 님');
      expect(speech, saidLine('잘 부탁드려요 진행 님.'));
    });

    test('제안한 호칭에 "아니요"라고 하면 호칭을 다시 듣는다', () async {
      final speech = FakeSpeech();
      final profile =
          await onboardingWith(speech, [...withName, '아니요', '대표님', '네']).run();

      expect(speech, saidLine('불리고 싶은 호칭을 말씀해 주세요.'));
      expect(profile.callName, '대표님');
      expect(speech, saidLine('잘 부탁드려요 대표님.'));
    });

    test('제안한 호칭에 "네"라고 하면 그대로 정한다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(speech, [...withName, '네']).run();

      expect(profile.callName, '진행 님');
      expect(speech, neverSaidLineStartingWith('앞으로'));
      expect(speech.said.last, featureGuide);
    });
  });

  group('계정', () {
    test('계정에 연결되면 정보를 올린다', () async {
      final account = FakeAccount(id: 'uid-1');
      final profile = await onboardingWith(
              FakeSpeech(), [...sampleAnswers, '네'],
              account: account)
          .run();

      expect(profile.accountId, 'uid-1');
      expect(account.uploaded?.agentName, '하늘');
    });

    test('로그인했는데 정보가 없으면 처음 오셨군요', () async {
      final speech = FakeSpeech();
      await onboardingWith(speech, [...sampleAnswers, '네'],
              account: FakeAccount(id: 'uid-new'))
          .run();

      expect(speech, saidLine('처음 오셨군요. 반가워요.'));
      expect(speech, neverSaidLine('지금은 계정 연결 없이 이 폰에만 저장할게요.'));
    });

    test('로그인한 계정에 전에 쓴 정보가 있으면 묻지 않고 불러와 바로 시작한다', () async {
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();
      final profile = await onboardingWith(speech, const [],
              store: store,
              account: FakeAccount(
                  id: 'uid-1',
                  saved: const UserProfile(
                      name: '김민수', agentName: '하늘', speechRate: 0.36)))
          .run();

      expect(profile.agentName, '하늘');
      expect(profile.consented, isTrue);
      expect(store.profile?.accountId, 'uid-1');
      expect(speech.rate, 0.36);
      expect(speech, saidLine('전에 쓰신 적 있군요. 기존 정보를 불러오겠습니다.'));
      expect(speech, neverSaidLine(speedQuestion));
      expect(
          speech,
          neverSaidLine(
              '제 이름은 심청이예요. 다른 이름으로 부르고 싶으시면 지금 말씀해 주시고, 이대로 좋으시면 "좋아"라고 해 주세요.'));
      expect(speech.said.last, '다시 만나서 반가워요. 저 하늘이에요. 오늘은 뭘 같이 해 볼까요?');
    });
  });
}
