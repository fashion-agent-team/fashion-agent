import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/screens/home_screen.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeech implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
}

class FakeWeatherService implements WeatherService {
  FakeWeatherService({this.fail = false});

  final bool fail;

  @override
  Future<Weather> fetchTodayWeather() async {
    if (fail) throw WeatherException('offline');
    return const Weather(
      temperature: 12,
      apparentTemperature: 10,
      minTemperature: 8,
      maxTemperature: 16,
      weatherCode: 0,
      precipitationProbability: 10,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('화면을 누르면 오늘 날씨를 읽어 준다', (tester) async {
    final speech = FakeSpeech();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
          speechService: speech, weatherService: FakeWeatherService()),
    ));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(speech.spoken.last, contains('오늘 날씨는 맑음입니다.'));
    expect(find.textContaining('맑음 12°'), findsOneWidget);
  });

  testWidgets('날씨를 못 가져오면 다시 시도하라고 알려 준다', (tester) async {
    final speech = FakeSpeech();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
          speechService: speech,
          weatherService: FakeWeatherService(fail: true)),
    ));

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(speech.spoken.last, contains('다시 눌러 주세요'));
  });
}
