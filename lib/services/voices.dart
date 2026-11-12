import 'package:shared_preferences/shared_preferences.dart';

/// 고를 수 있는 목소리. 2026-11-09 발표 피드백: 기기 목소리가 딱딱하니 구글의 부드러운 목소리를 몇 개 골라 쓰게.
///
/// [id]는 서버 목소리 이름이다. 게이트웨이가 엣지 목소리(edge-tts 사이드카)로 읽는다(2026-11-12, 발표용).
/// [device]는 폰에 든 목소리다. 서버가 없거나 실패하면 언제나 이 목소리로 읽는다.
class Voice {
  const Voice(this.id, this.description,
      {this.device = false, this.spec, this.rank = 0});

  /// 폰에 받아 둔 한국어 목소리(flutter_tts getVoices의 한 줄).
  ///
  /// 아이폰은 설정 → 손쉬운 사용 → 읽기 및 말하기 → 음성 → 한국어에서 "향상됨"·"프리미엄" 목소리를 무료로 받을 수 있다.
  /// 2026-11-09: 구글 클라우드는 카드 등록이 필요하고 Gemini TTS는 하루 15번쯤이라, 평소에는 이 목소리를 쓴다.
  factory Voice.fromDevice(Map<String, String> v) {
    final name = v['name'] ?? '';
    final quality = (v['quality'] ?? '').toLowerCase();
    final rank = switch (quality) {
      'premium' || 'very high' => 3,
      'enhanced' || 'high' => 2,
      _ => 0,
    };
    final gender = switch ((v['gender'] ?? '').toLowerCase()) {
      'female' => ' 여성',
      'male' => ' 남성',
      _ => '',
    };
    final level = rank >= 3
        ? ', 아주 자연스러운'
        : rank >= 2
            ? ', 자연스러운'
            : '';
    final label = RegExp(r'^[a-zA-Z]').hasMatch(name) ? name : '';
    return Voice('device:${v['identifier'] ?? name}',
        '폰에 들어 있는$level$gender 목소리${label.isEmpty ? '' : ' $label'}',
        device: true, spec: v, rank: rank);
  }

  final String id;

  /// 고를 때 읽어 주는 설명("차분하고 부드러운 여성 목소리").
  final String description;

  /// 폰 목소리인지.
  final bool device;

  /// 폰 목소리면 flutter_tts setVoice에 넘길 값. 기본 목소리는 null.
  final Map<String, String>? spec;

  /// 폰 목소리 품질. 프리미엄 3, 향상됨 2, 보통 0.
  final int rank;

  @override
  bool operator ==(Object other) => other is Voice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 폰 기본 목소리. 서버 없이도 된다.
const deviceVoice = Voice('device', '폰에 들어 있는 기본 목소리', device: true);

/// 고를 수 있는 서버 목소리. 첫째가 기본값이다.
///
/// 2026-11-12 진행 님 결정: 발표·시연용으로 엣지 목소리(Edge TTS, 무료·키 없음)를 쓴다. 상업 출시 때는 정식 서비스로 바꾼다.
/// 게이트웨이(EDGE_TTS_URL)가 edge-tts 사이드카로 읽는다. 엣지 한국어 목소리는 이 셋뿐이다.
/// 예전에 고른 유진(Azure) 같은 이름은 목록에 없으니 선희로 돌아간다. 서버가 안 되면 문장마다 폰 목소리로 읽는다.
const cloudVoices = [
  Voice('SunHi', '밝고 상냥한 여성 목소리, 선희'),
  Voice('InJoon', '차분한 남성 목소리, 인준'),
  Voice('Hyunsu', '부드러운 남성 목소리, 현수'),
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
