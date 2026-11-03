import 'package:flutter/material.dart';

import 'agent/agent_controller.dart';
import 'agent/onboarding_flow.dart';
import 'screens/agent_screen.dart';
import 'services/account_service.dart';
import 'services/capture_service.dart';
import 'services/fake_vision_service.dart';
import 'services/listen_service.dart';
import 'services/profile_store.dart';
import 'services/speech_service.dart';
import 'services/vision_service.dart';
import 'services/wardrobe_store.dart';
import 'services/weather_service.dart';
import 'session/session_controller.dart';

/// 프록시 주소. 비어 있으면 가짜 비전 AI로 돈다.
/// 예: `flutter run --dart-define=VISION_URL=https://example.workers.dev`
const _visionUrl = String.fromEnvironment('VISION_URL');

/// 카메라 없는 시뮬레이터에서 돌릴 때: `--dart-define=FAKE_CAMERA=true`
const _fakeCamera = bool.fromEnvironment('FAKE_CAMERA');

void main() {
  final speech = SpeechService();
  final listen = DeviceListenService();
  final profiles = LocalProfileStore();
  final weather = WeatherService();
  runApp(FashionAgentApp(
    agent: AgentController(
      speech: speech,
      listen: listen,
      profiles: profiles,
      weatherService: weather,
      onboarding: OnboardingFlow(
        speech: speech,
        listen: listen,
        profiles: profiles,
        // TODO(계정 담당): docs/ACCOUNT.md대로 Firebase를 붙인 뒤 FirebaseAccountService로 바꾼다.
        account: DeviceOnlyAccountService(),
      ),
    ),
    outfitCheck: SessionController(
      speech: speech,
      weatherService: weather,
      capture: _fakeCamera ? FakeCaptureService() : CameraCaptureService(),
      vision: _visionUrl.isEmpty
          ? FakeVisionService()
          : HttpVisionService(Uri.parse(_visionUrl)),
      wardrobe: LocalWardrobeStore(),
    ),
  ));
}

class FashionAgentApp extends StatelessWidget {
  const FashionAgentApp(
      {super.key, required this.agent, required this.outfitCheck});

  final AgentController agent;
  final SessionController outfitCheck;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '패션 에이전트',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: AgentScreen(agent: agent, outfitCheck: outfitCheck),
    );
  }
}
