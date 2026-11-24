import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fashion_agent/services/cloud_tts.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:fashion_agent/services/server_stt.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 로그인된 게이트웨이. [handler]가 토큰이 붙은 요청에 답한다.
Future<(GatewayAuth, List<http.Request>)> _signedIn(
    Future<http.Response> Function(http.Request req) handler) async {
  final seen = <http.Request>[];
  final store = MemoryTokenStore()
    ..tokens = GatewayTokens(
        accessToken: 'a1',
        refreshToken: 'r1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)));
  final auth = GatewayAuth(
    baseUrl: Uri.parse('https://gw.test'),
    tokens: store,
    client: MockClient((req) async {
      seen.add(req);
      expect(req.headers['authorization'], 'Bearer a1');
      return handler(req);
    }),
  );
  return (auth, seen);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('서버 목소리(GatewayTtsApi)', () {
    test('문장과 목소리, 빠르기를 보내고 받은 소리와 엔진을 기억한다', () async {
      final (auth, seen) = await _signedIn((req) async => http.Response.bytes(
          [1, 2, 3], 200,
          headers: {'x-tts-engine': 'gemini'}));
      final api = GatewayTtsApi(auth);

      expect(await api.available, isTrue);
      expect(api.wholeText, isFalse);
      final bytes = await api.synthesize('안녕하세요.', 'YuJin', rate: 1.2);

      expect(bytes, [1, 2, 3]);
      expect(api.engine, 'gemini');
      expect(api.wholeText, isTrue);
      expect(seen.single.url.path, '/api/v1/tts');
      expect(jsonDecode(seen.single.body),
          {'text': '안녕하세요.', 'voice': 'YuJin', 'rate': 1.2});
    });

    test('보통 빠르기면 rate를 빼고, 빈 소리는 오류로 본다', () async {
      final (auth, seen) =
          await _signedIn((req) async => http.Response.bytes([], 200));
      final api = GatewayTtsApi(auth);

      await expectLater(
          api.synthesize('네.', 'JiMin'),
          throwsA(isA<GatewayException>()
              .having((e) => e.code, 'code', 'empty_audio')));
      expect(jsonDecode(seen.single.body), {'text': '네.', 'voice': 'JiMin'});
      expect(api.engine, isNull);
    });
  });

  group('서버 음성 인식(GatewayServerStt)', () {
    test('녹음을 base64로 보내고 받아 적은 글자를 다듬어 돌려준다', () async {
      final (auth, seen) = await _signedIn((req) async => http.Response(
          jsonEncode({'text': '  오늘 뭐 입지  '}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      final stt = GatewayServerStt(auth);

      final text = await stt.transcribe(
          Uint8List.fromList([7, 8, 9]), 'audio/m4a', '심청이, 날씨');

      expect(text, '오늘 뭐 입지');
      final body = jsonDecode(seen.single.body) as Map;
      expect(body['audioBase64'], base64Encode([7, 8, 9]));
      expect(seen.single.url.path, '/api/v1/stt');
    });

    test('답이 객체가 아니면 빈 글자', () async {
      final (auth, _) =
          await _signedIn((req) async => http.Response('[]', 200));
      expect(
          await GatewayServerStt(auth)
              .transcribe(Uint8List(1), 'audio/m4a', ''),
          '');
    });

    test('로그인이 안 돼 있으면 보내지 않고 unauthorized', () async {
      final auth = GatewayAuth(
        baseUrl: Uri.parse('https://gw.test'),
        tokens: MemoryTokenStore(),
        client: MockClient((_) async => fail('보내면 안 됨')),
      );
      await expectLater(
          GatewayServerStt(auth).transcribe(Uint8List(1), 'audio/m4a', ''),
          throwsA(
              isA<GatewayException>().having((e) => e.status, 'status', 401)));
    });
  });

  group('agent 대화(GatewayTurnApi)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('미리 준비(warm)는 위치를 함께 보낸다', () async {
      final (auth, seen) =
          await _signedIn((req) async => http.Response('', 204));
      final api = GatewayTurnApi(auth,
          modes: MemoryOutfitModeStore(),
          gptConsent: MemoryGptConsentStore(),
          colorDetail: MemoryColorDetailStore());

      await api.warm(location: const TurnLocation(35.1, 129.0));
      await api.warm();

      expect(seen.map((r) => r.url.path),
          ['/api/v1/agent/warm', '/api/v1/agent/warm']);
      expect(jsonDecode(seen[0].body), {
        'location': {'lat': 35.1, 'lon': 129.0, 'locationFallback': false}
      });
      expect(jsonDecode(seen[1].body), isEmpty);
    });

    test('빈 답이 오면 empty_reply 오류', () async {
      final (auth, _) = await _signedIn((req) async => http.Response('', 200));
      final api = GatewayTurnApi(auth,
          modes: MemoryOutfitModeStore(),
          gptConsent: MemoryGptConsentStore(),
          colorDetail: MemoryColorDetailStore());
      await expectLater(
          api.say(null, '안녕'),
          throwsA(isA<GatewayException>()
              .having((e) => e.code, 'code', 'empty_reply')));
    });

    test('폰에 기억한 방식·동의·색 설명을 보내고, 답으로 바뀐 값을 저장한다', () async {
      SharedPreferences.setMockInitialValues({
        'outfit.mode': 'worn',
        'gpt.consent': false,
        'color.detail': true,
      });
      final (auth, seen) = await _signedIn((req) async => http.Response(
          jsonEncode({
            'sessionId': 's1',
            'speech': '알겠어요.',
            'next': 'listen',
            'result': {'type': 'mode', 'outfitMode': 'laid'},
            'gptConsent': true,
            'colorDetail': false,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      final api = GatewayTurnApi(auth);

      final reply = await api.say(null, '내려놓고 보여 줄게');

      final sent = jsonDecode(seen.single.body) as Map;
      expect(sent['outfitMode'], 'worn');
      expect(sent['allowGpt'], false);
      expect(sent['colorDetail'], true);
      expect(reply.speech, '알겠어요.');
      expect(await LocalOutfitModeStore().load(), OutfitMode.laid);
      expect(await LocalGptConsentStore().load(), isTrue);
      expect(await LocalColorDetailStore().load(), isFalse);
    });
  });

  group('로그인 토큰', () {
    test('토큰을 JSON으로 바꿨다가 되살린다', () {
      final t = GatewayTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.utc(2026, 11, 23, 9));
      final back = GatewayTokens.fromJson(t.toJson());
      expect(back.accessToken, 'a');
      expect(back.refreshToken, 'r');
      expect(back.expiresAt, DateTime.utc(2026, 11, 23, 9));
    });

    test('키체인 저장소: 쓰고 읽고 지운다, 깨진 값은 없는 것으로 본다', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureTokenStore();
      expect(await store.read(), isNull);

      await store.write(GatewayTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.utc(2026, 12, 1)));
      expect((await SecureTokenStore().read())!.refreshToken, 'r');

      await store.clear();
      expect(await store.read(), isNull);

      FlutterSecureStorage.setMockInitialValues(
          {'gateway_tokens': '{not json'});
      expect(await SecureTokenStore().read(), isNull);
    });

    test('로그아웃하면 토큰을 지운다', () async {
      final (auth, _) = await _signedIn((req) async => http.Response('', 204));
      expect(await auth.isSignedIn, isTrue);
      await auth.signOut();
      expect(await auth.isSignedIn, isFalse);
    });

    test('개발용 로그인 연결이 끊기면 false, 다음에 다시 해 본다', () async {
      var calls = 0;
      final auth = GatewayAuth(
        baseUrl: Uri.parse('https://gw.test'),
        tokens: MemoryTokenStore(),
        devDeviceId: () async => 'phone-1',
        client: MockClient((_) async {
          calls++;
          throw const SocketException('연결 안 됨');
        }),
      );
      expect(await auth.ensureSignedIn(), isFalse);
      expect(await auth.ensureSignedIn(), isFalse);
      expect(calls, 2);
    });

    test('기기 id는 처음 한 번 만들고 그다음부터는 같은 값을 쓴다', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = await secureDeviceId();
      expect(first, matches(RegExp(r'^phone-[0-9a-f]{32}$')));
      expect(await secureDeviceId(), first);
    });
  });

  group('목소리 캐시(TtsCache)', () {
    test('메모리 한도를 넘으면 가장 오래 안 쓴 문장부터 잊는다', () async {
      final dir = await Directory.systemTemp.createTemp('tts');
      addTearDown(() => dir.delete(recursive: true));
      final cache = TtsCache(memoryLimit: 2, dir: () async => dir);
      var loads = 0;
      Future<Uint8List> load() async => Uint8List.fromList([++loads]);

      await cache.get('v', '하나', load);
      await cache.get('v', '둘', load);
      // '하나'를 다시 써서 최근 것으로 옮긴다 → '둘'이 가장 오래됨
      expect(await cache.get('v', '하나', load), [1]);
      await cache.get('v', '셋', load);
      expect(loads, 3);

      // '둘'은 메모리에서 빠졌지만 파일에 남아 있어 다시 받지 않는다.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cache.get('v', '둘', load), [2]);
      expect(loads, 3);
    });

    test('폴더를 못 쓰면 파일 없이 받아서 돌려준다', () async {
      final cache =
          TtsCache(dir: () async => throw const FileSystemException());
      final bytes =
          await cache.get('v', '안녕', () async => Uint8List.fromList([9]));
      expect(bytes, [9]);
    });

    test('짧은 끝말은 앞 문장에 붙인다', () {
      expect(splitSentences('오늘은 맑아요. 네.'), ['오늘은 맑아요. 네.']);
    });
  });
}
