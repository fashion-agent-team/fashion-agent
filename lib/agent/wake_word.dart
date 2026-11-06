/// 에이전트 이름 부르기. 시리·지니처럼 이름이 들리면 듣기 시작한다.
library;

/// 이름을 정하지 않았을 때 부르는 말.
const defaultWakeName = '에이전트';

String _squash(String s) =>
    s.replaceAll(RegExp(r'[\s.,!?~"' "'" r']'), '').toLowerCase();

/// [heard]에 에이전트 이름([name])이 있으면 이름 뒤에 한 말을 돌려준다. 이름만 불렀으면 빈 문자열, 이름이 없으면 null.
///
/// 음성 인식은 띄어쓰기를 제멋대로 하므로("코디 야", "헤이코디") 공백을 빼고 찾는다.
/// 이름 뒤 부르는 말(야·아·님·씨)과 "헤이"는 버린다.
/// 예: name="코디", "코디야 오늘 뭐 입지?" → "오늘 뭐 입지?"
String? afterWakeWord(String heard, String? name) {
  final wake =
      _squash(name == null || name.trim().isEmpty ? defaultWakeName : name);
  if (wake.isEmpty) return null;

  // 원문에서 공백을 뺀 위치와 원래 위치를 짝지어 두고, 이름이 끝난 원래 위치를 찾는다.
  final kept = <int>[];
  final squashed = StringBuffer();
  for (var i = 0; i < heard.length; i++) {
    final ch = heard[i];
    if (_squash(ch).isEmpty) continue;
    kept.add(i);
    squashed.write(ch.toLowerCase());
  }
  final at = squashed.toString().indexOf(wake);
  if (at < 0) return null;

  final end = kept[at + wake.length - 1] + 1;
  var rest = heard.substring(end);
  final call = RegExp(r'^\s*(야|(아|님|씨)(?=$|[\s,.!?~]))');
  final m = call.firstMatch(rest);
  if (m != null) rest = rest.substring(m.end);
  return rest.replaceFirst(RegExp(r'^[\s,.!?~]+'), '').trim();
}
