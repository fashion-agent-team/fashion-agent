import 'dart:ui' as ui;

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/camera_turn.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/screens/agent_screen.dart';
import 'package:fashion_agent/screens/camera_turn_screen.dart';
import 'package:fashion_agent/screens/mascot.dart';
import 'package:fashion_agent/screens/palette.dart';
import 'package:fashion_agent/services/auto_capture.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../agent/agent_test.dart'
    show FakeSpeech, FakeWeatherService, ScriptedListen, onboardingWith;
import '../agent/turn_test.dart' show FakeTurnApi, here;

/// 화면(위젯) 테스트. 마스코트가 계속 움직여서 pumpAndSettle은 끝나지 않으므로 정해진 시간만큼 pump한다.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('첫 화면(AgentScreen)', () {
    AgentController agentWith(FakeSpeech speech, {UserProfile? profile}) =>
        AgentController(
          speech: speech,
          listen: ScriptedListen(const []),
          profiles: InMemoryProfileStore(profile),
          weatherService: FakeWeatherService(),
          onboarding: onboardingWith(speech, const [], consentFirst: false),
        );

    const profile = UserProfile(agentName: '하늘', consent: consentVersion);

    testWidgets('처음 그리면 에이전트가 먼저 말을 걸고, 이름·상태·마지막 안내·다시 듣기를 보여 준다',
        (tester) async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, profile: profile);

      await tester.pumpWidget(MaterialApp(home: AgentScreen(agent: agent)));
      await settle(tester);

      expect(speech.spoken, isNotEmpty, reason: '버튼을 누르지 않아도 먼저 말한다');
      expect(find.text('하늘'), findsOneWidget);
      expect(find.text('화면을 눌러 말씀해 주세요'), findsOneWidget);
      expect(find.text('다시 듣기'), findsOneWidget);
      expect(agent.message, isNotEmpty);
      expect(find.text(agent.message), findsOneWidget);
      expect(find.byType(MascotView), findsOneWidget);
    });

    testWidgets('다시 듣기를 누르면 마지막 안내를 한 번 더 읽는다', (tester) async {
      final speech = FakeSpeech();
      final agent = agentWith(speech, profile: profile);
      await tester.pumpWidget(MaterialApp(home: AgentScreen(agent: agent)));
      await settle(tester);
      final before = speech.spoken.length;

      await tester.tap(find.text('다시 듣기'));
      await settle(tester);

      expect(speech.spoken.length, greaterThan(before));
      expect(speech.spoken.last, contains(agent.message.split('.').first));
    });

    testWidgets('VoiceOver: 위쪽 큰 영역은 "말하기" 버튼 하나로 읽히고 긴 안내는 읽지 않는다',
        (tester) async {
      final handle = tester.ensureSemantics();
      final agent = agentWith(FakeSpeech(), profile: profile);
      await tester.pumpWidget(MaterialApp(home: AgentScreen(agent: agent)));
      await settle(tester);

      expect(find.bySemanticsLabel('말하기'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('말하기'));
      expect(node.hint, '두 번 탭하면 말씀하실 수 있어요.');
      expect(node.label, isNot(contains(agent.message)));
      expect(find.bySemanticsLabel('다시 듣기'), findsOneWidget);
      handle.dispose();
    });
  });

  group('VoiceOver 이름·힌트', () {
    test('상태마다 이름이 다르다', () {
      expect(semanticsLabelFor(AgentPhase.idle), '말하기');
      expect(semanticsLabelFor(AgentPhase.listening), '듣는 중');
      expect(semanticsLabelFor(AgentPhase.thinking), '알아보는 중');
      expect(semanticsLabelFor(AgentPhase.speaking), '말하는 중');
    });

    test('누르면 되는 일만 힌트로 읽고, 알아보는 중·듣는 중·바쁠 때는 읽지 않는다', () {
      expect(semanticsHintFor(AgentPhase.idle, busy: false),
          '두 번 탭하면 말씀하실 수 있어요.');
      expect(semanticsHintFor(AgentPhase.idle, busy: true), isNull);
      expect(
          semanticsHintFor(AgentPhase.speaking, busy: true), '두 번 탭하면 말을 멈춰요.');
      expect(semanticsHintFor(AgentPhase.thinking, busy: true), isNull);
      expect(semanticsHintFor(AgentPhase.listening, busy: true), isNull);
    });
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

    testWidgets('안내가 없으면 "멈추면 알아서 찍어요", 옷이면 진행 막대, 그만하기 버튼', (tester) async {
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera)..kind = ImageKind.outfit;

      await tester.pumpWidget(
          MaterialApp(home: CameraTurnScreen(controller: c, camera: camera)));

      expect(find.text('멈추면 알아서 찍어요'), findsOneWidget);
      expect(find.text('그만하기'), findsOneWidget);
      expect(find.text('돕는 분이 보는 화면'), findsOneWidget);
      // 진행 막대 세 칸
      expect(find.byType(AnimatedContainer), findsNWidgets(3));
    });

    testWidgets('안내는 첫 문장을 크게(마침표 빼고), 나머지를 작게 나눠 쓴다', (tester) async {
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera)
        ..message = '한 걸음 뒤로 가 주세요. 발끝까지 보이면 찍을게요.';

      await tester.pumpWidget(
          MaterialApp(home: CameraTurnScreen(controller: c, camera: camera)));

      expect(find.text('한 걸음 뒤로 가 주세요'), findsOneWidget);
      expect(find.text('발끝까지 보이면 찍을게요.'), findsOneWidget);
    });

    testWidgets('얼굴·이는 한 장이라 진행 막대가 없다', (tester) async {
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera)..kind = ImageKind.face;

      await tester.pumpWidget(
          MaterialApp(home: CameraTurnScreen(controller: c, camera: camera)));

      expect(find.byType(AnimatedContainer), findsNothing);
    });

    testWidgets('확인 중이면 "확인 중이에요"이고 VoiceOver 이름도 "확인 중"(힌트 없음)',
        (tester) async {
      final handle = tester.ensureSemantics();
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera)..busy = true;

      await tester.pumpWidget(
          MaterialApp(home: CameraTurnScreen(controller: c, camera: camera)));

      expect(find.text('확인 중이에요'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('확인 중'));
      expect(node.hint, isEmpty);
      handle.dispose();
    });

    testWidgets('카메라 대화 중 그만하기를 누르면 카메라를 끄고 끝낸다', (tester) async {
      final camera = FakeAutoCaptureCamera();
      final c = controllerWith(camera);
      late Future<TurnReply?> end;
      await tester.runAsync(() async {
        end = c.run('s_1', ImageKind.outfit);
      });

      await tester.pumpWidget(
          MaterialApp(home: CameraTurnScreen(controller: c, camera: camera)));
      await tester.tap(find.text('그만하기'));
      await tester.runAsync(() async {
        expect(await end, isNull);
      });

      expect(camera.closed, isTrue);
    });
  });

  group('splitGuide', () {
    test('첫 문장과 나머지로 나누고 첫 문장 마침표는 뺀다', () {
      expect(
          splitGuide('폰을 조금 왼쪽으로. 그대로 있어 주세요.'), ('폰을 조금 왼쪽으로', '그대로 있어 주세요.'));
    });

    test('물음표·느낌표는 남긴다', () {
      expect(splitGuide('다 보이나요? 좋아요!'), ('다 보이나요?', '좋아요!'));
    });

    test('한 문장이면 나머지는 빈 글자', () {
      expect(splitGuide('  멈추면 찍어요.  '), ('멈추면 찍어요', ''));
      expect(splitGuide('마침표 없음'), ('마침표 없음', ''));
    });

    test('소수점(1.5배)은 문장 끝으로 보지 않는다', () {
      expect(splitGuide('1.5배 줌이에요. 다시 찍을게요.'), ('1.5배 줌이에요', '다시 찍을게요.'));
    });
  });

  group('마스코트·바탕 그림', () {
    testWidgets('네 상태 모두 그려지고, 화면 읽기에서는 빠진다', (tester) async {
      final handle = tester.ensureSemantics();
      for (final phase in AgentPhase.values) {
        await tester.pumpWidget(MaterialApp(
            home: Center(child: MascotView(phase: phase, size: 180))));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: '$phase');
        expect(tester.getSize(find.byType(MascotView)),
            const Size(180, 180 * 1.12));
      }
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      handle.dispose();
    });

    test('MascotPainter는 시간이 바뀌면 다시 그리고 같으면 다시 그리지 않는다', () {
      final a = MascotPainter(phase: AgentPhase.idle, t: 1);
      expect(a.shouldRepaint(MascotPainter(phase: AgentPhase.idle, t: 1)),
          isFalse);
      expect(
          a.shouldRepaint(MascotPainter(phase: AgentPhase.idle, t: 2)), isTrue);
      expect(a.shouldRepaint(MascotPainter(phase: AgentPhase.listening, t: 1)),
          isTrue);
      // 0~6초 내내 예외 없이 그린다.
      for (var t = 0.0; t <= 6; t += 0.5) {
        for (final phase in AgentPhase.values) {
          final rec = ui.PictureRecorder();
          MascotPainter(phase: phase, t: t)
              .paint(Canvas(rec), const Size(220, 246));
          rec.endRecording().dispose();
        }
      }
    });

    testWidgets('SlabButton: 누르면 부르고, onPressed가 없으면 꺼진 버튼으로 읽힌다',
        (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Column(children: [
        SlabButton(
            label: '켜짐',
            icon: Icons.replay_rounded,
            onPressed: () => taps++,
            background: SeaColors.jeogori,
            foreground: SeaColors.sea),
        const SlabButton(
            label: '꺼짐',
            icon: Icons.stop_rounded,
            onPressed: null,
            background: SeaColors.hanji,
            foreground: SeaColors.sea),
        const WaveEdge(color: SeaColors.deep),
      ])));

      await tester.tap(find.text('켜짐'));
      await tester.tap(find.text('꺼짐'), warnIfMissed: false);
      expect(taps, 1);
      expect(tester.getSemantics(find.bySemanticsLabel('꺼짐')),
          matchesSemantics(label: '꺼짐', isButton: true, hasEnabledState: true));
      expect(
          tester.getSemantics(find.bySemanticsLabel('켜짐')),
          matchesSemantics(
              label: '켜짐',
              isButton: true,
              hasEnabledState: true,
              isEnabled: true));
      handle.dispose();
    });
  });
}
