import 'package:fashion_agent/models/clothes_scan.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/screens/session_screen.dart';
import 'package:fashion_agent/services/fake_vision_service.dart';
import 'package:fashion_agent/services/vision_service.dart';
import 'package:fashion_agent/services/wardrobe_store.dart';
import 'package:fashion_agent/session/session_controller.dart';
import 'package:fashion_agent/session/session_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  test('날씨와 일정을 조용히 가져오고 옷을 찍어 달라고 한다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(speech: speech);
    await c.start();

    expect(speech.said, hasLength(1));
    expect(speech.said.single, contains('펼쳐 놓고'));
    expect(c.weather, isNotNull);
    expect(c.step, SessionStep.capturing);
  });

  test('찍으면 일정·날씨·얼룩을 한 번에 알려 주고, 끝나면 돌아간다', () async {
    final speech = FakeSpeech();
    final wardrobe = InMemoryWardrobeStore();
    final c = controllerWith(
      speech: speech,
      wardrobe: wardrobe,
      events: [ScheduleEvent(title: '면접', start: DateTime(2026, 11, 3, 14))],
    );
    var finished = false;
    c.onFinished = () => finished = true;
    await c.start();

    await c.primary(); // 옷 찍기
    expect(c.step, SessionStep.result);
    final said = speech.said.last;
    expect(said, startsWith('보이는 옷은 남색 셔츠, 파란색 청바지예요.'));
    expect(said, contains('오늘은 체감 온도 12도, 최저 8도 최고 16도예요. 오후 2시 면접이 있어요.'));
    expect(said, contains('파란색 청바지는 편한 옷이라 면접에는'));
    expect(said, contains('겉옷은 보이지 않아요.'));
    expect(said, contains('남색 셔츠 오른쪽 소매 끝에 얼룩이 있어요.'));
    expect(c.result?.allGood, isFalse);

    // 사진은 저장하지 않고 본 옷의 설명만 쌓인다.
    expect(wardrobe.garments, hasLength(2));

    expect(c.primaryLabel, '돌아가기');
    await c.primary();
    expect(finished, isTrue);
  });

  test('어두우면 다시 찍어 달라고 한다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(
      speech: speech,
      vision: FakeVisionService(scripted: {
        ScanPurpose.outfit: [const ClothesScan(garments: [], isDark: true)],
      }),
    );
    await c.start();
    await c.primary();

    expect(c.step, SessionStep.capturing);
    expect(speech.said.last, contains('너무 어두워요'));
  });

  group('말로 하기', () {
    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    group('말 명령 읽기(sessionCommand)', () {
      const commands = {
        '첫 화면으로 돌아가 줘': SessionCommand.back,
        '그만할래': SessionCommand.back,
        '다시 검사': SessionCommand.again,
        '찍어 줘': SessionCommand.shoot,
      };
      commands.forEach((said, command) {
        test('"$said" → ${command.name}',
            () => expect(sessionCommand(said), command));
      });

      test('비정상: 명령이 아닌 "음" → null', () => expect(sessionCommand('음'), isNull));
    });

    test('"찍어 줘"로 검사하고 "돌아가기"로 첫 화면에 간다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['찍어 줘', '돌아가기'], blockWhenDone: true);
      final c = controllerWith(speech: speech, listen: listen);
      var finished = false;
      c.onFinished = () => finished = true;
      await c.start();
      await settle();

      expect(speech, saidLineStartingWith('보이는 옷은'));
      expect(speech.said.last, '처음으로 돌아갈게요.');
      expect(finished, isTrue);
    });

    test('못 알아들으면 할 수 있는 말을 알려 준다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['음'], blockWhenDone: true);
      final c = controllerWith(speech: speech, listen: listen);
      c.onFinished = () {};
      await c.start();
      await settle();

      expect(speech.said.last, contains('"찍어 줘"라고 말씀해 주세요'));
      expect(c.step, SessionStep.capturing);
    });

    test('버튼을 누르면 듣기를 멈추고 버튼대로 한다', () async {
      final listen = ScriptedListen([], blockWhenDone: true);
      final c = controllerWith(listen: listen);
      await c.start();
      await settle();
      await c.primary();

      expect(listen.cancels, greaterThan(0));
      expect(c.step, SessionStep.result);
    });
  });

  testWidgets('화면은 위·아래 두 개의 큰 버튼이다', (tester) async {
    final c = controllerWith();
    await tester.pumpWidget(MaterialApp(home: SessionScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.text('옷 찍기'), findsOneWidget);
    expect(find.text('다시 듣기'), findsOneWidget);

    await tester.tap(find.text('옷 찍기'));
    await tester.pumpAndSettle();
    expect(find.text('다시 검사'), findsOneWidget);
  });
}
