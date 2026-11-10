import 'dart:async';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/answer_parsing.dart';
import 'package:fashion_agent/agent/intent_router.dart';
import 'package:fashion_agent/agent/onboarding_flow.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/account_service.dart';
import 'package:fashion_agent/services/listen_service.dart';
import 'package:fashion_agent/services/permission_service.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_speech_extras.dart';

class FakeSpeech with FakeSpeechExtras implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  int stops = 0;

  @override
  bool get speaking => false;

  @override
  Future<void> stop() async => stops++;
}

/// 정해 둔 답을 차례로 "듣는다". null은 아무 말도 못 들은 경우다.
class ScriptedListen implements ListenService {
  ScriptedListen(this.answers, {this.blockWhenDone = false});

  final List<String?> answers;

  /// 답이 다 떨어지면 null 대신 [cancel]될 때까지 기다린다. 계속 듣는 흐름을 시험할 때.
  final bool blockWhenDone;
  var _i = 0;
  Completer<String?>? _waiting;
  int cancels = 0;

  bool get waiting => _waiting != null && !_waiting!.isCompleted;

  @override
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 15),
    Duration pauseFor = const Duration(seconds: 3),
    Duration waitFor = const Duration(seconds: 8),
    bool Function(String partial)? stopWhen,
    Duration settle = const Duration(milliseconds: 700),
    bool server = false,
  }) async {
    if (_i < answers.length) return answers[_i++];
    if (!blockWhenDone) return null;
    return (_waiting = Completer<String?>()).future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final w = _waiting;
    if (w != null && !w.isCompleted) w.complete(null);
  }
}

class FakeAccount implements AccountService {
  FakeAccount({this.id, this.saved});

  final String? id;
  final UserProfile? saved;
  UserProfile? uploaded;

  @override
  Future<String?> signIn() async => id;

  @override
  Future<UserProfile?> restore(String accountId) async => saved;

  @override
  Future<void> upload(String accountId, UserProfile profile) async =>
      uploaded = profile;
}

class FakeWeatherService implements WeatherService {
  @override
  Future<Weather> fetchTodayWeather() async => const Weather(
        temperature: 15,
        apparentTemperature: 14,
        minTemperature: 5,
        maxTemperature: 18,
        weatherCode: 0,
        precipitationProbability: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OnboardingFlow onboardingWith(FakeSpeech speech, List<String?> answers,
        {ProfileStore? store,
        AccountService? account,
        PermissionService? permissions,
        bool consentFirst = true}) =>
    OnboardingFlow(
      speech: speech,
      // 처음 켤 때 말 빠르기부터 묻는다(허용하면 동의, 음성 동의는 없음).
      listen: ScriptedListen([if (consentFirst) '괜찮아', ...answers]),
      profiles: store ?? InMemoryProfileStore(),
      account: account ?? FakeAccount(),
      permissions: permissions,
    );

void main() {
  group('답 읽기', () {
    test('네/아니요', () {
      expect(parseYesNo('네 맞아요'), isTrue);
      expect(parseYesNo('응'), isTrue);
      expect(parseYesNo('아니요'), isFalse);
      expect(parseYesNo('다시 할게요'), isFalse);
      expect(parseYesNo('글쎄'), isNull);
    });

    test('생년월일은 여러 말투를 받는다', () {
      final today = DateTime(2026, 10, 30);
      for (final said in [
        '1990년 3월 5일',
        '1990.3.5',
        '1990-03-05',
        '19900305',
        '천구백구십년 삼월 오일',
        '구십년 삼월 오일',
      ]) {
        expect(parseBirthDate(said, today: today), DateTime(1990, 3, 5),
            reason: said);
      }
      expect(parseBirthDate('2030년 1월 1일', today: today), isNull);
      expect(parseBirthDate('1990년 2월 30일', today: today), isNull);
    });

    test('키·몸무게는 숫자나 한글 수로 받는다', () {
      expect(parseMeasure('백칠십 센티요', min: 80, max: 230), 170);
      expect(parseMeasure('62.5킬로', min: 20, max: 250), 62.5);
      expect(parseMeasure('3', min: 80, max: 230), isNull);
    });

    test('이름·성별·직업', () {
      expect(parseName('제 이름은 김민수예요'), '김민수');
      expect(parseName('하늘이라고 불러줘'), '하늘');
      expect(parseGender('남자요'), '남성');
      expect(parseGender('여성입니다'), '여성');
      expect(parseJob('저는 회사원이에요'), '회사원');
      expect(isSkip('건너뛸게요'), isTrue);
    });
  });

  test('말에서 기능을 고른다', () {
    expect(routeIntent('오늘 일정 알려 줘'), Intent.schedule);
    expect(routeIntent('오늘 날씨 어때'), Intent.weather);
    expect(routeIntent('겉옷 챙겨야 해?'), Intent.weather);
    expect(routeIntent('날씨에 맞게 입었는지 옷 검사해 줘'), Intent.outfitCheck);
    expect(routeIntent('이에 뭐 꼈는지 봐 줘'), Intent.faceCheck);
    // 2026-11-09 리허설: "옷 검사"가 얼굴 확인으로 넘어갔다.
    expect(routeIntent('옷검사 해 줘'), Intent.outfitCheck);
    expect(routeIntent('머리부터 옷 검사해 줘'), Intent.outfitCheck);
    expect(routeIntent('머리 정돈됐는지 봐 줘'), Intent.faceCheck);
    expect(routeIntent('뭐 할 수 있어?'), Intent.help);
    expect(routeIntent('안녕'), Intent.unknown);
  });

  group('온보딩', () {
    const answers = [
      '하늘', '네', // 에이전트 이름
      '아니요', // 다른 폰에서 쓴 적 없음
      '김민수예요', '1990년 3월 5일', '남자', '회사원이에요', '170', '건너뛰기',
    ];

    test('인사 → 이름 짓기 → 정보 → 재확인 → 기능 설명 순서로 묻고 저장한다', () async {
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();
      final profile =
          await onboardingWith(speech, [...answers, '네'], store: store).run();

      expect(speech.spoken.first, firstGreeting);
      expect(speech.spoken, contains(startsWith('좋아요, 이제 제 이름은 하늘이에요.')));
      expect(
          speech.spoken,
          contains('말씀해주신 정보를 읽어 드릴게요. 이름 김민수, 생년월일 1990년 3월 5일, '
              '성별 남성, 직업 회사원, 키 170센티미터, 몸무게 건너뜀. 말씀해주신 정보와 일치할까요?'));
      expect(speech.spoken, contains('알려 주셔서 고마워요. 이제 더 잘 맞춰서 도와드릴게요.'));
      expect(speech.spoken, contains('지금은 계정 연결 없이 이 폰에만 저장할게요.'));
      expect(speech.spoken.last, '$featureIntro $homeHint $askFeature');

      expect(profile.agentName, '하늘');
      expect(profile.birthDate, DateTime(1990, 3, 5));
      expect(profile.weightKg, isNull);
      expect(store.profile?.name, '김민수');
    });

    test('틀렸다고 하면 고칠 항목만 다시 묻는다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(
          speech, [...answers, '아니요', '키가 틀렸어', '175', '네']).run();

      expect(profile.heightCm, 175);
      expect(profile.name, '김민수');
      expect(speech.spoken.where((s) => s.contains('일치할까요')).length, 2);
    });

    test('재확인에 대답을 못 알아들으면 맞다고 치지 않고 다시 묻는다', () async {
      final speech = FakeSpeech();
      await onboardingWith(speech, [...answers, '음', '음', '음', '네']).run();
      expect(speech.spoken.where((s) => s.contains('일치할까요')).length, 4);
    });

    test('이름에 대답이 없으면 심청이로 정한다', () async {
      final speech = FakeSpeech();
      final profile =
          await onboardingWith(speech, [null, ...answers.skip(2), '네']).run();

      expect(speech.spoken, contains(keepAgentName));
      expect(profile.agentName, '심청이');
    });

    test('"좋아"라고 하면 심청이 그대로, 비슷한 이름은 맞는지 묻는다', () async {
      final keep =
          await onboardingWith(FakeSpeech(), ['좋아', ...answers.skip(2), '네'])
              .run();
      expect(keep.agentName, '심청이');

      final speech = FakeSpeech();
      final guessed =
          await onboardingWith(speech, ['신청이', '네', ...answers.skip(2), '네'])
              .run();
      expect(speech.spoken, contains('제 이름이 심청이, 맞나요?'));
      expect(guessed.agentName, '심청이');
    });

    test('허용하면 동의로 보고, 음성으로 동의를 묻지 않는다', () async {
      final speech = FakeSpeech();
      final permissions = FakePermissionService();
      final profile = await onboardingWith(speech, [...answers, '네'],
              permissions: permissions)
          .run();

      expect(permissions.requests, 1);
      expect(profile.consented, isTrue);
      expect(speech.spoken.take(8), [
        firstGreeting,
        consentIntro,
        permissionIntro,
        permissionThanks,
        speedQuestion,
        askAgentName,
        '제 이름이 하늘, 맞나요?',
        '좋아요, 이제 제 이름은 하늘이에요.',
      ]);
      expect(speech.spoken[8], startsWith('혹시 다른 폰에서'));
    });

    test('"천천히"라고 하면 느리게 바꾸고 다시 묻는다', () async {
      final speech = FakeSpeech();
      final flow = OnboardingFlow(
        speech: speech,
        listen: ScriptedListen(['너무 빨라 천천히', '괜찮아', ...answers, '네']),
        profiles: InMemoryProfileStore(),
        account: FakeAccount(),
      );
      await flow.run();
      expect(speech.rate, lessThan(SpeechService.speechRate));
      expect(speech.spoken, contains(speedChanged));
      expect(parseSpeed('괜찮아요'), 0);
      expect(parseSpeed('더 빠르게'), 1);
      expect(speedCommand('천천히 말해 줘'), -1);
      expect(speedCommand('말 좀 빠르게 해 줘'), 1);
      expect(speedCommand('빨리 옷 추천해 줘'), isNull);
      expect(isRepeatRequest('다시 말해 줘'), isTrue);
      expect(isRepeatRequest('뭐라고?'), isTrue);
      expect(isRepeatRequest('다시 찍어 줘'), isFalse);
    });

    test('마이크를 막으면 들을 수 없다고 알려 준다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(speech, [...answers, '네'],
              permissions: FakePermissionService(canListen: false))
          .run();

      expect(speech.spoken.last, permissionDeniedListen);
      expect(profile.isOnboarded, isFalse);
    });

    test('계정에 연결되면 정보를 올린다', () async {
      final account = FakeAccount(id: 'uid-1');
      final profile = await onboardingWith(FakeSpeech(), [...answers, '네'],
              account: account)
          .run();

      expect(profile.accountId, 'uid-1');
      expect(account.uploaded?.agentName, '하늘');
    });

    test('다른 폰에서 쓰던 계정이 있으면 이어서 쓴다', () async {
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();
      final profile = await onboardingWith(speech, ['좋아', '네'],
              store: store,
              account: FakeAccount(
                  id: 'uid-1',
                  saved: const UserProfile(
                      name: '김민수', agentName: '하늘', consent: consentVersion)))
          .run();

      expect(profile.agentName, '하늘');
      expect(store.profile?.accountId, 'uid-1');
      expect(speech.spoken.last, startsWith('다시 만나서 정말 반가워요. 저는 하늘이에요.'));
    });
  });

  group('에이전트', () {
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
      final agent = agentWith(speech, ['오늘 날씨 어때'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion));
      await agent.start();

      expect(
          speech.spoken.first,
          '반가워요. 저 하늘이에요. 오늘도 같이 준비해 봐요. '
          '$homeHint 필요한 게 있으면 편하게 말씀해 주세요.');
      expect(speech.spoken[1], contains('일교차가 13도로 커요'));
      expect(speech.spoken.last, tapToTalk);
    });

    test('옷 검사를 말하면 옷 검사 화면을 연다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['옷 검사해 줘'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion));
      var opened = false;
      agent.openOutfitCheck = () async => opened = true;
      await agent.start();

      expect(opened, isTrue);
      expect(speech.spoken.last, startsWith('옷 다 봤어요.'));
    });

    test('서버 없이 옷 검사를 말하면 예전 프록시로 보내지 않고 서버가 필요하다고 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['옷 검사해 줘'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion));
      await agent.start();

      expect(speech.spoken, contains(noServerOutfitSpeech));
    });

    test('준비 중인 기능은 그렇다고 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['얼굴 좀 봐 줘'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion));
      await agent.start();

      expect(speech.spoken, contains('얼굴 확인 기능은 지금 준비 중이에요.'));
    });
  });

  group('말로 설정 바꾸기', () {
    test('"첫 화면"을 알아듣는다', () {
      expect(isHomeCommand('첫 화면'), isTrue);
      expect(isHomeCommand('첫화면으로 가 줘'), isTrue);
      expect(isHomeCommand('처음 화면'), isTrue);
      expect(isHomeCommand('오늘 날씨 어때'), isFalse);
    });

    test('설정 말을 고른다', () {
      expect(routeSetting('네 이름 바꿔 줘'), Setting.agentName);
      expect(routeSetting('이름을 코디로 바꿔 줘'), Setting.agentName);
      expect(routeSetting('에이전트 이름 변경'), Setting.agentName);
      expect(routeSetting('나를 진행 님이라고 불러 줘'), Setting.callName);
      expect(routeSetting('호칭 바꿔 줘'), Setting.callName);
      expect(routeSetting('저를 어떻게 부를지 정하고 싶어'), Setting.callName);
      expect(routeSetting('내 키 바꿔 줘'), Setting.profile);
      expect(routeSetting('제 정보 수정할래'), Setting.profile);
      expect(routeSetting('생일 바꿔 줘'), Setting.profile);
      expect(routeSetting('내 정보 알려 줘'), Setting.readProfile);
      expect(routeSetting('오늘 뭐 입지'), isNull);
      expect(routeSetting('날씨 어때'), isNull);
      expect(routeSetting('옷 바꿔 입을까'), isNull);
      expect(routeSetting('내 키에 맞는 옷 골라 줘'), isNull);
      expect(routeSetting('오늘 날씨에 친구 불러도 될까'), isNull);
      expect(routeSetting('이 옷 이름이 뭐야'), isNull);
    });

    test('말에서 새 이름·호칭을 꺼낸다', () {
      expect(newNameIn('이름을 코디로 바꿔 줘'), '코디');
      expect(newNameIn('네 이름 하늘이라고 해'), '하늘');
      expect(newNameIn('네 이름 바꿔 줘'), isNull);
      expect(newCallNameIn('나를 진행 님이라고 불러 줘'), '진행 님');
      expect(newCallNameIn('저를 대표님으로 불러 주세요'), '대표님');
      expect(newCallNameIn('호칭 바꿔 줘'), isNull);
      expect(parseCallName('진행 님이요'), '진행 님');
      expect(parseCallName('그냥 진행이라고 불러'), '그냥 진행');
    });

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

    test('첫 화면에서 "첫 화면"이라고 하면 처음부터 듣는다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['첫 화면', '날씨 어때'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion));
      await agent.start();
      expect(speech.spoken, contains('첫 화면이에요. $askFeature'));
      expect(speech.spoken, contains(contains('일교차')));
    });

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
          profile: before,
          answers: ['코디', '네'],
          store: store,
          account: account);
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
      final store = InMemoryProfileStore(
          const UserProfile(agentName: '하늘', consent: consentVersion));
      final agent = agentWith(speech, ['나를 진행 님이라고 불러 줘'],
          profile: const UserProfile(agentName: '하늘', consent: consentVersion),
          answers: ['응'],
          store: store);
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

    test('온보딩에서 호칭을 묻는다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(speech, [
        '하늘', '네', '아니요', //
        '이진행이요', '건너뛰기', '건너뛰기', '건너뛰기', '건너뛰기', '건너뛰기', '네',
        '진행 님', '네',
      ]).run();

      expect(speech.spoken, contains('제가 어떻게 불러 드릴까요? 예를 들어 진행 님처럼 말씀해 주세요.'));
      expect(profile.callName, '진행 님');
    });
  });
}
