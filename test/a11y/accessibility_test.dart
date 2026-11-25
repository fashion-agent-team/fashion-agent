import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/camera_turn.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/screens/agent_screen.dart';
import 'package:fashion_agent/screens/camera_turn_screen.dart';
import 'package:fashion_agent/screens/session_screen.dart';
import 'package:fashion_agent/services/auto_capture.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/agent_fakes.dart'
    show FakeSpeech, FakeWeatherService, ScriptedListen, onboardingWith;
import '../agent/turn_test.dart' show FakeTurnApi, here;
import '../session/session_controller_test.dart' as session;

/// 접근성 검사. 이 앱은 시각장애인이 VoiceOver·TalkBack으로 쓰므로 화면마다 아래 네 가지를 자동으로 확인한다.
///
/// 1. 누를 수 있는 것에는 모두 읽을 이름이 있다(labeledTapTargetGuideline).
/// 2. 누르는 곳이 충분히 크다: iOS 44×44, Android 48×48 이상(iOS/androidTapTargetGuideline).
/// 3. 글씨와 바탕의 명암비가 WCAG AA(작은 글씨 4.5:1, 큰 글씨 3:1) 이상이다(textContrastGuideline).
///    저시력 사용자나 옆에서 돕는 분이 화면을 볼 때를 위해서다.
/// 4. 글씨를 크게(시스템 글씨 크기 200%, 300%) 해도 작은 폰에서 화면이 넘치거나 깨지지 않는다.
///    iOS '더 큰 텍스트'를 끝까지 올리면 300% 남짓이다.
///
/// 마스코트가 계속 움직여서 pumpAndSettle은 끝나지 않으므로 정해진 시간만큼 pump한다.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 화면 하나에 접근성 기준 네 가지를 모두 건다.
  Future<void> expectAccessible(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  /// 시스템 글씨 크기를 [scale]배로 한 앱.
  Widget app(Widget home, {double scale = 1}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: home,
          ),
        ),
      );

  /// 작은 폰(iPhone SE, 375×667 논리 픽셀) 크기로 그린다.
  void smallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  group('첫 화면(AgentScreen)', () {
    const profile = UserProfile(agentName: '하늘', consent: consentVersion);

    AgentController agentWith(FakeSpeech speech) => AgentController(
          speech: speech,
          listen: ScriptedListen(const []),
          profiles: InMemoryProfileStore(profile),
          weatherService: FakeWeatherService(),
          onboarding: onboardingWith(speech, const [], consentFirst: false),
        );

    testWidgets('기다리는 중: 이름·크기·명암비 기준을 지킨다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(AgentScreen(agent: agentWith(FakeSpeech()))));
      await settle(tester);

      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('듣는 중(다홍 바탕): 이름·크기·명암비 기준을 지킨다', (tester) async {
      final handle = tester.ensureSemantics();
      final agent = agentWith(FakeSpeech());
      await tester.pumpWidget(app(AgentScreen(agent: agent)));
      await settle(tester);
      agent.phase = AgentPhase.listening;
      agent.notifyListeners();
      await settle(tester);

      expect(find.text('듣고 있어요'), findsOneWidget);
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('VoiceOver로 읽히는 것은 "말하기"와 "다시 듣기" 두 버튼뿐이다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(AgentScreen(agent: agentWith(FakeSpeech()))));
      await settle(tester);

      final talk = tester.getSemantics(find.bySemanticsLabel('말하기'));
      expect(talk.flagsCollection.isButton, isTrue);
      final repeat = tester.getSemantics(find.bySemanticsLabel('다시 듣기'));
      expect(repeat.flagsCollection.isButton, isTrue);
      // 마스코트(꾸밈 그림)는 읽지 않는다.
      expect(find.bySemanticsLabel(RegExp('마스코트|그림')), findsNothing);
      handle.dispose();
    });

    for (final scale in [2.0, 3.0]) {
      testWidgets('글씨 ${(scale * 100).round()}%·작은 폰에서도 넘치지 않는다',
          (tester) async {
        smallPhone(tester);
        await tester.pumpWidget(
            app(AgentScreen(agent: agentWith(FakeSpeech())), scale: scale));
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('다시 듣기'), findsOneWidget);
      });
    }
  });

  group('카메라 화면(CameraTurnScreen)', () {
    CameraTurnController controllerWith(FakeAutoCaptureCamera camera) =>
        CameraTurnController(
          speech: FakeSpeech(),
          listen: ScriptedListen(const []),
          turns: FakeTurnApi(const []),
          camera: camera,
          location: here,
        );

    for (final kind in [ImageKind.outfit, ImageKind.face]) {
      testWidgets('${kind.name}: 이름·크기·명암비 기준을 지킨다', (tester) async {
        final handle = tester.ensureSemantics();
        final camera = FakeAutoCaptureCamera();
        final c = controllerWith(camera)..kind = kind;
        await tester
            .pumpWidget(app(CameraTurnScreen(controller: c, camera: camera)));
        await settle(tester);

        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('"그만하기"는 VoiceOver에서 버튼으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera)..kind = ImageKind.outfit;
      await tester
          .pumpWidget(app(CameraTurnScreen(controller: c, camera: camera)));
      await settle(tester);

      final stop = tester.getSemantics(find.bySemanticsLabel(RegExp('그만하기')));
      expect(stop.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    for (final scale in [2.0, 3.0]) {
      testWidgets('글씨 ${(scale * 100).round()}%·작은 폰에서도 넘치지 않는다',
          (tester) async {
        smallPhone(tester);
        final camera = FakeAutoCaptureCamera();
        final c = controllerWith(camera)..kind = ImageKind.outfit;
        await tester.pumpWidget(
            app(CameraTurnScreen(controller: c, camera: camera), scale: scale));
        await settle(tester);

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('옷 검사 화면(SessionScreen, 데모)', () {
    testWidgets('이름·크기·명암비 기준을 지킨다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(app(SessionScreen(controller: session.controllerWith())));
      await tester.pumpAndSettle();

      await expectAccessible(tester);
      handle.dispose();
    });

    for (final scale in [2.0, 3.0]) {
      testWidgets('글씨 ${(scale * 100).round()}%·작은 폰에서도 넘치지 않는다',
          (tester) async {
        smallPhone(tester);
        await tester.pumpWidget(app(
            SessionScreen(controller: session.controllerWith()),
            scale: scale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
