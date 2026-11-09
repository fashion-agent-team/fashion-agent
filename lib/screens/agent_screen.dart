import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../agent/agent_controller.dart';
import '../agent/camera_turn.dart';
import '../services/turn_api.dart';
import '../session/session_controller.dart';
import 'camera_turn_screen.dart';
import 'mascot.dart';
import 'session_screen.dart';

/// 앱의 첫 화면. 위쪽 큰 버튼은 "말하기", 아래쪽은 "다시 듣기"다.
///
/// 처음 실행하면 버튼을 누르지 않아도 에이전트가 먼저 말을 건다.
class AgentScreen extends StatefulWidget {
  const AgentScreen(
      {super.key,
      required this.agent,
      required this.outfitCheck,
      this.cameraTurn,
      this.heardNow});

  final AgentController agent;

  /// 지금 듣고 있는 말(중간 결과). 화면에 보여 준다.
  final ValueListenable<String>? heardNow;
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
      backgroundColor: HanjiColors.paper,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HanjiColors.sky, HanjiColors.paper, HanjiColors.paper],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _a,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _TalkArea(
                    agent: _a,
                    heardNow: widget.heardNow,
                    onTap: () => unawaited(_a.talk()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    height: 96,
                    child: Semantics(
                      button: true,
                      enabled: !_a.busy,
                      label: '다시 듣기',
                      excludeSemantics: true,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: HanjiColors.navy,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              HanjiColors.navy.withValues(alpha: 0.4),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                          textStyle: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        onPressed:
                            _a.busy ? null : () => unawaited(_a.repeat()),
                        icon: const Icon(Icons.replay_rounded, size: 34),
                        label: const Text('다시 듣기'),
                      ),
                    ),
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

/// 한지·연꽃·인당수 느낌의 색.
class HanjiColors {
  static const paper = Color(0xFFFFF8EC);
  static const sky = Color(0xFFFFE9EF);
  static const navy = Color(0xFF283A6B);
  static const ink = Color(0xFF2A2633);
  static const red = Color(0xFFC62F45);
  static const water = Color(0xFF6FB7D6);
}

/// 위쪽 큰 영역: 마스코트, 지금 상태, 들은 말, 마지막 안내. 어디를 눌러도 "말하기"다.
class _TalkArea extends StatelessWidget {
  const _TalkArea({required this.agent, required this.onTap, this.heardNow});

  final AgentController agent;
  final VoidCallback onTap;
  final ValueListenable<String>? heardNow;

  String get _status => switch (agent.phase) {
        AgentPhase.listening => '듣고 있어요',
        AgentPhase.thinking => '알아보는 중이에요',
        AgentPhase.speaking => '말하는 중이에요',
        AgentPhase.idle =>
          agent.handsFree ? '"${agent.wakeName}" 하고 불러 주세요' : '화면을 눌러 말씀해 주세요',
      };

  IconData get _icon => switch (agent.phase) {
        AgentPhase.listening => Icons.hearing_rounded,
        AgentPhase.thinking => Icons.more_horiz_rounded,
        AgentPhase.speaking => Icons.record_voice_over_rounded,
        AgentPhase.idle => Icons.mic_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: agent.busy ? '듣는 중' : '말하기',
      hint: agent.message,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, box) {
              final mascot = (box.maxHeight * 0.48).clamp(120.0, 260.0);
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  children: [
                    Text(
                      agent.profile?.agentName ?? '패션 에이전트',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: HanjiColors.ink,
                          letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    MascotView(phase: agent.phase, size: mascot / 1.12),
                    const SizedBox(height: 8),
                    _StatusChip(icon: _icon, text: _status),
                    const SizedBox(height: 10),
                    if (heardNow != null && agent.phase == AgentPhase.listening)
                      ValueListenableBuilder<String>(
                        valueListenable: heardNow!,
                        builder: (context, heard, _) => heard.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('"$heard"',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontStyle: FontStyle.italic,
                                        color: HanjiColors.navy)),
                              ),
                      ),
                    Expanded(
                      child: agent.message.isEmpty
                          ? const SizedBox.shrink()
                          : _SpeechBubble(text: agent.message),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: HanjiColors.red,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 마지막 안내를 말풍선으로 보여 준다. 길면 스크롤된다.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF3C6D1), width: 2),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 21, height: 1.45, color: HanjiColors.ink)),
      ),
    );
  }
}
