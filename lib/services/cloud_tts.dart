import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'gateway_auth.dart';

/// 게이트웨이 `POST /api/v1/tts`로 문장을 소리(MP3·WAV)로 바꾼다.
abstract class TtsApi {
  /// 게이트웨이에 로그인했으면 true.
  Future<bool> get available;

  /// [text]를 [voice] 목소리로 읽은 소리 파일 바이트. [rate]는 빠르기 배수(1.0 보통, 2026-11-12).
  Future<Uint8List> synthesize(String text, String voice, {double rate = 1.0});

  /// 서버가 Gemini TTS로 읽으면 true. 무료 횟수가 하루 15번쯤이라 문장으로 나누지 않고 한 번에 받는다.
  bool get wholeText;
}

class GatewayTtsApi implements TtsApi {
  GatewayTtsApi(this.gateway, {this.timeout = const Duration(seconds: 20)});

  final GatewayAuth gateway;
  final Duration timeout;

  @override
  Future<bool> get available => gateway.ensureSignedIn();

  /// 게이트웨이가 알려 준 엔진(X-Tts-Engine: cloud | gemini). 처음에는 모른다.
  String? engine;

  @override
  bool get wholeText => engine == 'gemini';

  @override
  Future<Uint8List> synthesize(String text, String voice,
      {double rate = 1.0}) async {
    final res = await gateway.send('POST', '/api/v1/tts', json: {
      'text': text,
      'voice': voice,
      if (rate != 1.0) 'rate': rate,
    }).timeout(timeout);
    engine = res.headers['x-tts-engine'] ?? engine;
    if (res.bodyBytes.isEmpty) {
      throw GatewayException(502, 'empty_audio', '소리가 비어 있어요');
    }
    return res.bodyBytes;
  }
}

/// 읽은 소리를 기억해 두는 곳. 같은 문장(인사, 추임새, 안내)은 다시 받지 않고 바로 읽는다.
///
/// 메모리에 최근 [memoryLimit]개, 폰 임시 폴더에 파일로 남긴다. 파일 이름은 목소리+문장의 해시다.
class TtsCache {
  TtsCache({this.memoryLimit = 60, Future<Directory> Function()? dir})
      : _dir = dir ?? _defaultDir;

  final int memoryLimit;
  final Future<Directory> Function() _dir;
  final _memory = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};

  static Future<Directory> _defaultDir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/tts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 기억해 둔 소리를 쓰고, 없으면 [load]로 받아 기억한다. 같은 문장을 동시에 받지 않는다.
  Future<Uint8List> get(
      String voice, String text, Future<Uint8List> Function() load) {
    final key = cacheKey(voice, text);
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit; // 최근에 쓴 것으로 옮긴다
      return Future.value(hit);
    }
    // whenComplete 안에서 값을 돌려주면 안 된다. remove는 이 Future 자신을 돌려주고,
    // whenComplete는 돌려받은 Future를 기다리므로 자기 자신을 영원히 기다리게 된다(2026-11-12 시뮬레이터:
    // 새 문장마다 9초 뒤 폰 목소리로 넘어감).
    return _pending[key] ??= _fromDiskOrLoad(key, load).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<Uint8List> _fromDiskOrLoad(
      String key, Future<Uint8List> Function() load) async {
    File? file;
    try {
      file = File('${(await _dir()).path}/$key.audio');
      if (await file.exists()) return _remember(key, await file.readAsBytes());
    } on Object catch (e) {
      debugPrint('TTS 파일 읽기 실패: $e');
      file = null;
    }
    final bytes = await load();
    _remember(key, bytes);
    if (file != null) {
      unawaited(file.writeAsBytes(bytes).then((_) {}, onError: (Object e) {
        debugPrint('TTS 파일 저장 실패: $e');
      }));
    }
    return bytes;
  }

  Uint8List _remember(String key, Uint8List bytes) {
    _memory[key] = bytes;
    while (_memory.length > memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
    return bytes;
  }

  /// 목소리+문장의 64비트 FNV-1a 해시(16진수).
  @visibleForTesting
  static String cacheKey(String voice, String text) {
    // 웹에서도 돌게 32비트 두 개로 나눠 계산한다.
    var h1 = 0x811c9dc5, h2 = 0x050c5d1f;
    for (final c in '$voice\u0000$text'.codeUnits) {
      h1 = ((h1 ^ c) * 0x01000193) & 0xffffffff;
      h2 = ((h2 ^ (c + 7)) * 0x01000193) & 0xffffffff;
    }
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }
}

/// 서버 목소리로 받을 조각. 첫 문장만 따로 두고(바로 읽기 시작), 나머지는 [max]자까지 이어 붙인다.
/// 게이트웨이는 한 번에 500자까지 받는다.
///
/// 2026-11-13: 긴 답에서 서버 목소리가 끊기고 폰 목소리로 넘어갔다. 마침표 없이 긴 문장은 통째로 한 조각이 되어
/// 500자를 넘기거나(게이트웨이 400), 큰 조각을 받는 데 시간제한을 넘겼다. 그래서 문장이 길면 쉼표·띄어쓰기에서
/// 자르고, 첫 조각은 [firstMax]자, 나머지는 [max]자로 짧게 둔다(소리 파일이 작아 제때 도착).
List<String> speechChunks(String text, {int max = 120, int firstMax = 100}) {
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return sentences;
  final head = splitLong(sentences.first, firstMax);
  final out = [head.first];
  final rest = [
    ...head.skip(1),
    for (final s in sentences.skip(1)) ...splitLong(s, max),
  ];
  final buf = StringBuffer();
  for (final s in rest) {
    if (buf.isNotEmpty && buf.length + 1 + s.length > max) {
      out.add(buf.toString());
      buf.clear();
    }
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(s);
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

/// [s]가 [max]자보다 길면 쉼표 뒤나 띄어쓰기에서 [max]자 이하로 자른다. 끊을 곳이 없으면 [max]자에서 자른다.
List<String> splitLong(String s, int max) {
  final out = <String>[];
  var t = s.trim();
  while (t.length > max) {
    var cut = -1;
    for (final mark in const [', ', ',', ' ']) {
      final i = t.lastIndexOf(mark, max - mark.length);
      if (i >= max ~/ 3) {
        cut = i + mark.length;
        break;
      }
    }
    if (cut <= 0) cut = max;
    out.add(t.substring(0, cut).trim());
    t = t.substring(cut).trim();
  }
  if (t.isNotEmpty) out.add(t);
  return out;
}

/// 긴 안내를 문장으로 나눈다. 첫 문장을 먼저 받아 읽는 동안 다음 문장을 받아서 기다림을 줄인다.
List<String> splitSentences(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  final chars = text.trim().split('');
  for (var i = 0; i < chars.length; i++) {
    buf.write(chars[i]);
    final end = '.?!'.contains(chars[i]) &&
        (i + 1 == chars.length || chars[i + 1] == ' ' || chars[i + 1] == '"');
    if (end && buf.toString().trim().length >= 6) {
      out.add(buf.toString().trim());
      buf.clear();
    }
  }
  final rest = buf.toString().trim();
  if (rest.isNotEmpty) {
    if (out.isNotEmpty && rest.length < 6) {
      out[out.length - 1] = '${out.last} $rest';
    } else {
      out.add(rest);
    }
  }
  return out;
}
