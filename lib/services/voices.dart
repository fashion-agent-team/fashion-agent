import 'package:shared_preferences/shared_preferences.dart';

/// 고를 수 있는 목소리. 2026-11-09 발표 피드백: 기기 목소리가 딱딱하니 구글의 부드러운 목소리를 몇 개 골라 쓰게.
///
/// [id]는 구글 목소리 이름이다. 게이트웨이가 Google Cloud Text-to-Speech(Chirp 3 HD, ko-KR)로 읽고,
/// 그 키가 없으면 Gemini TTS(같은 이름의 목소리)로 읽는다. 둘 다 무료 사용량 안에서 쓴다.
/// [device]는 폰에 든 목소리다. 서버가 없거나 실패하면 언제나 이 목소리로 읽는다.
class Voice {
  const Voice(this.id, this.description, {this.device = false});

  final String id;

  /// 고를 때 읽어 주는 설명("차분하고 부드러운 여성 목소리").
  final String description;

  /// 폰 기본 목소리인지.
  final bool device;

  @override
  bool operator ==(Object other) => other is Voice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 폰 기본 목소리. 서버 없이도 된다.
const deviceVoice = Voice('device', '폰에 들어 있는 기본 목소리', device: true);

/// 듣기 좋은 목소리 몇 가지. 앞쪽이 더 부드럽다. 첫째가 기본값이다.
const cloudVoices = [
  Voice('Achernar', '부드럽고 차분한 여성 목소리'),
  Voice('Sulafat', '따뜻한 여성 목소리'),
  Voice('Vindemiatrix', '상냥하고 온화한 여성 목소리'),
  Voice('Aoede', '산뜻하고 밝은 여성 목소리'),
  Voice('Achird', '친근한 남성 목소리'),
  Voice('Umbriel', '편안한 남성 목소리'),
];

/// 고른 목소리를 폰에 기억한다.
abstract class VoiceStore {
  Future<String?> load();
  Future<void> save(String id);
}

class LocalVoiceStore implements VoiceStore {
  static const _key = 'tts.voice';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String id) async =>
      (await SharedPreferences.getInstance()).setString(_key, id);
}

class MemoryVoiceStore implements VoiceStore {
  MemoryVoiceStore([this.id]);

  String? id;

  @override
  Future<String?> load() async => id;

  @override
  Future<void> save(String v) async => id = v;
}
