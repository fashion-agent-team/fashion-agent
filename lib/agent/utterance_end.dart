/// 사용자의 말이 끝났는지 글자만 보고 가늠한다.
///
/// 2026-11-09 발표 피드백: 말이 끝나고 몇 초를 기다리는 텀이 너무 길다.
/// 이제는 말이 명령으로 끝났으면(“내일 옷 추천해 줘”) 조용해지기를 다 기다리지 않고 바로 처리하고,
/// 말이 덜 끝난 것 같은데(“내일 결혼식이 있는데”) 끊겼으면 “더 말하실 내용 있을까요?”라고 묻는다.
library;

/// 말이 끝났는지.
enum UtteranceEnd {
  /// 명령으로 끝났다. 바로 처리한다.
  complete,

  /// 이어지는 말("~는데", "그리고", "~을")로 끝났다. 더 말할지 묻는다.
  incomplete,

  /// 잘 모르겠다. 잠깐 더 조용하면 처리한다.
  unsure,
}

/// 문장 끝에 오면 명령이 끝난 말. 해요체·반말·물음 모두.
final _endings = RegExp(
  r'(줘|줘요|줄래|줄래요|주세요|주실래요|주라|해|해요|하자|할래|할게|할게요|해라|봐|봐요|보자|볼래|볼게|볼게요|'
  r'알려|알려줘|말해|읽어|찾아|골라|켜|꺼|그만|됐어|됐어요|좋아|좋아요|싫어|아니|아니요|아뇨|네|응|어|그래|그래요|'
  r'맞아|맞아요|있어|있어요|없어|없어요|야|이야|예요|이에요|에요|지|죠|지요|니|냐|나요|까|까요|가요|래|래요|'
  r'어때|어때요|뭐야|뭐예요|뭐지|뭐|언제야|어디야|어디|몇\s*시야|돼|돼요|되나|되나요|될까|될까요|입지|입을까|입을까요|'
  r'다|요|습니다|니다|세요|고마워|고마워요|감사합니다|안녕|안녕하세요|화면)$',
);

/// 문장 끝에 오면 말이 이어질 것 같은 말: 이음말, 이어지는 어미, 조사, 망설이는 소리.
final _dangling = RegExp(
  r'((^|\s)(그리고|그런데|근데|그래서|그러니까|그러면|그럼|그리구|또|아니면|혹시|음|음음|어어|저기|그|그게|있잖아|그니까)'
  r'|는데|은데|인데|한데|던데|니까|으니까|려고|으려고|러|으러|면서|으면|하면|이면|라면|거나|든지|도록|'
  r'고|이랑|랑|이나|에서|에게|한테|께|으로|부터|까지|보다|처럼|이며|의|을|를|은|는|와|과|에)$',
);

/// 가장 짧은 명령 길이(공백 뺀 글자 수). "날씨"처럼 이름만 말해도 된다.
const _minCommand = 2;

/// [text]가 끝난 말인지 가늠한다.
UtteranceEnd utteranceEnd(String text) {
  final t = text.trim().replaceAll(RegExp(r'[.!~,\s]+$'), '');
  if (t.isEmpty) return UtteranceEnd.unsure;
  if (t.endsWith('?')) return UtteranceEnd.complete;
  final squashed = t.replaceAll(RegExp(r'\s+'), '');
  // "응", "네" 같은 짧은 대답은 끝난 말이다.
  if (RegExp(r'^(응|네|넹|예|어|엉|웅|아니|노)$').hasMatch(squashed)) {
    return UtteranceEnd.complete;
  }
  if (squashed.length < _minCommand) return UtteranceEnd.unsure;
  if (_dangling.hasMatch(t)) return UtteranceEnd.incomplete;
  if (_endings.hasMatch(t)) return UtteranceEnd.complete;
  return UtteranceEnd.unsure;
}

/// "더 말하실 내용 있을까요?"에 "없어", "아니", "그게 다야"처럼 답했으면 true.
bool isNothingMore(String text) {
  final s = text.replaceAll(RegExp(r'[\s?.!,~]+'), '');
  return RegExp(r'^(아니|아뇨|없|됐|괜찮|그게다|그거다|그거야|끝|그만|그냥해|처리해|이게다|다했|응없|네없|어없|노)')
          .hasMatch(s) ||
      RegExp(r'(없어|없어요|없습니다|없음|됐어|괜찮아|끝이야|그게다야|그거야)$').hasMatch(s);
}

/// 덜 끝난 말 뒤에 묻는 말.
const askMore = '더 말하실 내용 있을까요?';
