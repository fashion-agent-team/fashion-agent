/// 카메라 구도 안내. 폰 안에서 찾은 옷(또는 몸)의 위치를 보고 폰을 어디로 옮기면 될지 말로 알려 준다.
///
/// 2026-11-06 진행 님 요청: 시각장애인은 옷이 화면 어디에 있는지 모르니, 앱이 위치를 잡아 주고
/// 옷이 화면에 잘 들어왔을 때만 찍기. 좌표는 모두 화면(세로로 든 폰) 기준 0~1이다.
library;

import 'dart:typed_data';
import 'dart:ui';

/// 무엇을 찍는지.
enum Subject {
  /// 아무거나(얼굴·이). 구도 안내 없이 멈추면 찍는다.
  any,

  /// 내려놓은 옷.
  garment,

  /// 옷을 입은 사람(머리부터 발까지).
  body,

  /// 셀카로 찍는 얼굴(화장 확인). 2026-11-13 점검: 예전에는 구도 안내 없이 찍고 나서야 "얼굴이 다 안 보여요"라고 했다.
  face,

  /// 셀카로 찍는 입(치아 확인). 2026-11-17 정지원: 예전에는 멈추면 바로 찍고, 사진을 서버까지 올린 뒤에야
  /// "입을 더 벌려 주세요"를 들었다. 이제 폰 안에서 입 위치·크기·벌림·밝기를 먼저 본다.
  mouth,
}

/// 구도 판단 결과. [ready]면 찍어도 된다. 아니면 [speech]를 읽어 준다.
class Framing {
  const Framing.ready()
      : ready = true,
        speech = '좋아요, 그대로요.',
        closeness = 1,
        dark = false;
  const Framing.fix(this.speech, [this.closeness = 0, this.dark = false])
      : ready = false;

  final bool ready;
  final String speech;

  /// 어둡거나 한쪽이 그늘져서 못 찍는다. 앞쪽 카메라면 화면을 하얗게 밝혀 비춘다([AutoCaptureCamera.screenLight]).
  final bool dark;

  /// 찍기 좋은 자리에 얼마나 가까운지(0~1). 찾지 못했으면 0, 찍어도 되면 1.
  final double closeness;

  @override
  bool operator ==(Object other) =>
      other is Framing && other.ready == ready && other.speech == speech;

  @override
  int get hashCode => Object.hash(ready, speech);

  @override
  String toString() => ready ? 'Framing.ready' : 'Framing.fix($speech)';
}

const _edge = 0.02;

/// 내려놓은 옷 상자들(화면 기준 0~1)을 보고 안내한다. 여러 벌이면 모두 감싸는 상자로 본다.
Framing frameGarment(List<Rect> boxes) {
  if (boxes.isEmpty) {
    return const Framing.fix('옷이 안 보여요. 폰을 옷 쪽으로 비춰 주세요.');
  }
  final box = boxes.reduce((a, b) => a.expandToInclude(b));
  final area = box.width * box.height;
  final c = boxCloseness(box);
  final cutLeft = box.left <= _edge,
      cutRight = box.right >= 1 - _edge,
      cutTop = box.top <= _edge,
      cutBottom = box.bottom >= 1 - _edge;

  if (area > 0.85 || (cutLeft && cutRight) || (cutTop && cutBottom)) {
    return Framing.fix('조금 더 높이 들어 주세요.', c);
  }
  if (area < 0.08) {
    return Framing.fix('조금 더 가까이 가 주세요.', c);
  }
  // 한쪽이 잘렸거나 한쪽으로 치우쳤으면 그쪽으로 폰을 옮기게 한다.
  final cx = box.center.dx, cy = box.center.dy;
  if (cutLeft || cx < 0.35) {
    return Framing.fix('폰을 조금 왼쪽으로.', c);
  }
  if (cutRight || cx > 0.65) {
    return Framing.fix('폰을 조금 오른쪽으로.', c);
  }
  if (cutTop || cy < 0.35) {
    return Framing.fix('폰을 조금 위로.', c);
  }
  if (cutBottom || cy > 0.65) {
    return Framing.fix('폰을 조금 아래로.', c);
  }
  return const Framing.ready();
}

/// 몸의 점 하나(화면 기준 0~1)와 보일 확률.
typedef BodyPoint = ({double x, double y, double likelihood});

/// 입은 옷: 어깨부터 발까지 화면에 들어왔는지 본다. 폰은 세워 두고 사람이 움직인다.
///
/// 2026-11-09 진행 님: 서서 찍을 때 얼굴은 안 나와도 된다. 그래서 머리는 보지 않고 어깨·엉덩이·발(또는 아래쪽 무릎)만 본다.
///
/// [points]의 키: head(코나 귀), shoulder, hip, knee, foot(발목이나 발뒤꿈치). 없거나 확률이 낮으면 안 보이는 것이다.
///
/// 2026-11-09 리허설: "뒤로 가세요"와 "앞으로 오세요"를 번갈아 말하다 끝내 못 찍었다. 폰을 가슴 높이에 세우면
/// 발이 들어오는 거리와 "너무 멀다"로 보는 거리 사이가 반 걸음도 안 됐기 때문이다. 그래서
/// - 발목이 흐릿해도 무릎이 화면 아래쪽에 보이면 다 보인 것으로 친다(옷은 다 보인다).
/// - "너무 멀다"는 몸이 화면의 4분의 1보다 작을 때만 말한다.
Framing frameBody(Map<String, List<BodyPoint>> points) {
  bool seen(String key, [double min = 0.5]) =>
      (points[key] ?? const []).any((p) =>
          p.likelihood >= min && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1);
  bool kneeLow() => (points['knee'] ?? const []).any((p) =>
      p.likelihood >= 0.5 && p.x >= 0 && p.x <= 1 && p.y >= 0.7 && p.y <= 1);

  if (!seen('shoulder') || !seen('hip')) {
    return const Framing.fix('몸이 안 보여요. 폰 앞에 서 주세요.');
  }
  if (!seen('foot', 0.3) && !kneeLow()) {
    return const Framing.fix('한 걸음 뒤로 가 주세요.', 0.3);
  }
  final all = points.values
      .expand((list) => list)
      .where((p) => p.likelihood >= 0.5 && p.y >= 0 && p.y <= 1)
      .toList();
  final top = all.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  final bottom = all.map((p) => p.y).reduce((a, b) => a > b ? a : b);
  final cx = all.map((p) => p.x).reduce((a, b) => a + b) / all.length;
  final c = bodyCloseness(cx, bottom - top);
  if (bottom - top < 0.25) {
    return Framing.fix('한 걸음 앞으로 와 주세요.', c);
  }
  // 뒤쪽 카메라라 사진 왼쪽이 폰을 바라보는 사람의 오른쪽이다. 그 사람 기준으로 말한다.
  if (cx < 0.25) {
    return Framing.fix('왼쪽으로 반 걸음 가 주세요.', c);
  }
  if (cx > 0.75) {
    return Framing.fix('오른쪽으로 반 걸음 가 주세요.', c);
  }
  return const Framing.ready();
}

/// 두 밝기 칸([lumaGrid]) 사이의 평균 차이. 방금 찍은 장면과 같은지 볼 때 쓴다.
double sceneDifference(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return double.infinity;
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// 아이폰 카메라 프레임(BGRA, 가로로 누운 원본)을 [step]칸마다 하나씩 골라 줄이고
/// [rotation]도(시계 방향)만큼 돌려 똑바로 세운다. 폰 안 모델(ML Kit)에 넣는 작은 그림이다.
///
/// 아이폰 ML Kit 플러그인은 바이트로 받은 그림의 방향 정보를 쓰지 않아서, 누운 사람·옷을 그대로 넣으면
/// 몸 찾기가 잘 안 된다. 그래서 미리 세운다. 줄이면 빠르고 위치 안내에는 이 정도면 충분하다.
({Uint8List bytes, int width, int height}) uprightBgra(
  Uint8List src, {
  required int width,
  required int height,
  required int bytesPerRow,
  required int rotation,
  int step = 4,
}) {
  final w = width ~/ step, h = height ~/ step;
  final turn = ((rotation % 360) + 360) % 360;
  final outW = turn == 90 || turn == 270 ? h : w;
  final outH = turn == 90 || turn == 270 ? w : h;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final si = (y * step) * bytesPerRow + (x * step) * 4;
      if (si + 3 >= src.length) continue;
      final (ox, oy) = switch (turn) {
        90 => (h - 1 - y, x),
        180 => (w - 1 - x, h - 1 - y),
        270 => (y, w - 1 - x),
        _ => (x, y),
      };
      final oi = (oy * outW + ox) * 4;
      out[oi] = src[si];
      out[oi + 1] = src[si + 1];
      out[oi + 2] = src[si + 2];
      out[oi + 3] = 255;
    }
  }
  return (bytes: out, width: outW, height: outH);
}

/// 셀카 얼굴 상자들(화면 기준 0~1)을 보고 안내한다. 가장 큰 얼굴을 본다.
///
/// 앞쪽 카메라는 좌우가 뒤집혀 보일 수 있어서 "왼쪽/오른쪽"은 말하지 않고, 멀고 가까움과 "가운데로"만 말한다.
///
/// 2026-11-17 정지원: 고개 돌림·기울임·어두움도 찍기 전에 본다. 예전에는 사진을 서버까지 보낸 뒤에야
/// "고개가 기울었어요"를 들었다. [yaw]·[roll]은 ML Kit 고개 각도(도), [light]는 얼굴 밝기([FaceLight]).
/// 기준은 서버(mcp-face-check `FaceCheckProperties.Symmetry`)와 같거나 조금 엄하게 둔다.
Framing frameFace(List<Rect> faces,
    {double? yaw, double? roll, FaceLight? light}) {
  if (faces.isEmpty) {
    return const Framing.fix('얼굴이 안 보여요. 폰을 얼굴 정면에 들어 주세요.');
  }
  final box =
      faces.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
  final c = boxCloseness(box, small: 0.09, big: 0.64);
  final cutLeft = box.left <= _edge,
      cutRight = box.right >= 1 - _edge,
      cutTop = box.top <= _edge,
      cutBottom = box.bottom >= 1 - _edge;
  if (box.width > 0.8 || (cutLeft && cutRight) || (cutTop && cutBottom)) {
    return Framing.fix('조금 멀리 들어 주세요.', c);
  }
  if (box.width < 0.3) {
    return Framing.fix('조금 가까이 들어 주세요.', c);
  }
  if (cutTop) {
    return Framing.fix('이마가 화면 위로 나갔어요. 폰을 조금 위로 올려 주세요.', c);
  }
  if (cutBottom) {
    return Framing.fix('턱이 화면 아래로 나갔어요. 폰을 조금 아래로 내려 주세요.', c);
  }
  if (cutLeft || cutRight) {
    return Framing.fix('얼굴이 화면 끝에 걸려요. 폰을 얼굴 정가운데로 천천히 옮겨 주세요.', c);
  }
  // 각도·밝기가 안 맞으면 자리는 맞아도 소리를 조금 늦춘다(아직 다 된 건 아니라는 뜻).
  final almost = c * 0.8;
  if (yaw != null && yaw.abs() > maxFaceYaw) {
    return Framing.fix('얼굴이 옆으로 돌아가 있어요. 폰을 코 앞에 두고 똑바로 봐 주세요.', almost);
  }
  if (roll != null && roll.abs() > maxFaceRoll) {
    return Framing.fix('고개가 한쪽으로 기울었어요. 고개를 똑바로 해 주세요.', almost);
  }
  if (light != null) {
    if (light.mean < faceDarkLuma) {
      return Framing.fix('얼굴이 어두워요. 불을 켜거나 밝은 쪽을 봐 주세요.', almost, true);
    }
    if ((light.left - light.right).abs() > faceUnevenLuma) {
      return Framing.fix(
          '얼굴 한쪽이 그늘져요. 빛이 얼굴 정면에서 오게 몸을 조금 돌려 주세요.', almost, true);
    }
  }
  return const Framing.ready();
}

/// 얼굴 밝기(0~255): 얼굴 전체 평균과 왼쪽·오른쪽 뺨 평균. 어느 쪽이 사용자 왼쪽인지는 따지지 않는다(차이만 본다).
typedef FaceLight = ({double mean, double left, double right});

/// 서버는 고개 돌림 12°, 기울임 25°를 넘으면 다시 찍으라고 한다. 기울임은 폰에서 조금 엄하게 본다.
const double maxFaceYaw = 12;
const double maxFaceRoll = 20;

/// 카메라 프레임 밝기(감마 적용 0~255) 기준. 서버 기준(L* 28, 좌우 차이 L* 15)을 프레임 밝기로 옮긴 첫 값이다.
/// 실기기에서 조정한다.
const double faceDarkLuma = 70;
const double faceUnevenLuma = 35;

/// 폰 안에서 본 입. 모두 화면(세로로 든 폰) 기준 0~1.
///
/// [inner]는 입 안쪽(윗입술 아래선 + 아랫입술 위선) 상자, 곧 서버 `mouthBox`와 같은 점으로 만든다.
/// [lips]는 입술 바깥선까지 감싼 상자로, 화면 끝에 걸렸는지 볼 때 쓴다. [luma]는 서버가 잘라 보는 자리(입 안쪽 긴 변 × 1.36)의 밝기.
/// [inner]가 null이면 입술 윤곽 없이 입 끝 점(왼쪽·오른쪽·아래)만 찾은 것이다. 벌림은 찍은 뒤 정밀 확인에 맡긴다.
typedef MouthView = ({Rect? inner, Rect lips, double? luma});

/// 서버(mcp-face-check `TeethCheckService.framing`)는 입 안쪽 너비가 사진의 15%보다 작거나, 높이 ÷ 너비가 0.10보다
/// 작으면 다시 찍으라고 한다. 폰에서는 조금 넉넉하게 봐서 찍은 사진이 서버 기준을 넘게 한다.
///
/// 2026-11-17 폰 확인("이빨 인식을 못 한다"): ML Kit은 얼굴 전체가 보여야 입을 찾는다. 입만 크게 들이대면 얼굴을 못 찾는다.
/// 그래서 "가까이"는 서버 기준을 겨우 넘는 정도(0.16)만 요구하고, 입술이 화면의 60%를 넘으면 멀리 들라고 한다.
const double mouthMinWidth = 0.16;
const double mouthMaxLipsWidth = 0.6;
const double mouthMinOpen = 0.12;

/// 서버는 입 자리 밝기 L* 25 아래를 어둡다고 본다. 프레임 밝기로 옮긴 첫 값.
const double mouthDarkLuma = 65;

/// 치아 확인: 입이 화면 가운데에 알맞은 크기로, 이가 보이게 벌어져 있고, 밝은지 본다.
///
/// 얼굴과 같이 좌우는 말하지 않는다(앞쪽 카메라 좌우가 폰마다 다를 수 있다). 위아래는 얼굴이 똑바로 찾아졌다는 뜻이라
/// 화면 위쪽 = 사용자 머리 쪽이어서 그대로 말한다.
Framing frameMouth(MouthView? mouth, {bool faceSeen = false}) {
  if (mouth == null) {
    return faceSeen
        ? const Framing.fix('입이 잘 안 보여요. 고개를 똑바로 하고 "이~" 해 주세요.', 0.1)
        : const Framing.fix(
            '얼굴이 안 보여요. 얼굴 전체가 화면에 들어오게 폰을 조금 떨어뜨려 들고 "이~" 해 주세요.');
  }
  final lips = mouth.lips, inner = mouth.inner;
  final open = inner == null
      ? mouthMinOpen
      : inner.width <= 0
          ? 0.0
          : inner.height / inner.width;
  final c = mouthCloseness(lips, open);
  final cutLeft = lips.left <= _edge,
      cutRight = lips.right >= 1 - _edge,
      cutTop = lips.top <= _edge,
      cutBottom = lips.bottom >= 1 - _edge;
  if (lips.width > mouthMaxLipsWidth || (cutLeft && cutRight)) {
    return Framing.fix('너무 가까워요. 폰을 조금 멀리 들어 주세요.', c);
  }
  if (cutTop) {
    return Framing.fix('입이 화면 위쪽으로 나갔어요. 폰을 조금 위로 올려 주세요.', c);
  }
  if (cutBottom) {
    return Framing.fix('입이 화면 아래쪽으로 나갔어요. 폰을 조금 아래로 내려 주세요.', c);
  }
  if (cutLeft || cutRight) {
    return Framing.fix('입이 화면 옆으로 나갔어요. 폰을 입 정면으로 천천히 옮겨 주세요.', c);
  }
  if ((inner?.width ?? lips.width * 0.85) < mouthMinWidth) {
    return Framing.fix('입이 작게 보여요. 폰을 입에 조금 더 가까이 대 주세요.', c);
  }
  if (open < mouthMinOpen) {
    return Framing.fix('이가 잘 안 보여요. 입을 조금 더 벌리고 "이~" 해 주세요.', c);
  }
  final luma = mouth.luma;
  if (luma != null && luma < mouthDarkLuma) {
    return Framing.fix('입 안이 어두워요. 불을 켜거나 밝은 쪽을 봐 주세요.', c * 0.8, true);
  }
  return const Framing.ready();
}

/// 입이 가운데에서 알맞은 크기로 벌어져 있을수록 1에 가깝다.
double mouthCloseness(Rect lips, double open) {
  final dx = (lips.center.dx - 0.5).abs(), dy = (lips.center.dy - 0.5).abs();
  final centered = (1 - (dx > dy ? dx : dy) / 0.5).clamp(0.0, 1.0);
  final w = lips.width;
  final sized = w < 0.3
      ? w / 0.3
      : w > 0.7
          ? ((1 - w) / 0.3).clamp(0.0, 1.0)
          : 1.0;
  final opened = 0.5 + 0.5 * (open / mouthMinOpen).clamp(0.0, 1.0);
  return (0.15 + 0.85 * centered * sized * opened).clamp(0.0, 1.0);
}

/// 카메라 프레임 원본(누운 채)에서, 똑바로 세운 화면 기준 [region](0~1) 안 평균 밝기(0~255).
///
/// [rotation]은 [uprightBgra]와 같다(세우려면 시계 방향으로 돌릴 각도). [bytesPerPixel]이 1이면 Y 평면(안드로이드),
/// 4면 BGRA(아이폰). 칸마다 [samples]×[samples] 점만 읽는다.
double uprightRegionLuma(
  Uint8List bytes, {
  required int width,
  required int height,
  required int bytesPerRow,
  required int rotation,
  required Rect region,
  int bytesPerPixel = 1,
  int samples = 12,
}) {
  final turn = ((rotation % 360) + 360) % 360;
  final r = Rect.fromLTRB(
      region.left.clamp(0.0, 1.0),
      region.top.clamp(0.0, 1.0),
      region.right.clamp(0.0, 1.0),
      region.bottom.clamp(0.0, 1.0));
  var sum = 0.0;
  var n = 0;
  for (var j = 0; j < samples; j++) {
    for (var i = 0; i < samples; i++) {
      final u = r.left + r.width * (i + 0.5) / samples;
      final v = r.top + r.height * (j + 0.5) / samples;
      // 세운 화면 (u, v) → 원본 (rx, ry). uprightBgra의 돌림을 거꾸로 한다.
      final (rx, ry) = switch (turn) {
        90 => (v, 1 - u),
        180 => (1 - u, 1 - v),
        270 => (1 - v, u),
        _ => (u, v),
      };
      final x = (rx * width).floor().clamp(0, width - 1);
      final y = (ry * height).floor().clamp(0, height - 1);
      final k = y * bytesPerRow + x * bytesPerPixel;
      if (k + bytesPerPixel > bytes.length) continue;
      sum += bytesPerPixel == 1
          ? bytes[k]
          : 0.114 * bytes[k] + 0.587 * bytes[k + 1] + 0.299 * bytes[k + 2];
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// 상자가 화면 가운데에 알맞은 크기로 있을수록 1에 가깝다. [small]~[big]은 알맞은 넓이(화면 비율).
/// 찾기만 했으면 0.15부터 시작해서, 찾았다는 것도 소리로 알 수 있게 한다.
double boxCloseness(Rect box, {double small = 0.08, double big = 0.85}) {
  final dx = (box.center.dx - 0.5).abs(), dy = (box.center.dy - 0.5).abs();
  final centered = (1 - (dx > dy ? dx : dy) / 0.5).clamp(0.0, 1.0);
  final area = box.width * box.height;
  final sized = area < small
      ? area / small
      : area > big
          ? ((1 - area) / (1 - big)).clamp(0.0, 1.0)
          : 1.0;
  return (0.15 + 0.85 * centered * sized).clamp(0.0, 1.0);
}

/// 몸이 가운데에서 머리부터 발까지 크게 보일수록 1에 가깝다.
double bodyCloseness(double cx, double span) {
  final centered = (1 - (cx - 0.5).abs() / 0.5).clamp(0.0, 1.0);
  final tall = (span / 0.6).clamp(0.0, 1.0);
  return (0.15 + 0.85 * centered * tall).clamp(0.0, 1.0);
}
