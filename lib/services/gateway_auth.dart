import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// 게이트웨이가 준 토큰. 계약은 `docs/contracts/openapi.yaml`의 `Tokens`.
class GatewayTokens {
  const GatewayTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory GatewayTokens.fromJson(Map<String, dynamic> json) => GatewayTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}

/// 토큰을 보관하는 곳. 앱은 키체인/키스토어([SecureTokenStore])를 쓰고, 테스트는 메모리를 쓴다.
abstract class TokenStore {
  Future<GatewayTokens?> read();
  Future<void> write(GatewayTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'gateway_tokens';
  final FlutterSecureStorage _storage;

  @override
  Future<GatewayTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return GatewayTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(GatewayTokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  GatewayTokens? tokens;

  @override
  Future<GatewayTokens?> read() async => tokens;

  @override
  Future<void> write(GatewayTokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}

/// 게이트웨이 오류. [code]는 계약의 오류 코드(`unauthorized`, `rate_limited` 등).
class GatewayException implements Exception {
  GatewayException(this.status, this.code, [this.message]);

  final int status;
  final String code;
  final String? message;

  @override
  String toString() => 'GatewayException($status $code${message == null ? '' : ': $message'})';
}

/// 게이트웨이 로그인과 토큰 관리.
///
/// - [login]: Firebase ID 토큰을 게이트웨이 토큰으로 바꾼다.
/// - [send]: 토큰을 붙여 보낸다. 만료가 가까우면 먼저 갱신하고, 401이면 한 번 갱신해서 다시 보낸다.
/// - 갱신까지 실패하면 토큰을 지우고 [GatewayException] `unauthorized`를 던진다. 앱은 다시 로그인하면 된다.
class GatewayAuth {
  GatewayAuth({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final Uri baseUrl;
  final TokenStore tokens;
  final http.Client _client;
  final DateTime Function() _now;

  /// 동시에 여러 요청이 401을 받아도 갱신은 한 번만 한다. 게이트웨이는 같은 refresh 토큰을 두 번 쓰면 전부 끊는다.
  Future<GatewayTokens>? _refreshing;

  /// 만료 이만큼 전부터 미리 갱신한다.
  static const _skew = Duration(minutes: 1);

  Uri _url(String path) => baseUrl.resolve(path);

  Future<bool> get isSignedIn async => await tokens.read() != null;

  /// Firebase ID 토큰으로 로그인한다. 새로 가입했으면 true.
  Future<bool> login(String firebaseIdToken) async {
    final res = await _client.post(
      _url('/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'idToken': firebaseIdToken}),
    );
    final body = _decode(res);
    await tokens.write(_tokensFrom(body));
    return body['isNewUser'] == true;
  }

  Future<void> signOut() => tokens.clear();

  /// 토큰을 붙여 [method] [path]를 부른다. 2xx가 아니면 [GatewayException].
  Future<http.Response> send(String method, String path, {Object? json}) async {
    var current = await tokens.read();
    if (current == null) throw GatewayException(401, 'unauthorized', '로그인하지 않았어요');
    if (!_now().isBefore(current.expiresAt.subtract(_skew))) {
      current = await _refresh(current);
    }

    var res = await _sendOnce(method, path, json, current.accessToken);
    if (res.statusCode == 401) {
      current = await _refresh(current);
      res = await _sendOnce(method, path, json, current.accessToken);
    }
    if (res.statusCode >= 300) _decode(res);
    return res;
  }

  /// [send] 후 JSON 본문을 돌려준다. 본문이 없으면 null.
  Future<Map<String, dynamic>?> sendJson(String method, String path, {Object? json}) async {
    final res = await send(method, path, json: json);
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<http.Response> _sendOnce(String method, String path, Object? json, String access) {
    final req = http.Request(method, _url(path))
      ..headers['authorization'] = 'Bearer $access';
    if (json != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(json);
    }
    return _client.send(req).then(http.Response.fromStream);
  }

  Future<GatewayTokens> _refresh(GatewayTokens stale) {
    return _refreshing ??= _doRefresh(stale).whenComplete(() => _refreshing = null);
  }

  Future<GatewayTokens> _doRefresh(GatewayTokens stale) async {
    // 다른 요청이 이미 갱신했으면 그 토큰을 쓴다.
    final latest = await tokens.read();
    if (latest != null && latest.refreshToken != stale.refreshToken) return latest;

    final res = await _client.post(
      _url('/api/v1/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refreshToken': stale.refreshToken}),
    );
    if (res.statusCode == 401) {
      await tokens.clear();
    }
    final fresh = _tokensFrom(_decode(res));
    await tokens.write(fresh);
    return fresh;
  }

  GatewayTokens _tokensFrom(Map<String, dynamic> body) => GatewayTokens(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
        expiresAt: _now().add(Duration(seconds: (body['expiresIn'] as num).toInt())),
      );

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>?;
    } on Object {
      body = null;
    }
    if (res.statusCode >= 300) {
      throw GatewayException(
        res.statusCode,
        body?['code'] as String? ?? 'http_${res.statusCode}',
        body?['message'] as String?,
      );
    }
    return body ?? const {};
  }
}
