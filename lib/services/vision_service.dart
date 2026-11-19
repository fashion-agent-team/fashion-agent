import 'dart:typed_data';

import '../models/clothes_scan.dart';

/// 무엇을 찍었는지.
enum ScanPurpose {
  /// 입을 옷을 펼쳐 놓은 사진. 옷마다 격식과 얼룩·찢어짐까지 본다.
  outfit,
}

/// 사진 속 옷을 사실 그대로 알려 주는 비전 AI.
///
/// 어울림 판단은 하지 않는다. 판단은 `styling/`의 규칙이 맡는다.
///
/// 실제 옷 사진 분석은 게이트웨이 → agent → mcp-clothes-state(자체 모델)가 맡는다([CameraTurnController]).
/// 예전 Gemini 프록시(Cloudflare Worker)는 2026-11-10에 뺐다. 지금 구현은 데모용 [FakeVisionService]뿐이다.
abstract class VisionService {
  Future<ClothesScan> describe(Uint8List jpeg, ScanPurpose purpose);
}

class VisionException implements Exception {
  VisionException(this.message);

  final String message;

  @override
  String toString() => message;
}
