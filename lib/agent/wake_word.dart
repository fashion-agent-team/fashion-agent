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
///
/// 세 글자 사람 이름("박창근")이면 성을 뺀 이름("창근아")만 불러도 알아듣는다(2026-11-09 진행 님 폰 확인: 잘 못 알아들음).
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
  final text = squashed.toString();
  final lastAt = _find(text, wake) ??
      (_isPersonName(wake)
          ? _find(text, wake.substring(1), exactOnly: true)
          : null);
  if (lastAt == null) return null;

  final end = kept[lastAt] + 1;
  var rest = heard.substring(end);
  final call = RegExp(r'^\s*(이?야|(아|님|씨)(?=$|[\s,.!?~]))');
  final m = call.firstMatch(rest);
  if (m != null) rest = rest.substring(m.end);
  return rest.replaceFirst(RegExp(r'^[\s,.!?~]+'), '').trim();
}

/// 한글 세 글자면 "성+이름"으로 본다.
bool _isPersonName(String wake) =>
    wake.length == 3 && wake.runes.every(_isHangul);

bool _isHangul(int c) => c >= 0xAC00 && c <= 0xD7A3;

/// [text]에서 [wake]를 찾아 이름의 마지막 글자 위치를 돌려준다.
///
/// 같은 글자가 없으면 음성 인식이 살짝 다르게 쓴 이름도 찾는다. 글자를 소리(자모)로 풀어 이어 놓고 비교한다.
/// - 비슷한 소리는 같게 본다: ㄱ·ㅋ·ㄲ, ㄷ·ㅌ·ㄸ, ㅂ·ㅍ·ㅃ, ㅈ·ㅊ·ㅉ, ㅅ·ㅆ, ㅐ·ㅔ, ㅚ·ㅙ·ㅞ.
/// - 소리 없는 첫소리 ㅇ은 뺀다. 그래서 받침이 넘어간 "창그나"도 "창근아"로 읽는다.
/// - 그래도 다르면 두 글자 이름은 소리 하나, 세 글자 이상은 소리 둘까지 달라도 같은 이름으로 본다.
///   "어디"는 "코디"와 소리 둘이 달라서 이름으로 보지 않는다.
///
/// [exactOnly]면 비슷한 소리만 같게 보고, 다른 소리는 하나도 허용하지 않는다(성을 뺀 이름 찾기).
int? _find(String text, String wake, {bool exactOnly = false}) {
  final exact = text.indexOf(wake);
  if (exact >= 0) return exact + wake.length - 1;
  if (wake.length < 2) return null;
  final limit = exactOnly ? 0 : (wake.length >= 3 ? 2 : 1);
  final target = _sounds(wake).map((s) => s.$1).toList();
  final heard = _sounds(text);
  for (var start = 0; start < heard.length; start++) {
    if (!heard[start].$3) continue; // 글자의 첫소리에서만 시작한다.
    // 차이가 같으면 글자가 끝나는 곳에서 끊는 쪽을 고른다("에이전 날씨"에서 "날"의 ㄴ까지 이름으로 먹지 않게).
    int? bestEnd;
    var bestScore = 2 * limit + 2;
    for (var len = target.length - limit; len <= target.length + limit; len++) {
      if (len < 2 || start + len > heard.length) continue;
      final window = [for (var k = start; k < start + len; k++) heard[k].$1];
      final d = _distance(window, target);
      if (d > limit) continue;
      final atEnd = start + len == heard.length || heard[start + len].$3;
      final score = 2 * d + (atEnd ? 0 : 1);
      if (score < bestScore) {
        bestScore = score;
        bestEnd = heard[start + len - 1].$2;
      }
    }
    if (bestEnd != null) return bestEnd;
  }
  return null;
}

// 소리 묶음 번호. 비슷한 자음은 같은 번호다.
const _k = 1, _n = 2, _t = 3, _l = 4, _m = 5, _p = 6, _s = 7, _ng = 8;
const _c = 9, _h = 10;

/// 첫소리 19개 → 소리 묶음. ㅇ(11)은 0(소리 없음).
const _initial = [
  _k, _k, _n, _t, _t, _l, _m, _p, _p, _s, _s, 0, _c, _c, _c, _k, _t, _p, _h, //
];

/// 받침 28개 → 소리 묶음. 겹받침은 앞 자음으로 읽는다.
const _final = [
  0, _k, _k, _k, _n, _n, _n, _t, _l, _l, _l, _l, _l, _l, _l, _l, //
  _m, _p, _p, _s, _s, _ng, _c, _c, _k, _t, _p, _h,
];

/// 모음 21개. 비슷한 모음(ㅐ·ㅔ, ㅒ·ㅖ, ㅙ·ㅚ·ㅞ)은 같은 번호로.
int _vowel(int v) =>
    100 +
    switch (v) {
      5 => 1, // ㅔ → ㅐ
      7 => 3, // ㅖ → ㅒ
      11 || 15 => 10, // ㅚ·ㅞ → ㅙ
      _ => v,
    };

/// 글자를 소리 목록으로 푼다. (소리 번호, 원래 글자 위치, 글자의 첫소리인지).
List<(int, int, bool)> _sounds(String s) {
  final out = <(int, int, bool)>[];
  var at = 0;
  for (final c in s.runes) {
    if (_isHangul(c)) {
      final i = c - 0xAC00;
      final first = _initial[i ~/ 588];
      if (first != 0) out.add((first, at, true));
      out.add((_vowel((i % 588) ~/ 28), at, first == 0));
      final last = _final[i % 28];
      if (last != 0) out.add((last, at, false));
    } else {
      out.add((1000 + c, at, true));
    }
    at += String.fromCharCode(c).length;
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

/// 두 말의 소리(자모) 차이. 비슷한 소리는 같게 본다([afterWakeWord]와 같은 기준).
int soundDistance(String a, String b) => _distance(
    _sounds(_squash(a)).map((s) => s.$1).toList(),
    _sounds(_squash(b)).map((s) => s.$1).toList());
