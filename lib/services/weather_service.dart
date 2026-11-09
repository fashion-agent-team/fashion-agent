import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// 위치를 찾는 함수. 못 찾으면 null(서울 기준으로 조회한다).
typedef Locate = Future<({double latitude, double longitude})?> Function(
    {required bool askPermission});

/// 오늘 날씨와 기온을 가져온다.
///
/// Open-Meteo(https://open-meteo.com)를 쓴다. API 키가 필요 없고 웹(CORS)에서도 동작한다.
///
/// 빨리 답하려고 세 가지를 한다 (2026-11-09 폰에서 날씨 답이 늦다는 지적).
/// - 결과를 [cacheTtl](30분) 동안 기억한다. 좌표는 소수 둘째 자리(약 1km)로 묶는다.
///   mcp-weather 서버와 같은 기준이다.
/// - 위치는 폰이 마지막으로 알던 위치를 먼저 쓴다. GPS를 새로 잡으면 몇 초씩 걸린다.
/// - 앱을 켤 때 [prefetch]로 미리 받아 둔다. 처음 물어봐도 바로 답한다.
class WeatherService {
  WeatherService({
    http.Client? client,
    Locate? locate,
    DateTime Function()? now,
    this.cacheTtl = const Duration(minutes: 30),
  })  : _client = client ?? http.Client(),
        _locate = locate ?? _deviceLocation,
        _now = now ?? DateTime.now;

  final http.Client _client;
  final Locate _locate;
  final DateTime Function() _now;

  /// 같은 동네 날씨를 다시 받지 않고 쓰는 시간.
  final Duration cacheTtl;

  final Map<String, _Cached> _cache = {};
  final Map<String, Future<Weather>> _inFlight = {};

  // 위치를 못 얻으면 서울시청 기준으로 조회한다.
  static const double fallbackLatitude = 37.5665;
  static const double fallbackLongitude = 126.9780;

  /// 현재 위치의 오늘 날씨. 위치 권한이 없거나 실패하면 서울 기준으로 조회한다.
  Future<Weather> fetchTodayWeather() => _today(askPermission: true);

  /// 앱을 켤 때 미리 받아 둔다. 권한 창은 띄우지 않고, 실패해도 조용히 넘어간다.
  Future<void> prefetch() async {
    try {
      await _today(askPermission: false);
    } catch (_) {
      // 물어볼 때 다시 받는다.
    }
  }

  Future<Weather> _today({required bool askPermission}) async {
    final position = await _locate(askPermission: askPermission);
    if (position == null) {
      return fetchWeather(fallbackLatitude, fallbackLongitude,
          isFallbackLocation: true);
    }
    return fetchWeather(position.latitude, position.longitude);
  }

  /// 좌표의 오늘 날씨. [cacheTtl] 안에 같은 동네를 받은 적이 있으면 그 값을 준다.
  Future<Weather> fetchWeather(double latitude, double longitude,
      {bool isFallbackLocation = false}) {
    final now = _now();
    // 날짜가 바뀌면 오늘 최고·최저 기온이 달라지니 날짜도 키에 넣는다.
    final key = '${now.year}-${now.month}-${now.day}|'
        '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}|'
        '$isFallbackLocation';
    final hit = _cache[key];
    if (hit != null && now.difference(hit.at) < cacheTtl) {
      return Future.value(hit.weather);
    }
    // 미리 받기와 사용자의 질문이 겹치면 한 번만 부른다.
    return _inFlight[key] ??= () async {
      try {
        final weather = await _download(latitude, longitude,
            isFallbackLocation: isFallbackLocation);
        _cache[key] = _Cached(weather, now);
        return weather;
      } finally {
        _inFlight.remove(key);
      }
    }();
  }

  Future<Weather> _download(double latitude, double longitude,
      {required bool isFallbackLocation}) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,apparent_temperature,weather_code',
      'daily':
          'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '1',
    });

    final response =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw WeatherException('날씨 서버 응답 오류 (${response.statusCode})');
    }
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return Weather.fromOpenMeteo(json, isFallbackLocation: isFallbackLocation);
  }

  static Future<({double latitude, double longitude})?> _deviceLocation(
      {required bool askPermission}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // 날씨 조회에는 동네 수준 정확도면 충분하다. 마지막 위치가 있으면 GPS를 기다리지 않는다.
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 5),
            ),
          );
      return (latitude: p.latitude, longitude: p.longitude);
    } catch (_) {
      return null;
    }
  }
}

class _Cached {
  _Cached(this.weather, this.at);

  final Weather weather;
  final DateTime at;
}

class WeatherException implements Exception {
  WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
