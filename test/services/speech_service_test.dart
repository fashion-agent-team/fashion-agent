import 'dart:io' show FileSystemException;

import 'package:fashion_agent/services/cloud_tts.dart';
import 'package:fashion_agent/services/gateway_auth.dart' show GatewayException;
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/voices.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 폰 TTS(flutter_tts 채널) 흉내. 부른 메서드와 읽은 문장을 적어 둔다.
class FakeDeviceTts {
  final calls = <MethodCall>[];
  List<Map<String, String>> voices = const [];
  Object? voicesError;

  List<String> get spoken => [
        for (final c in calls)
          if (c.method == 'speak')
            c.arguments is Map
                ? '${(c.arguments as Map)['text']}'
                : '${c.arguments}'
      ];

  Iterable<MethodCall> named(String m) => calls.where((c) => c.method == m);

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'getVoices') {
      if (voicesError != null) throw PlatformException(code: 'x');
      return voices;
    }
    return 1;
  }
}

/// 서버 목소리 흉내. [fail]이 있으면 그 오류로 실패한다.
class FakeTtsApi implements TtsApi {
  FakeTtsApi({this.up = true, this.fail});

  bool up;
  Object? fail;
  final asked = <String>[];
  final rates = <double>[];

  @override
  Future<bool> get available async => up;

  @override
  bool get wholeText => false;

  @override
  Future<Uint8List> synthesize(String text, String voice,
      {double rate = 1.0}) async {
    asked.add('$voice:$text');
    rates.add(rate);
    final f = fail;
    if (f != null) throw f;
    return Uint8List.fromList([1, 2, 3]);
  }
}

/// 파일 없이 메모리만 쓰는 캐시.
TtsCache _memoryCache() =>
    TtsCache(dir: () async => throw const FileSystemException('테스트'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDeviceTts device;
  const channel = MethodChannel('flutter_tts');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    device = FakeDeviceTts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, device.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('폰 목소리 고르기', () {
    test('한국어 목소리만, 장난감 목소리는 빼고 좋은 것부터 고른다', () async {
      device.voices = [
        {'name': 'Samantha', 'locale': 'en-US', 'quality': 'premium'},
        {
          'name': 'Eddy',
          'locale': 'ko-KR',
          'identifier': 'com.apple.eloquence.ko-KR.Eddy'
        },
        {'name': 'Yuna', 'locale': 'ko-KR', 'identifier': 'yuna-basic'},
        {
          'name': 'Yuna',
          'locale': 'ko-KR',
          'identifier': 'yuna-premium',
          'quality': 'premium',
          'gender': 'female'
        },
        {'name': 'Yuna', 'locale': 'ko-KR', 'identifier': 'yuna-basic'},
      ];
      final speech = SpeechService(voices: MemoryVoiceStore());

      await speech.loadDeviceVoices();
      await speech.loadDeviceVoices(); // 두 번째는 다시 읽지 않는다

      expect(device.named('getVoices'), hasLength(1));
      expect(speech.voices.map((v) => v.id),
          ['device:yuna-premium', 'device:yuna-basic']);
      // 서버가 없으면 폰의 좋은 목소리(프리미엄)가 기본
      expect((await speech.voice).id, 'device:yuna-premium');
    });

    test('목록을 못 읽으면 폰 기본 목소리', () async {
      device.voicesError = true;
      final speech = SpeechService(voices: MemoryVoiceStore());
      expect(await speech.voice, deviceVoice);
      expect(speech.voices, [deviceVoice]);
    });

    test('서버 목소리가 있으면 유진이 기본, 고른 목소리는 기억한다', () async {
      final store = MemoryVoiceStore();
      final speech = SpeechService(cloud: FakeTtsApi(), voices: store);
      expect(speech.voices, cloudVoices);
      expect((await speech.voice).id, 'YuJin');

      await speech.setVoice(cloudVoices[1]);
      expect(store.id, 'JiMin');
      expect((await SpeechService(cloud: FakeTtsApi(), voices: store).voice).id,
          'JiMin');
    });
  });

  group('말 빠르기', () {
    test('한 칸씩 바꾸고 끝에 닿으면 false', () async {
      final speech = SpeechService(voices: MemoryVoiceStore());
      expect(speech.rate, SpeechService.speechRate);

      expect(await speech.changeRate(-1), isTrue);
      expect(speech.rate, closeTo(0.36, 1e-9));
      expect(await speech.changeRate(-5), isTrue);
      expect(speech.rate, SpeechService.minRate);
      expect(await speech.changeRate(-1), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('tts.rate'), SpeechService.minRate);
    });

    test('계정 빠르기로 맞추면 범위 안으로 자르고 저장한다', () async {
      final speech = SpeechService(voices: MemoryVoiceStore());
      await speech.setRate(2);
      expect(speech.rate, SpeechService.maxRate);
      expect(device.named('setSpeechRate').last.arguments, 0.6);
    });

    test('저장해 둔 빠르기를 켤 때 불러온다', () async {
      SharedPreferences.setMockInitialValues({'tts.rate': 0.54});
      final speech = SpeechService(voices: MemoryVoiceStore());
      await pumpEventQueue();
      expect(speech.rate, 0.54);
    });

    test('빠르기를 바꾸면 서버 목소리에도 배수로 보낸다', () async {
      final api = FakeTtsApi(fail: GatewayException(500, 'x'));
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.setRate(0.6);
      await speech.speak('안녕하세요.');
      expect(api.rates.single, 1.43);
    });
  });

  group('읽기', () {
    test('폰 목소리는 한국어로 맞추고 문장마다 쉬며 읽는다', () async {
      final speech = SpeechService(voices: MemoryVoiceStore('device'));
      await speech.speak('오늘은 맑아요. 겉옷은 필요 없어요.');

      expect(device.spoken, ['오늘은 맑아요.', '겉옷은 필요 없어요.']);
      expect(device.named('setLanguage').single.arguments, 'ko-KR');
    });

    test('빈 글은 읽지 않는다', () async {
      final speech = SpeechService(voices: MemoryVoiceStore('device'));
      await speech.speak('   ');
      expect(device.spoken, isEmpty);
    });

    test('고른 폰 목소리로 바꿔서 읽는다(한 번만 바꾼다)', () async {
      device.voices = [
        {
          'name': 'Yuna',
          'locale': 'ko-KR',
          'identifier': 'yuna-premium',
          'quality': 'premium'
        },
      ];
      final speech = SpeechService(voices: MemoryVoiceStore());
      await speech.speak('첫 번째 안내예요.');
      await speech.speak('두 번째 안내예요.');

      final set = device.named('setVoice').toList();
      expect(set, hasLength(1));
      expect((set.single.arguments as Map)['identifier'], 'yuna-premium');
      expect(device.named('setLanguage'), isEmpty);
    });

    test('서버가 로그인 안 돼 있으면 폰 목소리로 읽는다', () async {
      final api = FakeTtsApi(up: false);
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.speak('오늘 비가 와요.');
      expect(api.asked, isEmpty);
      expect(device.spoken, ['오늘 비가 와요.']);
    });

    test('서버 목소리가 실패하면 그 자리부터 폰 목소리로, 잠깐은 서버를 안 부른다', () async {
      final api = FakeTtsApi(fail: GatewayException(500, 'tts_failed'));
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());

      await speech.speak('우산을 챙기세요. 오후에 비가 와요.');
      expect(api.asked, ['YuJin:우산을 챙기세요.']);
      expect(device.spoken, ['우산을 챙기세요.', '오후에 비가 와요.']);

      await speech.speak('다음 안내예요.');
      expect(api.asked, hasLength(1), reason: '실패 뒤 20초 동안은 폰 목소리만');
      expect(device.spoken.last, '다음 안내예요.');
    });

    test('무료 횟수가 끝나면(429) 폰 목소리로 읽는다', () async {
      final api = FakeTtsApi(fail: GatewayException(429, 'rate_limited'));
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.speak('안녕하세요.');
      await speech.speak('또 만나요.');
      expect(api.asked, hasLength(1));
      expect(device.spoken, ['안녕하세요.', '또 만나요.']);
    });

    test('미리 들려주기는 고른 폰 목소리로 바로 읽는다', () async {
      final api = FakeTtsApi();
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.speakWith('이 목소리예요.', voice: deviceVoice);
      expect(api.asked, isEmpty);
      expect(device.spoken, ['이 목소리예요.']);
    });

    test('멈추면 지금 읽는 중이 아니다', () async {
      final speech = SpeechService(voices: MemoryVoiceStore('device'));
      await speech.stop();
      expect(speech.speaking, isFalse);
    });
  });

  group('서버 목소리 미리 받기', () {
    test('자주 하는 안내를 문장마다 미리 받아 둔다', () async {
      final api = FakeTtsApi();
      final cache = _memoryCache();
      final speech =
          SpeechService(cloud: api, voices: MemoryVoiceStore(), cache: cache);

      await speech.prefetch(['말씀해 주세요. 듣고 있어요.', '잠깐만요.']);
      expect(api.asked, ['YuJin:말씀해 주세요.', 'YuJin:듣고 있어요.', 'YuJin:잠깐만요.']);

      // 같은 문장은 다시 받지 않는다
      await speech.prefetch(['잠깐만요.']);
      expect(api.asked, hasLength(3));
    });

    test('실패하면 나머지는 건너뛴다', () async {
      final api = FakeTtsApi(fail: GatewayException(500, 'x'));
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.prefetch(['하나예요.', '둘이에요.']);
      expect(api.asked, ['YuJin:하나예요.']);
    });

    test('폰 목소리를 골랐거나 서버가 없으면 받지 않는다', () async {
      final api = FakeTtsApi();
      final picked = SpeechService(cloud: api, voices: MemoryVoiceStore());
      await picked.setVoice(deviceVoice);
      await picked.prefetch(['네.']);
      await SpeechService(voices: MemoryVoiceStore()).prefetch(['네.']);
      expect(api.asked, isEmpty);
    });

    test('앱을 켤 때 "네."를 한 번만 받아 연결해 둔다', () async {
      final api = FakeTtsApi();
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await Future.wait([speech.warmUp(), speech.warmUp()]);
      expect(api.asked, ['YuJin:네.']);
    });

    test('미리 연결이 실패해도 조용히 넘어간다', () async {
      final api = FakeTtsApi(fail: GatewayException(503, 'down'));
      final speech = SpeechService(
          cloud: api, voices: MemoryVoiceStore(), cache: _memoryCache());
      await speech.warmUp();
      expect(api.asked, ['YuJin:네.']);
      await SpeechService(voices: MemoryVoiceStore()).warmUp();
    });
  });

  group('신호', () {
    test('듣기 신호와 기다림 진동은 오류 없이 끝난다', () async {
      final speech = SpeechService(voices: MemoryVoiceStore('device'));
      await speech.listeningCue();
      await speech.waitingTick();
      expect(speech.speaking, isFalse);
    });

    test('소리 형식: RIFF로 시작하면 WAV, 아니면 MP3', () {
      expect(audioMime(toneWav([440])), 'audio/wav');
      expect(
          audioMime(Uint8List.fromList([0xff, 0xfb, 0, 0, 0])), 'audio/mpeg');
    });
  });
}
