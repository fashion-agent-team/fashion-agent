import 'dart:convert';

import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> sampleResponse({
  double temperature = 12.4,
  double apparent = 10.6,
  int code = 0,
  int? rain = 10,
}) =>
    {
      'current': {
        'temperature_2m': temperature,
        'apparent_temperature': apparent,
        'weather_code': code,
      },
      'daily': {
        'temperature_2m_max': [16.2],
        'temperature_2m_min': [7.8],
        'precipitation_probability_max': [rain],
      },
    };

void main() {
  group('Weather', () {
    test('Open-Meteo 응답을 읽는다', () {
      final weather = Weather.fromOpenMeteo(sampleResponse());
      expect(weather.temperature, 12.4);
      expect(weather.minTemperature, 7.8);
      expect(weather.maxTemperature, 16.2);
      expect(weather.condition, '맑음');
      expect(weather.precipitationProbability, 10);
    });

    test('강수 확률이 없으면 0으로 본다', () {
      final weather = Weather.fromOpenMeteo(sampleResponse(rain: null));
      expect(weather.precipitationProbability, 0);
    });

    test('날씨 코드를 한국어로 바꾼다', () {
      Weather of(int code) => Weather.fromOpenMeteo(sampleResponse(code: code));
      expect(of(3).condition, '흐림');
      expect(of(63).condition, '비');
      expect(of(81).condition, '비');
      expect(of(73).condition, '눈');
      expect(of(95).condition, '뇌우');
    });

    test('음성 안내 문장을 만든다', () {
      final speech = Weather.fromOpenMeteo(sampleResponse()).toSpeech();
      expect(speech, contains('오늘 날씨는 맑음입니다.'));
      expect(speech, contains('지금 기온은 12도'));
      expect(speech, contains('체감 온도는 11도'));
      expect(speech, contains('최저 8도, 최고 16도'));
      expect(speech, contains('강수 확률은 10퍼센트'));
      expect(speech, isNot(contains('우산')));
      expect(speech, contains('트렌치코트'));
    });

    test('영하 기온과 비 소식을 읽어 준다', () {
      final speech = Weather.fromOpenMeteo(sampleResponse(
              temperature: -3.2, apparent: -7, code: 61, rain: 80))
          .toSpeech();
      expect(speech, contains('지금 기온은 영하 3도'));
      expect(speech, contains('우산을 챙기세요'));
      expect(speech, contains('패딩'));
    });

    test('기본 위치로 조회했으면 먼저 알려 준다', () {
      final speech =
          Weather.fromOpenMeteo(sampleResponse(), isFallbackLocation: true)
              .toSpeech();
      expect(speech, startsWith('현재 위치를 알 수 없어 서울 기준'));
    });
  });

  group('WeatherService', () {
    test('좌표로 Open-Meteo를 호출한다', () async {
      late Uri requested;
      final service = WeatherService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(jsonEncode(sampleResponse()), 200);
        }),
      );

      final weather = await service.fetchWeather(37.5, 127.0);

      expect(requested.host, 'api.open-meteo.com');
      expect(requested.queryParameters['latitude'], '37.5');
      expect(requested.queryParameters['longitude'], '127.0');
      expect(weather.condition, '맑음');
    });

    test('서버 오류면 WeatherException을 던진다', () async {
      final service = WeatherService(
        client: MockClient((_) async => http.Response('error', 500)),
      );
      expect(
          service.fetchWeather(37.5, 127.0), throwsA(isA<WeatherException>()));
    });
  });
}
