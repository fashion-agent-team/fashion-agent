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
}

/// 구도 판단 결과. [ready]면 찍어도 된다. 아니면 [speech]를 읽어 준다.
class Framing {
  const Framing.ready()
      : ready = true,
        speech = '좋아요, 그대로 계세요.';
  const Framing.fix(this.speech) : ready = false;

  final bool ready;
  final String speech;

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
    return const Framing.fix('옷이 안 보여요. 폰을 옷 쪽으로 천천히 비춰 주세요.');
  }
  final box = boxes.reduce((a, b) => a.expandToInclude(b));
  final area = box.width * box.height;
  final cutLeft = box.left <= _edge,
      cutRight = box.right >= 1 - _edge,
      cutTop = box.top <= _edge,
      cutBottom = box.bottom >= 1 - _edge;

  if (area > 0.85 || (cutLeft && cutRight) || (cutTop && cutBottom)) {
    return const Framing.fix('너무 가까워요. 폰을 조금 더 높이 들어 주세요.');
  }
  if (area < 0.08) {
    return const Framing.fix('옷이 작게 보여요. 폰을 옷에 조금 더 가까이 가져가 주세요.');
  }
  // 한쪽이 잘렸거나 한쪽으로 치우쳤으면 그쪽으로 폰을 옮기게 한다.
  final cx = box.center.dx, cy = box.center.dy;
  if (cutLeft || cx < 0.35) {
    return const Framing.fix('옷이 왼쪽에 걸쳐 있어요. 폰을 조금 왼쪽으로 옮겨 주세요.');
  }
  if (cutRight || cx > 0.65) {
    return const Framing.fix('옷이 오른쪽에 걸쳐 있어요. 폰을 조금 오른쪽으로 옮겨 주세요.');
  }
  if (cutTop || cy < 0.35) {
    return const Framing.fix('옷이 위쪽에 걸쳐 있어요. 폰을 폰 윗부분 쪽으로 조금 옮겨 주세요.');
  }
  if (cutBottom || cy > 0.65) {
    return const Framing.fix('옷이 아래쪽에 걸쳐 있어요. 폰을 폰 아랫부분 쪽으로 조금 옮겨 주세요.');
  }
  return const Framing.ready();
}

/// 몸의 점 하나(화면 기준 0~1)와 보일 확률.
typedef BodyPoint = ({double x, double y, double likelihood});

/// 입은 옷: 머리부터 발까지 화면에 들어왔는지 본다. 폰은 세워 두고 사람이 움직인다.
///
/// [points]의 키: head(코나 귀), shoulder, hip, foot(발목이나 발뒤꿈치). 없거나 확률이 낮으면 안 보이는 것이다.
Framing frameBody(Map<String, List<BodyPoint>> points) {
  bool seen(String key) => (points[key] ?? const []).any((p) =>
      p.likelihood >= 0.5 && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1);

  if (!seen('shoulder') || !seen('hip')) {
    return const Framing.fix('몸이 안 보여요. 폰 앞 두세 걸음 떨어진 곳에 서 주세요.');
  }
  if (!seen('foot')) {
    return const Framing.fix('발까지 보이게 한 걸음 뒤로 가 주세요.');
  }
  if (!seen('head')) {
    return const Framing.fix('머리까지 보이게 한 걸음 뒤로 가 주세요.');
  }
  final all = points.values
      .expand((list) => list)
      .where((p) => p.likelihood >= 0.5)
      .toList();
  final top = all.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  final bottom = all.map((p) => p.y).reduce((a, b) => a > b ? a : b);
  final cx = all.map((p) => p.x).reduce((a, b) => a + b) / all.length;
  if (bottom - top < 0.45) {
    return const Framing.fix('조금 멀어요. 한 걸음 앞으로 와 주세요.');
  }
  if (cx < 0.3 || cx > 0.7) {
    return const Framing.fix('화면 가운데에서 벗어났어요. 폰 정면으로 조금 옮겨 서 주세요.');
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
