import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent/agent_controller.dart';
import 'agent/camera_turn.dart';
import 'agent/onboarding_flow.dart';
import 'firebase_options.dart';
import 'screens/agent_screen.dart';
import 'screens/palette.dart';
import 'services/account_service.dart';
import 'services/auto_capture.dart';
import 'services/capture_service.dart';
import 'services/cloud_tts.dart';
import 'services/fake_vision_service.dart';
import 'services/firebase_account_service.dart';
import 'services/gateway_auth.dart';
import 'services/listen_service.dart';
import 'services/server_stt.dart';
import 'services/face_landmark_finder.dart';
import 'services/mouth_finder.dart';
import 'services/permission_service.dart';
import 'services/profile_store.dart';
import 'services/schedule_reminders.dart';
import 'services/schedule_store.dart';
import 'services/speech_service.dart';
import 'services/turn_api.dart';
import 'services/wardrobe_store.dart';
import 'services/weather_service.dart';
import 'session/session_controller.dart';

/// 서버 없이 예시 응답으로 옷 검사 화면을 돌려 볼 때: `--dart-define=FAKE_VISION=true`
/// 실제 옷 사진은 게이트웨이(`GATEWAY_URL`)로만 보낸다. 예전 Gemini 프록시는 쓰지 않는다(2026-11-10).
const _fakeVision = bool.fromEnvironment('FAKE_VISION');

/// 카메라 없는 시뮬레이터에서 돌릴 때: `--dart-define=FAKE_CAMERA=true`
///
/// 시뮬레이터는 release로 못 돌리므로 release 빌드에서는 무시한다. 2026-11-12 실기기에
/// `flutter run --release ... FAKE_CAMERA=true`로 깔려서 가짜 사진만 보내고 얼굴을 못 찾은 일이 있었다.
const _fakeCamera = bool.fromEnvironment('FAKE_CAMERA') && !kReleaseMode;

/// 화면을 누르지 않고 에이전트 이름을 불러 말하기. 끄려면 `--dart-define=HANDS_FREE=false`
const _handsFree = bool.fromEnvironment('HANDS_FREE', defaultValue: true);

/// 서버 목소리(Azure 유진·지민·서현·순복, 엣지 선희·인준·현수). 게이트웨이가 있으면 기본으로 켠다. 끄려면 `--dart-define=CLOUD_TTS=false`
/// 2026-11-12: 기본이 꺼짐이라 빌드할 때 옵션을 빠뜨리면 폰 목소리 그대로였다. 서버가 안 되면 어차피 폰 목소리로 읽는다.
const _cloudTts = bool.fromEnvironment('CLOUD_TTS', defaultValue: true);

/// 게이트웨이 주소. 비우면 서버 없이 폰 안 기능(날씨 등)만 쓴다. 옷 검사·얼굴 확인은 서버가 있어야 한다.
/// 노트북에서 띄운 게이트웨이: `flutter run --dart-define=GATEWAY_URL=http://192.168.0.10:8080`
const _gatewayUrl = String.fromEnvironment('GATEWAY_URL');

/// 게이트웨이와 Firebase가 준비되면 구글 로그인, 아니면 이 폰에만 저장.
///
/// 로그인하지 않아도(구글 로그인 전, Firebase 실패) 게이트웨이는 쓴다. 개발용 로그인으로 들어가서
/// 로그인한 것과 똑같이 옷 검사·얼굴 확인을 서버로 한다(2026-11-09 정지원).
Future<(AccountService, GatewayAuth?)> _account() async {
  if (_gatewayUrl.isEmpty) return (DeviceOnlyAccountService(), null);
  final gateway = GatewayAuth(
      baseUrl: Uri.parse(_gatewayUrl),
      tokens: SecureTokenStore(),
      devDeviceId: secureDeviceId);
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } on Object catch (e) {
    debugPrint('Firebase 시작 실패, 구글 로그인 없이 게이트웨이를 씁니다: $e');
    return (DeviceOnlyAccountService(), gateway);
  }
  return (FirebaseAccountService(gateway: gateway), gateway);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (account, gateway) = await _account();
  // 목소리는 하나로 통일한다(2026-11-09 진행 님). 기본은 폰의 고품질 한국어 목소리.
  // 게이트웨이가 있으면 유진(Azure)이 기본, 엣지 선희·인준·현수도 고를 수 있다(AZURE_SPEECH_KEY, EDGE_TTS_URL). 끄려면 CLOUD_TTS=false.
  // Gemini TTS는 무료 횟수가 끝나면 목소리가 바뀌어서 쓰지 않는다.
  final speech = SpeechService(
      cloud: _cloudTts && gateway != null ? GatewayTtsApi(gateway) : null);
  // 첫 안내가 폰 목소리로 새지 않게 서버 목소리 연결을 미리 해 둔다.
  unawaited(speech.warmUp());
  final profiles = LocalProfileStore();
  // 부른 뒤 명령과 온보딩 답만 서버(OpenAI) 음성 인식으로 다시 받아 적는다(2026-11-09 진행 님 결정).
  // 게이트웨이에 OPENAI_API_KEY가 없거나 실패하면 폰 음성 인식 글자를 그대로 쓴다.
  final listen = DeviceListenService(
    serverStt: gateway == null ? null : GatewayServerStt(gateway),
    hint: () async => sttHint((await profiles.load())?.agentName),
  );
  final capture = _fakeCamera ? FakeCaptureService() : CameraCaptureService();
  final weather = WeatherService();
  // 처음 "날씨 알려 줘"에도 바로 답하도록 미리 받아 둔다. 권한 창은 띄우지 않는다.
  unawaited(weather.prefetch());
  final turns = gateway == null ? null : GatewayTurnApi(gateway);
  final location = LocationProvider();
  // 일정 전날 저녁·당일 아침 알림. 서버 일정을 받아 폰 안에 예약한다(원격 푸시는 유료 Apple 계정이 필요해서).
  LocalReminderScheduler? reminderScheduler;
  ScheduleReminders? reminders;
  if (gateway != null && !kIsWeb && !_fakeCamera) {
    reminderScheduler = LocalReminderScheduler();
    reminders = ScheduleReminders(
      source: GatewayScheduleSource(gateway),
      scheduler: reminderScheduler,
    );
  }
  final agent = AgentController(
    speech: speech,
    listen: listen,
    profiles: profiles,
    weatherService: weather,
    turns: turns,
    reminders: reminders,
    location: location,
    handsFree: _handsFree,
    onboarding: OnboardingFlow(
      speech: speech,
      listen: listen,
      profiles: profiles,
      account: account,
      permissions: _fakeCamera
          ? FakePermissionService()
          : DevicePermissionService(
              listen: listen,
              camera: capture,
              reminders: reminderScheduler,
            ),
    ),
  );
  // 일정 알림을 누르면 그날 옷 추천으로 바로 시작한다(2026-11-13 진행 님).
  unawaited(reminderScheduler?.listenTaps((day) =>
      unawaited(agent.askFromReminder(reminderAsk(day, DateTime.now())))));
  runApp(FashionAgentApp(
    cameraTurn: turns == null
        ? null
        : CameraTurnController(
            speech: speech,
            listen: listen,
            turns: turns,
            location: location,
            handsFree: _handsFree,
            mouths: _fakeCamera || kIsWeb ? null : MlKitMouthFinder(),
            faces: _fakeCamera || kIsWeb ? null : MlKitFaceLandmarkFinder(),
            camera: _fakeCamera
                ? FakeAutoCaptureCamera()
                : DeviceAutoCaptureCamera(),
          ),
    heardNow: listen.heardNow,
    agent: agent,
    // 서버 없이 쓰는 옷 검사 화면은 데모(FAKE_VISION)일 때만 연다. 진짜 사진 분석은 서버로만 한다.
    outfitCheck: _fakeVision
        ? SessionController(
            speech: speech,
            weatherService: weather,
            schedule: LocalScheduleStore(),
            capture: capture,
            vision: FakeVisionService(),
            wardrobe: LocalWardrobeStore(),
            listen: listen,
          )
        : null,
  ));
}

class FashionAgentApp extends StatelessWidget {
  const FashionAgentApp(
      {super.key,
      required this.agent,
      this.outfitCheck,
      this.cameraTurn,
      this.heardNow});

  final AgentController agent;
  final SessionController? outfitCheck;
  final CameraTurnController? cameraTurn;
  final ValueListenable<String>? heardNow;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '심청이',
      debugShowCheckedModeBanner: false,
      // 2026-11-12 화면 개편 "인당수의 밤": 쪽빛 바탕, 저고리 노랑 글씨(저시력 대비), 글꼴 Gothic A1.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: SeaColors.jeogori,
          brightness: Brightness.dark,
          primary: SeaColors.jeogori,
          onPrimary: SeaColors.sea,
          surface: SeaColors.sea,
          onSurface: SeaColors.hanji,
        ),
        scaffoldBackgroundColor: SeaColors.sea,
        fontFamily: SeaFonts.gothic,
        useMaterial3: true,
      ),
      home: AgentScreen(
          agent: agent,
          outfitCheck: outfitCheck,
          cameraTurn: cameraTurn,
          heardNow: heardNow),
    );
  }
}
