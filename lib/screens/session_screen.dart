import 'package:flutter/material.dart';

import '../session/session_controller.dart';

/// 앱의 유일한 화면. 위쪽 절반과 아래쪽 절반이 각각 하나의 큰 버튼이다.
///
/// VoiceOver를 켠 사용자도 화면 어디를 눌러도 버튼을 찾을 수 있게, 작은 버튼은 두지 않는다.
class SessionScreen extends StatefulWidget {
  const SessionScreen(
      {super.key, required this.controller, this.outfitCheckOnly = false});

  final SessionController controller;

  /// 에이전트에서 열었으면 날씨 안내 없이 바로 옷 검사부터 한다.
  final bool outfitCheckOnly;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  SessionController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.outfitCheckOnly ? _c.startOutfitCheck() : _c.start());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: BigButton(
                  label: _c.primaryLabel,
                  detail: _c.message,
                  hint: _c.message,
                  onTap: _c.busy ? null : _c.primary,
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
              Expanded(
                flex: 2,
                child: BigButton(
                  label: _c.secondaryLabel,
                  onTap: _c.busy ? null : _c.secondary,
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

/// 화면 절반을 차지하는 버튼. VoiceOver가 [label]과 [hint]만 읽게 한다.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.color,
    this.detail,
    this.hint,
  });

  final String label;
  final String? detail;
  final String? hint;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      hint: hint,
      excludeSemantics: true,
      child: Material(
        color: color,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 36, fontWeight: FontWeight.bold)),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(detail!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
