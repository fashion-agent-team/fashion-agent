import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/camera_turn.dart';
import 'package:fashion_agent/agent/waiting_cue.dart';
import 'package:fashion_agent/services/auto_capture.dart';
import 'package:fashion_agent/services/turn_api.dart' show ImageKind;
import 'package:fashion_agent/screens/agent_screen.dart';
import 'package:fashion_agent/services/framing.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-13 시각장애인 관점 점검에서 고친 것들.
void main() {
  group('기다리는 동안 알리기', () {
    test('빨리 끝나면 아무것도 안 한다', () async {
      var ticks = 0;
      final v = await withWaitingCue(Future.value(1), tick: () => ticks++);
      expect(v, 1);
      expect(ticks, 0);
    });

    test('오래 걸리면 진동하고, 더 길어지면 한 번 말한다', () async {
      var ticks = 0, stills = 0;
      final done = Completer<int>();
      final waiting = withWaitingCue(done.future,
          tick: () => ticks++,
          still: () => stills++,
          firstAfter: const Duration(milliseconds: 20),
          every: const Duration(milliseconds: 20),
          stillAfter: const Duration(milliseconds: 90));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ticks, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stills, 1);
      done.complete(3);
      expect(await waiting, 3);
      final before = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(ticks, before, reason: '끝나면 멈춘다');
      expect(stills, 1);
    });
  });

  group('연결 오류면 한 번 더 보내기', () {
    test('연결이 끊겼으면 한 번 더 보낸다', () async {
      var calls = 0;
      final v = await retryOnceIfUnsent(() async {
        if (++calls == 1) throw const SocketException('끊김');
        return 'ok';
      }, wait: Duration.zero);
      expect(v, 'ok');
      expect(calls, 2);
    });

    test('서버가 답한 오류와 시간 초과는 다시 보내지 않는다', () async {
      for (final e in <Object>[
        GatewayException(502, 'upstream'),
        TimeoutException('늦음')
      ]) {
        var calls = 0;
        await expectLater(
            retryOnceIfUnsent(() async {
              calls++;
              throw e;
            }, wait: Duration.zero),
            throwsA(same(e)));
        expect(calls, 1);
      }
    });
  });

  test('허용 창 안내는 \'허용 안 함\'을 지나치라고 한다', () {
    expect(permissionIntro, contains('허용 안 함'));
    expect(permissionIntro, contains('확인'));
  });

  test('VoiceOver 이름은 지금 상태대로, 설명은 짧게', () {
    expect(semanticsLabelFor(AgentPhase.speaking), '말하는 중');
    expect(semanticsLabelFor(AgentPhase.thinking), '알아보는 중');
    expect(semanticsLabelFor(AgentPhase.listening), '듣는 중');
    expect(semanticsLabelFor(AgentPhase.idle), '말하기');
    expect(semanticsHintFor(AgentPhase.speaking, busy: true), contains('멈춰요'));
    expect(semanticsHintFor(AgentPhase.thinking, busy: true), isNull);
  });

  group('셀카 얼굴 구도', () {
    test('얼굴이 없으면 정면에 들라고 한다', () {
      expect(frameFace(const []).speech, contains('정면'));
    });
    test('너무 크면 멀리, 작으면 가까이', () {
      expect(frameFace([const Rect.fromLTRB(0.05, 0.1, 0.95, 0.8)]).speech,
          '조금 멀리 들어 주세요.');
      expect(frameFace([const Rect.fromLTRB(0.4, 0.4, 0.6, 0.6)]).speech,
          '조금 가까이 들어 주세요.');
    });
    test('끝에 걸리면 가운데로', () {
      expect(frameFace([const Rect.fromLTRB(0.0, 0.3, 0.5, 0.7)]).speech,
          contains('가운데'));
    });
    test('가운데에 알맞으면 찍는다', () {
      expect(
          frameFace([const Rect.fromLTRB(0.2, 0.2, 0.8, 0.75)]).ready, isTrue);
    });
  });

  test('"기능 뭐 있어?" 같은 비슷한 말도 기능 설명으로', () {
    for (final said in [
      '기능 설명',
      '기능 뭐 있어?',
      '어떤 기능 있어',
      '기능이 뭐야',
      '너 뭐 할 수 있어?',
      '할 수 있는 거 알려 줘',
      '할 줄 아는 거 말해 봐',
      '뭘 도와줄 수 있어',
      '사용법 알려 줘',
      '이거 어떻게 써?',
    ]) {
      expect(isFeatureExplainCommand(said), isTrue, reason: said);
    }
    for (final said in ['오늘 뭐 입지?', '옷 추천해 줘', '내일 날씨 어때', '이거 무슨 색이야?']) {
      expect(isFeatureExplainCommand(said), isFalse, reason: said);
    }
  });

  group('소리 구도 안내', () {
    test('가운데에 알맞을수록 가깝고, 찍어도 되면 1', () {
      final off = frameGarment([const Rect.fromLTRB(0.0, 0.0, 0.3, 0.3)]);
      final near = frameGarment([const Rect.fromLTRB(0.3, 0.2, 0.9, 0.8)]);
      final ready = frameGarment([const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8)]);
      expect(frameGarment(const []).closeness, 0);
      expect(off.closeness, greaterThan(0));
      expect(near.closeness, greaterThan(off.closeness));
      expect(ready.ready, isTrue);
      expect(ready.closeness, 1);
    });

    test('가까울수록 소리 사이가 짧고, 못 찾으면 조용하다', () {
      expect(FramingBeeper.gapFor(0), isNull);
      expect(FramingBeeper.gapFor(1), FramingBeeper.fastest);
      expect(FramingBeeper.gapFor(0.2)! > FramingBeeper.gapFor(0.8)!, isTrue);
    });

    test('소리를 내면 간격마다 울린다', () async {
      var beeps = 0;
      final b = FramingBeeper(beep: () => beeps++)..start();
      b.closeness = 1;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      b.stop();
      expect(beeps, greaterThanOrEqualTo(2));
      final after = beeps;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(beeps, after, reason: '멈추면 조용');
    });

    test('옷·몸·얼굴은 소리 뜻을 알려 주고, 이는 알려 주지 않는다', () {
      expect(beepHintFor(ImageKind.outfit), contains('빨라지면 잘하고 있는 거예요'));
      expect(beepHintFor(ImageKind.worn), isNotNull);
      expect(beepHintFor(ImageKind.face), isNotNull);
      expect(beepHintFor(ImageKind.teeth), isNull);
    });
  });
}
