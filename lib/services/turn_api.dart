import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'gateway_auth.dart';

/// agent가 정한 다음 동작. 계약 `docs/contracts/openapi.yaml`의 `TurnResponse.next`.
enum TurnNext {
  listen,
  cameraOutfit,
  cameraFace,
  cameraTeeth,
  done;

  static TurnNext parse(String? s) => switch (s) {
        'listen' => listen,
        'camera_outfit' => cameraOutfit,
        'camera_face' => cameraFace,
        'camera_teeth' => cameraTeeth,
        _ => done,
      };

  /// 카메라를 켜 둬야 하면 그 카메라가 볼 것. 아니면 null.
  ImageKind? get camera => switch (this) {
        cameraOutfit => ImageKind.outfit,
        cameraFace => ImageKind.face,
        cameraTeeth => ImageKind.teeth,
        _ => null,
      };
}

/// 보내는 사진의 종류. face·teeth는 앞쪽 카메라로 찍고 셀카처럼 좌우를 뒤집어 보낸다.
enum ImageKind {
  outfit,
  face,
  teeth;

  bool get selfie => this != outfit;
}

/// 계약의 `Location`. 위치 권한이 없으면 서울로 보내고 [fallback]을 켠다.
class TurnLocation {
  const TurnLocation(this.lat, this.lon, {this.fallback = false});

  static const seoul = TurnLocation(37.5665, 126.9780, fallback: true);

  final double lat;
  final double lon;
  final bool fallback;

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lon': lon, 'locationFallback': fallback};
}

/// agent의 답 한 번.
class TurnReply {
  const TurnReply({
    required this.sessionId,
    required this.speech,
    required this.next,
    this.resultType,
  });

  factory TurnReply.fromJson(Map<String, dynamic> json) => TurnReply(
        sessionId: json['sessionId'] as String,
        speech: json['speech'] as String? ?? '',
        next: TurnNext.parse(json['next'] as String?),
        resultType:
            (json['result'] as Map<String, dynamic>?)?['type'] as String?,
      );

  final String sessionId;

  /// 앱이 그대로 읽어 줄 문장.
  final String speech;
  final TurnNext next;

  /// `outfit_advice`, `outfit_check`, `weather` 등. 앱은 [speech]만 읽어도 된다.
  final String? resultType;
}

/// `POST /api/v1/agent/turn`. 게이트웨이에 로그인했을 때만 쓴다.
abstract class TurnApi {
  /// 게이트웨이 토큰이 있으면 true. 없으면 앱은 폰 안 기능(키워드)으로 처리한다.
  Future<bool> get available;

  /// 사용자가 한 말을 보낸다. 첫 말이면 [sessionId]는 null.
  Future<TurnReply> say(String? sessionId, String utterance,
      {TurnLocation? location});

  /// 자동으로 찍은 사진 한 장(JPEG)을 보낸다.
  Future<TurnReply> show(String? sessionId, ImageKind kind, Uint8List jpeg,
      {TurnLocation? location});
}

class GatewayTurnApi implements TurnApi {
  GatewayTurnApi(this.gateway, {this.timeout = const Duration(seconds: 40)});

  final GatewayAuth gateway;

  /// agent는 25초, 게이트웨이는 30초 안에 답한다. 사진 올리는 시간을 더해 조금 더 기다린다.
  final Duration timeout;

  static const _path = '/api/v1/agent/turn';

  @override
  Future<bool> get available => gateway.isSignedIn;

  @override
  Future<TurnReply> say(String? sessionId, String utterance,
          {TurnLocation? location}) =>
      _post(turnRequestJson(
          sessionId: sessionId, utterance: utterance, location: location));

  @override
  Future<TurnReply> show(String? sessionId, ImageKind kind, Uint8List jpeg,
          {TurnLocation? location}) =>
      _post(turnRequestJson(
          sessionId: sessionId, kind: kind, jpeg: jpeg, location: location));

  Future<TurnReply> _post(Map<String, dynamic> body) async {
    final json =
        await gateway.sendJson('POST', _path, json: body).timeout(timeout);
    if (json == null) {
      throw GatewayException(502, 'empty_reply', 'agent가 빈 답을 보냈어요');
    }
    return TurnReply.fromJson(json);
  }
}

/// 계약의 `TurnRequest` 모양.
@visibleForTesting
Map<String, dynamic> turnRequestJson({
  String? sessionId,
  String? utterance,
  ImageKind? kind,
  Uint8List? jpeg,
  TurnLocation? location,
}) =>
    {
      if (sessionId != null) 'sessionId': sessionId,
      if (utterance != null) 'utterance': utterance,
      if (jpeg != null) ...{
        'image': base64Encode(jpeg),
        'imageKind': (kind ?? ImageKind.outfit).name,
        'autoCaptured': true,
      },
      if (location != null) 'location': location.toJson(),
    };

/// 지금 위치. 권한이 없거나 늦으면 서울. 대화 중에는 10분 동안 같은 값을 쓴다.
class LocationProvider {
  LocationProvider(
      {Future<TurnLocation?> Function()? read, DateTime Function()? now})
      : _read = read ?? _readDevice,
        _now = now ?? DateTime.now;

  final Future<TurnLocation?> Function() _read;
  final DateTime Function() _now;
  TurnLocation? _cached;
  DateTime? _at;

  Future<TurnLocation> current() async {
    final at = _at;
    if (_cached != null &&
        at != null &&
        _now().difference(at) < const Duration(minutes: 10)) {
      return _cached!;
    }
    final read = await _read();
    if (read == null) return TurnLocation.seoul;
    _at = _now();
    return _cached = read;
  }

  static Future<TurnLocation?> _readDevice() async {
    try {
      final permission = await Geolocator.checkPermission();
      // 권한 창은 온보딩에서 이미 띄웠다. 대화 중에는 새로 묻지 않는다.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      final p = last ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
      return TurnLocation(p.latitude, p.longitude);
    } on Object catch (e) {
      debugPrint('위치 확인 실패, 서울로 보냅니다: $e');
      return null;
    }
  }
}

/// 오류를 사용자에게 읽어 줄 말로 바꾼다.
String turnErrorSpeech(Object error) {
  if (error is GatewayException) {
    return switch (error.status) {
      401 => '로그인이 풀렸어요. 이번에는 이 폰 안의 기능으로 도와 드릴게요.',
      413 => '사진이 너무 커서 보내지 못했어요. 다시 한 번 보여 주세요.',
      429 => '요청이 너무 많아요. 잠시 뒤에 다시 말씀해 주세요.',
      504 => '서버가 답하는 데 너무 오래 걸렸어요. 잠시 뒤에 다시 말씀해 주세요.',
      _ => '서버에서 문제가 생겼어요. 잠시 뒤에 다시 말씀해 주세요.',
    };
  }
  if (error is TimeoutException) {
    return '서버가 답하는 데 너무 오래 걸렸어요. 잠시 뒤에 다시 말씀해 주세요.';
  }
  return '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.';
}
