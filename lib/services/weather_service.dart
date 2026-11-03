import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// 오늘 날씨와 기온을 가져온다.
///
/// Open-Meteo(https://open-meteo.com)를 쓴다. API 키가 필요 없고 웹(CORS)에서도 동작한다.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // 위치를 못 얻으면 서울시청 기준으로 조회한다.
  static const double fallbackLatitude = 37.5665;
  static const double fallbackLongitude = 126.9780;

  /// 현재 위치의 오늘 날씨. 위치 권한이 없거나 실패하면 서울 기준으로 조회한다.
  Future<Weather> fetchTodayWeather() async {
    final position = await _currentPosition();
    if (position == null) {
      return fetchWeather(fallbackLatitude, fallbackLongitude,
          isFallbackLocation: true);
    }
    return fetchWeather(position.latitude, position.longitude);
  }

  Future<Weather> fetchWeather(double latitude, double longitude,
      {bool isFallbackLocation = false}) async {
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

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // 날씨 조회에는 동네 수준 정확도면 충분하다.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

class WeatherException implements Exception {
  WeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
