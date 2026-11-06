import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/camera_turn.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/auto_capture.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

import 'agent_test.dart'
    show
        FakeAccount,
        FakeSpeech,
        ScriptedListen,
        FakeWeatherService,
        onboardingWith;

TurnReply reply(String speech, TurnNext next, {String id = 's_1'}) =>
    TurnReply(sessionId: id, speech: speech, next: next);

/// agent 흉내. 받은 요청을 적어 두고 정해 둔 답을 차례로 준다.
class FakeTurnApi implements TurnApi {
  FakeTurnApi(this.replies, {this.signedIn = true});

  final List<Object> replies;
  bool signedIn;
  final sent = <String>[];
  final sessions = <String?>[];
  final locations = <TurnLocation?>[];

  @override
  Future<bool> get available async => signedIn;

  Future<TurnReply> _next() async {
    final r = replies.removeAt(0);
    if (r is TurnReply) return r;
    throw r;
  }

  @override
  Future<TurnReply> say(String? sessionId, String utterance,
      {TurnLocation? location}) {
    sent.add('say:$utterance');
    sessions.add(sessionId);
    locations.add(location);
    return _next();
  }

  @override
  Future<TurnReply> show(String? sessionId, ImageKind kind, Uint8List jpeg,
      {TurnLocation? location}) {
    sent.add('show:${kind.name}:${jpeg.length}');
    sessions.add(sessionId);
    locations.add(location);
    return _next();
  }
}

final here =
    LocationProvider(read: () async => const TurnLocation(35.1, 129.0));

AgentController agentWith(FakeSpeech speech, FakeTurnApi turns,
        {List<String?> heard = const []}) =>
    AgentController(
      speech: speech,
      listen: ScriptedListen(heard),
      profiles: InMemoryProfileStore(),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: turns,
      location: here,
    );

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('계약 모양', () {
    test('말은 sessionId·utterance·location으로 보낸다', () {
      expect(
        turnRequestJson(
            sessionId: 's_1',
            utterance: '오늘 뭐 입지?',
            location: const TurnLocation(37.5, 127.0)),
        {
          'sessionId': 's_1',
          'utterance': '오늘 뭐 입지?',
          'location': {'lat': 37.5, 'lon': 127.0, 'locationFallback': false},
        },
      );
    });

    test('사진은 base64와 imageKind, autoCaptured=true로 보낸다', () {
      final json = turnRequestJson(
          kind: ImageKind.teeth, jpeg: Uint8List.fromList([1, 2, 3]));
      expect(
          json, {'image': 'AQID', 'imageKind': 'teeth', 'autoCaptured': true});
    });

    test('답의 next를 읽는다', () {
      final r = TurnReply.fromJson({
        'sessionId': 's_9',
        'speech': '옷을 보여 주세요.',
        'next': 'camera_outfit',
        'result': {'type': 'outfit_advice'},
      });
      expect(r.next, TurnNext.cameraOutfit);
      expect(r.next.camera, ImageKind.outfit);
      expect(r.resultType, 'outfit_advice');
      expect(TurnNext.parse('camera_teeth').camera, ImageKind.teeth);
      expect(TurnNext.parse('camera_worn').camera, ImageKind.worn);
      expect(ImageKind.worn.selfie, isFalse);
      expect(TurnNext.parse('listen').camera, isNull);
      expect(TurnNext.parse('모름'), TurnNext.done);
    });

    test('게이트웨이로 토큰을 붙여 POST /api/v1/agent/turn을 부른다', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response.bytes(
          utf8.encode(jsonEncode(
              {'sessionId': 's_2', 'speech': '안녕하세요', 'next': 'listen'})),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final store = MemoryTokenStore()
        ..tokens = GatewayTokens(
            accessToken: 'a1',
            refreshToken: 'r1',
            expiresAt: DateTime.now().add(const Duration(hours: 1)));
      final modes = MemoryOutfitModeStore();
      final api = GatewayTurnApi(
          GatewayAuth(
              baseUrl: Uri.parse('http://gw:8080'),
              tokens: store,
              client: client),
          modes: modes);

      expect(await api.available, isTrue);
      final r = await api.say(null, '안녕');
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://gw:8080/api/v1/agent/turn');
      expect(seen.headers['authorization'], 'Bearer a1');
      expect(jsonDecode(seen.body), {'utterance': '안녕'});
      expect(r.sessionId, 's_2');
      expect(r.speech, '안녕하세요');
    });

    test('고른 방식을 기억해서 다음 말부터 보낸다', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'sessionId': 's_3',
            'speech': '좋아요.',
            'next': 'camera_worn',
            'result': {'type': 'outfit_advice', 'outfitMode': 'worn'},
          })),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final store = MemoryTokenStore()
        ..tokens = GatewayTokens(
            accessToken: 'a1',
            refreshToken: 'r1',
            expiresAt: DateTime.now().add(const Duration(hours: 1)));
      final modes = MemoryOutfitModeStore();
      final api = GatewayTurnApi(
          GatewayAuth(
              baseUrl: Uri.parse('http://gw:8080'),
              tokens: store,
              client: client),
          modes: modes);

      final r = await api.say(null, '오늘 뭐 입지?');
      expect(bodies.first.containsKey('outfitMode'), isFalse);
      expect(r.next.camera, ImageKind.worn);
      expect(modes.mode, OutfitMode.worn);

      await api.say('s_3', '입고 볼게');
      expect(bodies.last['outfitMode'], 'worn');
    });

    test('위치 권한이 없으면 서울(locationFallback=true)로 보낸다', () async {
      final loc = await LocationProvider(read: () async => null).current();
      expect(loc.toJson(),
          {'lat': 37.5665, 'lon': 126.978, 'locationFallback': true});
    });

    test('오류는 읽어 줄 말로 바꾼다', () {
      expect(turnErrorSpeech(GatewayException(429, 'rate_limited')),
          contains('잠시 뒤'));
      expect(turnErrorSpeech(TimeoutException('늦음')), contains('오래'));
      expect(turnErrorSpeech(const FormatException()), contains('인터넷'));
    });
  });

  group('에이전트 대화', () {
    test('next=listen이면 바로 다시 듣고, done이면 대화를 끝낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        reply('오늘은 맑고 15도예요.', TurnNext.listen),
        reply('좋은 하루 보내세요.', TurnNext.done),
      ]);
      final agent = agentWith(speech, turns, heard: ['고마워']);

      await agent.handle('오늘 날씨 어때?');

      expect(turns.sent, ['say:오늘 날씨 어때?', 'say:고마워']);
      expect(turns.sessions, [null, 's_1']);
      expect(turns.locations.first?.lat, 35.1);
      expect(speech.spoken, ['오늘은 맑고 15도예요.', '좋은 하루 보내세요.', tapToTalk]);
    });

    test('done 뒤 새 대화는 sessionId 없이 시작한다', () async {
      final turns = FakeTurnApi([
        reply('네.', TurnNext.done),
        reply('네.', TurnNext.done, id: 's_2'),
      ]);
      final agent = agentWith(FakeSpeech(), turns);
      await agent.handle('하나');
      await agent.handle('둘');
      expect(turns.sessions, [null, null]);
    });

    test('듣다가 아무 말이 없으면 멈추고, 다음 말은 같은 대화로 이어 간다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        reply('얼굴 화장을 볼까요, 이를 확인할까요?', TurnNext.listen),
        reply('이를 볼게요.', TurnNext.done),
      ]);
      final agent = agentWith(speech, turns);
      await agent.handle('얼굴 확인해 줘');
      expect(speech.spoken.last, tapToTalk);

      await agent.handle('이');
      expect(turns.sessions, [null, 's_1']);
    });

    test('camera_*면 카메라를 열고, 카메라가 끝난 답을 이어서 읽는다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        reply('옷을 꺼내서 카메라에 보여 주세요.', TurnNext.cameraOutfit),
      ]);
      final agent = agentWith(speech, turns);
      final opened = <String>[];
      agent.openCamera = (id, kind) async {
        opened.add('$id:${kind.name}');
        return reply('좋은 선택이에요. 잘 다녀오세요.', TurnNext.done);
      };

      await agent.handle('오늘 뭐 입지?');

      expect(opened, ['s_1:outfit']);
      expect(speech.spoken, [
        '옷을 꺼내서 카메라에 보여 주세요.',
        '좋은 선택이에요. 잘 다녀오세요.',
        tapToTalk,
      ]);
    });

    test('카메라를 그만두면 껐다고 알린다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(
          speech, FakeTurnApi([reply('얼굴을 보여 주세요.', TurnNext.cameraFace)]));
      agent.openCamera = (_, __) async => null;
      await agent.handle('화장 봐 줘');
      expect(speech.spoken, ['얼굴을 보여 주세요.', '카메라를 껐어요.', tapToTalk]);
    });

    test('서버 오류면 이유를 말한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(
          speech, FakeTurnApi([GatewayException(502, 'upstream_error')]));
      await agent.handle('오늘 뭐 입지?');
      expect(speech.spoken, [contains('서버'), tapToTalk]);
    });

    test('로그인이 풀리면 폰 안 기능으로 이어서 처리한다', () async {
      final speech = FakeSpeech();
      final agent = agentWith(
          speech, FakeTurnApi([GatewayException(401, 'unauthorized')]));
      await agent.handle('오늘 날씨 어때?');
      expect(speech.spoken.first, contains('로그인이 풀렸어요'));
      expect(speech.spoken.any((s) => s.contains('15')), isTrue);
    });

    test('로그인하지 않았으면 agent를 부르지 않는다', () async {
      final turns = FakeTurnApi([], signedIn: false);
      final speech = FakeSpeech();
      await agentWith(speech, turns).handle('기능 알려 줘');
      expect(turns.sent, isEmpty);
      expect(speech.spoken.first, featureIntro);
    });

    test('로그인이 풀린 채 다시 켜면 먼저 다시 로그인하고 agent로 보낸다', () async {
      final speech = FakeSpeech();
      final turns =
          FakeTurnApi([reply('네, 말씀하세요.', TurnNext.done)], signedIn: false);
      final store = InMemoryProfileStore();
      await store.save(const UserProfile(name: '진행', agentName: '코디'));
      final account = _SigningAccount(() => turns.signedIn = true);
      final agent = AgentController(
        speech: speech,
        listen: ScriptedListen(['안녕']),
        profiles: store,
        onboarding: onboardingWith(speech, const [], account: account),
        weatherService: FakeWeatherService(),
        turns: turns,
        location: here,
      );
      await agent.start();
      expect(speech.spoken.first, contains('다시 로그인'));
      expect(turns.sent, ['say:안녕']);
      expect((await store.load())!.accountId, 'acc-1');
      expect(account.uploaded?.name, '진행');
    });

    test('다시 로그인을 취소하면 폰 안 기능으로', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([], signedIn: false);
      final store = InMemoryProfileStore();
      await store.save(const UserProfile(name: '진행', agentName: '코디'));
      final agent = AgentController(
        speech: speech,
        listen: ScriptedListen(['기능 알려 줘']),
        profiles: store,
        onboarding: onboardingWith(speech, const []),
        weatherService: FakeWeatherService(),
        turns: turns,
        location: here,
      );
      await agent.start();
      expect(speech.spoken, contains('로그인하지 못해서 지금은 폰 안의 기능만 쓸게요.'));
      expect(speech.spoken, contains(featureIntro));
      expect(turns.sent, isEmpty);
    });

    test('온보딩한 사용자도 첫 말부터 agent로 보낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([reply('네, 말씀하세요.', TurnNext.done)]);
      final store = InMemoryProfileStore();
      await store.save(const UserProfile(name: '진행', agentName: '코디'));
      final agent = AgentController(
        speech: speech,
        listen: ScriptedListen(['안녕']),
        profiles: store,
        onboarding: onboardingWith(speech, const []),
        weatherService: FakeWeatherService(),
        turns: turns,
        location: here,
      );
      await agent.start();
      expect(turns.sent, ['say:안녕']);
    });
  });

  group('카메라 대화', () {
    final photo = Uint8List.fromList([9, 9, 9]);

    CameraTurnController cameraWith(
            FakeSpeech speech, FakeTurnApi turns, FakeAutoCaptureCamera camera,
            {List<String?> heard = const []}) =>
        CameraTurnController(
          speech: speech,
          listen: ScriptedListen(heard),
          turns: turns,
          camera: camera,
          location: here,
        );

    test('멈추면 찍어 보내고, camera_outfit이면 읽고 계속 보다가 done이면 돌려준다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        reply('흰 셔츠가 면접에 잘 맞아요. 겉옷도 보여 주세요.', TurnNext.cameraOutfit),
        reply('자켓도 좋아요. 이걸로 하시겠어요?', TurnNext.listen),
      ]);
      final camera = FakeAutoCaptureCamera([photo, photo]);
      final c = cameraWith(speech, turns, camera);

      final end = await c.run('s_1', ImageKind.outfit);

      expect(camera.opened, [false]);
      expect(turns.sent, ['show:outfit:3', 'show:outfit:3']);
      expect(turns.locations.first?.lat, 35.1);
      expect(end?.speech, '자켓도 좋아요. 이걸로 하시겠어요?');
      expect(camera.closed, isTrue);
      expect(speech.spoken, [
        '찍었어요. 확인하고 있어요.',
        '흰 셔츠가 면접에 잘 맞아요. 겉옷도 보여 주세요.',
        '찍었어요. 확인하고 있어요.',
      ]);
    });

    test('얼굴·이는 앞쪽 카메라로 보고, 다른 카메라를 달라고 하면 바꾼다', () async {
      final turns = FakeTurnApi([
        reply('입을 보여 주세요.', TurnNext.cameraTeeth),
        reply('이 사이에 낀 것은 없어요.', TurnNext.listen),
      ]);
      final camera = FakeAutoCaptureCamera([photo, photo]);
      final c = cameraWith(FakeSpeech(), turns, camera);

      await c.run('s_1', ImageKind.face);

      expect(camera.opened, [true]);
      expect(turns.sent, ['show:face:3', 'show:teeth:3']);
    });

    test('입고 한 바퀴는 뒤쪽 카메라로 앞·옆·뒤를 차례로 보낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        reply('앞모습을 봤어요. 이제 천천히 옆으로 돌아서 잠시 멈춰 주세요.', TurnNext.cameraWorn),
        reply('옆모습도 봤어요. 이제 뒤로 돌아서 잠시 멈춰 주세요.', TurnNext.cameraWorn),
        reply('잘 어울려요.', TurnNext.listen),
      ]);
      final camera = FakeAutoCaptureCamera([photo, photo, photo]);
      final end =
          await cameraWith(speech, turns, camera).run('s_1', ImageKind.worn);
      expect(camera.opened, [false]);
      expect(turns.sent, ['show:worn:3', 'show:worn:3', 'show:worn:3']);
      expect(end?.speech, '잘 어울려요.');
    });

    test('입고 한 바퀴에서 오래 안 멈추면 물러나라고 안내한다', () async {
      final speech = FakeSpeech();
      final camera = FakeAutoCaptureCamera([null, null, null]);
      await cameraWith(speech, FakeTurnApi([]), camera)
          .run('s_1', ImageKind.worn);
      expect(speech.spoken.first, contains('물러나'));
    });

    test('옷 카메라에서 얼굴 카메라로 가면 앞쪽 카메라를 켠다', () async {
      final turns = FakeTurnApi([
        reply('얼굴을 보여 주세요.', TurnNext.cameraFace),
        reply('화장이 고르게 됐어요.', TurnNext.listen),
      ]);
      final camera = FakeAutoCaptureCamera([photo, photo]);
      await cameraWith(FakeSpeech(), turns, camera)
          .run('s_1', ImageKind.outfit);
      expect(camera.opened, [false, true]);
    });

    test('그만하기면 null로 끝나고 카메라를 끈다', () async {
      final camera = FakeAutoCaptureCamera();
      final c = cameraWith(FakeSpeech(), FakeTurnApi([]), camera);
      final end = c.run('s_1', ImageKind.outfit);
      await settle();
      expect(camera.waiting, isTrue);

      await c.stop();
      expect(await end, isNull);
      expect(camera.closed, isTrue);
    });

    test('카메라가 켜진 동안 말하면 그 말을 보낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([reply('좋아요. 잘 다녀오세요.', TurnNext.done)]);
      final camera = FakeAutoCaptureCamera();
      final c = cameraWith(speech, turns, camera, heard: ['이걸로 할게']);
      final end = c.run('s_1', ImageKind.outfit);
      await settle();

      await c.talk();

      expect((await end)?.speech, '좋아요. 잘 다녀오세요.');
      expect(turns.sent, ['say:이걸로 할게']);
      expect(turns.sessions, ['s_1']);
    });

    test('오래 안 멈추면 안내하고, 세 번 넘으면 카메라를 끈다', () async {
      final speech = FakeSpeech();
      final camera = FakeAutoCaptureCamera([null, null, null]);
      final end = await cameraWith(speech, FakeTurnApi([]), camera)
          .run('s_1', ImageKind.outfit);
      expect(end, isNull);
      expect(speech.spoken, [
        contains('옷이 잘 보이지 않아요'),
        contains('옷이 잘 보이지 않아요'),
        '잘 보이지 않아서 카메라를 끌게요.',
      ]);
    });

    test('보내다 실패하면 이유를 말하고 계속 본다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([
        GatewayException(504, 'upstream_timeout'),
        reply('좋아요.', TurnNext.done),
      ]);
      final camera = FakeAutoCaptureCamera([photo, photo]);
      final end =
          await cameraWith(speech, turns, camera).run('s_1', ImageKind.outfit);
      expect(end?.speech, '좋아요.');
      expect(speech.spoken, contains(contains('오래 걸렸어요')));
    });
  });

  group('자동 촬영', () {
    List<double> flat(double v) => List.filled(256, v);

    test('1초 동안 거의 안 바뀌면 찍을 때가 된다', () {
      final d = StillnessDetector();
      expect(d.feed(flat(120), Duration.zero), FrameState.moving);
      expect(d.feed(flat(122), const Duration(milliseconds: 200)),
          FrameState.settling);
      expect(d.feed(flat(121), const Duration(milliseconds: 900)),
          FrameState.settling);
      expect(d.feed(flat(120), const Duration(milliseconds: 1250)),
          FrameState.ready);
    });

    test('움직이면 처음부터 다시 센다', () {
      final d = StillnessDetector();
      d.feed(flat(120), Duration.zero);
      d.feed(flat(120), const Duration(milliseconds: 100));
      expect(d.feed(flat(160), const Duration(milliseconds: 800)),
          FrameState.moving);
      expect(d.feed(flat(160), const Duration(milliseconds: 1300)),
          FrameState.settling);
      expect(d.feed(flat(160), const Duration(milliseconds: 2400)),
          FrameState.ready);
    });

    test('어두우면 찍지 않는다', () {
      final d = StillnessDetector();
      d.feed(flat(20), Duration.zero);
      expect(d.feed(flat(20), const Duration(seconds: 3)), FrameState.dark);
    });

    test('Y 평면과 BGRA에서 칸별 밝기를 구한다', () {
      // 왼쪽 절반 검정, 오른쪽 절반 흰색인 8x4 프레임
      final y = Uint8List(8 * 4);
      final bgra = Uint8List(8 * 4 * 4);
      for (var r = 0; r < 4; r++) {
        for (var c = 4; c < 8; c++) {
          y[r * 8 + c] = 255;
          bgra.fillRange((r * 8 + c) * 4, (r * 8 + c) * 4 + 4, 255);
        }
      }
      final g1 = lumaGrid(y, width: 8, height: 4, bytesPerRow: 8, cells: 2);
      final g4 = lumaGrid(bgra,
          width: 8, height: 4, bytesPerRow: 32, bytesPerPixel: 4, cells: 2);
      expect(g1, [0, 255, 0, 255]);
      expect(g4.map((v) => v.round()), [0, 255, 0, 255]);
    });

    test('셀카 사진은 좌우를 뒤집는다', () {
      final src = img.Image(width: 2, height: 1)
        ..setPixelRgb(0, 0, 255, 0, 0)
        ..setPixelRgb(1, 0, 0, 0, 255);
      final out = img.decodeJpg(
          mirrorJpeg(Uint8List.fromList(img.encodeJpg(src, quality: 100))))!;
      final left = out.getPixel(0, 0);
      expect(left.b, greaterThan(left.r));
    });
  });
}

/// 로그인하면 게이트웨이 토큰이 생기는 것처럼 [onSignIn]을 부른다.
class _SigningAccount extends FakeAccount {
  _SigningAccount(this.onSignIn) : super(id: 'acc-1');

  final void Function() onSignIn;

  @override
  Future<String?> signIn() async {
    onSignIn();
    return id;
  }
}
