import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/listen_service.dart';
import '../services/gateway_auth.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../services/turn_api.dart';
import '../services/weather_service.dart';
import '../styling/weather_rules.dart';
import 'acknowledge.dart';
import 'agent_speech.dart';
import 'command_listener.dart';
import 'intent_router.dart';
import 'onboarding_flow.dart';
import 'small_talk.dart';
import 'utterance_end.dart';
import 'voice_picker.dart';
import 'wake_word.dart';

/// 화면의 마스코트가 보여 줄 지금 상태.
enum AgentPhase {
  /// 기다리는 중(이름을 부르면 대답).
  idle,

  /// 사용자의 말을 듣는 중.
  listening,

  /// 알아들은 말을 처리하는 중(서버를 기다림).
  thinking,

  /// 말하는 중.
  speaking,
}

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
    this.handsFree = false,
  }) : location = location ?? LocationProvider() {
    onboarding.onSay ??= showMessage;
    _command = CommandListener(listen, ask: _say);
  }

  late final CommandListener _command;

  /// 마스코트가 보여 줄 상태.
  AgentPhase phase = AgentPhase.idle;

  void _setPhase(AgentPhase p) {
    if (phase == p) return;
    phase = p;
    notifyListeners();
  }

  /// 서버 답이 이보다 늦으면 추임새를 한다. 빨리 오면 추임새 없이 바로 답한다.
  static const ackAfter = Duration(milliseconds: 300);

  final SpeechService speech;
  final ListenService listen;
  final ProfileStore profiles;
  final OnboardingFlow onboarding;
  final WeatherService weatherService;
  final TurnApi? turns;
  final LocationProvider location;

  /// 화면을 누르지 않고 에이전트 이름을 불러 말하기. 켜 두면 앱이 화면에 있는 동안 계속 듣는다.
  final bool handsFree;
  bool _waking = false;
  bool _paused = false;

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
  Future<void> start() async {
    await _busy(() async {
      profile = await profiles.load();
      if (profile == null || !profile!.isOnboarded) {
        profile = await onboarding.run();
        if (handsFree) {
          await _say('앞으로는 화면을 누르지 않아도 돼요. "$wakeName" 하고 부르면 언제든 대답할게요.');
        }
      } else {
        await _reconnect();
        await _say(returningGreeting(profile!.agentName!,
            callName: profile!.callName));
        // 동의 단계가 생기기 전에 깔았던 사용자는 한 번만 묻는다.
        if (!profile!.consented) {
          final at = await onboarding.askConsent();
          if (at != null) {
            profile = profile!.copyWith(consent: at);
            await profiles.save(profile!);
          }
        }
      }
      unawaited(speech.prefetch(const [
        '말씀해 주세요.',
        '네, 말씀해 주세요.',
        shortAcknowledgement,
        askMore,
      ]));
      await _listenAndHandle();
    });
    unawaited(_wakeLoop());
  }

  /// 게이트웨이 주소가 있는데 로그인이 풀려 있으면 다시 로그인한다.
  /// 2026-11-06 폰 확인: 서버 DB를 새로 만들자 로그인이 풀렸고, 로그인은 온보딩에서만 해서
  /// 다시 깔아도 계속 폰 안 기능으로만 돌았다(agent·GPT에 말이 안 감).
  Future<void> _reconnect() async {
    final api = turns;
    if (api == null || await api.available) return;
    await _say('에이전트 서버에 다시 로그인할게요. $signInGuide');
    final id = await onboarding.account.signIn();
    if (id == null || !await api.available) {
      await _say('로그인이 잘 안 돼서, 지금은 폰 안에서 되는 것만 같이 할게요.');
      return;
    }
    final linked = profile!.copyWith(accountId: id);
    try {
      await onboarding.account.upload(id, linked);
    } catch (_) {
      // 회원정보 올리기는 다음에 다시 해도 된다. 대화는 이어 간다.
    }
    await profiles.save(linked);
    profile = linked;
  }

  /// 화면 위쪽 큰 버튼: 말하기. 이름을 부르지 않아도 된다.
  ///
  /// 에이전트가 말하는 중에 누르면 말을 끊는다. 하던 대화가 이어서 듣는 차례면 바로 듣는다.
  Future<void> talk() async {
    if (busy) {
      if (speech.speaking) await speech.stop();
      return;
    }
    await _busy(() async {
      // 이름을 기다리며 듣던 것을 먼저 멈춘다. busy를 켠 뒤라 이름 듣기는 다시 시작하지 않는다.
      if (_waking) await listen.cancel();
      await _say('말씀해 주세요.');
      await _listenAndHandle();
    });
  }

  /// 부를 이름. 온보딩에서 지은 에이전트 이름이다.
  String get wakeName => profile?.agentName ?? defaultWakeName;

  /// 한 가지를 마친 뒤 하는 안내.
  String get _nextHint =>
      handsFree ? '다른 게 필요하면 "$wakeName" 하고 불러 주세요.' : tapToTalk;

  /// 앱이 화면에서 나가면 듣기를 멈춘다.
  Future<void> pauseHandsFree() async {
    _paused = true;
    await listen.cancel();
  }

  /// 앱이 다시 화면에 오면 이름 듣기를 다시 시작한다.
  void resumeHandsFree() {
    _paused = false;
    unawaited(_wakeLoop());
  }

  /// 이름이 들릴 때까지 계속 듣는다. "코디야"면 "네, 말씀해 주세요." 뒤 한 번 더 듣고,
  /// "코디야 오늘 뭐 입지?"처럼 이름 뒤에 말이 있으면 바로 그 말을 처리한다.
  Future<void> _wakeLoop() async {
    if (!handsFree || _waking || _paused) return;
    _waking = true;
    var quickMisses = 0;
    try {
      while (!_paused) {
        if (busy) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        final started = DateTime.now();
        final heard = await listen.listen(
          listenFor: const Duration(seconds: 60),
          // "코디야 … 오늘 뭐 입지"처럼 이름 뒤에 잠깐 쉬어도 이어 듣게.
          pauseFor: const Duration(seconds: 3),
          // 이름을 부르기 전까지는 마이크를 끄지 않고 계속 듣는다. 예전에는 3초 조용하면 끄고 다시 켰는데,
          // 다시 켜는 사이에 부르면 못 들었다(2026-11-09 진행 님 폰 확인: 가만히 있다 부르면 귀를 닫고 있는 것 같다).
          waitFor: const Duration(seconds: 60),
          // 이름만 부르고 기다리면 3초를 다 기다리지 않고 바로 대답한다(2026-11-06 폰 확인: 불러도 대답이 없다고 느낌).
          // "심청아 내일 뭐 입지?"처럼 이름 뒤 명령이 끝났으면 그것도 바로 처리한다(2026-11-09 발표 피드백: 텀이 길다).
          stopWhen: (partial) {
            final rest = afterWakeWord(partial, wakeName);
            return rest != null &&
                (rest.isEmpty || utteranceEnd(rest) == UtteranceEnd.complete);
          },
          settle: const Duration(milliseconds: 400),
        );
        if (_paused || busy) continue;
        if (heard == null) {
          // 권한이 없거나 인식기가 바로 실패하면 쉬었다가 다시 한다.
          final quick =
              DateTime.now().difference(started) < const Duration(seconds: 1);
          quickMisses = quick ? quickMisses + 1 : 0;
          // 예전에는 5초를 쉬어서 그동안 이름을 불러도 못 들었다(2026-11-09 피드백: 이름을 너무 못 듣는다).
          if (quickMisses >= 3) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          continue;
        }
        quickMisses = 0;
        final rest = afterWakeWord(heard, wakeName);
        if (rest == null) continue;
        await _busy(() async {
          if (rest.isEmpty) {
            final call = profile?.callName;
            await _say(call == null ? '네, 말씀해 주세요.' : '네, $call. 말씀해 주세요.');
            await _listenAndHandle();
          } else {
            await handle(await _command.complete(rest));
          }
        });
      }
    } finally {
      _waking = false;
    }
  }

  @override
  void dispose() {
    _paused = true;
    unawaited(listen.cancel());
    super.dispose();
  }

  /// 화면 아래쪽 큰 버튼: 마지막 안내 다시 듣기.
  Future<void> repeat() async {
    if (busy) return;
    await speech.speak(message);
  }

  /// 명령을 한 번 듣는다. 듣기 전에 "띵" 소리로 말해도 된다고 알린다.
  Future<String?> _hear() async {
    await speech.listeningCue();
    _setPhase(AgentPhase.listening);
    try {
      return await _command.hear();
    } finally {
      _setPhase(AgentPhase.thinking);
    }
  }

  Future<void> _listenAndHandle() async {
    final heard = await _hear();
    if (heard == null) {
      await _say('앗, 제가 잘 못 들었어요. $_nextHint');
      return;
    }
    await handle(heard);
  }

  /// 사용자가 한 말을 기능으로 옮긴다.
  Future<void> handle(String text) async {
    if (isHomeCommand(text)) {
      // 첫 화면에서 "첫 화면": 하던 대화를 끝내고 처음부터 듣는다.
      _sessionId = null;
      await _say('첫 화면이에요. $askFeature');
      await _listenAndHandle();
      return;
    }
    final setting = profile == null ? null : routeSetting(text);
    if (setting != null) {
      await _changeSetting(setting, text);
      return;
    }
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
          final watch = Stopwatch()..start();
          final asking = api.say(_sessionId, utterance,
              location: await location.current());
          await _acknowledgeIfSlow(asking, utterance,
              first: _sessionId == null);
          reply = await asking;
          debugPrint('[시간] agent 답 ${watch.elapsedMilliseconds}ms: $utterance');
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
          await _say('미안해요, 카메라를 켤 수가 없어요.');
          break;
        }
        fromCamera = await open(reply.sessionId, camera);
        if (fromCamera == null) {
          // "그만하기"로 나오면 옷 추천 대화를 끝낸다. 이어 두면 다음 말에 agent가 다시 카메라를 켠다(2026-11-06 폰 확인).
          _sessionId = null;
          await _say('카메라를 껐어요.');
          break;
        }
        continue;
      }
      if (reply.next == TurnNext.done) {
        _sessionId = null;
        break;
      }
      final heard = await _hear();
      if (heard == null) break;
      if (isHomeCommand(heard)) {
        _sessionId = null;
        await _say('첫 화면으로 돌아왔어요.');
        break;
      }
      utterance = heard;
    }
    await _say(_nextHint);
    return true;
  }

  /// 에이전트 이름·호칭·사용자 정보를 말로 바꾼다. 폰에 저장하고, 계정에 연결돼 있으면 서버에도 올린다.
  Future<void> _changeSetting(Setting setting, String text) async {
    final before = profile!;
    final after = switch (setting) {
      Setting.agentName => await onboarding.changeAgentName(before, said: text),
      Setting.callName => await onboarding.changeCallName(before, said: text),
      Setting.profile => await onboarding.editProfile(before, said: text),
      Setting.readProfile || Setting.voice => null,
    };
    if (setting == Setting.voice) {
      await VoicePicker(speech: speech, listen: listen).run(_say);
    }
    if (setting == Setting.readProfile) {
      await _say('${summarize(before)} '
          '바꾸고 싶으면 "내 키 바꿔 줘"처럼 말씀해 주세요.');
    }
    if (after != null) {
      profile = after;
      await profiles.save(after);
      final id = after.accountId;
      if (id != null) {
        try {
          await onboarding.account.upload(id, after);
        } catch (_) {
          // 폰에는 저장했다. 서버에는 다음에 다시 올리면 된다.
        }
      }
    }
    // 이름을 바꿨으면 새 이름으로 안내한다("다른 게 필요하면 "코디" 하고 불러 주세요.").
    await _say(_nextHint);
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
        await _say('좋아요, 옷 같이 볼게요.');
        await open();
        await _say('옷 다 봤어요. $_nextHint');
        return;
      case Intent.faceCheck:
        await _say('얼굴 확인 기능은 지금 준비 중이에요.');
      case Intent.schedule:
        await _say('일정 기능은 지금 준비 중이에요.');
      case Intent.help:
        await _say(featureIntro);
      case Intent.unknown:
        await _say(smallTalk(text) ?? unknownSpeech);
    }
    await _say(_nextHint);
  }

  Future<String> _weatherSpeech() async {
    try {
      final weather = await weatherService.fetchTodayWeather();
      return '${weather.toSpeech()} ${dailyRangeAdvice(weather) ?? ''}'.trim();
    } catch (_) {
      return '미안해요, 날씨를 못 가져왔어요. 인터넷이 연결돼 있는지 한번 봐 주실래요?';
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
      phase = AgentPhase.idle;
      notifyListeners();
    }
  }

  Future<void> _say(String text) async {
    message = text;
    _setPhase(AgentPhase.speaking);
    notifyListeners();
    try {
      await speech.speak(text);
    } finally {
      _setPhase(busy ? AgentPhase.thinking : AgentPhase.idle);
    }
  }

  /// 서버 답이 [ackAfter] 안에 오지 않으면 들은 말에 맞는 추임새를 한다("네, 내일 입을 옷을 골라 볼게요.").
  /// 새 요청이 아니면(되묻기에 대한 답) 짧게 "네, 잠시만요."만 한다. 답이 먼저 오면 아무 말도 하지 않는다.
  Future<void> _acknowledgeIfSlow(Future<Object?> pending, String heard,
      {required bool first}) async {
    var arrived = false;
    final done =
        pending.then((_) => arrived = true, onError: (_) => arrived = true);
    await Future.any([done, Future<void>.delayed(ackAfter)]);
    if (arrived) return;
    final ack = first ? acknowledgementFor(heard) : null;
    final text = ack ??
        (heard.replaceAll(' ', '').length >= 4 ? shortAcknowledgement : null);
    if (text == null) return;
    message = text;
    _setPhase(AgentPhase.speaking);
    notifyListeners();
    await speech.speak(text);
    _setPhase(AgentPhase.thinking);
  }

  /// 온보딩 대화도 화면에 보이게 한다.
  void showMessage(String text) {
    message = text;
    notifyListeners();
  }
}
