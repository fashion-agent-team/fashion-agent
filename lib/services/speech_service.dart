import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_tts.dart';
import 'gateway_auth.dart' show GatewayException;
import 'voices.dart';

/// 앱의 모든 음성 안내를 담당한다.
///
/// 2026-11-09 발표 피드백: 기기 목소리(flutter_tts)가 딱딱하다. 기본은 폰에 받아 둔 고품질 한국어 목소리
/// (향상됨·프리미엄) 하나로 모든 안내를 읽는다. 2026-11-12부터 서버 목소리([cloud], 유진·선희 등)가 켜져 있으면
/// 유진이 기본이다(`--dart-define=CLOUD_TTS=false`로 끔). 고른 목소리는 기억한다([voices]).
/// 서버가 없거나 늦으면(4초, 앱을 켠 뒤 첫 문장은 15초) 그 문장부터는 폰 목소리로 읽는다. 사용자는 끊김 없이 듣는다.
///
/// 긴 안내는 문장으로 나눠, 첫 문장을 읽는 동안 다음 문장을 받아 둔다. 같은 문장은 폰에 기억해 두어
/// 인사·추임새·자주 하는 안내는 바로 읽는다.
class SpeechService {
  SpeechService({this.cloud, VoiceStore? voices, TtsCache? cache})
      : _voices = voices ?? LocalVoiceStore(),
        _cache = cache ?? TtsCache() {
    _tts.setStartHandler(() => _deviceSpeaking = true);
    _tts.setCompletionHandler(() => _deviceSpeaking = false);
    _tts.setCancelHandler(() => _deviceSpeaking = false);
    _tts.setErrorHandler((_) => _deviceSpeaking = false);
    // 안내가 끝난 뒤 다음 안내로 넘어가도록 speak가 읽기를 마칠 때까지 기다리게 한다.
    _tts.awaitSpeakCompletion(true);
    if (_isIOS) {
      _tts.setSharedInstance(true);
    }
    _tts.setVolume(1.0);
    _tts.setSpeechRate(_rate);
    unawaited(_loadRate());
  }

  /// 처음 읽는 속도. 0.5가 폰의 보통 속도, 클수록 빠르다.
  ///
  /// 2026-11-10 진행 님: 0.5도 빨라서 시각장애인은 한 번 놓치면 이해하기 어렵다. 그래서 더 느리게 시작하고,
  /// 첫 실행 때 빠르기를 묻고, "천천히 말해 줘"/"빠르게 말해 줘"로 바꿀 수 있게 한다([changeRate]).
  static const speechRate = 0.42;

  /// 한 번에 바꾸는 폭과 바꿀 수 있는 범위.
  static const rateStep = 0.06, minRate = 0.3, maxRate = 0.6;

  static const _rateKey = 'tts.rate';
  double _rate = speechRate;

  /// 지금 읽는 속도.
  double get rate => _rate;

  Future<void> _loadRate() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getDouble(_rateKey);
      if (saved != null) {
        _rate = saved.clamp(minRate, maxRate);
        await _tts.setSpeechRate(_rate);
      }
    } on Object catch (e) {
      debugPrint('말 속도 불러오기 실패: $e');
    }
  }

  /// 계정에 저장된 빠르기로 맞춘다(다른 폰에서 로그인했을 때).
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(minRate, maxRate);
    await _tts.setSpeechRate(_rate);
    try {
      await (await SharedPreferences.getInstance()).setDouble(_rateKey, _rate);
    } on Object catch (e) {
      debugPrint('말 속도 저장 실패: $e');
    }
  }

  /// 말 속도를 [steps]칸만큼 바꾸고 기억한다(음수면 느리게). 더 바꿀 수 없으면 false.
  Future<bool> changeRate(int steps) async {
    final next = (_rate + steps * rateStep).clamp(minRate, maxRate);
    if ((next - _rate).abs() < 0.001) return false;
    _rate = next;
    await _tts.setSpeechRate(_rate);
    try {
      await (await SharedPreferences.getInstance()).setDouble(_rateKey, _rate);
    } on Object catch (e) {
      debugPrint('말 속도 저장 실패: $e');
    }
    return true;
  }

  /// 구글 목소리를 받는 곳. null이면 언제나 폰 목소리.
  TtsApi? cloud;

  final VoiceStore _voices;
  final TtsCache _cache;
  final FlutterTts _tts = FlutterTts();
  AudioPlayer? _player;
  bool _deviceSpeaking = false;
  bool _playing = false;
  Completer<void>? _playDone;

  /// [stop]하거나 새로 읽기 시작할 때마다 늘린다. 읽던 문장들은 번호가 바뀌면 멈춘다.
  int _generation = 0;

  Voice? _voice;

  /// 서버 목소리가 실패하면 잠깐(1분) 폰 목소리만 쓴다. 매 문장 4초씩 기다리지 않게.
  DateTime? _cloudPausedUntil;

  static const _firstTimeout = Duration(seconds: 4);
  static const _slowTimeout = Duration(seconds: 9);

  /// 앱을 켜고 서버 목소리를 처음 받을 때. 로그인, 서버의 첫 연결, Azure 첫 연결이 겹쳐 9초를 넘기기도 한다
  /// (2026-11-12 시뮬레이터: 첫 안내만 폰 목소리로 읽음). 한 번 받으면 [_slowTimeout]으로 돌아간다.
  static const _coldTimeout = Duration(seconds: 15);

  /// 서버 목소리가 한 번 늦거나 실패하면 이만큼 폰 목소리로 읽고 다시 서버로 간다(예전 1분: 오래 폰 목소리로 남음).
  static const _retryAfter = Duration(seconds: 20);

  /// 서버 목소리를 한 번이라도 받았는지.
  bool _cloudWarm = false;

  /// [warmUp]이 진행 중일 때 그 작업.
  Future<void>? _warming;

  /// 앱을 켜자마자 불러, 첫 안내 전에 로그인과 서버·Azure 연결을 미리 해 둔다.
  /// 짧은 말("네.")을 지금 목소리로 받아 둔다. 실패해도 조용히 넘어간다.
  Future<void> warmUp() => _warming ??= _warmUp();

  Future<void> _warmUp() async {
    final api = cloud;
    if (api == null) return;
    try {
      final v = await voice;
      if (v.device || !await api.available) return;
      final watch = Stopwatch()..start();
      await _cache.get(v.id, '네.', () => api.synthesize('네.', v.id));
      _cloudWarm = true;
      debugPrint('[시간] 서버 목소리 미리 연결 ${watch.elapsedMilliseconds}ms');
    } on Object catch (e) {
      debugPrint('서버 목소리 미리 연결 실패: $e');
    }
  }

  /// 서버 목소리가 안 될 때 대신 읽을 폰 목소리.
  Voice get _bestDevice =>
      _deviceVoices.isEmpty ? deviceVoice : _deviceVoices.first;

  /// 지금 폰 TTS에 걸어 둔 목소리 id.
  String? _deviceVoiceSet;

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 폰에 받아 둔 한국어 목소리. 좋은 것부터. [loadDeviceVoices]가 채운다.
  List<Voice> _deviceVoices = const [];
  bool _deviceVoicesLoaded = false;

  /// 고를 수 있는 목소리: 폰 목소리(좋은 것부터) 다음 구글 목소리.
  List<Voice> get voices => [
        ...(_deviceVoices.isEmpty ? const [deviceVoice] : _deviceVoices),
        if (cloud != null) ...cloudVoices,
      ];

  /// 폰에 받아 둔 한국어 목소리를 읽는다. 한 번만 읽는다.
  Future<void> loadDeviceVoices() async {
    if (_deviceVoicesLoaded) return;
    _deviceVoicesLoaded = true;
    try {
      final raw = await _tts.getVoices;
      final list = <Voice>[];
      final seen = <String>{};
      for (final item in (raw as List? ?? const [])) {
        if (item is! Map) continue;
        final v = item.map((k, val) => MapEntry('$k', '$val'));
        if (!(v['locale'] ?? '').toLowerCase().startsWith('ko')) continue;
        final voice = Voice.fromDevice(v);
        if (seen.add(voice.id)) list.add(voice);
      }
      list.sort((a, b) => b.rank.compareTo(a.rank));
      _deviceVoices = list;
      debugPrint('폰 한국어 목소리 ${list.length}개: '
          '${list.map((v) => '${v.spec?['name']}(${v.spec?['quality']})').join(', ')}');
    } on Object catch (e) {
      debugPrint('폰 목소리 목록 실패: $e');
    }
  }

  /// 지금 목소리. 고른 적 있으면 그것, 없으면 서버 목소리가 켜져 있을 때 유진, 아니면 폰의 좋은 목소리(향상됨·프리미엄), 그다음 폰 기본.
  Future<Voice> get voice async {
    final known = _voice;
    if (known != null) return known;
    await loadDeviceVoices();
    final id = await _voices.load();
    final all = voices;
    final saved = all.where((v) => v.id == id);
    if (saved.isNotEmpty) return _voice = saved.first;
    // 서버 목소리가 켜져 있으면 첫째(유진)가 기본이다(2026-11-12: 폰에 고품질 목소리가 있으면 그걸 먼저 골라서
    // 새 목소리로 바꿨는데도 그대로라는 피드백). 서버가 안 되면 문장마다 폰 목소리로 대신 읽는다.
    if (cloud != null) return _voice = cloudVoices.first;
    final good = _deviceVoices.where((v) => v.rank >= 2);
    if (good.isNotEmpty) return _voice = good.first;
    return _voice = all.first;
  }

  /// 목소리를 바꾸고 기억한다.
  Future<void> setVoice(Voice v) async {
    _voice = v;
    await _voices.save(v.id);
  }

  /// 읽기 직전에 iOS 오디오를 "재생 전용"으로 바꾼다.
  ///
  /// 음성 인식이 켜졌던 녹음+재생(playAndRecord) 모드로 읽으면, 스피커로 나와도 통화용 음량이라
  /// 최대로 키워도 작게 들린다. 읽는 동안에는 녹음할 일이 없으므로 재생 전용(playback)으로 크게 읽고,
  /// 음성 인식은 들을 때 스스로 녹음 모드로 바꿨다가 끝나면 이 모드로 되돌린다.
  Future<void> _loudPlayback() async {
    if (!_isIOS) return;
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );
  }

  /// 지금 읽고 있는지.
  bool get speaking => _deviceSpeaking || _playing;

  /// 읽던 안내를 멈춘다. 말하는 중에 말하기 버튼을 누르면 끊고 바로 듣게 할 때 쓴다.
  Future<void> stop() async {
    _generation++;
    await _stopNow();
  }

  Future<void> _stopNow() async {
    if (_playing) {
      _playing = false;
      final done = _playDone;
      if (done != null && !done.isCompleted) done.complete();
      try {
        await _player?.stop();
      } on Object catch (e) {
        debugPrint('소리 멈추기 실패: $e');
      }
    }
    if (_deviceSpeaking) {
      await _tts.stop();
      // 웹 TTS는 멈춤이 끝났다는 이벤트가 오기 전에 speak를 부르면 무시한다.
      // 그래서 이전 안내가 완전히 멈출 때까지 잠깐 기다린다.
      for (var i = 0; i < 20 && _deviceSpeaking; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      _deviceSpeaking = false;
    }
  }

  /// 읽고 있던 안내를 끊고 [text]를 지금 목소리로 읽는다. 다 읽을 때까지 기다린다.
  Future<void> speak(String text) => speakWith(text);

  /// [voice](없으면 지금 목소리)로 읽는다. 목소리 고르기에서 미리 들려줄 때 쓴다.
  Future<void> speakWith(String text, {Voice? voice}) async {
    final gen = ++_generation;
    await _stopNow();
    if (text.trim().isEmpty) return;
    final v = voice ?? await this.voice;
    final api = cloud;
    if (v.device || api == null || _cloudPaused || !await api.available) {
      if (gen == _generation) await _speakDevice(text, v);
      return;
    }
    // Gemini TTS는 하루 횟수가 적어서 한 번에 받는다. Cloud TTS는 문장으로 나눠 첫 문장부터 읽는다.
    final sentences = api.wholeText ? [text.trim()] : splitSentences(text);
    Future<Uint8List> fetch(int i) => _cache.get(
        v.id, sentences[i], () => api.synthesize(sentences[i], v.id));
    // 한 번에 하나만 앞서 받는다. 2026-11-12: 모든 문장을 한꺼번에 받았더니 Azure 무료 등급(1분 20번)에 걸려
    // 두세 번째 문장부터 폰 목소리로 넘어갔다.
    var next = fetch(0);
    for (var i = 0; i < sentences.length; i++) {
      Uint8List bytes;
      final watch = Stopwatch()..start();
      try {
        // Gemini는 읽는 데 2~6초 걸린다. 엔진을 아직 모르면 Gemini일 수 있어 넉넉히 기다린다.
        // 앱을 켠 뒤 처음 받는 문장은 연결이 늦어서 더 기다린다.
        bytes = await next.timeout(!_cloudWarm
            ? _coldTimeout
            : api.wholeText || i == 0
                ? _slowTimeout
                : _firstTimeout);
        _cloudWarm = true;
      } on Object catch (e) {
        // 무료 횟수를 다 쓰면(429) 한동안 폰 목소리만 쓴다.
        final quota = e is GatewayException && e.status == 429;
        // 처음 연결이 늦었을 뿐이면 받던 소리는 계속 받아 두고, 다음 안내부터 바로 서버 목소리로 읽는다.
        final coldSlow = e is TimeoutException && !_cloudWarm;
        debugPrint('서버 목소리 실패${quota ? '(무료 횟수 끝)' : ''}, 폰 목소리로 읽어요: $e');
        if (!coldSlow) {
          _cloudPausedUntil = DateTime.now()
              .add(quota ? const Duration(minutes: 30) : _retryAfter);
        }
        if (gen == _generation) {
          await _speakDevice(sentences.sublist(i).join(' '), _bestDevice);
        }
        return;
      }
      if (i == 0) debugPrint('[시간] 첫 문장 소리 ${watch.elapsedMilliseconds}ms');
      if (gen != _generation) return;
      // 읽는 동안 다음 문장을 받아 둔다.
      if (i + 1 < sentences.length) {
        next = fetch(i + 1);
        unawaited(next.then((_) {}, onError: (_) {}));
      }
      await _play(bytes);
      if (gen != _generation) return;
    }
  }

  bool get _cloudPaused {
    final until = _cloudPausedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// 자주 하는 안내를 미리 받아 둔다(추임새, "말씀해 주세요"). 실패해도 괜찮다.
  Future<void> prefetch(Iterable<String> texts) async {
    final api = cloud;
    if (api == null || !await api.available) return;
    final v = await voice;
    if (v.device) return;
    for (final t in texts) {
      for (final s in splitSentences(t)) {
        try {
          await _cache.get(v.id, s, () => api.synthesize(s, v.id));
        } on Object catch (_) {
          return;
        }
      }
    }
  }

  /// 듣기 시작을 알리는 신호. 말씀하셔도 된다는 뜻이다(2026-11-09 피드백: 듣고 있는지 모르겠다).
  ///
  /// 폰을 짧게 진동하고 시스템 "딸깍" 소리를 낸다. 예전에는 audioplayers로 "띵" 소리를 틀었는데,
  /// audioplayers는 소리가 끝나면 iOS 오디오 세션을 꺼 버려서(setActive(false)) 바로 이어 켠 마이크가
  /// 아무 소리도 못 들었다(2026-11-09 폰 확인: 이름을 불러도 못 알아들음). 시스템 소리와 진동은 세션을 건드리지 않는다.
  Future<void> listeningCue() async {
    final gen = ++_generation;
    await _stopNow();
    if (gen != _generation) return;
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    } on Object catch (e) {
      debugPrint('신호 실패: $e');
    }
  }

  Future<void> _speakDevice(String text, [Voice? voice]) async {
    final spec = voice?.spec;
    if (spec != null && _deviceVoiceSet != voice!.id) {
      try {
        await _tts.setVoice({
          'name': spec['name'] ?? '',
          'locale': spec['locale'] ?? 'ko-KR',
          if (spec['identifier'] != null) 'identifier': spec['identifier']!,
        });
        _deviceVoiceSet = voice.id;
      } on Object catch (e) {
        debugPrint('폰 목소리 바꾸기 실패: $e');
      }
    }
    if (_deviceVoiceSet == null) await _tts.setLanguage('ko-KR');
    await _loudPlayback();
    // 문장 사이에 잠깐 쉰다. 한 번에 이어 읽으면 놓친 말을 따라잡기 어렵다(2026-11-10 진행 님).
    final gen = _generation;
    final sentences = splitSentences(text);
    for (var i = 0; i < sentences.length; i++) {
      if (gen != _generation) return;
      await _tts.speak(sentences[i]);
      if (i < sentences.length - 1 && gen == _generation) {
        await Future<void>.delayed(sentencePause);
      }
    }
  }

  /// 문장 사이에 쉬는 시간.
  static const sentencePause = Duration(milliseconds: 350);

  Future<void> _play(Uint8List bytes, {String? mimeType}) async {
    final player = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.duckOthers).build());
    final done = _playDone = Completer<void>();
    final sub = player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    _playing = true;
    try {
      await player
          .play(BytesSource(bytes, mimeType: mimeType ?? audioMime(bytes)));
      // 끝 이벤트를 놓쳐도 멈춰 있지 않게, 길이의 두 배쯤 지나면 넘어간다.
      await done.future.timeout(const Duration(seconds: 40), onTimeout: () {});
    } finally {
      _playing = false;
      await sub.cancel();
    }
  }
}

/// 소리 바이트의 형식. WAV는 "RIFF"로 시작한다. 나머지는 MP3로 본다.
String audioMime(Uint8List bytes) => bytes.length > 4 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46
    ? 'audio/wav'
    : 'audio/mpeg';

/// 짧은 신호음을 WAV(16비트 모노 22.05kHz)로 만든다. [hz]를 차례로 이어 울린다.
@visibleForTesting
Uint8List toneWav(List<double> hz, {int ms = 100, double volume = 0.3}) {
  const rate = 22050;
  final per = rate * ms ~/ 1000;
  final samples = per * hz.length;
  final data = ByteData(44 + samples * 2);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var n = 0; n < hz.length; n++) {
    for (var i = 0; i < per; i++) {
      // 부드럽게 커졌다 작아지게(딸깍 소리 없게).
      final env = math.sin(math.pi * i / per);
      final v = volume * env * math.sin(2 * math.pi * hz[n] * i / rate);
      data.setInt16(44 + (n * per + i) * 2, (v * 32767).round(), Endian.little);
    }
  }
  return data.buffer.asUint8List();
}
