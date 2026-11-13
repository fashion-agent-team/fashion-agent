import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../agent/camera_turn.dart';
import '../services/auto_capture.dart';
import '../services/turn_api.dart' show ImageKind;
import 'palette.dart';

/// agent가 카메라를 켜라고 했을 때의 화면. 찍기 버튼은 없다. 멈추면 자동으로 찍는다.
///
/// 첫 화면과 같은 자리에 둔다: 위쪽 큰 영역은 "말하기", 아래쪽은 "그만하기".
/// 2026-11-12 화면 개편: 위는 옆에서 돕는 사람이 보는 미리 보기, 그 아래는 사용자를 위한 큰 안내 한 줄.
/// 미리 보기와 안내를 합친 위쪽 전체가 "말하기" 버튼 하나다.
class CameraTurnScreen extends StatelessWidget {
  const CameraTurnScreen(
      {super.key, required this.controller, required this.camera});

  final CameraTurnController controller;
  final AutoCaptureCamera camera;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      // 뒤로 가기도 그만하기와 같다.
      onPopInvokedWithResult: (didPop, _) => unawaited(controller.stop()),
      child: Scaffold(
        backgroundColor: SeaColors.sea,
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: controller.busy ? '확인 중' : '말하기',
                  // 안내는 앱이 소리로 읽는다. 여기에 긴 안내를 넣으면 VoiceOver와 겹친다(2026-11-13 점검).
                  hint: controller.busy ? null : '두 번 탭하면 말씀하실 수 있어요.',
                  excludeSemantics: true,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => unawaited(controller.talk()),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: _Preview(camera: camera)),
                          Expanded(
                            flex: 9,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                              child: _Guide(controller: controller),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
                child: SlabButton(
                  label: '그만하기',
                  icon: Icons.stop_rounded,
                  background: SeaColors.hanji,
                  foreground: SeaColors.sea,
                  onPressed: () => unawaited(controller.stop()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 아래쪽 안내: 진행 막대 세 칸, 노랑 큰 글씨 한 줄(첫 문장), 그 아래 한지색 작은 설명(나머지).
class _Guide extends StatelessWidget {
  const _Guide({required this.controller});

  final CameraTurnController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.message.isEmpty
        ? (controller.busy ? '확인 중이에요' : '멈추면 알아서 찍어요')
        : controller.message;
    final (head, rest) = splitGuide(text);
    // 옷을 찍을 때만 몇 장째인지 보여 준다(얼굴·이는 한 장).
    final steps = switch (controller.kind) {
      ImageKind.outfit || ImageKind.worn => 3,
      _ => 0,
    };
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (steps > 0) ...[
            _Steps(total: steps, done: controller.shots),
            const SizedBox(height: 22),
          ],
          Text(
            head,
            style: const TextStyle(
              fontFamily: SeaFonts.gothic,
              fontWeight: FontWeight.w900,
              fontSize: 40,
              height: 1.18,
              letterSpacing: -0.8,
              color: SeaColors.jeogori,
            ),
          ),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                rest,
                style: const TextStyle(
                  fontFamily: SeaFonts.batang,
                  fontSize: 21,
                  height: 1.6,
                  color: SeaColors.hanji,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 첫 문장과 나머지로 나눈다. 첫 문장 끝의 마침표는 큰 글씨에서 뺀다("한 걸음 뒤로 가 주세요").
(String, String) splitGuide(String text) {
  final t = text.trim();
  final m = RegExp(r'[.?!。](\s+|$)').firstMatch(t);
  if (m == null || m.end >= t.length) return (_dropPeriod(t), '');
  return (_dropPeriod(t.substring(0, m.start + 1)), t.substring(m.end).trim());
}

String _dropPeriod(String s) =>
    s.endsWith('.') ? s.substring(0, s.length - 1) : s;

/// 진행 막대: 찍은 만큼 노랑, 남은 칸은 흐린 파랑. 꾸밈이라 화면 읽기에서 뺀다.
class _Steps extends StatelessWidget {
  const _Steps({required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 7,
                decoration: BoxDecoration(
                  color: i < done ? SeaColors.jeogori : const Color(0xFF34477F),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 돕는 사람이 보는 미리 보기. 노란 모서리로 찍히는 칸을 보여 준다. 화면 읽기에서는 뺀다.
class _Preview extends StatelessWidget {
  const _Preview({required this.camera});

  final AutoCaptureCamera camera;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ExcludeSemantics(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<CameraController?>(
              valueListenable: camera.preview,
              builder: (context, c, _) => c != null && c.value.isInitialized
                  ? FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: c.value.previewSize?.height ?? 1,
                        height: c.value.previewSize?.width ?? 1,
                        child: CameraPreview(c),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(56, top + 40, 56, 20),
              child: const CustomPaint(painter: _CornerPainter()),
            ),
            Positioned(
              left: 20,
              top: top + 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: SeaColors.deep.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text('돕는 분이 보는 화면',
                      style: TextStyle(
                          fontFamily: SeaFonts.gothic,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: SeaColors.hanji)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 38.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = SeaColors.jeogori;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      canvas.drawPath(
          Path()
            ..moveTo(x, y + dy * arm)
            ..lineTo(x, y)
            ..lineTo(x + dx * arm, y),
          paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
