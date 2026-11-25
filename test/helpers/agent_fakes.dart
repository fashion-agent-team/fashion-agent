import 'dart:async';

import 'package:fashion_agent/agent/onboarding_flow.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/models/weather.dart';
import 'package:fashion_agent/services/account_service.dart';
import 'package:fashion_agent/services/listen_service.dart';
import 'package:fashion_agent/services/permission_service.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/weather_service.dart';

import 'fake_speech_extras.dart';

/// 에이전트 시험에서 같이 쓰는 가짜들. 말한 문장은 [FakeSpeech.spoken]에 남는다.
class FakeSpeech with FakeSpeechExtras implements SpeechService {
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  int stops = 0;

  @override
  bool get speaking => false;

  @override
  Future<void> stop() async => stops++;
}

/// 정해 둔 답을 차례로 "듣는다". null은 아무 말도 못 들은 경우다.
class ScriptedListen implements ListenService {
  ScriptedListen(this.answers, {this.blockWhenDone = false});

  final List<String?> answers;

  /// 답이 다 떨어지면 null 대신 [cancel]될 때까지 기다린다. 계속 듣는 흐름을 시험할 때.
  final bool blockWhenDone;
  var _i = 0;
  Completer<String?>? _waiting;
  int cancels = 0;

  bool get waiting => _waiting != null && !_waiting!.isCompleted;

  @override
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 15),
    Duration pauseFor = const Duration(seconds: 3),
    Duration waitFor = const Duration(seconds: 8),
    bool Function(String partial)? stopWhen,
    Duration settle = const Duration(milliseconds: 700),
    bool server = false,
  }) async {
    if (_i < answers.length) return answers[_i++];
    if (!blockWhenDone) return null;
    return (_waiting = Completer<String?>()).future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final w = _waiting;
    if (w != null && !w.isCompleted) w.complete(null);
  }
}

class FakeAccount implements AccountService {
  FakeAccount({this.id, this.saved});

  final String? id;
  final UserProfile? saved;
  UserProfile? uploaded;

  @override
  Future<String?> signIn() async => id;

  @override
  Future<UserProfile?> restore(String accountId) async => saved;

  @override
  Future<void> upload(String accountId, UserProfile profile) async =>
      uploaded = profile;
}

/// 오늘 5~18도(일교차 13도), 맑음.
class FakeWeatherService implements WeatherService {
  @override
  Future<Weather> fetchTodayWeather() async => const Weather(
        temperature: 15,
        apparentTemperature: 14,
        minTemperature: 5,
        maxTemperature: 18,
        weatherCode: 0,
        precipitationProbability: 0,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 온보딩에서 흔히 하는 대답: 에이전트 이름 "하늘"로 정하고, 내 정보를 말한다(몸무게는 건너뜀).
/// 뒤에 재확인 대답('네' 등)을 붙여 쓴다.
const sampleAnswers = [
  '하늘', '네', // 에이전트 이름
  '김민수예요', '1990년 3월 5일', '남자', '회사원이에요', '170', '건너뛰기',
];

OnboardingFlow onboardingWith(FakeSpeech speech, List<String?> answers,
        {ProfileStore? store,
        AccountService? account,
        PermissionService? permissions,
        bool consentFirst = true}) =>
    OnboardingFlow(
      speech: speech,
      // 처음 켤 때 말 빠르기부터 묻는다(허용하면 동의, 음성 동의는 없음).
      listen: ScriptedListen([
        if (consentFirst) ...['괜찮아', '괜찮아'],
        ...answers
      ]),
      profiles: store ?? InMemoryProfileStore(),
      account: account ?? FakeAccount(),
      permissions: permissions,
    );
