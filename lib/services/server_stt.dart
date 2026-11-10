import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'gateway_auth.dart';

/// 서버 음성 인식에 주는 힌트. 이 낱말이 나오면 그대로 적어 준다.
String sttHint(String? agentName) {
  final name = agentName == null || agentName.trim().isEmpty
      ? '에이전트 이름 예: 심청이, 지니, 코디, 하늘이.'
      : '에이전트 이름: ${agentName.trim()}.';
  return '시각장애인용 패션 도우미 앱과 나누는 한국어 대화. $name '
      '자주 쓰는 말: 옷 추천해 줘, 내일 뭐 입지, 날씨, 일정, 옷 검사, 얼굴 확인, 이 확인, '
      '내려놓고 볼게, 입고 볼게, 봐 줘, 찍어 줘, 첫 화면, 목소리 바꿔 줘, 더 말할 거 없어.';
}

/// 녹음한 말을 서버(게이트웨이 `POST /api/v1/stt`, OpenAI 음성 인식)에서 받아 적는다.
///
/// 2026-11-09 진행 님 폰 확인: 폰 음성 인식이 "심청이"를 "신청"으로 적는 등 너무 못 알아들었다.
/// 진행 님 결정: 이름 부르기 대기는 폰이 듣고, 부른 뒤 명령과 온보딩 답만 서버로 보낸다.
abstract class ServerStt {
  /// [audio]를 받아 적은 글자. 실패하면 예외.
  Future<String> transcribe(Uint8List audio, String mimeType, String hint);
}

class GatewayServerStt implements ServerStt {
  GatewayServerStt(this.gateway, {this.timeout = const Duration(seconds: 4)});

  final GatewayAuth gateway;
  final Duration timeout;

  @override
  Future<String> transcribe(
      Uint8List audio, String mimeType, String hint) async {
    if (!await gateway.ensureSignedIn()) {
      throw GatewayException(401, 'unauthorized', '로그인하지 않았어요');
    }
    final res = await gateway.send('POST', '/api/v1/stt', json: {
      'audioBase64': base64Encode(audio),
      'mimeType': mimeType,
      'prompt': hint,
    }).timeout(timeout);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is Map ? '${body['text'] ?? ''}'.trim() : '';
  }
}

/// 폰 음성 인식이 듣는 동안 같은 소리를 파일로 녹음한다(m4a, 모노).
///
/// iOS 오디오 세션은 음성 인식(speech_to_text)이 이미 녹음용으로 켜 두므로 여기서는 건드리지 않는다
/// (manageAudioSession=false). 세션을 끄면 음성 인식 마이크가 죽는다(2026-11-09 신호음 사건).
class SpeechRecorder {
  final _rec = AudioRecorder();
  bool _configured = false;
  String? _path;

  Future<void> start() async {
    try {
      if (!_configured) {
        _configured = true;
        await _rec.ios?.manageAudioSession(false);
      }
      final dir = await getTemporaryDirectory();
      final path = _path = '${dir.path}/speech.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 48000,
          numChannels: 1,
          bitRate: 48000,
        ),
        path: path,
      );
    } on Object catch (e) {
      debugPrint('녹음 시작 실패: $e');
      _path = null;
    }
  }

  /// 녹음을 멈추고 소리 바이트. 녹음하지 못했으면 null.
  Future<Uint8List?> stop() async {
    if (_path == null) return null;
    try {
      final path = await _rec.stop() ?? _path!;
      _path = null;
      final bytes = await File(path).readAsBytes();
      return bytes.length < 1000 ? null : bytes;
    } on Object catch (e) {
      debugPrint('녹음 멈추기 실패: $e');
      _path = null;
      return null;
    }
  }
}
