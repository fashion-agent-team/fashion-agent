import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/clothes_scan.dart';

/// 무엇을 찍었는지. 프록시가 프롬프트를 고르는 데 쓴다.
enum ScanPurpose {
  /// 사용자가 고른 옷을 펼쳐 놓은 사진.
  outfit,

  /// 옷장 사진. 여러 벌과 위치가 필요하다.
  closet,

  /// 꺼낸 옷 한 벌을 든 사진.
  check,
}

/// 사진 속 옷을 사실 그대로 알려 주는 비전 AI.
///
/// 어울림 판단은 하지 않는다. 판단은 `styling/`의 규칙이 맡는다.
abstract class VisionService {
  Future<ClothesScan> describe(Uint8List jpeg, ScanPurpose purpose);
}

/// 프록시 서버의 `/describe-clothes`를 부른다. API 키는 프록시에만 있다.
///
/// 요청·응답 형식은 `server/README.md`를 보라.
class HttpVisionService implements VisionService {
  HttpVisionService(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  @override
  Future<ClothesScan> describe(Uint8List jpeg, ScanPurpose purpose) async {
    final response = await _client
        .post(
          baseUrl.resolve('/describe-clothes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'purpose': purpose.name,
            'image': base64Encode(jpeg),
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw VisionException('옷 분석 서버 응답 오류 (${response.statusCode})');
    }
    return ClothesScan.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }
}

class VisionException implements Exception {
  VisionException(this.message);

  final String message;

  @override
  String toString() => message;
}
