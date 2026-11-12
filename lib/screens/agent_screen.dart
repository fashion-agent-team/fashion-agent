import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../agent/agent_controller.dart';
import '../agent/camera_turn.dart';
import '../models/garment.dart';
import '../services/turn_api.dart';
import '../session/session_controller.dart';
import 'camera_turn_screen.dart';
import 'mascot.dart';
import 'palette.dart';
import 'session_screen.dart';

/// 앱의 첫 화면. 위쪽 큰 버튼은 "말하기", 아래쪽은 "다시 듣기"다.
///
/// 2026-11-12 화면 개편 "인당수의 밤": 쪽빛 바탕, 노랑 큰 상태 글씨, 듣는 중에는 아래쪽 물이 다홍으로 바뀐다.
///
/// 처음 실행하면 버튼을 누르지 않아도 에이전트가 먼저 말을 건다.
class AgentScreen extends StatefulWidget {
  const AgentScreen(
      {super.key,
      required this.agent,
      this.outfitCheck,
      this.cameraTurn,
      this.heardNow});

  final AgentController agent;

  /// 지금 듣고 있는 말(중간 결과). 화면에 보여 준다.
  final ValueListenable<String>? heardNow;

  /// 서버 없이 도는 옷 검사 화면(데모용). null이면 옷 검사는 서버 대화로만 한다.
  final SessionController? outfitCheck;

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
    if (widget.outfitCheck != null) _a.openOutfitCheck = _openOutfitCheck;
    if (widget.cameraTurn != null) _a.openCamera = _openCamera;
    WidgetsBinding.instance.addPostFrameCallback((_) => _a.start());
  }

  Future<void> _openOutfitCheck() async {
    final session = widget.outfitCheck!;
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
    // 카메라에서 본 옷은 첫 화면 "오늘의 색동"에 남긴다.
    _a.addOutfit(camera.garments);
    if (mounted && navigator.canPop()) navigator.pop();
    return reply;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: SeaColors.sea,
      body: ListenableBuilder(
        listenable: _a,
        builder: (context, _) {
          final listening = _a.phase == AgentPhase.listening;
          // 듣는 중이면 아래쪽 물이 다홍으로 차오른다.
          return TweenAnimationBuilder<Color?>(
            tween:
                ColorTween(end: listening ? SeaColors.dahong : SeaColors.deep),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 320),
            builder: (context, water, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SafeArea(
                    bottom: false,
                    child: _TalkArea(
                      agent: _a,
                      water: water!,
                      heardNow: widget.heardNow,
                      onTap: () => unawaited(_a.talk()),
                    ),
                  ),
                ),
                ColoredBox(
                  color: water,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
                    child: SlabButton(
                      label: '다시 듣기',
                      icon: Icons.replay_rounded,
                      // 듣는 중에는 다홍 위에 쪽빛 버튼, 평소에는 노랑 버튼.
                      background: listening ? SeaColors.sea : SeaColors.jeogori,
                      foreground: listening ? SeaColors.jeogori : SeaColors.sea,
                      onPressed: _a.busy ? null : () => unawaited(_a.repeat()),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 위쪽 큰 영역: 이름, 마스코트, 지금 상태, 들은 말, 마지막 안내. 어디를 눌러도 "말하기"다.
class _TalkArea extends StatelessWidget {
  const _TalkArea(
      {required this.agent,
      required this.onTap,
      required this.water,
      this.heardNow});

  final AgentController agent;
  final VoidCallback onTap;
  final Color water;
  final ValueListenable<String>? heardNow;

  String get _status => switch (agent.phase) {
        AgentPhase.listening => '듣고 있어요',
        AgentPhase.thinking => '알아보는 중이에요',
        AgentPhase.speaking => '말하는 중이에요',
        AgentPhase.idle =>
          agent.handsFree ? '“${agent.wakeName}” 하고 불러 주세요' : '화면을 눌러 말씀해 주세요',
      };

  @override
  Widget build(BuildContext context) {
    final listening = agent.phase == AgentPhase.listening;
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
              // 옷 검사 결과가 있으면 "오늘의 색동". 다시 들을 때는 평소 화면으로.
              if (agent.outfit.isNotEmpty && !listening) {
                return _OutfitResult(
                    garments: agent.outfit, message: agent.message);
              }
              final mascot = (box.maxHeight * 0.34).clamp(110.0, 236.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
                    child: Text(
                      agent.profile?.agentName ?? '패션 에이전트',
                      style: const TextStyle(
                          fontFamily: SeaFonts.batang,
                          fontSize: 22,
                          color: SeaColors.jeogori),
                    ),
                  ),
                  // 마스코트가 물 위 연꽃에 앉아 있다.
                  SizedBox(
                    height: mascot * 1.12 - 10,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                            left: 0,
                            right: 0,
                            // 1px 겹쳐서 물결과 아래 판 사이에 틈이 보이지 않게.
                            bottom: -1,
                            child: WaveEdge(color: water)),
                        Positioned(
                          bottom: -10,
                          child: MascotView(phase: agent.phase, size: mascot),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: water,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 듣는 중: 소리 막대. 멀리서도 "듣고 있다"가 보이게.
                            if (listening)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 6),
                                child: Icon(Icons.graphic_eq_rounded,
                                    size: 52, color: SeaColors.sea),
                              ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _status,
                                key: ValueKey(_status),
                                style: TextStyle(
                                  fontFamily: SeaFonts.gothic,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 42,
                                  height: 1.15,
                                  letterSpacing: -0.8,
                                  color: listening
                                      ? SeaColors.sea
                                      : SeaColors.jeogori,
                                ),
                              ),
                            ),
                            if (heardNow != null && listening)
                              ValueListenableBuilder<String>(
                                valueListenable: heardNow!,
                                builder: (context, heard, _) => heard.isEmpty
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: Text('“$heard”',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontFamily: SeaFonts.batang,
                                                fontSize: 32,
                                                height: 1.45,
                                                color: SeaColors.hanji)),
                                      ),
                              ),
                            if (!listening && agent.message.isNotEmpty)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: SingleChildScrollView(
                                    child: Text(agent.message,
                                        style: const TextStyle(
                                            fontFamily: SeaFonts.batang,
                                            fontSize: 22,
                                            height: 1.7,
                                            color: SeaColors.hanji)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 새 화면 "오늘의 색동": 찍은 옷의 실제 색을 상의·하의·신발 순서로 화면 가득 쌓는다.
///
/// 마스코트 소매의 색동처럼. 저시력 사용자는 색 덩어리로, 돕는 사람은 조합을 한눈에 본다.
/// 화면 읽기는 위쪽 영역 전체("말하기")가 마지막 안내를 읽으므로 따로 읽지 않는다.
class _OutfitResult extends StatelessWidget {
  const _OutfitResult({required this.garments, required this.message});

  final List<Garment> garments;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('오늘의 색동',
                style: TextStyle(
                    fontFamily: SeaFonts.gothic,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: SeaColors.jeogori)),
          ),
          if (message.isNotEmpty)
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                child: SingleChildScrollView(
                  child: Text(message,
                      style: const TextStyle(
                          fontFamily: SeaFonts.batang,
                          fontSize: 24,
                          height: 1.55,
                          color: SeaColors.hanji)),
                ),
              ),
            )
          else
            const SizedBox(height: 18),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in garments)
                    Expanded(child: _ColorBand(garment: g)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 옷 한 벌의 색 띠. 작은 글씨로 "상의, 니트", 큰 글씨로 색 이름.
class _ColorBand extends StatelessWidget {
  const _ColorBand({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context) {
    final color = swatchFor(garment.colorFamily, garment.tone);
    // 밝은 색 위에는 쪽빛 글씨, 어두운 색 위에는 한지 글씨.
    final ink =
        color.computeLuminance() > 0.35 ? SeaColors.sea : SeaColors.hanji;
    final kind = categoryLabel(garment.category);
    final label = garment.name == kind ? kind : '$kind, ${garment.name}';
    return ColoredBox(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: SeaFonts.gothic,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: ink)),
              Text(garment.colorName,
                  style: TextStyle(
                      fontFamily: SeaFonts.gothic,
                      fontWeight: FontWeight.w900,
                      fontSize: 38,
                      height: 1.1,
                      letterSpacing: -0.6,
                      color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}
