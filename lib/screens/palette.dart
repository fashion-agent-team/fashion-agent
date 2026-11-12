import 'package:flutter/material.dart';

import '../models/garment.dart';

/// 화면 개편(2026-11-12) "인당수의 밤" 색.
///
/// 쪽빛 바탕에 노랑 큰 글씨는 저시력 사용자가 가장 잘 읽는 대비 조합이다(바탕 대비 약 11:1).
/// 다홍은 "듣는 중"에만 쓴다. 멀리서 흐릿하게 봐도 지금 듣고 있다는 게 색 하나로 보이게.
class SeaColors {
  /// 인당수 쪽빛: 바탕
  static const sea = Color(0xFF14204A);

  /// 깊은 물: 화면 아래쪽
  static const deep = Color(0xFF0B1433);

  /// 저고리 노랑: 큰 글씨·주 버튼
  static const jeogori = Color(0xFFFFD86B);

  /// 한지: 안내 문장
  static const hanji = Color(0xFFF3EBDD);

  /// 다홍: 듣는 중
  static const dahong = Color(0xFFE0474C);

  /// 연꽃: 키보드 초점 테두리
  static const lotus = Color(0xFFF7A1B5);
}

/// 옷 색 계열·톤을 화면에 칠할 색으로. "오늘의 색동" 띠에 쓴다.
/// 실제 옷 사진 색이 아니라 계열의 대표색이다(사진은 폰에 남기지 않는다).
Color swatchFor(ColorFamily family, Tone tone) {
  final base = switch (family) {
    ColorFamily.black => const Color(0xFF232327),
    ColorFamily.white => const Color(0xFFF1EBDF),
    ColorFamily.gray => const Color(0xFF8D9097),
    ColorFamily.navy => const Color(0xFF2B3A64),
    ColorFamily.beige => const Color(0xFFD8C4A2),
    ColorFamily.brown => const Color(0xFF6B4A33),
    ColorFamily.khaki => const Color(0xFF7C7A4E),
    ColorFamily.blue => const Color(0xFF3E6DB3),
    ColorFamily.red => const Color(0xFFC03A3D),
    ColorFamily.pink => const Color(0xFFE8A0B4),
    ColorFamily.orange => const Color(0xFFDF7A34),
    ColorFamily.yellow => const Color(0xFFE6C24A),
    ColorFamily.green => const Color(0xFF3E7C4E),
    ColorFamily.purple => const Color(0xFF6D4E99),
    ColorFamily.unknown => const Color(0xFF5A6072),
  };
  // 검정·흰색은 톤을 따로 두지 않는다.
  if (family == ColorFamily.black || family == ColorFamily.white) return base;
  final hsl = HSLColor.fromColor(base);
  final l = switch (tone) {
    Tone.light => hsl.lightness + (1 - hsl.lightness) * 0.4,
    Tone.mid => hsl.lightness,
    Tone.dark => hsl.lightness * 0.8,
  };
  // 쪽빛 바탕(밝기 약 0.18)에 묻히지 않게 0.22 밑으로는 내리지 않는다.
  return hsl.withLightness(l.clamp(0.22, 1.0)).toColor();
}

/// 글꼴 규칙: 누르는 것과 상태는 고딕, 에이전트가 하는 말과 들은 말은 명조.
class SeaFonts {
  static const gothic = 'GothicA1';
  static const batang = 'GowunBatang';
}

/// 화면 위쪽 영역과 아래쪽 물 사이의 물결 경계.
class WaveEdge extends StatelessWidget {
  const WaveEdge({super.key, required this.color, this.height = 24});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _WavePainter(color)),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const waves = 4;
    final step = size.width / waves;
    final mid = size.height / 2;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, mid);
    for (var i = 0; i < waves; i++) {
      final x = i * step;
      path
        ..quadraticBezierTo(x + step / 4, 0, x + step / 2, mid)
        ..quadraticBezierTo(x + step * 3 / 4, size.height, x + step, mid);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}

/// 화면 아래 큰 버튼. 둥근 판에 굵은 고딕 글씨와 아이콘.
class SlabButton extends StatelessWidget {
  const SlabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.45),
            disabledForegroundColor: foreground.withValues(alpha: 0.75),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            textStyle: const TextStyle(
                fontFamily: SeaFonts.gothic,
                fontSize: 32,
                fontWeight: FontWeight.w900),
          ).copyWith(
            side: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.focused)
                    ? const BorderSide(color: SeaColors.lotus, width: 5)
                    : null),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 36),
          label: Text(label),
        ),
      ),
    );
  }
}
