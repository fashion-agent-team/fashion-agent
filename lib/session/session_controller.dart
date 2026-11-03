import 'package:flutter/foundation.dart';

import '../models/clothes_scan.dart';
import '../models/outfit_check.dart';
import '../models/schedule_event.dart';
import '../models/weather.dart';
import '../services/capture_service.dart';
import '../services/schedule_store.dart';
import '../services/speech_service.dart';
import '../services/vision_service.dart';
import '../services/wardrobe_store.dart';
import '../services/weather_service.dart';
import '../styling/outfit_check_engine.dart';
import 'session_step.dart';

/// 옷 검사 흐름(상태 머신). 화면은 [step]과 버튼 문구만 그리고, 탭은 [primary]·[secondary]로 넘긴다.
///
/// 흐름: 날씨·오늘 일정 가져오기 → 옷 찍기 → 일정·날씨·얼룩/찢어짐 결과 → 돌아가기.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.speech,
    required this.weatherService,
    required this.schedule,
    required this.capture,
    required this.vision,
    required this.wardrobe,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SpeechService speech;
  final WeatherService weatherService;
  final ScheduleStore schedule;
  final CaptureService capture;
  final VisionService vision;
  final WardrobeStore wardrobe;
  final DateTime Function() _now;

  /// 에이전트에서 열었을 때, 끝나고 돌아갈 곳. 있으면 결과 뒤 위쪽 버튼이 "돌아가기"가 된다.
  VoidCallback? onFinished;

  SessionStep step = SessionStep.idle;
  bool busy = false;

  /// 화면에 크게 보여 줄 마지막 안내.
  String message = '';

  Weather? weather;
  List<ScheduleEvent> todayEvents = const [];
  OutfitCheck? result;

  String get primaryLabel => switch (step) {
        SessionStep.idle => '시작',
        SessionStep.preparing => '준비 중',
        SessionStep.capturing => '옷 찍기',
        SessionStep.analyzing => '분석 중',
        SessionStep.result => onFinished == null ? '다시 검사' : '돌아가기',
      };

  String get secondaryLabel => '다시 듣기';

  /// 날씨와 오늘 일정을 조용히 가져온 뒤 옷을 찍어 달라고 한다.
  /// 날씨·일정은 에이전트가 이미 말했을 수 있으므로 판단에만 쓴다.
  Future<void> start() async {
    result = null;
    _set(SessionStep.preparing);
    try {
      weather = await weatherService.fetchTodayWeather();
    } catch (_) {
      weather = null;
    }
    todayEvents = await schedule.on(_now());
    await _askForPhoto();
  }

  /// 화면 위쪽 큰 버튼.
  Future<void> primary() async {
    if (busy) return;
    switch (step) {
      case SessionStep.idle:
        await start();
      case SessionStep.capturing:
        await _check();
      case SessionStep.result:
        if (onFinished != null) {
          onFinished!();
        } else {
          await _askForPhoto();
        }
      case SessionStep.preparing:
      case SessionStep.analyzing:
        break;
    }
  }

  /// 화면 아래쪽 큰 버튼: 마지막 안내 다시 듣기.
  Future<void> secondary() async {
    if (busy) return;
    await speech.speak(message);
  }

  Future<void> _askForPhoto() async {
    _set(SessionStep.capturing);
    await _say('입을 옷을 침대나 바닥에 펼쳐 놓고, 폰을 위에서 비춘 뒤 화면 위쪽을 눌러 주세요. '
        '뒷면도 보려면 뒤집어서 한 번 더 검사하세요.');
  }

  Future<void> _check() async {
    final scan = await _scan();
    if (scan == null) return;

    final check = checkOutfit(scan.garments,
        weather: weather, todayEvents: todayEvents, now: _now());
    if (check.unsure != null) {
      _set(SessionStep.capturing);
      await _say(check.unsure!);
      return;
    }
    result = check;
    _set(SessionStep.result);
    await _say('${checkSpeech(check)} '
        '${onFinished == null ? '다시 검사하려면' : '돌아가려면'} 위쪽, 다시 들으려면 아래쪽을 눌러 주세요.');
  }

  /// 찍고 분석한다. 다시 찍어야 하면 안내하고 null을 돌려준다.
  Future<ClothesScan?> _scan() async {
    busy = true;
    _set(SessionStep.analyzing);
    try {
      await _say('찰칵. 분석할게요.');
      final photo = await capture.capture();
      final scan = await vision.describe(photo, ScanPurpose.outfit);
      if (scan.needsRetake) {
        _set(SessionStep.capturing);
        await _say(_retakeSpeech(scan));
        return null;
      }
      await wardrobe.addAll(scan.garments);
      return scan;
    } catch (_) {
      _set(SessionStep.capturing);
      await _say('분석하지 못했어요. 인터넷 연결을 확인하고 다시 위쪽을 눌러 주세요.');
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _retakeSpeech(ClothesScan scan) {
    if (scan.isDark) return '너무 어두워요. 불을 켜고 다시 위쪽을 눌러 주세요.';
    if (scan.framing != null) return '${scan.framing} 그다음 위쪽을 눌러 주세요.';
    return '옷을 찾지 못했어요. 옷이 화면에 다 들어오게 폰을 조금 더 멀리 하고 위쪽을 눌러 주세요.';
  }

  Future<void> _say(String text) async {
    message = text;
    notifyListeners();
    await speech.speak(text);
  }

  void _set(SessionStep next) {
    step = next;
    notifyListeners();
  }
}
