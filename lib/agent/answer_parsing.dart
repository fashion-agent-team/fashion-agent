/// 음성 인식 결과(글자)를 온보딩 답으로 바꾼다.
///
/// 음성 인식은 숫자를 "170"으로 줄 때도, "백칠십"으로 줄 때도 있어서 둘 다 받는다.
library;

/// 문장 부호를 걷어 낸다. "62.5"처럼 숫자 사이의 점은 남긴다.
String _clean(String text) =>
    text.replaceAll(RegExp(r'[,!?]|\.(?!\d)'), ' ').trim();

/// 네/아니오. 어느 쪽인지 모르면 null.
bool? parseYesNo(String text) {
  final t = _clean(text);
  // "아니"가 "네"보다 먼저다. "아니요 네 번째"처럼 섞여도 부정으로 본다.
  if (RegExp(r'아니|아뇨|틀려|틀렸|다시|싫어').hasMatch(t)) return false;
  if (RegExp(r'^(네|예|응|어|맞|좋아|그래|그렇|오케이|ok)', caseSensitive: false)
          .hasMatch(t) ||
      RegExp(r'맞아|맞습니다|맞아요|일치|좋아요').hasMatch(t)) {
    return true;
  }
  return null;
}

/// "건너뛰기", "패스", "말하기 싫어요" 같은 답.
bool isSkip(String text) =>
    RegExp(r'건너|넘어가|패스|말 ?안 ?할|말하기 싫|비밀|생략').hasMatch(_clean(text));

const _digits = {
  '영': 0,
  '공': 0,
  '일': 1,
  '이': 2,
  '삼': 3,
  '사': 4,
  '오': 5,
  '육': 6,
  '칠': 7,
  '팔': 8,
  '구': 9,
};
const _units = {'십': 10, '백': 100, '천': 1000};

/// "백칠십" → 170, "천구백구십" → 1990, "일구구공" → 1990. 한자어 수만 읽는다.
int? _koreanNumber(String word) {
  if (word.isEmpty) return null;
  if (!word.split('').any(_units.containsKey)) {
    // 단위 없이 한 자리씩 읽은 수.
    final digits = word.split('').map((ch) => _digits[ch]);
    if (digits.contains(null)) return null;
    return int.parse(digits.join());
  }
  var total = 0, current = 0;
  for (final ch in word.split('')) {
    if (_digits.containsKey(ch)) {
      current = _digits[ch]!;
    } else if (_units.containsKey(ch)) {
      total += (current == 0 ? 1 : current) * _units[ch]!;
      current = 0;
    } else {
      return null;
    }
  }
  return total + current;
}

/// 글 속 수를 앞에서부터 모두 찾는다. "1990년 3월 5일" → [1990, 3, 5].
List<num> numbersIn(String text) {
  final found = <num>[];
  final pattern = RegExp(r'\d+(?:\.\d+)?|[영공일이삼사오육칠팔구십백천]+');
  for (final m in pattern.allMatches(_clean(text))) {
    final word = m.group(0)!;
    final n = num.tryParse(word) ?? _koreanNumber(word);
    if (n != null) found.add(n);
  }
  return found;
}

/// 키·몸무게 같은 수 하나. [min]~[max] 밖이면 잘못 들은 것으로 본다.
double? parseMeasure(String text, {required num min, required num max}) {
  for (final n in numbersIn(text)) {
    if (n >= min && n <= max) return n.toDouble();
  }
  return null;
}

/// "1990년 3월 5일", "1990.3.5", "1990-03-05", "1990 3 5" → 날짜.
DateTime? parseBirthDate(String text, {DateTime? today}) {
  final now = today ?? DateTime.now();
  // "삼월 오일"의 "일"이 수 1로 읽히지 않게 년·월·일과 구분 기호를 띄어쓰기로 바꾼다.
  text = text
      .replaceAll(RegExp(r'[년월./-]'), ' ')
      .replaceAll(RegExp(r'(?<=\S)일(?=\s|$)'), ' ');
  final compact = RegExp(r'\b(\d{4})(\d{2})(\d{2})\b').firstMatch(text);
  final parts = compact != null
      ? [for (var i = 1; i <= 3; i++) int.parse(compact.group(i)!)]
      : numbersIn(text).map((n) => n.toInt()).toList();
  if (parts.length < 3) return null;
  var (y, m, d) = (parts[0], parts[1], parts[2]);
  // "구십년 삼월 오일"처럼 두 자리 연도로 말하면 1900년대·2000년대 중 지나간 쪽으로 본다.
  if (y < 100) y += (2000 + y <= now.year) ? 2000 : 1900;
  if (y < 1900 || y > now.year || m < 1 || m > 12 || d < 1 || d > 31) {
    return null;
  }
  final date = DateTime(y, m, d);
  if (date.month != m || date.isAfter(now)) return null;
  return date;
}

/// "남자", "남성", "여자", "여성".
String? parseGender(String text) {
  final t = _clean(text);
  if (RegExp(r'여자|여성|^여').hasMatch(t)) return '여성';
  if (RegExp(r'남자|남성|^남').hasMatch(t)) return '남성';
  return null;
}

/// "제 이름은 김민수예요" → "김민수". 앞뒤의 군말을 걷어 낸다.
String? parseName(String text) {
  var t = _clean(text)
      .replaceFirst(RegExp(r'^(음+|어+|저는|제 이름은|이름은|내 이름은|나는)\s*'), '')
      .replaceFirst(
          RegExp(
              r'\s*(이라고 해요|라고 해요|이라고 합니다|라고 합니다|이라고 불러 ?줘|라고 불러 ?줘|입니다|이에요|예요|이야|야|요)$'),
          '')
      .trim();
  if (t.isEmpty || t.length > 20) return null;
  return t;
}

/// 직업은 말한 그대로 받되, 끝의 "이에요/입니다"만 걷어 낸다.
String? parseJob(String text) {
  final t = _clean(text)
      .replaceFirst(RegExp(r'^(저는|제 직업은|직업은)\s*'), '')
      .replaceFirst(RegExp(r'\s*(입니다|이에요|예요|이야|야|요)$'), '')
      .trim();
  return t.isEmpty ? null : t;
}

/// 날짜를 읽기 좋게: "1990년 3월 5일".
String spokenDate(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

/// 170.0 → "170", 62.5 → "62.5".
String spokenNumber(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();
