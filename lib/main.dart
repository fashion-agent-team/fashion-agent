import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'agent/agent_controller.dart';
import 'agent/camera_turn.dart';
import 'agent/onboarding_flow.dart';
import 'firebase_options.dart';
import 'screens/agent_screen.dart';
import 'services/account_service.dart';
import 'services/auto_capture.dart';
import 'services/capture_service.dart';
import 'services/fake_vision_service.dart';
import 'services/firebase_account_service.dart';
import 'services/gateway_auth.dart';
import 'services/listen_service.dart';
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
  final speech = SpeechService();
  final listen = DeviceListenService();
  final capture = _fakeCamera ? FakeCaptureService() : CameraCaptureService();
  final profiles = LocalProfileStore();
  final weather = WeatherService();
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
            camera: _fakeCamera
                ? FakeAutoCaptureCamera()
                : DeviceAutoCaptureCamera(),
          ),
    agent: AgentController(
      speech: speech,
      listen: listen,
      profiles: profiles,
      weatherService: weather,
      turns: turns,
      location: location,
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
    ),
  ));
}

class FashionAgentApp extends StatelessWidget {
  const FashionAgentApp(
      {super.key,
      required this.agent,
      required this.outfitCheck,
      this.cameraTurn});

  final AgentController agent;
  final SessionController outfitCheck;
  final CameraTurnController? cameraTurn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '패션 에이전트',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: AgentScreen(
          agent: agent, outfitCheck: outfitCheck, cameraTurn: cameraTurn),
    );
  }
}
