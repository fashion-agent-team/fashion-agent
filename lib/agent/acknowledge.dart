/// 서버 답을 기다리는 동안 하는 추임새. "잘 알아들었어요, 잠시만요"를 들은 말에 맞게 짧게.
///
/// 2026-11-09 발표 피드백:
/// - 명령을 처리하는 동안 말이 없으면 알아들었는지 몰라 불안하다. 알아들었다는 말을 먼저 해 달라.
/// - 추임새가 뜬금없으면 안 된다. 그래서 들은 말에서 확실히 알아본 것(날짜, 기능)만 되짚고,
///   모르는 말이면 "네, 잠시만요."처럼 어디에나 맞는 말만 한다.
library;

import 'intent_router.dart';

/// 말 속의 날짜 표현. 들은 그대로 되짚는다("내일", "11월 20일", "다음 주 토요일").
String? spokenDay(String text) {
  final m = RegExp(
    r'(\d{1,2}\s*월\s*\d{1,2}\s*일|오늘|내일|모레|글피|'
    r'(?:이번\s*주|다음\s*주|담주)?\s*[월화수목금토일]요일)',
  ).firstMatch(text);
  if (m == null) return null;
  return m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 옷을 추천해 달라는 말인지("내일 뭐 입지?", "옷 추천해 줘").
bool asksOutfitAdvice(String text) =>
    RegExp(r'뭐\s*입|뭘\s*입|입을\s*(옷|거|만한)|옷\s*추천|추천.*옷|패션|코디|입을까|옷\s*골라')
        .hasMatch(text);

/// 처음 한 말(새 요청)에 하는 추임새. 짧은 대답("응", "어 봐 줘")에는 null.
String? acknowledgementFor(String text) {
  final s = text.replaceAll(RegExp(r'\s+'), '');
  if (s.length < 4) return null;
  final day = spokenDay(text);
  final on = day == null ? '' : '$day ';
  if (asksOutfitAdvice(text)) {
    return '좋아요, $on입을 옷 같이 골라 볼게요. 잠깐만 기다려 주세요.';
  }
  switch (routeIntent(text)) {
    case Intent.weather:
      return '네, $on날씨 금방 알아봐 드릴게요.';
    case Intent.schedule:
      if (RegExp(r'넣어|등록|추가|잡아').hasMatch(text)) return '네, 일정 넣어 둘게요. 잠깐만요.';
      if (RegExp(r'지워|삭제|취소|빼').hasMatch(text)) return '네, 그 일정 찾아볼게요. 잠깐만요.';
      return '네, $on일정 같이 볼게요. 잠깐만요.';
    case Intent.outfitCheck:
      return '좋아요, 옷 같이 볼 준비 할게요.';
    case Intent.faceCheck:
      return '좋아요, 얼굴 봐 드릴 준비 할게요.';
    case Intent.help:
    case Intent.unknown:
      return '네, 잘 들었어요. 잠깐만요.';
  }
}

/// 이어지는 대화(되묻기에 대한 답)에서 하는 추임새. 길게 말하지 않는다.
const shortAcknowledgement = '네, 잘 들었어요. 잠깐만요.';
