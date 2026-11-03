import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../models/weather.dart';
import '../services/listen_service.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../services/weather_service.dart';
import 'agent_speech.dart';
import 'intent_router.dart';
import 'onboarding_flow.dart';

/// 앱의 첫 화면 뒤에서 도는 에이전트. 처음이면 온보딩을, 아니면 인사를 하고 원하는 기능을 듣는다.
class AgentController extends ChangeNotifier {
  AgentController({
    required this.speech,
    required this.listen,
    required this.profiles,
    required this.onboarding,
    required this.weatherService,
  }) {
    onboarding.onSay ??= showMessage;
  }

  final SpeechService speech;
  final ListenService listen;
  final ProfileStore profiles;
  final OnboardingFlow onboarding;
  final WeatherService weatherService;

  /// 옷 검사 화면을 연다. 화면이 닫히면 끝난다. 화면(AgentScreen)이 채운다.
  Future<void> Function()? openOutfitCheck;

  UserProfile? profile;

  /// 화면에 크게 보여 줄 마지막 안내.
  String message = '';

  /// 묻거나 듣는 중이면 true. 그동안 버튼을 막는다.
  bool busy = false;

  /// 처음 실행이면 온보딩을, 아니면 인사를 한다. 그다음 원하는 기능을 듣는다.
  Future<void> start() => _busy(() async {
        profile = await profiles.load();
        if (profile == null || !profile!.isOnboarded) {
          profile = await onboarding.run();
        } else {
          await _say(returningGreeting(profile!.agentName!));
        }
        await _listenAndHandle();
      });

  /// 화면 위쪽 큰 버튼: 말하기.
  Future<void> talk() => _busy(() async {
        await _say('말씀해 주세요.');
        await _listenAndHandle();
      });

  /// 화면 아래쪽 큰 버튼: 마지막 안내 다시 듣기.
  Future<void> repeat() async {
    if (busy) return;
    await speech.speak(message);
  }

  Future<void> _listenAndHandle() async {
    final heard = await listen.listen();
    if (heard == null) {
      await _say('잘 듣지 못했어요. $tapToTalk');
      return;
    }
    await handle(heard);
  }

  /// 사용자가 한 말을 기능으로 옮긴다.
  Future<void> handle(String text) async {
    switch (routeIntent(text)) {
      case Intent.weather:
        await _say(await _weatherSpeech());
      case Intent.outfitCheck:
        final open = openOutfitCheck;
        if (open == null) {
          await _say('옷 검사 화면을 열 수 없어요.');
          return;
        }
        await _say('옷 검사를 시작할게요.');
        await open();
        await _say('옷 검사를 마쳤어요. $tapToTalk');
        return;
      case Intent.faceCheck:
        await _say('얼굴 확인 기능은 지금 준비 중이에요.');
      case Intent.schedule:
        await _say('일정 기능은 지금 준비 중이에요.');
      case Intent.help:
        await _say(featureIntro);
      case Intent.unknown:
        await _say('잘 이해하지 못했어요. 일정, 날씨, 얼굴 확인, 옷 검사 중에서 말씀해 주세요.');
    }
    await _say(tapToTalk);
  }

  Future<String> _weatherSpeech() async {
    try {
      final weather = await weatherService.fetchTodayWeather();
      return '${weather.toSpeech()} ${dailyRangeAdvice(weather) ?? ''}'.trim();
    } catch (_) {
      return '날씨를 가져오지 못했어요. 인터넷 연결을 확인해 주세요.';
    }
  }

  Future<void> _busy(Future<void> Function() work) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await work();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _say(String text) async {
    message = text;
    notifyListeners();
    await speech.speak(text);
  }

  /// 온보딩 대화도 화면에 보이게 한다.
  void showMessage(String text) {
    message = text;
    notifyListeners();
  }
}

/// 일교차가 이 이상이면 겉옷을 챙기라고 한다.
const bigDailyRange = 10;

/// 일교차가 크면 겉옷 안내. 아니면 null.
String? dailyRangeAdvice(Weather w) {
  final range = (w.maxTemperature - w.minTemperature).round();
  if (range < bigDailyRange) return null;
  return '오늘은 일교차가 $range도로 커요. 낮에 덥더라도 아침저녁을 위해 겉옷을 챙기세요.';
}
