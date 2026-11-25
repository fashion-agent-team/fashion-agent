import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/onboarding_flow.dart';
import 'package:fashion_agent/services/account_service.dart';
import 'package:fashion_agent/services/permission_service.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/turn_api.dart';

import 'fake_account.dart';
import 'fake_listen.dart';
import 'fake_speech.dart';
import 'fake_turn_api.dart';
import 'fake_weather.dart';

/// 처음 켤 때 앱이 먼저 묻는 두 가지(말 빠르기 괜찮은지, 동의)에 "괜찮아"로 답한 말.
const consentAnswers = ['괜찮아', '괜찮아'];

/// 온보딩에서 흔히 하는 대답: 에이전트 이름 "하늘"로 정하고, 내 정보를 말한다(몸무게는 건너뜀).
/// 뒤에 재확인 대답('네' 등)을 붙여 쓴다.
const sampleAnswers = [
  '하늘', '네', // 에이전트 이름
  '김민수예요', '1990년 3월 5일', '남자', '회사원이에요', '170', '건너뛰기',
];

/// [answers]를 차례로 듣는 온보딩. [consentFirst]면 [consentAnswers]를 앞에 붙인다.
OnboardingFlow onboardingWith(FakeSpeech speech, List<String?> answers,
        {ProfileStore? store,
        AccountService? account,
        PermissionService? permissions,
        bool consentFirst = true}) =>
    OnboardingFlow(
      speech: speech,
      listen: ScriptedListen([
        if (consentFirst) ...consentAnswers,
        ...answers,
      ]),
      profiles: store ?? InMemoryProfileStore(),
      account: account ?? FakeAccount(),
      permissions: permissions,
    );

/// 부산(35.1, 129.0)에 있다고 알려 주는 위치.
final busanLocation =
    LocationProvider(read: () async => const TurnLocation(35.1, 129.0));

/// 온보딩이 끝난 상태에서 서버 대화([turns])로 움직이는 에이전트.
AgentController agentWith(FakeSpeech speech, FakeTurnApi turns,
        {List<String?> heard = const []}) =>
    AgentController(
      speech: speech,
      listen: ScriptedListen(heard),
      profiles: InMemoryProfileStore(),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: turns,
      location: busanLocation,
    );

/// 지금 쌓인 비동기 일을 한 바퀴 돌린다.
Future<void> settle() => Future<void>.delayed(Duration.zero);
