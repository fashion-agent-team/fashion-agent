import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/listen_service.dart';
import '../services/gateway_auth.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../services/turn_api.dart';
import '../services/weather_service.dart';
import '../styling/weather_rules.dart';
import 'agent_speech.dart';
import 'intent_router.dart';
import 'onboarding_flow.dart';

/// 앱의 첫 화면 뒤에서 도는 에이전트. 처음이면 온보딩을, 아니면 인사를 하고 원하는 기능을 듣는다.
///
/// 게이트웨이에 로그인돼 있으면([turns]) 들은 말을 agent(`/api/v1/agent/turn`)에 보내고 답을 따른다.
/// 아니면 폰 안에서 키워드로 기능을 고른다.
class AgentController extends ChangeNotifier {
  AgentController({
    required this.speech,
    required this.listen,
    required this.profiles,
    required this.onboarding,
    required this.weatherService,
    this.turns,
    LocationProvider? location,
  }) : location = location ?? LocationProvider() {
    onboarding.onSay ??= showMessage;
  }

  final SpeechService speech;
  final ListenService listen;
  final ProfileStore profiles;
  final OnboardingFlow onboarding;
  final WeatherService weatherService;
  final TurnApi? turns;
  final LocationProvider location;

  /// agent가 카메라를 켜라고 하면(`camera_*`) 카메라 화면을 연다. 카메라가 끝난 뒤의 답을 돌려준다.
  /// 그만두면 null. 화면(AgentScreen)이 채운다.
  Future<TurnReply?> Function(String sessionId, ImageKind kind)? openCamera;

  /// agent와 이어지는 대화. `done`을 받으면 비운다.
  String? _sessionId;

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
    final api = turns;
    if (api != null && await api.available && await _converse(api, text)) {
      return;
    }
    await _handleLocally(text);
  }

  /// agent와 대화한다. 로그인이 풀려 폰 안 기능으로 넘겨야 하면 false.
  Future<bool> _converse(TurnApi api, String text) async {
    var utterance = text;
    TurnReply? fromCamera;
    while (true) {
      TurnReply reply;
      if (fromCamera != null) {
        reply = fromCamera;
        fromCamera = null;
      } else {
        try {
          reply = await api.say(_sessionId, utterance,
              location: await location.current());
        } on Object catch (e) {
          debugPrint('turn 실패: $e');
          await _say(turnErrorSpeech(e));
          if (e is GatewayException && e.status == 401) {
            _sessionId = null;
            return false;
          }
          break;
        }
      }
      _sessionId = reply.sessionId;
      await _say(reply.speech);

      final camera = reply.next.camera;
      if (camera != null) {
        final open = openCamera;
        if (open == null) {
          await _say('카메라를 켤 수 없어요.');
          break;
        }
        fromCamera = await open(reply.sessionId, camera);
        if (fromCamera == null) {
          await _say('카메라를 껐어요.');
          break;
        }
        continue;
      }
      if (reply.next == TurnNext.done) {
        _sessionId = null;
        break;
      }
      final heard = await listen.listen();
      if (heard == null) break;
      utterance = heard;
    }
    await _say(tapToTalk);
    return true;
  }

  Future<void> _handleLocally(String text) async {
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
