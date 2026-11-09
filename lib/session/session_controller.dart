import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent_speech.dart' show isHomeCommand;
import '../models/clothes_scan.dart';
import '../models/outfit_check.dart';
import '../models/schedule_event.dart';
import '../models/weather.dart';
import '../services/capture_service.dart';
import '../services/listen_service.dart';
import '../services/schedule_store.dart';
import '../services/speech_service.dart';
import '../services/vision_service.dart';
import '../services/wardrobe_store.dart';
import '../services/weather_service.dart';
import '../styling/outfit_check_engine.dart';
import 'session_step.dart';

/// 옷 검사 흐름(상태 머신). 화면은 [step]과 버튼 문구만 그리고, 탭은 [primary]·[secondary]로 넘긴다.
///
/// 흐름: 날씨·오늘 일정 가져오기 → 옷 찍기 → 옷·얼룩/찢어짐·날씨와 일정 결과 → 돌아가기.
///
/// [listen]이 있으면 버튼 없이 말로도 된다: "찍어 줘", "다시 검사", "돌아가기"(2026-11-09 진행 님 요청).
class SessionController extends ChangeNotifier {
  SessionController({
    required this.speech,
    required this.weatherService,
    required this.schedule,
    required this.capture,
    required this.vision,
    required this.wardrobe,
    this.listen,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SpeechService speech;
  final WeatherService weatherService;
  final ScheduleStore schedule;
  final CaptureService capture;
  final VisionService vision;
  final WardrobeStore wardrobe;

  /// 말로 하는 명령을 듣는다. null이면 버튼만 쓴다(테스트).
  final ListenService? listen;
  final DateTime Function() _now;

  /// 지금 말 명령을 듣고 있는지. 버튼을 누르면 먼저 멈춘다.
  bool _listening = false;

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
    await _stopListening();
    switch (step) {
      case SessionStep.idle:
        await start();
      case SessionStep.capturing:
        await _check();
      case SessionStep.result:
        if (onFinished != null) {
          _finish();
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
    await _stopListening();
    await speech.speak(message);
    _startListening();
  }

  /// 첫 화면으로 돌아간다. 에이전트에서 열지 않았으면(돌아갈 곳이 없으면) 아무것도 하지 않는다.
  void _finish() {
    final done = onFinished;
    if (done == null) return;
    step = SessionStep.idle;
    done();
  }

  Future<void> _askForPhoto() async {
    _set(SessionStep.capturing);
    await _say('입을 옷을 침대나 바닥에 펼쳐 놓고, 폰을 위에서 비춘 뒤 화면 위쪽을 누르거나 '
        '"찍어 줘"라고 말씀해 주세요. 뒷면도 보려면 뒤집어서 한 번 더 검사하세요.');
    _startListening();
  }

  /// 말 명령을 기다린다. 기다리는 동안에도 버튼은 그대로 쓸 수 있다.
  void _startListening() {
    if (listen == null || _listening) return;
    unawaited(_listenForCommand());
  }

  Future<void> _stopListening() async {
    if (_listening) await listen?.cancel();
  }

  /// 못 알아들으면 이만큼 더 묻는다. 아무 말이 없으면 그만 듣고 버튼을 기다린다.
  static const _commandRetries = 2;

  Future<void> _listenForCommand() async {
    final l = listen!;
    _listening = true;
    try {
      for (var i = 0; i <= _commandRetries; i++) {
        final at = step;
        final heard = await l.listen();
        if (heard == null || busy || step != at) return;
        final command = sessionCommand(heard);
        if (command == SessionCommand.back && onFinished != null) {
          await _say('첫 화면으로 돌아갈게요.');
          _finish();
          return;
        }
        if (command == SessionCommand.shoot ||
            command == SessionCommand.again) {
          // 찍는 중이면 지금 비춘 옷을 검사하고, 결과를 들은 뒤면 처음부터 다시 찍는다.
          // 기다리지 않는다. 다음 듣기는 그쪽에서 새로 시작한다.
          unawaited(step == SessionStep.capturing ? _check() : _askForPhoto());
          return;
        }
        if (i < _commandRetries) await _say(_commandHint);
      }
    } finally {
      _listening = false;
    }
  }

  String get _commandHint => step == SessionStep.result
      ? '${onFinished == null ? '' : '처음으로 가려면 "첫 화면", '}'
          '다시 검사하려면 "다시 검사"라고 말씀해 주세요.'
      : '옷을 비추고 "찍어 줘"라고 말씀해 주세요.'
          '${onFinished == null ? '' : ' 그만하려면 "첫 화면"이라고 말씀해 주세요.'}';

  Future<void> _check() async {
    final scan = await _scan();
    if (scan == null) {
      _startListening();
      return;
    }

    final check = checkOutfit(scan.garments,
        weather: weather, todayEvents: todayEvents, now: _now());
    if (check.unsure != null) {
      _set(SessionStep.capturing);
      await _say(check.unsure!);
      _startListening();
      return;
    }
    result = check;
    _set(SessionStep.result);
    await _say(
        '${checkSpeech(check, weather: weather)} ${onFinished == null ? '' : '처음으로 가려면 "첫 화면", '}'
        '다시 검사하려면 "다시 검사"라고 말씀해 주세요. 다시 들으려면 화면 아래쪽을 눌러 주세요.');
    _startListening();
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

/// 옷 검사 화면에서 말로 하는 명령.
enum SessionCommand { back, again, shoot }

/// "돌아가기", "첫 화면", "그만" → back, "다시 검사", "한 번 더" → again, "찍어 줘", "검사해" → shoot. 모르면 null.
SessionCommand? sessionCommand(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), '');
  if (isHomeCommand(text)) return SessionCommand.back;
  if (RegExp(r'돌아가|돌아갈|처음화면|첫화면|메인|홈으로|그만|끝내|끝낼|나가|나갈|닫아|종료|취소').hasMatch(t)) {
    return SessionCommand.back;
  }
  if (RegExp(r'다시|한번더|또').hasMatch(t)) return SessionCommand.again;
  if (RegExp(r'찍어|찍을|찰칵|촬영|검사해|검사할|봐줘|봐주|확인해|됐어|다했어|준비됐').hasMatch(t)) {
    return SessionCommand.shoot;
  }
  return null;
}
