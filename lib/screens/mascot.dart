import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../agent/agent_controller.dart' show AgentPhase;

/// 앱 마스코트 "심청이". 연꽃 위에 앉은 요즘 느낌의 소녀.
///
/// 2026-11-09 발표 피드백: 시각장애인용이지만 발표 때 보여지는 것도 있어야 한다. 마스코트를 심청이 느낌으로.
/// 2026-11-12 화면 개편: 더 어리고 요즘 캐릭터처럼 다시 그렸다. 긴 생머리에 다홍 리본 머리핀,
/// 짧은 노랑 저고리와 색동 소매 끝, 무선 이어폰(말로 대화하는 친구), 흰 운동화.
/// 화면을 못 보는 사용자에게는 꾸밈이라 읽지 않는다(ExcludeSemantics). 상태는 소리로 알린다.
///
/// - 기다림: 천천히 숨 쉬듯 위아래로, 가끔 눈을 깜빡인다.
/// - 듣는 중: 물결(인당수)이 퍼지고 눈이 조금 커진다.
/// - 생각 중: 머리 위 점 세 개가 차례로 뛴다.
/// - 말하는 중: 입이 움직인다.
class MascotView extends StatefulWidget {
  const MascotView({super.key, required this.phase, this.size = 220});

  final AgentPhase phase;
  final double size;

  @override
  State<MascotView> createState() => _MascotViewState();
}

class _MascotViewState extends State<MascotView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size * 1.12,
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) => CustomPaint(
            painter: MascotPainter(
              phase: widget.phase,
              t: reduce ? 0 : _clock.value * 6,
            ),
          ),
        ),
      ),
    );
  }
}

/// 심청이 그리기. [t]는 초 단위 시간(0~6 반복). 220×220 칸 기준으로 그리고 위쪽 여백에 생각 점을 둔다.
class MascotPainter extends CustomPainter {
  MascotPainter({required this.phase, required this.t});

  final AgentPhase phase;
  final double t;

  static const skin = Color(0xFFFFE1CC);
  static const hair = Color(0xFF3A2A4A);
  static const hairShine = Color(0xFF6E5A8A);
  static const eye = Color(0xFF2B2440);
  static const jeogori = Color(0xFFFFD23F);
  static const chima = Color(0xFFFF5A6E);
  static const ribbonDeep = Color(0xFFE23A52);
  static const lotus = Color(0xFFFF8FB1);
  static const lotusLight = Color(0xFFFFB3C9);
  static const leaf = Color(0xFF4FB286);
  static const leafLight = Color(0xFF7FD3A8);
  static const sky = Color(0xFF3EC6FF);
  static const water = Color(0xFF6FB7D6);
  static const saekdong = [chima, sky, Color(0xFF7B6CFF)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 220;
    canvas.save();
    canvas.scale(s);
    final h = size.height / s;
    final top = h - 220; // 생각 점이 들어갈 위쪽 여백
    final bob = math.sin(t * math.pi / 1.5) * 2.5;

    if (phase == AgentPhase.thinking) _thinkingDots(canvas, bob);
    canvas.translate(0, top);
    if (phase == AgentPhase.listening) _ripples(canvas);

    _lotusBack(canvas);
    canvas.save();
    canvas.translate(0, bob);
    _hairBack(canvas);
    _body(canvas);
    _head(canvas);
    canvas.restore();
    _sneakers(canvas);
    _fill(canvas, 'M56 198 Q44 178 62 162 Q80 180 76 198Z', lotusLight);
    _fill(canvas, 'M164 198 Q176 178 158 162 Q140 180 144 198Z', lotusLight);
    _sparkles(canvas);
    canvas.restore();
  }

  void _ripples(Canvas canvas) {
    const center = Offset(110, 200);
    for (var i = 0; i < 3; i++) {
      final p = ((t / 1.6) + i / 3) % 1.0;
      canvas.drawOval(
          Rect.fromCenter(
              center: center, width: 184 + p * 60, height: 26 + p * 30),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = water.withValues(alpha: (1 - p) * 0.7));
    }
  }

  void _lotusBack(Canvas canvas) {
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(110, 200), width: 184, height: 26),
        Paint()..color = leaf);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(110, 197), width: 152, height: 16),
        Paint()..color = leafLight);
    _fill(canvas, 'M40 192 Q24 160 52 140 Q70 168 64 192Z', lotus);
    _fill(canvas, 'M180 192 Q196 160 168 140 Q150 168 156 192Z', lotus);
  }

  void _hairBack(Canvas canvas) {
    _fill(
        canvas,
        'M64 84 Q60 34 110 32 Q160 34 156 84 Q160 120 166 146 Q170 160 158 162 '
        'Q160 150 150 152 Q154 140 146 142 L74 142 Q66 140 70 152 '
        'Q60 150 62 162 Q50 160 54 146 Q60 120 64 84Z',
        hair);
  }

  void _body(Canvas canvas) {
    // 치마, 짧은 저고리, 소매
    _fill(canvas, 'M78 168 Q78 140 110 136 Q142 140 142 168Z', chima);
    _fill(
        canvas,
        'M80 150 Q82 122 110 118 Q138 122 140 150 Q126 158 110 156 Q94 158 80 150Z',
        jeogori);
    _fill(canvas, 'M84 126 Q66 134 62 156 L78 160 Q80 144 90 136Z', jeogori);
    _fill(canvas, 'M136 126 Q154 134 158 156 L142 160 Q140 144 130 136Z',
        jeogori);
    // 색동 소매 끝
    for (final x in [60.0, 140.0]) {
      for (var i = 0; i < saekdong.length; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, 154 + i * 4.0, 20, 4),
                const Radius.circular(2)),
            Paint()..color = saekdong[i]);
      }
    }
    // 손
    canvas.drawCircle(const Offset(70, 169), 7, Paint()..color = skin);
    canvas.drawCircle(const Offset(150, 169), 7, Paint()..color = skin);
    // 고름 리본
    _fill(
        canvas,
        'M110 132 Q100 126 98 134 Q100 140 110 136 Q120 140 122 134 Q120 126 110 132Z',
        chima);
    _stroke(canvas, 'M108 136 L104 150 M112 136 L117 148', chima, 4);
  }

  void _head(Canvas canvas) {
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(110, 80), width: 84, height: 80),
        Paint()..color = skin);
    // 앞머리와 옆머리
    _fill(
        canvas,
        'M68 86 Q64 40 110 38 Q156 40 152 86 Q146 66 136 60 Q132 70 124 72 '
        'Q122 62 116 60 Q112 70 104 72 Q102 64 96 64 Q90 72 82 72 Q74 74 68 86Z',
        hair);
    _fill(canvas, 'M68 84 Q62 110 70 132 Q76 112 78 92Z', hair);
    _fill(canvas, 'M152 84 Q158 110 150 132 Q144 112 142 92Z', hair);
    _stroke(canvas, 'M88 48 Q100 42 114 43', hairShine, 3.5);
    // 다홍 리본 머리핀
    _fill(canvas, 'M140 52 Q156 38 162 52 Q154 60 142 56Z', chima);
    _fill(canvas, 'M140 54 Q130 40 122 50 Q128 60 140 56Z', chima);
    canvas.drawCircle(const Offset(141, 54), 4.5, Paint()..color = ribbonDeep);

    // 눈: 듣는 중에는 조금 크게, 그 밖에는 가끔 깜빡인다.
    final blink = phase != AgentPhase.listening && (t % 3.2) < 0.14;
    final grow = phase == AgentPhase.listening ? 1.12 : 1.0;
    for (final x in [94.0, 126.0]) {
      if (blink) {
        canvas.drawLine(
            Offset(x - 6, 89),
            Offset(x + 6, 89),
            Paint()
              ..color = eye
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round);
        continue;
      }
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x, 88), width: 13 * grow, height: 17 * grow),
          Paint()..color = eye);
      canvas.drawCircle(
          Offset(x + 2.5, 85), 2.6, Paint()..color = Colors.white);
      canvas.drawCircle(
          Offset(x - 1.5, 92), 1.2, Paint()..color = Colors.white);
    }
    // 볼
    final blush = Paint()..color = lotus.withValues(alpha: 0.7);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(84, 100), width: 14, height: 9),
        blush);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(136, 100), width: 14, height: 9),
        blush);
    // 입
    if (phase == AgentPhase.speaking) {
      final open = 4 + (math.sin(t * math.pi * 5) + 1) * 3;
      canvas.drawOval(
          Rect.fromCenter(
              center: const Offset(110, 103), width: 11, height: open),
          Paint()..color = ribbonDeep);
    } else {
      _fill(canvas, 'M104 100 Q110 108 116 100Z', ribbonDeep);
    }
    // 무선 이어폰
    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(65, 90, 10, 14), const Radius.circular(5)),
        white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(68, 101, 4, 9), const Radius.circular(2)),
        white);
  }

  void _sneakers(Canvas canvas) {
    for (final x in [78.0, 108.0]) {
      canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, 176, 34, 10),
              topLeft: const Radius.circular(6),
              topRight: const Radius.circular(6)),
          Paint()..color = Colors.white);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 186, 34, 4), const Radius.circular(2)),
          Paint()..color = sky);
    }
  }

  /// 반짝이 두 개. 천천히 커졌다 작아진다.
  void _sparkles(Canvas canvas) {
    final pulse = 1 + math.sin(t * math.pi / 1.5) * 0.15;
    _star(canvas, const Offset(43, 63), 12 * pulse, jeogori);
    _star(canvas, const Offset(184, 110), 8 * (2 - pulse), lotusLight);
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final k = r / 4;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + k, c.dy - k)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx + k, c.dy + k)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - k, c.dy + k)
      ..lineTo(c.dx - r, c.dy)
      ..lineTo(c.dx - k, c.dy - k)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _thinkingDots(Canvas canvas, double bob) {
    for (var i = 0; i < 3; i++) {
      final jump = math.max(0.0, math.sin((t * 4 - i * 0.6) * math.pi)) * 6;
      canvas.drawCircle(Offset(150 + i * 13.0, 14 - jump + bob), 4.5,
          Paint()..color = jeogori);
    }
  }

  void _fill(Canvas canvas, String d, Color color) =>
      canvas.drawPath(svgPath(d), Paint()..color = color);

  void _stroke(Canvas canvas, String d, Color color, double width) =>
      canvas.drawPath(
          svgPath(d),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..color = color);

  @override
  bool shouldRepaint(MascotPainter old) => old.t != t || old.phase != phase;
}

/// 마스코트 그림에 쓰는 SVG 경로 중 M, L, Q, Z(절대 좌표)만 읽는다.
Path svgPath(String d) {
  final tokens = RegExp(r'[MLQZ]|-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var cmd = 'M';
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'[MLQZ]').hasMatch(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(n(), n());
        cmd = 'L';
      case 'L':
        path.lineTo(n(), n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), n(), n());
      case 'Z':
        path.close();
    }
  }
  return path;
}
