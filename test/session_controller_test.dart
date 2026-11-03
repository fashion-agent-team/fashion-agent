import 'package:fashion_agent/models/clothes_scan.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/screens/session_screen.dart';
import 'package:fashion_agent/services/capture_service.dart';
import 'package:fashion_agent/services/fake_vision_service.dart';
import 'package:fashion_agent/services/schedule_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/vision_service.dart';
import 'package:fashion_agent/services/wardrobe_store.dart';
import 'package:fashion_agent/services/weather_service.dart';
import 'package:fashion_agent/session/session_controller.dart';
import 'package:fashion_agent/session/session_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeech implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);
}

class FakeWeatherService implements WeatherService {
  FakeWeatherService({this.apparent = 12});

  final double apparent;

  @override
  Future<Weather> fetchTodayWeather() async => Weather(
        temperature: apparent,
        apparentTemperature: apparent,
        minTemperature: 8,
        maxTemperature: 16,
        weatherCode: 0,
        precipitationProbability: 10,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SessionController controllerWith({
  FakeSpeech? speech,
  VisionService? vision,
  WardrobeStore? wardrobe,
  List<ScheduleEvent> events = const [],
}) =>
    SessionController(
      speech: speech ?? FakeSpeech(),
      weatherService: FakeWeatherService(),
      schedule: InMemoryScheduleStore([...events]),
      capture: FakeCaptureService(),
      vision: vision ?? FakeVisionService(),
      wardrobe: wardrobe ?? InMemoryWardrobeStore(),
      clock: () => DateTime(2026, 11, 3, 9),
    );

void main() {
  test('날씨와 일정을 조용히 가져오고 옷을 찍어 달라고 한다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(speech: speech);
    await c.start();

    expect(speech.spoken, hasLength(1));
    expect(speech.spoken.single, contains('펼쳐 놓고'));
    expect(c.weather, isNotNull);
    expect(c.step, SessionStep.capturing);
  });

  test('찍으면 일정·날씨·얼룩을 한 번에 알려 주고, 끝나면 돌아간다', () async {
    final speech = FakeSpeech();
    final wardrobe = InMemoryWardrobeStore();
    final c = controllerWith(
      speech: speech,
      wardrobe: wardrobe,
      events: [ScheduleEvent(title: '면접', start: DateTime(2026, 11, 3, 14))],
    );
    var finished = false;
    c.onFinished = () => finished = true;
    await c.start();

    await c.primary(); // 옷 찍기
    expect(c.step, SessionStep.result);
    final said = speech.spoken.last;
    expect(said, startsWith('보이는 옷은 남색 셔츠, 파란색 청바지예요.'));
    expect(said, contains('오후 2시 면접 일정 기준으로 볼게요.'));
    expect(said, contains('파란색 청바지는 편한 옷이라 면접에는'));
    expect(said, contains('겉옷은 보이지 않아요.'));
    expect(said, contains('남색 셔츠 오른쪽 소매 끝에 얼룩이 있어요.'));
    expect(c.result?.allGood, isFalse);

    // 사진은 저장하지 않고 본 옷의 설명만 쌓인다.
    expect(wardrobe.garments, hasLength(2));

    expect(c.primaryLabel, '돌아가기');
    await c.primary();
    expect(finished, isTrue);
  });

  test('어두우면 다시 찍어 달라고 한다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(
      speech: speech,
      vision: FakeVisionService(scripted: {
        ScanPurpose.outfit: [const ClothesScan(garments: [], isDark: true)],
      }),
    );
    await c.start();
    await c.primary();

    expect(c.step, SessionStep.capturing);
    expect(speech.spoken.last, contains('너무 어두워요'));
  });

  testWidgets('화면은 위·아래 두 개의 큰 버튼이다', (tester) async {
    final c = controllerWith();
    await tester.pumpWidget(MaterialApp(home: SessionScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.text('옷 찍기'), findsOneWidget);
    expect(find.text('다시 듣기'), findsOneWidget);

    await tester.tap(find.text('옷 찍기'));
    await tester.pumpAndSettle();
    expect(find.text('다시 검사'), findsOneWidget);
  });
}
