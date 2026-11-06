import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../agent/agent_controller.dart';
import '../agent/camera_turn.dart';
import '../services/turn_api.dart';
import '../session/session_controller.dart';
import 'camera_turn_screen.dart';
import 'session_screen.dart';

/// 앱의 첫 화면. 위쪽 큰 버튼은 "말하기", 아래쪽은 "다시 듣기"다.
///
/// 처음 실행하면 버튼을 누르지 않아도 에이전트가 먼저 말을 건다.
class AgentScreen extends StatefulWidget {
  const AgentScreen(
      {super.key,
      required this.agent,
      required this.outfitCheck,
      this.cameraTurn});

  final AgentController agent;
  final SessionController outfitCheck;

  /// agent와 대화할 때 쓰는 카메라. 게이트웨이를 쓰지 않으면 null.
  final CameraTurnController? cameraTurn;

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> with WidgetsBindingObserver {
  AgentController get _a => widget.agent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keepAwake(true);
    _a.openOutfitCheck = _openOutfitCheck;
    if (widget.cameraTurn != null) _a.openCamera = _openCamera;
    WidgetsBinding.instance.addPostFrameCallback((_) => _a.start());
  }

  Future<void> _openOutfitCheck() async {
    final session = widget.outfitCheck;
    final navigator = Navigator.of(context);
    session.onFinished = navigator.pop;
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => SessionScreen(controller: session),
    ));
    session.onFinished = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAwake(false);
    super.dispose();
  }

  /// 앱이 화면에 있는 동안만 이름을 듣는다. 잠그거나 다른 앱으로 가면 멈춘다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_a.handsFree) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _keepAwake(true);
        _a.resumeHandsFree();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _keepAwake(false);
        unawaited(_a.pauseHandsFree());
      default:
        break;
    }
  }

  /// 폰을 세워 두고 쓰므로, 이름을 듣는 동안은 화면이 꺼지지 않게 한다.
  void _keepAwake(bool on) {
    if (!_a.handsFree) return;
    unawaited(WakelockPlus.toggle(enable: on).catchError((Object e) {
      debugPrint('화면 켜 두기 실패: $e');
    }));
  }

  /// 카메라 화면을 띄우고 카메라 대화가 끝나면 닫는다.
  Future<TurnReply?> _openCamera(String sessionId, ImageKind kind) async {
    final camera = widget.cameraTurn!;
    final navigator = Navigator.of(context);
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) =>
          CameraTurnScreen(controller: camera, camera: camera.camera),
    )));
    final reply = await camera.run(sessionId, kind);
    if (mounted && navigator.canPop()) navigator.pop();
    return reply;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _a,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: BigButton(
                  label: _a.busy ? '듣는 중' : '말하기',
                  detail: _a.message,
                  hint: _a.message,
                  onTap: _a.busy ? null : () => unawaited(_a.talk()),
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
              Expanded(
                flex: 2,
                child: BigButton(
                  label: '다시 듣기',
                  onTap: _a.busy ? null : () => unawaited(_a.repeat()),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
