import '../services/listen_service.dart';
import 'utterance_end.dart';

/// 명령 한 번을 듣는다. 말이 명령으로 끝나면 조용해지기를 다 기다리지 않고 바로 돌려준다.
///
/// 2026-11-09 발표 피드백: 말이 끝나고 몇 초 기다리는 텀이 너무 길다.
/// - 명령으로 끝난 말("내일 옷 추천해 줘")은 [settle](0.45초) 동안 더 바뀌지 않으면 바로 끝낸다.
/// - 그 밖에는 [pauseFor](1.4초) 조용하면 끝낸다. 예전에는 5초를 기다렸다.
/// - 덜 끝난 말("내일 결혼식이 있는데")로 끊겼으면 [ask]로 "더 말하실 내용 있을까요?"를 묻고,
///   "없어"면 들은 말 그대로, 더 말하면 이어 붙여 돌려준다.
class CommandListener {
  CommandListener(this.listen, {required this.ask, this.maxMore = 1});

  final ListenService listen;

  /// 안내를 읽는다. 읽는 동안은 듣지 않는다.
  final Future<void> Function(String text) ask;

  /// "더 말하실 내용 있을까요?"를 몇 번까지 물을지.
  final int maxMore;

  static const pauseFor = Duration(milliseconds: 1400);
  static const settle = Duration(milliseconds: 450);

  /// 한 번 듣는 데 쓰는 기본값. 한 곳에서 고치려고 모았다.
  static Future<String?> once(ListenService listen,
          {Duration listenFor = defaultListenFor, Duration pause = pauseFor}) =>
      listen.listen(
        listenFor: listenFor,
        pauseFor: pause,
        stopWhen: (partial) => utteranceEnd(partial) == UtteranceEnd.complete,
        settle: settle,
        // 명령은 서버 음성 인식으로 다시 받아 적는다(2026-11-09 진행 님 결정: 명령만 서버로).
        server: true,
      );

  /// 명령 하나를 듣는다. 아무 말도 못 들으면 null.
  Future<String?> hear({Duration listenFor = defaultListenFor}) async {
    var heard = await once(listen, listenFor: listenFor);
    if (heard == null) return null;
    return complete(heard);
  }

  /// 이미 들은 [heard]가 덜 끝났으면 더 말할지 묻고 이어 붙인다.
  Future<String> complete(String heard) async {
    var text = heard;
    for (var i = 0; i < maxMore; i++) {
      if (utteranceEnd(text) != UtteranceEnd.incomplete) return text;
      await ask(askMore);
      final more =
          await once(listen, pause: const Duration(milliseconds: 1800));
      if (more == null || isNothingMore(more)) return text;
      text = '$text $more';
    }
    return text;
  }
}
