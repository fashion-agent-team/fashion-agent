import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/answer_parsing.dart';
import 'package:fashion_agent/agent/intent_router.dart';
import 'package:fashion_agent/agent/onboarding_flow.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/account_service.dart';
import 'package:fashion_agent/services/listen_service.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeech implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
}

/// 정해 둔 답을 차례로 "듣는다". null은 아무 말도 못 들은 경우다.
class ScriptedListen implements ListenService {
  ScriptedListen(this.answers);

  final List<String?> answers;
  var _i = 0;

  @override
  Future<String?> listen() async => _i < answers.length ? answers[_i++] : null;
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
        {ProfileStore? store, AccountService? account}) =>
    OnboardingFlow(
      speech: speech,
      listen: ScriptedListen(answers),
      profiles: store ?? InMemoryProfileStore(),
      account: account ?? FakeAccount(),
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
    expect(routeIntent('뭐 할 수 있어?'), Intent.help);
    expect(routeIntent('안녕'), Intent.unknown);
  });

  group('온보딩', () {
    const answers = [
      '아니요', // 다른 폰에서 쓴 적 없음
      '하늘', '네', // 에이전트 이름
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
      expect(speech.spoken, contains('말씀해주신 정보를 바탕으로 도와드릴게요.'));
      expect(speech.spoken, contains('지금은 계정 연결 없이 이 폰에만 저장할게요.'));
      expect(speech.spoken.last, '$featureIntro $askFeature');

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

    test('못 들으면 다시 묻는다', () async {
      final speech = FakeSpeech();
      final profile = await onboardingWith(
          speech, ['아니요', null, '하늘', '네', ...answers.skip(3), '네']).run();

      expect(speech.spoken, contains('잘 듣지 못했어요. $askAgentName'));
      expect(profile.agentName, '하늘');
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
      final profile = await onboardingWith(speech, ['네'],
              store: store,
              account: FakeAccount(
                  id: 'uid-1',
                  saved: const UserProfile(name: '김민수', agentName: '하늘')))
          .run();

      expect(profile.agentName, '하늘');
      expect(store.profile?.accountId, 'uid-1');
      expect(speech.spoken.last, startsWith('다시 만나서 반가워요. 저는 하늘이에요.'));
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
          onboarding: onboardingWith(speech, const []),
        );

    test('다시 실행하면 이름을 넣어 인사하고, 날씨를 물으면 일교차도 알려 준다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['오늘 날씨 어때'],
          profile: const UserProfile(agentName: '하늘'));
      await agent.start();

      expect(speech.spoken.first,
          '반갑습니다. 오늘 하루도 좋은 하루 되세요. 당신의 에이전트 하늘입니다. 원하시는 기능 있으시면 말씀해주세요.');
      expect(speech.spoken[1], contains('일교차가 13도로 커요'));
      expect(speech.spoken.last, tapToTalk);
    });

    test('옷 검사를 말하면 옷 검사 화면을 연다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['옷 검사해 줘'],
          profile: const UserProfile(agentName: '하늘'));
      var opened = false;
      agent.openOutfitCheck = () async => opened = true;
      await agent.start();

      expect(opened, isTrue);
      expect(speech.spoken.last, startsWith('옷 검사를 마쳤어요.'));
    });

    test('준비 중인 기능은 그렇다고 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, ['얼굴 좀 봐 줘'],
          profile: const UserProfile(agentName: '하늘'));
      await agent.start();

      expect(speech.spoken, contains('얼굴 확인 기능은 지금 준비 중이에요.'));
    });
  });
}
