import 'dart:async';

import 'package:flutter/material.dart';

import '../agent/agent_controller.dart';
import '../session/session_controller.dart';
import 'session_screen.dart';

/// 앱의 첫 화면. 위쪽 큰 버튼은 "말하기", 아래쪽은 "다시 듣기"다.
///
/// 처음 실행하면 버튼을 누르지 않아도 에이전트가 먼저 말을 건다.
class AgentScreen extends StatefulWidget {
  const AgentScreen(
      {super.key, required this.agent, required this.outfitCheck});

  final AgentController agent;
  final SessionController outfitCheck;

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  AgentController get _a => widget.agent;

  @override
  void initState() {
    super.initState();
    _a.openOutfitCheck = _openOutfitCheck;
    WidgetsBinding.instance.addPostFrameCallback((_) => _a.start());
  }

  Future<void> _openOutfitCheck() async {
    final session = widget.outfitCheck;
    final navigator = Navigator.of(context);
    session.onFinished = navigator.pop;
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => SessionScreen(controller: session, outfitCheckOnly: true),
    ));
    session.onFinished = null;
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
