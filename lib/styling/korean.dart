/// 앞 단어의 받침에 맞춰 조사를 붙인다. TTS 문장이 어색하지 않게 하려는 용도.
///
/// 예: `josa('남색', '과', '와')` → "남색과", `josa('베이지', '과', '와')` → "베이지와".
String josa(String word, String withBatchim, String withoutBatchim) {
  final batchim = _batchim(word);
  if (withBatchim == '으로') {
    // "로"는 받침이 없거나 ㄹ 받침일 때 쓴다.
    return '$word${batchim == 0 || batchim == 8 ? '로' : '으로'}';
  }
  return '$word${batchim == 0 ? withoutBatchim : withBatchim}';
}

String eunNeun(String word) => josa(word, '은', '는');
String iGa(String word) => josa(word, '이', '가');
String gwaWa(String word) => josa(word, '과', '와');
String euro(String word) => josa(word, '으로', '로');
String ira(String word) => josa(word, '이라', '라');
String ieyo(String word) => josa(word, '이에요', '예요');

/// 마지막 글자의 종성 번호. 받침이 없거나 한글이 아니면 0.
int _batchim(String word) {
  if (word.isEmpty) return 0;
  final code = word.runes.last;
  if (code < 0xAC00 || code > 0xD7A3) return 0;
  return (code - 0xAC00) % 28;
}
