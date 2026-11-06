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
  final found = _find(squashed.toString(), wake);
  if (found == null) return null;
  final (at, length) = found;

  final end = kept[at + length - 1] + 1;
  var rest = heard.substring(end);
  final call = RegExp(r'^\s*(야|(아|님|씨)(?=$|[\s,.!?~]))');
  final m = call.firstMatch(rest);
  if (m != null) rest = rest.substring(m.end);
  return rest.replaceFirst(RegExp(r'^[\s,.!?~]+'), '').trim();
}

/// [text]에서 [wake]를 찾는다. 같은 글자가 없으면 음성 인식이 살짝 다르게 쓴 이름("코디" → "고디")도 찾는다.
/// 글자를 자모로 풀어 비교해서, 두 글자 이름은 자모 하나, 세 글자 이상은 자모 둘까지 다르면 같은 이름으로 본다.
/// "어디"(ㅇㅓ)는 "코디"(ㅋㅗ)와 자모 둘이 달라서 이름으로 보지 않는다.
(int, int)? _find(String text, String wake) {
  final exact = text.indexOf(wake);
  if (exact >= 0) return (exact, wake.length);
  if (wake.length < 2) return null;
  final limit = wake.length >= 3 ? 2 : 1;
  final target = _jamo(wake);
  (int, int)? best;
  var bestDistance = limit + 1;
  for (var start = 0; start < text.length; start++) {
    for (final len in [wake.length, wake.length - 1, wake.length + 1]) {
      if (len < 2 || start + len > text.length) continue;
      final d = _distance(_jamo(text.substring(start, start + len)), target);
      if (d < bestDistance) {
        bestDistance = d;
        best = (start, len);
      }
    }
    if (best != null && bestDistance <= limit) return best;
  }
  return null;
}

/// 한글 글자를 초성·중성·종성 번호로 푼다. 한글이 아니면 글자 코드 그대로.
List<int> _jamo(String s) {
  final out = <int>[];
  for (final c in s.runes) {
    if (c >= 0xAC00 && c <= 0xD7A3) {
      final i = c - 0xAC00;
      out
        ..add(i ~/ 588)
        ..add(100 + (i % 588) ~/ 28);
      if (i % 28 != 0) out.add(200 + i % 28);
    } else {
      out.add(1000 + c);
    }
  }
  return out;
}

int _distance(List<int> a, List<int> b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}
