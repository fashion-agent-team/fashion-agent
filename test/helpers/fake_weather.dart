import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/weather_service.dart';

/// 맑고 15도(체감 14도), 최저 5도·최고 18도, 비 0%.
const clearMildWeather = Weather(
  temperature: 15,
  apparentTemperature: 14,
  minTemperature: 5,
  maxTemperature: 18,
  weatherCode: 0,
  precipitationProbability: 0,
);

/// 정해 둔 날씨를 그대로 주는 가짜 날씨 서비스. 기본은 [clearMildWeather].
class FakeWeatherService implements WeatherService {
  FakeWeatherService([this.today = clearMildWeather]);

  final Weather today;

  @override
  Future<Weather> fetchTodayWeather() async => today;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
