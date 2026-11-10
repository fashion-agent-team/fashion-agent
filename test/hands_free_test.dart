import 'dart:typed_data';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/camera_turn.dart';
import 'package:fashion_agent/agent/wake_word.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/auto_capture.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_test.dart'
    show FakeSpeech, ScriptedListen, FakeWeatherService, onboardingWith;
import 'turn_test.dart' show FakeTurnApi, reply, here;

/// 비동기로 도는 루프가 한 바퀴씩 돌 시간을 준다.
Future<void> spin([int times = 20]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('이름 찾기', () {
    test('이름 뒤에 한 말을 돌려준다', () {
      expect(afterWakeWord('코디야 오늘 뭐 입지?', '코디'), '오늘 뭐 입지?');
      expect(afterWakeWord('코디야, 날씨 알려 줘', '코디'), '날씨 알려 줘');
      expect(afterWakeWord('헤이 코디 이 확인해 줘', '코디'), '이 확인해 줘');
    });

    test('이름만 부르면 빈 문자열', () {
      expect(afterWakeWord('코디야', '코디'), '');
      expect(afterWakeWord('코디 야!', '코디'), '');
      expect(afterWakeWord('코디님', '코디'), '');
    });

    test('음성 인식이 띄어 쓴 이름도 찾는다', () {
      expect(afterWakeWord('패션 봇아 일정 알려 줘', '패션봇'), '일정 알려 줘');
      expect(afterWakeWord('코 디야 뭐 입지', '코디'), '뭐 입지');
    });

    test('이름이 없으면 null', () {
      expect(afterWakeWord('오늘 뭐 입지?', '코디'), isNull);
      expect(afterWakeWord('', '코디'), isNull);
    });

    test('음성 인식이 살짝 다르게 쓴 이름도 알아듣는다', () {
      expect(afterWakeWord('고디야 날씨 어때', '코디'), '날씨 어때');
      expect(afterWakeWord('패숀봇 일정 알려 줘', '패션봇'), '일정 알려 줘');
      expect(afterWakeWord('어디야', '코디'), isNull);
      expect(afterWakeWord('오늘 뭐 입지', '코디'), isNull);
      expect(afterWakeWord('에이전 날씨', null), '날씨');
    });

    test('사람 이름은 잘못 들은 소리·성 뺀 이름·받침 넘김도 알아듣는다', () {
      const name = '박창근';
      expect(afterWakeWord('박창근 날씨 어때', name), '날씨 어때');
      expect(afterWakeWord('박 창근아 날씨 어때', name), '날씨 어때');
      expect(afterWakeWord('박찬근 날씨 어때', name), '날씨 어때');
      expect(afterWakeWord('박장근', name), '');
      expect(afterWakeWord('박창건아', name), '');
      expect(afterWakeWord('창근아 오늘 뭐 입지', name), '오늘 뭐 입지');
      expect(afterWakeWord('창그나 오늘 뭐 입지', name), '오늘 뭐 입지');
      expect(afterWakeWord('창근이야', name), '');
      expect(afterWakeWord('오늘 장군 영화 봤어', name), isNull);
      expect(afterWakeWord('오늘 날씨 어때', name), isNull);
    });

    test('비슷한 모음도 같게 본다', () {
      expect(afterWakeWord('세봄아 날씨', '새봄'), '날씨');
    });

    test('이름을 안 지었으면 "에이전트"로 부른다', () {
      expect(afterWakeWord('에이전트 날씨 어때', null), '날씨 어때');
    });
  });

  group('이름 불러 말하기', () {
    Future<(AgentController, FakeSpeech, FakeTurnApi, ScriptedListen)> started(
        List<String?> heard, List<Object> replies) async {
      final speech = FakeSpeech();
      final store = InMemoryProfileStore();
      await store.save(const UserProfile(
          name: '진행', agentName: '코디', consent: consentVersion));
      final listen = ScriptedListen(heard, blockWhenDone: true);
      final turns = FakeTurnApi(replies);
      final agent = AgentController(
        speech: speech,
        listen: listen,
        profiles: store,
        onboarding: onboardingWith(speech, const []),
        weatherService: FakeWeatherService(),
        turns: turns,
        location: here,
        handsFree: true,
      );
      await agent.start();
      return (agent, speech, turns, listen);
    }

    test('이름 뒤에 말이 있으면 바로 보낸다', () async {
      final (agent, speech, turns, listen) = await started(
        // 인사 뒤 첫 듣기는 조용함 → 그 뒤로 이름 듣기
        [null, '라디오 소리', '코디야 오늘 뭐 입지?'],
        [reply('맑고 15도예요.', TurnNext.done)],
      );
      await spin();
      expect(turns.sent, ['say:오늘 뭐 입지?']);
      expect(speech.spoken.last, '다른 게 필요하면 "코디" 하고 불러 주세요.');
      expect(listen.waiting, isTrue, reason: '끝나면 다시 이름을 기다린다');
      await agent.pauseHandsFree();
    });

    test('이름만 부르면 "네, 말씀해 주세요." 뒤 한 번 더 듣는다', () async {
      final (agent, speech, turns, _) = await started(
        [null, '코디야', '일정 알려 줘'],
        [reply('오늘은 일정이 없어요.', TurnNext.done)],
      );
      await spin();
      expect(speech.spoken, contains('네, 말씀해 주세요.'));
      expect(turns.sent, ['say:일정 알려 줘']);
      await agent.pauseHandsFree();
    });

    test('앱에서 나가면 듣기를 멈추고, 돌아오면 다시 듣는다', () async {
      final (agent, _, turns, listen) = await started([null], []);
      await spin();
      expect(listen.waiting, isTrue);

      await agent.pauseHandsFree();
      await spin();
      expect(listen.waiting, isFalse);

      agent.resumeHandsFree();
      await spin();
      expect(listen.waiting, isTrue);
      await agent.pauseHandsFree();
      expect(turns.sent, isEmpty);
    });

    test('말하기 버튼을 누르면 이름 듣기를 멈추고 바로 듣는다', () async {
      final (agent, _, turns, listen) =
          await started([null], [reply('네.', TurnNext.done)]);
      await spin();
      listen.answers.add('오늘 날씨 어때?');
      await agent.talk();
      expect(turns.sent, ['say:오늘 날씨 어때?']);
      await agent.pauseHandsFree();
    });
  });

  group('카메라 켜 둔 동안 계속 듣기', () {
    test('버튼 없이 한 말을 보내고, 카메라 대화를 끝낸다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['이걸로 할게'], blockWhenDone: true);
      final turns = FakeTurnApi([reply('좋아요. 잘 다녀오세요.', TurnNext.done)]);
      final camera = FakeAutoCaptureCamera();
      final c = CameraTurnController(
        speech: speech,
        listen: listen,
        turns: turns,
        camera: camera,
        location: here,
        handsFree: true,
      );

      final end = await c.run('s_1', ImageKind.outfit);

      expect(end?.speech, '좋아요. 잘 다녀오세요.');
      expect(turns.sent, ['say:이걸로 할게']);
      expect(camera.closed, isTrue);
    });

    test('"첫 화면"이라고 하면 서버에 보내지 않고 카메라를 끈다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['첫 화면'], blockWhenDone: true);
      final turns = FakeTurnApi(const []);
      final camera = FakeAutoCaptureCamera();
      final c = CameraTurnController(
        speech: speech,
        listen: listen,
        turns: turns,
        camera: camera,
        location: here,
        handsFree: true,
      );

      final end = await c.run('s_1', ImageKind.outfit);

      expect(end, isNull);
      expect(turns.sent, isEmpty);
      expect(speech.spoken, contains('처음으로 돌아갈게요.'));
      expect(camera.closed, isTrue);
    });

    test('안내를 읽기 전에 듣기를 멈춘다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen([], blockWhenDone: true);
      final turns = FakeTurnApi([
        reply('겉옷도 보여 주세요.', TurnNext.cameraOutfit),
        reply('좋아요.', TurnNext.listen),
      ]);
      final camera = FakeAutoCaptureCamera();
      final c = CameraTurnController(
        speech: speech,
        listen: listen,
        turns: turns,
        camera: camera,
        location: here,
        handsFree: true,
      );
      final end = c.run('s_1', ImageKind.outfit);
      await spin();
      expect(listen.waiting, isTrue);

      camera.shots.addAll([Uint8List(1), Uint8List(1)]);
      await camera.cancel(); // 기다리던 촬영을 깨워 다음 사진을 받게 한다
      // cancel은 null(시간 초과)로 처리돼 안내가 한 번 나온 뒤 사진 두 장을 받는다.
      expect((await end)?.speech, '좋아요.');
      expect(listen.cancels, greaterThan(0));
    });
  });
}
