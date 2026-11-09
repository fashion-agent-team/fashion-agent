import 'dart:convert';

import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/firebase_account_service.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 게이트웨이 흉내. refresh 토큰은 한 번만 쓸 수 있고, access 토큰은 [valid]에 있는 것만 받는다.
class FakeGateway {
  final valid = <String>{};
  final usedRefresh = <String>{};
  var refreshCalls = 0;
  var n = 0;
  final calls = <String>[];

  Map<String, dynamic> _issue() {
    n++;
    valid.add('a$n');
    return {
      'accessToken': 'a$n',
      'refreshToken': 'r$n',
      'expiresIn': 3600,
      'isNewUser': n == 1
    };
  }

  late final client = MockClient((req) async {
    calls.add('${req.method} ${req.url.path}');
    switch (req.url.path) {
      case '/api/v1/auth/login':
        return _json(200, _issue());
      case '/api/v1/auth/refresh':
        refreshCalls++;
        final r = (jsonDecode(req.body) as Map)['refreshToken'] as String;
        if (!usedRefresh.add(r)) {
          return _json(401, {'code': 'unauthorized', 'message': 'reused'});
        }
        return _json(200, _issue());
      default:
        final bearer =
            req.headers['authorization']?.replaceFirst('Bearer ', '');
        if (!valid.contains(bearer)) {
          return _json(401, {'code': 'unauthorized', 'message': 'x'});
        }
        if (req.method == 'PUT') return http.Response('', 204);
        return _json(
            200, {'name': '진행', 'birthDate': '1996-02-09', 'agentName': '코디'});
    }
  });

  static http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'});
}

void main() {
  late FakeGateway gw;
  late MemoryTokenStore store;
  late DateTime now;
  late GatewayAuth auth;

  setUp(() {
    gw = FakeGateway();
    store = MemoryTokenStore();
    now = DateTime(2026, 11, 5, 12);
    auth = GatewayAuth(
        baseUrl: Uri.parse('http://gw:8080'),
        tokens: store,
        client: gw.client,
        now: () => now);
  });

  test('로그인하면 토큰을 저장하고 새 가입 여부를 돌려준다', () async {
    expect(await auth.login('firebase-id'), isTrue);
    expect(store.tokens!.accessToken, 'a1');
    expect(store.tokens!.expiresAt, now.add(const Duration(hours: 1)));
  });

  test('401이면 한 번 갱신하고 다시 보낸다', () async {
    await auth.login('x');
    gw.valid.clear();
    final json = await auth.sendJson('GET', '/api/v1/me/profile');
    expect(json!['agentName'], '코디');
    expect(gw.refreshCalls, 1);
    expect(store.tokens!.refreshToken, 'r2');
  });

  test('여러 요청이 동시에 401을 받아도 갱신은 한 번만 한다', () async {
    await auth.login('x');
    gw.valid.clear();
    await Future.wait([
      auth.send('GET', '/api/v1/me/profile'),
      auth.send('GET', '/api/v1/me/profile'),
      auth.send('GET', '/api/v1/me/profile'),
    ]);
    expect(gw.refreshCalls, 1);
  });

  test('만료가 가까우면 보내기 전에 갱신한다', () async {
    await auth.login('x');
    now = now.add(const Duration(minutes: 59, seconds: 30));
    await auth.send('GET', '/api/v1/me/profile');
    expect(gw.calls, [
      'POST /api/v1/auth/login',
      'POST /api/v1/auth/refresh',
      'GET /api/v1/me/profile'
    ]);
  });

  test('갱신도 거절되면 토큰을 지우고 unauthorized를 던진다', () async {
    await auth.login('x');
    gw.valid.clear();
    gw.usedRefresh.add('r1');
    await expectLater(
        auth.send('GET', '/api/v1/me/profile'),
        throwsA(isA<GatewayException>()
            .having((e) => e.code, 'code', 'unauthorized')));
    expect(await auth.isSignedIn, isFalse);
  });

  test('로그인 전에는 보내지 않는다', () async {
    await expectLater(auth.send('GET', '/api/v1/me/profile'),
        throwsA(isA<GatewayException>()));
    expect(gw.calls, isEmpty);
  });

  test('회원정보는 게이트웨이 모양으로 주고받는다', () {
    final p = UserProfile(
        name: '진행',
        birthDate: DateTime(1996, 2, 9),
        heightCm: 175,
        agentName: '코디',
        consent: consentVersion);
    final out = profileToGateway(p);
    expect(out['birthDate'], '1996-02-09');
    expect(out.containsKey('accountId'), isFalse);

    final back = profileFromGateway(
        {'name': '진행', 'birthDate': '1996-02-09', 'agentName': '코디'}, 'uid-1');
    expect(back.birthDate, DateTime(1996, 2, 9));
    expect(back.accountId, 'uid-1');
    expect(back.isOnboarded, isTrue);
  });
}
