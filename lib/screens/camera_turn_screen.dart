import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../agent/camera_turn.dart';
import '../services/auto_capture.dart';
import 'session_screen.dart';

/// agent가 카메라를 켜라고 했을 때의 화면. 찍기 버튼은 없다. 멈추면 자동으로 찍는다.
///
/// 첫 화면과 같은 자리에 둔다: 위쪽 큰 영역은 "말하기", 아래쪽은 "그만하기".
/// 미리 보기는 옆에서 돕는 사람이 보라고 위쪽 영역 뒤에 깐다.
class CameraTurnScreen extends StatelessWidget {
  const CameraTurnScreen(
      {super.key, required this.controller, required this.camera});

  final CameraTurnController controller;
  final AutoCaptureCamera camera;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // 뒤로 가기도 그만하기와 같다.
      onPopInvokedWithResult: (didPop, _) => unawaited(controller.stop()),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExcludeSemantics(
                        child: ValueListenableBuilder<CameraController?>(
                          valueListenable: camera.preview,
                          builder: (context, c, _) =>
                              c != null && c.value.isInitialized
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
                      ),
                      BigButton(
                        label: controller.busy ? '확인 중' : '말하기',
                        detail: controller.message,
                        hint: controller.message,
                        onTap: () => unawaited(controller.talk()),
                        color: scheme.primaryContainer.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: BigButton(
                    label: '그만하기',
                    onTap: () => unawaited(controller.stop()),
                    color: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
