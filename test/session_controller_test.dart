import 'package:fashion_agent/models/clothes_scan.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/screens/session_screen.dart';
import 'package:fashion_agent/services/capture_service.dart';
import 'package:fashion_agent/services/fake_vision_service.dart';
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
}) =>
    SessionController(
      speech: speech ?? FakeSpeech(),
      weatherService: FakeWeatherService(),
      capture: FakeCaptureService(),
      vision: vision ?? FakeVisionService(),
      wardrobe: wardrobe ?? InMemoryWardrobeStore(),
    );

void main() {
  test('날씨를 읽고 고른 옷을 찍어 달라고 한다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(speech: speech);
    await c.start();

    expect(speech.spoken[1], startsWith('오늘 날씨는 맑음입니다.'));
    expect(c.step, SessionStep.capturingOutfit);
    expect(speech.spoken.last, contains('펼쳐 놓고'));
  });

  test('부딪히는 조합이면 경고하고, 옷장 대안 → 꺼낸 옷 확인 → 다시 피드백까지 간다', () async {
    final speech = FakeSpeech();
    final wardrobe = InMemoryWardrobeStore();
    final c = controllerWith(speech: speech, wardrobe: wardrobe);
    await c.start();

    await c.primary(); // 고른 옷 찍기
    expect(c.step, SessionStep.feedback);
    expect(speech.spoken.last, contains('상의는 빨간색 셔츠, 면 같음, 약간 구김 있음.'));
    expect(speech.spoken.last, contains('빨간색과 초록색은 서로 부딪혀 보일 수 있어요.'));

    await c.secondary(); // 다른 옷 찾기
    expect(c.step, SessionStep.capturingCloset);

    await c.primary(); // 옷장 찍기
    expect(c.step, SessionStep.alternative);
    expect(speech.spoken.last,
        contains('초록색 면바지 대신 가운데 아래, 왼쪽에서 두 번째에 있는 베이지 면바지는 어때요?'));

    await c.primary(); // 꺼냈어요
    expect(c.step, SessionStep.checkingPicked);

    await c.primary(); // 꺼낸 옷 찍기
    expect(c.step, SessionStep.feedback);
    expect(speech.spoken.last, startsWith('맞아요. 잘 어울리는 조합이에요.'));

    await c.primary(); // 다음 → 겉옷
    expect(c.step, SessionStep.outerAdvice);
    expect(speech.spoken.last, contains('자켓이나 가디건'));

    await c.primary(); // 완료
    expect(c.step, SessionStep.done);
    expect(speech.spoken.last, contains('빨간색 셔츠, 베이지 면바지'));

    // 사진은 저장하지 않고 본 옷의 설명만 쌓인다.
    expect(wardrobe.garments.length, 2 + 3 + 1);
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

    expect(c.step, SessionStep.capturingOutfit);
    expect(speech.spoken.last, contains('너무 어두워요'));
  });

  test('에이전트에서 열면 날씨 안내 없이 옷 검사부터 하고, 끝나면 돌아간다', () async {
    final speech = FakeSpeech();
    final c = controllerWith(speech: speech);
    var finished = false;
    c.onFinished = () => finished = true;
    await c.startOutfitCheck();

    expect(speech.spoken, hasLength(1));
    expect(speech.spoken.single, contains('펼쳐 놓고'));
    expect(c.weather, isNotNull);

    await c.primary(); // 고른 옷 찍기
    await c.primary(); // 다음 → 겉옷
    await c.primary(); // 완료
    expect(c.step, SessionStep.done);
    expect(c.primaryLabel, '돌아가기');
    await c.primary();
    expect(finished, isTrue);
  });

  testWidgets('화면은 위·아래 두 개의 큰 버튼이다', (tester) async {
    final c = controllerWith();
    await tester.pumpWidget(MaterialApp(home: SessionScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.text('고른 옷 찍기'), findsOneWidget);
    expect(find.text('다시 듣기'), findsOneWidget);

    await tester.tap(find.text('고른 옷 찍기'));
    await tester.pumpAndSettle();
    expect(find.text('다른 옷 찾기'), findsOneWidget);
  });
}
