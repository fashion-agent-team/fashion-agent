import 'package:flutter/foundation.dart';

import '../models/clothes_scan.dart';
import '../models/garment.dart';
import '../models/outfit_feedback.dart';
import '../models/weather.dart';
import '../services/capture_service.dart';
import '../services/speech_service.dart';
import '../services/vision_service.dart';
import '../services/wardrobe_store.dart';
import '../services/weather_service.dart';
import '../styling/color_rules.dart';
import '../styling/feedback_engine.dart';
import '../styling/korean.dart';
import '../styling/position_speech.dart';
import '../styling/weather_rules.dart';
import 'session_step.dart';

/// 세션 전체 흐름(상태 머신). 화면은 [step]과 버튼 문구만 그리고, 탭은 [primary]·[secondary]로 넘긴다.
///
/// 흐름: 날씨 → 고른 옷 찍기 → 피드백 → 겉옷 → 완료.
/// 피드백에서 "다른 옷 찾기"를 누르면 옷장 찍기 → 대안 안내 → 꺼낸 옷 확인 → 다시 피드백.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.speech,
    required this.weatherService,
    required this.capture,
    required this.vision,
    required this.wardrobe,
  });

  final SpeechService speech;
  final WeatherService weatherService;
  final CaptureService capture;
  final VisionService vision;
  final WardrobeStore wardrobe;

  /// 에이전트에서 열었을 때, 끝나고 돌아갈 곳. 있으면 완료 버튼이 "돌아가기"가 된다.
  VoidCallback? onFinished;

  SessionStep step = SessionStep.idle;
  bool busy = false;

  /// 화면에 크게 보여 줄 마지막 안내.
  String message = '';

  Weather? weather;
  OutfitFeedback? feedback;

  Garment? _keep;
  Garment? _replace;
  List<Garment> _closet = const [];
  List<Garment> _alternatives = const [];
  int _altIndex = 0;

  Garment? get currentAlternative =>
      _altIndex < _alternatives.length ? _alternatives[_altIndex] : null;

  String get primaryLabel => switch (step) {
        SessionStep.idle => '시작',
        SessionStep.briefing => '날씨 확인 중',
        SessionStep.capturingOutfit => '고른 옷 찍기',
        SessionStep.analyzing => '분석 중',
        SessionStep.feedback || SessionStep.outerAdvice => '다음',
        SessionStep.done => onFinished == null ? '처음부터' : '돌아가기',
        SessionStep.capturingCloset => '옷장 찍기',
        SessionStep.alternative => '꺼냈어요',
        SessionStep.checkingPicked => '꺼낸 옷 찍기',
      };

  String get secondaryLabel => switch (step) {
        SessionStep.feedback => '다른 옷 찾기',
        SessionStep.alternative => '다른 대안',
        _ => '다시 듣기',
      };

  Future<void> start() async {
    _set(SessionStep.briefing);
    await _say('패션 에이전트입니다. 오늘 날씨를 확인할게요.');
    try {
      weather = await weatherService.fetchTodayWeather();
      await _say(weather!.toSpeech());
    } catch (_) {
      await _say('날씨를 가져오지 못했어요. 날씨 없이 진행할게요.');
    }
    await _askForOutfit();
  }

  /// 에이전트의 "옷 검사". 날씨는 이미 에이전트가 말했을 수 있으니 조용히 가져와 판단에만 쓴다.
  Future<void> startOutfitCheck() async {
    feedback = null;
    _set(SessionStep.briefing);
    try {
      weather = await weatherService.fetchTodayWeather();
    } catch (_) {
      weather = null;
    }
    await _askForOutfit();
  }

  /// 화면 위쪽 큰 버튼.
  Future<void> primary() async {
    if (busy) return;
    switch (step) {
      case SessionStep.idle:
        await start();
      case SessionStep.capturingOutfit:
        await _scanOutfit();
      case SessionStep.feedback:
        final advice = weather == null ? null : outerAdvice(weather!);
        if (advice != null) {
          _set(SessionStep.outerAdvice);
          await _say('$advice 다 됐으면 위쪽을 눌러 주세요.');
        } else {
          await _finish();
        }
      case SessionStep.outerAdvice:
        await _finish();
      case SessionStep.done:
        if (onFinished != null) {
          onFinished!();
        } else {
          await _askForOutfit();
        }
      case SessionStep.capturingCloset:
        await _scanCloset();
      case SessionStep.alternative:
        _set(SessionStep.checkingPicked);
        await _say('꺼낸 옷을 카메라 앞에 들고 위쪽을 눌러 주세요.');
      case SessionStep.checkingPicked:
        await _checkPicked();
      case SessionStep.briefing:
      case SessionStep.analyzing:
        break;
    }
  }

  /// 화면 아래쪽 큰 버튼.
  Future<void> secondary() async {
    if (busy) return;
    switch (step) {
      case SessionStep.feedback:
        _set(SessionStep.capturingCloset);
        await _say('옷장 앞에 서서 폰을 옷장 쪽으로 비추고 위쪽을 눌러 주세요.');
      case SessionStep.alternative:
        _altIndex++;
        if (currentAlternative == null) {
          _set(SessionStep.feedback);
          await _say('더 찾은 대안이 없어요. 옷장의 다른 칸을 보려면 아래쪽을 눌러 주세요.');
        } else {
          await _sayAlternative();
        }
      default:
        await speech.speak(message);
    }
  }

  Future<void> _askForOutfit() async {
    _set(SessionStep.capturingOutfit);
    await _say('입고 싶은 상의와 하의를 침대나 바닥에 펼쳐 놓고, '
        '폰을 위에서 비춘 뒤 화면 위쪽을 눌러 주세요.');
  }

  Future<void> _finish() async {
    _set(SessionStep.done);
    final names = feedback?.garments.map((g) => g.spokenName).join(', ');
    await _say(
        names == null ? '오늘 코디 확인을 마쳤어요.' : '오늘 코디는 $names입니다. 좋은 하루 보내세요.');
  }

  Future<void> _scanOutfit() async {
    final scan =
        await _scan(ScanPurpose.outfit, retryStep: SessionStep.capturingOutfit);
    if (scan == null) return;

    final result = evaluateOutfit(scan.garments, weather: weather);
    if (result.verdict == Verdict.unsure) {
      _set(SessionStep.capturingOutfit);
      await _say(result.reasons.join(' '));
      return;
    }
    feedback = result;
    _set(SessionStep.feedback);
    await _say('${_describe(result.garments)} ${result.toSpeech()} '
        '${result.verdict == Verdict.clash ? '다른 옷을 찾으려면 아래쪽을, 그대로 입으려면 위쪽을 눌러 주세요.' : '다음은 위쪽, 다른 옷 찾기는 아래쪽을 눌러 주세요.'}');
  }

  Future<void> _scanCloset() async {
    final scan =
        await _scan(ScanPurpose.closet, retryStep: SessionStep.capturingCloset);
    if (scan == null) return;

    final top = feedback?.top, bottom = feedback?.bottom;
    _closet = scan.garments;
    _alternatives = const [];
    if (top != null && bottom != null) {
      // 하의를 먼저 바꿔 보고, 없으면 상의를 바꿔 본다.
      for (final (keep, replace) in [(top, bottom), (bottom, top)]) {
        final found =
            findAlternatives(keep: keep, replace: replace, closet: _closet);
        if (found.isNotEmpty) {
          _keep = keep;
          _replace = replace;
          _alternatives = found;
          break;
        }
      }
    }
    if (_alternatives.isEmpty) {
      _set(SessionStep.capturingCloset);
      await _say('이 사진에서는 어울리는 대안을 찾지 못했어요. 옷장의 다른 칸을 비추고 위쪽을 눌러 주세요.');
      return;
    }
    _altIndex = 0;
    await _sayAlternative();
  }

  Future<void> _sayAlternative() async {
    final alt = currentAlternative!;
    final where = describePosition(alt, _closet);
    final match = matchColors(_keep!, alt);
    _set(SessionStep.alternative);
    await _say('${_replace!.spokenName} 대신 '
        '${where.isEmpty ? '' : '$where에 있는 '}${eunNeun(alt.spokenName)} 어때요? '
        '${match.reason} 꺼냈으면 위쪽, 다른 대안은 아래쪽을 눌러 주세요.');
  }

  Future<void> _checkPicked() async {
    final scan =
        await _scan(ScanPurpose.check, retryStep: SessionStep.checkingPicked);
    if (scan == null) return;

    final expected = currentAlternative!;
    final seen = scan.garments.first;
    final same = isSameGarment(expected, seen);
    if (same == null) {
      _set(SessionStep.checkingPicked);
      await _say('확실하지 않아요. 불을 켜고 다시 비춘 뒤 위쪽을 눌러 주세요.');
      return;
    }
    if (!same) {
      _set(SessionStep.alternative);
      await _say('이건 ${seen.spokenName}이에요. 안내한 옷은 ${expected.spokenName}이에요. '
          '다시 꺼냈으면 위쪽을 눌러 주세요.');
      return;
    }
    feedback = evaluateOutfit([_keep!, seen], weather: weather);
    _set(SessionStep.feedback);
    await _say('맞아요. ${feedback!.toSpeech()} 다음은 위쪽을 눌러 주세요.');
  }

  /// 찍고 분석한다. 다시 찍어야 하면 안내하고 null을 돌려준다.
  Future<ClothesScan?> _scan(ScanPurpose purpose,
      {required SessionStep retryStep}) async {
    busy = true;
    _set(SessionStep.analyzing);
    try {
      await _say('찰칵. 분석할게요.');
      final photo = await capture.capture();
      final scan = await vision.describe(photo, purpose);
      if (scan.needsRetake) {
        _set(retryStep);
        await _say(_retakeSpeech(scan));
        return null;
      }
      await wardrobe.addAll(scan.garments);
      return scan;
    } catch (_) {
      _set(retryStep);
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

  String _describe(List<Garment> garments) => garments.map((g) {
        final label = switch (g.category) {
          GarmentCategory.top => '상의는',
          GarmentCategory.bottom => '하의는',
          _ => '',
        };
        final extra = [
          if (g.material != null) g.material,
          if (g.notes != null) g.notes
        ];
        return '$label ${g.spokenName}${extra.isEmpty ? '' : ', ${extra.join(', ')}'}.';
      }).join(' ');

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
