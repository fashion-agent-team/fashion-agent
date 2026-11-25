import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/capture_service.dart';
import 'package:fashion_agent/services/fake_vision_service.dart';
import 'package:fashion_agent/services/listen_service.dart';
import 'package:fashion_agent/services/schedule_store.dart';
import 'package:fashion_agent/services/vision_service.dart';
import 'package:fashion_agent/services/wardrobe_store.dart';
import 'package:fashion_agent/session/session_controller.dart';

import 'fake_speech.dart';
import 'fake_weather.dart';

/// 맑고 12도(체감 12도), 최저 8도·최고 16도, 비 10%.
const coolWeather = Weather(
  temperature: 12,
  apparentTemperature: 12,
  minTemperature: 8,
  maxTemperature: 16,
  weatherCode: 0,
  precipitationProbability: 10,
);

/// 2026-11-03 오전 9시, [coolWeather]인 날의 옷 검사 세션.
SessionController controllerWith({
  FakeSpeech? speech,
  ListenService? listen,
  VisionService? vision,
  WardrobeStore? wardrobe,
  List<ScheduleEvent> events = const [],
}) =>
    SessionController(
      speech: speech ?? FakeSpeech(),
      weatherService: FakeWeatherService(coolWeather),
      schedule: InMemoryScheduleStore([...events]),
      capture: FakeCaptureService(),
      vision: vision ?? FakeVisionService(),
      wardrobe: wardrobe ?? InMemoryWardrobeStore(),
      listen: listen,
      clock: () => DateTime(2026, 11, 3, 9),
    );
