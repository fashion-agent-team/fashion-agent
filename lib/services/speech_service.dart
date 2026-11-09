import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'cloud_tts.dart';
import 'voices.dart';

/// 앱의 모든 음성 안내를 담당한다.
///
/// 2026-11-09 발표 피드백: 기기 목소리(flutter_tts)가 딱딱하다. 로그인돼 있으면 게이트웨이를 거쳐
/// 구글의 부드러운 목소리로 읽고([cloud]), 고른 목소리를 기억한다([voices]).
/// 서버가 없거나 늦으면(4초) 그 문장부터는 폰 목소리로 읽는다. 사용자는 끊김 없이 듣는다.
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
    // 기본 속도(0.5)는 느리다는 의견(2026-11-09 리허설). iOS·안드로이드 모두 0.5가 보통 속도다.
    _tts.setSpeechRate(speechRate);
  }

  /// 읽는 속도. 0.5가 보통, 클수록 빠르다.
  static const speechRate = 0.58;

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

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 고를 수 있는 목소리. 서버 목소리가 없으면 폰 목소리 하나.
  List<Voice> get voices =>
      cloud == null ? const [deviceVoice] : const [...cloudVoices, deviceVoice];

  /// 지금 목소리. 고른 적 없으면 서버 목소리 첫째(서버가 없으면 폰 목소리).
  Future<Voice> get voice async {
    final known = _voice;
    if (known != null) return known;
    final id = await _voices.load();
    final all = voices;
    return _voice = all.firstWhere((v) => v.id == id, orElse: () => all.first);
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
      if (gen == _generation) await _speakDevice(text);
      return;
    }
    final sentences = splitSentences(text);
    Future<Uint8List> fetch(int i) => _cache.get(
        v.id, sentences[i], () => api.synthesize(sentences[i], v.id));
    var next = fetch(0);
    for (var i = 0; i < sentences.length; i++) {
      Uint8List bytes;
      final watch = Stopwatch()..start();
      try {
        bytes = await next.timeout(_firstTimeout);
      } on Object catch (e) {
        debugPrint('구글 목소리 실패, 폰 목소리로 읽어요: $e');
        _cloudPausedUntil = DateTime.now().add(const Duration(minutes: 1));
        if (gen == _generation) {
          await _speakDevice(sentences.sublist(i).join(' '));
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

  /// 듣기 시작을 알리는 짧은 "띵" 소리. 말씀하셔도 된다는 신호다(2026-11-09 피드백: 듣고 있는지 모르겠다).
  Future<void> listeningCue() async {
    final gen = ++_generation;
    await _stopNow();
    if (gen != _generation) return;
    try {
      await _play(_cue, mimeType: 'audio/wav');
    } on Object catch (e) {
      debugPrint('신호음 실패: $e');
    }
  }

  static final Uint8List _cue = toneWav(const [880, 1320], ms: 90);

  Future<void> _speakDevice(String text) async {
    await _tts.setLanguage('ko-KR');
    await _loudPlayback();
    await _tts.speak(text);
  }

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
