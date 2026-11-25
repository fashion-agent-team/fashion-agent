import 'dart:async';

import 'package:fashion_agent/services/listen_service.dart';

/// 정해 둔 답을 차례로 "듣는" 가짜 마이크. null은 아무 말도 못 들은 경우다.
///
/// ```dart
/// ScriptedListen(['네', null, '오늘 날씨']) // 1번째 "네", 2번째 못 들음, 3번째 "오늘 날씨"
/// ```
class ScriptedListen implements ListenService {
  ScriptedListen(this.answers, {this.blockWhenDone = false});

  final List<String?> answers;

  /// 답이 다 떨어지면 null 대신 [cancel]될 때까지 기다린다. 계속 듣는 흐름을 시험할 때.
  final bool blockWhenDone;
  var _i = 0;
  Completer<String?>? _waiting;
  int cancels = 0;

  bool get waiting => _waiting != null && !_waiting!.isCompleted;

  @override
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 15),
    Duration pauseFor = const Duration(seconds: 3),
    Duration waitFor = const Duration(seconds: 8),
    bool Function(String partial)? stopWhen,
    Duration settle = const Duration(milliseconds: 700),
    bool server = false,
  }) async {
    if (_i < answers.length) return answers[_i++];
    if (!blockWhenDone) return null;
    return (_waiting = Completer<String?>()).future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final w = _waiting;
    if (w != null && !w.isCompleted) w.complete(null);
  }
}
