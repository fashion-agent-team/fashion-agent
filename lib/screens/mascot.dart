import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../agent/agent_controller.dart' show AgentPhase;

/// 앱 마스코트 "심청이". 연꽃 위에 앉은 댕기머리 소녀(노랑 저고리, 색동 소매, 다홍 치마).
///
/// 2026-11-09 발표 피드백: 시각장애인용이지만 발표 때 보여지는 것도 있어야 한다. 마스코트를 심청이 느낌으로.
/// 화면을 못 보는 사용자에게는 꾸밈이라 읽지 않는다(ExcludeSemantics). 상태는 소리로 알린다.
///
/// - 기다림: 천천히 숨 쉬듯 위아래로, 가끔 눈을 깜빡인다.
/// - 듣는 중: 물결(인당수)이 퍼진다.
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

/// 심청이 그리기. [t]는 초 단위 시간(0~6 반복).
class MascotPainter extends CustomPainter {
  MascotPainter({required this.phase, required this.t});

  final AgentPhase phase;
  final double t;

  static const skin = Color(0xFFFFE3CF);
  static const hair = Color(0xFF2A2633);
  static const jeogori = Color(0xFFFFD86B);
  static const chima = Color(0xFFE0474C);
  static const goreum = Color(0xFFC62F45);
  static const lotus = Color(0xFFF7A1B5);
  static const lotusDeep = Color(0xFFEA6F8E);
  static const leaf = Color(0xFF5BAE7E);
  static const water = Color(0xFF6FB7D6);
  static const saekdong = [
    Color(0xFFE0474C),
    Color(0xFFFFB347),
    Color(0xFFFFE066),
    Color(0xFF6CC28A),
    Color(0xFF5B8DEF),
    Color(0xFFB57EDC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 220; // 220 기준으로 그린다
    canvas.save();
    canvas.scale(s);
    const w = 220.0;
    final h = size.height / s;

    if (phase == AgentPhase.listening) _ripples(canvas, w, h);

    // 숨쉬기
    final bob = math.sin(t * math.pi / 1.5) * 2.5;
    _lotus(canvas, w, h);
    canvas.save();
    canvas.translate(0, bob);
    _body(canvas, w, h);
    _head(canvas, w, h);
    canvas.restore();
    _frontPetals(canvas, w, h);

    if (phase == AgentPhase.thinking) _thinkingDots(canvas, w, bob);
    canvas.restore();
  }

  void _ripples(Canvas canvas, double w, double h) {
    final center = Offset(w / 2, h - 40);
    for (var i = 0; i < 3; i++) {
      final p = ((t / 1.6) + i / 3) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = water.withValues(alpha: (1 - p) * 0.7);
      canvas.drawOval(
          Rect.fromCenter(
              center: center, width: 120 + p * 120, height: 30 + p * 40),
          paint);
    }
  }

  void _lotus(Canvas canvas, double w, double h) {
    final base = h - 40;
    // 연잎
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w / 2, base + 8), width: 190, height: 34),
        Paint()..color = leaf);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w / 2, base + 4), width: 170, height: 22),
        Paint()..color = const Color(0xFF7CC79A));
    // 꽃잎: 뒤쪽은 진하게, 앞쪽은 밝게
    for (final (dx, angle, color) in [
      (-58.0, -0.9, lotusDeep),
      (58.0, 0.9, lotusDeep),
      (-36.0, -0.45, lotus),
      (36.0, 0.45, lotus),
      (0.0, 0.0, lotus),
    ]) {
      canvas.save();
      canvas.translate(w / 2 + dx, base - 6);
      canvas.rotate(angle);
      final petal = Path()
        ..moveTo(0, 14)
        ..quadraticBezierTo(-22, -6, 0, -34)
        ..quadraticBezierTo(22, -6, 0, 14)
        ..close();
      canvas.drawPath(petal, Paint()..color = color);
      canvas.drawPath(
          petal,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white.withValues(alpha: 0.6));
      canvas.restore();
    }
  }

  /// 치마 앞을 감싸는 앞쪽 꽃잎. 연꽃 위에 앉은 것처럼 보이게.
  void _frontPetals(Canvas canvas, double w, double h) {
    final base = h - 40;
    for (final (dx, angle) in [
      (-44.0, -0.35),
      (44.0, 0.35),
      (-16.0, -0.1),
      (16.0, 0.1)
    ]) {
      canvas.save();
      canvas.translate(w / 2 + dx, base + 8);
      canvas.rotate(angle);
      final petal = Path()
        ..moveTo(0, 8)
        ..quadraticBezierTo(-17, -6, 0, -26)
        ..quadraticBezierTo(17, -6, 0, 8)
        ..close();
      canvas.drawPath(petal, Paint()..color = lotus);
      canvas.drawPath(
          petal,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = lotusDeep.withValues(alpha: 0.5));
      canvas.restore();
    }
  }

  void _body(Canvas canvas, double w, double h) {
    final base = h - 46;
    final cx = w / 2;
    // 다홍 치마(종 모양)
    final skirt = Path()
      ..moveTo(cx - 34, base - 74)
      ..quadraticBezierTo(cx - 70, base - 20, cx - 66, base)
      ..quadraticBezierTo(cx, base + 12, cx + 66, base)
      ..quadraticBezierTo(cx + 70, base - 20, cx + 34, base - 74)
      ..close();
    canvas.drawPath(skirt, Paint()..color = chima);
    // 치마 주름
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFB8333A).withValues(alpha: 0.6);
    for (final x in [-30.0, -10.0, 10.0, 30.0]) {
      canvas.drawLine(Offset(cx + x * 0.6, base - 66),
          Offset(cx + x * 1.3, base - 4), fold);
    }
    // 저고리
    final jacket = RRect.fromRectAndCorners(
      Rect.fromCenter(center: Offset(cx, base - 84), width: 78, height: 42),
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: const Radius.circular(10),
      bottomRight: const Radius.circular(10),
    );
    canvas.drawRRect(jacket, Paint()..color = jeogori);
    // 색동 소매(양쪽)
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < saekdong.length; i++) {
        final x = cx + side * (40 + i * 5.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(x, base - 78 + i * 2.0), width: 6, height: 26),
              const Radius.circular(3)),
          Paint()..color = saekdong[i],
        );
      }
      // 손
      canvas.drawCircle(
          Offset(cx + side * 72, base - 64), 6.5, Paint()..color = skin);
    }
    // 깃과 동정
    final collar = Path()
      ..moveTo(cx - 16, base - 104)
      ..lineTo(cx + 6, base - 82)
      ..lineTo(cx + 16, base - 104);
    canvas.drawPath(
        collar,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
    // 고름(리본)
    final ribbon = Paint()..color = goreum;
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + 10, base - 80), width: 14, height: 9),
        ribbon);
    final tails = Path()
      ..moveTo(cx + 10, base - 80)
      ..quadraticBezierTo(cx + 4, base - 62, cx + 2, base - 50)
      ..moveTo(cx + 10, base - 80)
      ..quadraticBezierTo(cx + 18, base - 64, cx + 14, base - 52);
    canvas.drawPath(
        tails,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = goreum);
  }

  void _head(Canvas canvas, double w, double h) {
    final cx = w / 2;
    final cy = h - 46 - 140;
    // 댕기머리(뒤로 늘어진 땋은 머리) + 빨간 댕기
    final braid = Paint()..color = hair;
    for (var i = 0; i < 5; i++) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx + 40 + i * 2.0, cy + 18 + i * 13.0),
              width: 13,
              height: 16),
          braid);
    }
    final daenggi = Path()
      ..moveTo(cx + 48, cy + 78)
      ..lineTo(cx + 40, cy + 100)
      ..lineTo(cx + 50, cy + 94)
      ..lineTo(cx + 58, cy + 100)
      ..close();
    canvas.drawPath(daenggi, Paint()..color = goreum);

    // 얼굴
    canvas.drawCircle(Offset(cx, cy), 42, Paint()..color = skin);
    // 머리카락(가운데 가르마)
    final hairTop = Path()
      ..moveTo(cx - 44, cy + 4)
      ..quadraticBezierTo(cx - 46, cy - 46, cx, cy - 46)
      ..quadraticBezierTo(cx + 46, cy - 46, cx + 44, cy + 4)
      ..quadraticBezierTo(cx + 30, cy - 26, cx + 2, cy - 30)
      ..lineTo(cx - 2, cy - 30)
      ..quadraticBezierTo(cx - 30, cy - 26, cx - 44, cy + 4)
      ..close();
    canvas.drawPath(hairTop, Paint()..color = hair);
    // 머리 윤기
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx - 18, cy - 30), width: 26, height: 12),
        math.pi * 1.1,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.35));

    // 볼
    final blush = Paint()
      ..color = const Color(0xFFFF9FB0).withValues(alpha: 0.55);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - 24, cy + 14), width: 16, height: 9),
        blush);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx + 24, cy + 14), width: 16, height: 9),
        blush);

    // 눈: 듣는 중에는 동그랗게, 그 밖에는 가끔 깜빡인다.
    final blink = phase != AgentPhase.listening && (t % 3.2) < 0.14;
    final eye = Paint()..color = hair;
    for (final side in [-1.0, 1.0]) {
      final at = Offset(cx + side * 15, cy + 2);
      if (blink) {
        canvas.drawLine(
            at.translate(-5, 0),
            at.translate(5, 0),
            eye
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round);
      } else {
        final r = phase == AgentPhase.listening ? 5.5 : 4.8;
        canvas.drawCircle(at, r, eye);
        canvas.drawCircle(
            at.translate(1.6, -1.8), 1.6, Paint()..color = Colors.white);
      }
    }

    // 입
    final mouth = Offset(cx, cy + 22);
    if (phase == AgentPhase.speaking) {
      final open = 3 + (math.sin(t * math.pi * 5) + 1) * 3;
      canvas.drawOval(Rect.fromCenter(center: mouth, width: 11, height: open),
          Paint()..color = const Color(0xFFB8454F));
    } else {
      canvas.drawArc(
          Rect.fromCenter(center: mouth.translate(0, -3), width: 14, height: 9),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFB8454F));
    }
  }

  void _thinkingDots(Canvas canvas, double w, double bob) {
    for (var i = 0; i < 3; i++) {
      final jump = math.max(0.0, math.sin((t * 4 - i * 0.6) * math.pi)) * 6;
      canvas.drawCircle(Offset(w / 2 + 50 + i * 13.0, 16 - jump + bob), 4.5,
          Paint()..color = goreum.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(MascotPainter old) => old.t != t || old.phase != phase;
}
