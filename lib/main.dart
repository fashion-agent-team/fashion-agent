import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'agent/agent_controller.dart';
import 'agent/camera_turn.dart';
import 'agent/onboarding_flow.dart';
import 'firebase_options.dart';
import 'screens/agent_screen.dart';
import 'services/account_service.dart';
import 'services/auto_capture.dart';
import 'services/capture_service.dart';
import 'services/cloud_tts.dart';
import 'services/fake_vision_service.dart';
import 'services/firebase_account_service.dart';
import 'services/gateway_auth.dart';
import 'services/listen_service.dart';
import 'services/mouth_finder.dart';
import 'services/permission_service.dart';
import 'services/profile_store.dart';
import 'services/schedule_store.dart';
import 'services/speech_service.dart';
import 'services/turn_api.dart';
import 'services/vision_service.dart';
import 'services/wardrobe_store.dart';
import 'services/weather_service.dart';
import 'session/session_controller.dart';

/// 비전 프록시 주소. 기본은 팀이 배포한 Cloudflare Worker다.
/// 로컬 서버: `flutter run --dart-define=VISION_URL=http://localhost:8787`
const _visionUrl = String.fromEnvironment(
  'VISION_URL',
  defaultValue: 'https://fashion-agent-vision.fashion-agent-team.workers.dev',
);

/// 서버 없이 예시 응답으로 돌릴 때: `--dart-define=FAKE_VISION=true`
const _fakeVision = bool.fromEnvironment('FAKE_VISION');

/// 카메라 없는 시뮬레이터에서 돌릴 때: `--dart-define=FAKE_CAMERA=true`
const _fakeCamera = bool.fromEnvironment('FAKE_CAMERA');

/// 화면을 누르지 않고 에이전트 이름을 불러 말하기. 끄려면 `--dart-define=HANDS_FREE=false`
const _handsFree = bool.fromEnvironment('HANDS_FREE', defaultValue: true);

/// 구글 Cloud TTS 목소리 켜기. 게이트웨이에 GOOGLE_TTS_API_KEY가 있을 때만: `--dart-define=CLOUD_TTS=true`
const _cloudTts = bool.fromEnvironment('CLOUD_TTS');

/// 게이트웨이 주소. 비우면 로그인 없이 이 폰에만 저장한다.
/// 노트북에서 띄운 게이트웨이: `flutter run --dart-define=GATEWAY_URL=http://192.168.0.10:8080`
const _gatewayUrl = String.fromEnvironment('GATEWAY_URL');

/// 게이트웨이와 Firebase가 준비되면 구글 로그인, 아니면 이 폰에만 저장.
Future<(AccountService, GatewayAuth?)> _account() async {
  if (_gatewayUrl.isEmpty) return (DeviceOnlyAccountService(), null);
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } on Object catch (e) {
    debugPrint('Firebase 시작 실패, 이 폰에만 저장합니다: $e');
    return (DeviceOnlyAccountService(), null);
  }
  final gateway =
      GatewayAuth(baseUrl: Uri.parse(_gatewayUrl), tokens: SecureTokenStore());
  return (FirebaseAccountService(gateway: gateway), gateway);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (account, gateway) = await _account();
  // 목소리는 하나로 통일한다(2026-11-09 진행 님). 기본은 폰의 고품질 한국어 목소리.
  // 구글 Cloud TTS 키(카드 등록 필요)를 게이트웨이에 넣었을 때만 `--dart-define=CLOUD_TTS=true`로 구글 목소리를 켠다.
  // Gemini TTS는 무료 횟수가 끝나면 목소리가 바뀌어서 쓰지 않는다.
  final speech = SpeechService(
      cloud: _cloudTts && gateway != null ? GatewayTtsApi(gateway) : null);
  final listen = DeviceListenService();
  final capture = _fakeCamera ? FakeCaptureService() : CameraCaptureService();
  final profiles = LocalProfileStore();
  final weather = WeatherService();
  // 처음 "날씨 알려 줘"에도 바로 답하도록 미리 받아 둔다. 권한 창은 띄우지 않는다.
  unawaited(weather.prefetch());
  final turns = gateway == null ? null : GatewayTurnApi(gateway);
  final location = LocationProvider();
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
            camera: _fakeCamera
                ? FakeAutoCaptureCamera()
                : DeviceAutoCaptureCamera(),
          ),
    heardNow: listen.heardNow,
    agent: AgentController(
      speech: speech,
      listen: listen,
      profiles: profiles,
      weatherService: weather,
      turns: turns,
      location: location,
      handsFree: _handsFree,
      onboarding: OnboardingFlow(
        speech: speech,
        listen: listen,
        profiles: profiles,
        account: account,
        permissions: _fakeCamera
            ? FakePermissionService()
            : DevicePermissionService(listen: listen, camera: capture),
      ),
    ),
    outfitCheck: SessionController(
      speech: speech,
      weatherService: weather,
      schedule: LocalScheduleStore(),
      capture: capture,
      vision: _fakeVision || _visionUrl.isEmpty
          ? FakeVisionService()
          : HttpVisionService(Uri.parse(_visionUrl)),
      wardrobe: LocalWardrobeStore(),
      listen: listen,
    ),
  ));
}

class FashionAgentApp extends StatelessWidget {
  const FashionAgentApp(
      {super.key,
      required this.agent,
      required this.outfitCheck,
      this.cameraTurn,
      this.heardNow});

  final AgentController agent;
  final SessionController outfitCheck;
  final CameraTurnController? cameraTurn;
  final ValueListenable<String>? heardNow;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '패션 에이전트',
      debugShowCheckedModeBanner: false,
      // 심청이 마스코트에 맞춘 색: 다홍(주), 남색(보조), 한지 바탕.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC62F45),
          secondary: const Color(0xFF283A6B),
          surface: const Color(0xFFFFF8EC),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8EC),
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
