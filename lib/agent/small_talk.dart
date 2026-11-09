/// 기능 밖의 짧은 말에 대화하듯 답한다. 로그인하지 않아 폰 안에서 처리할 때 쓴다.
/// 로그인하면 agent가 답한다(GPT가 켜져 있으면 어떤 말에도 자연스럽게).
///
/// 2026-11-06 진행 님 폰 확인: 기능 밖 질문에 "잘 이해하지 못했어요"만 해서 대화가 끊겼다.
library;

/// 모르는 말. 못 한다고 솔직히 말하고 할 수 있는 일을 짧게 알려 준다.
const unknownSpeech = '아, 그건 아직 제가 못 하는 일이라 아쉬워요. '
    '대신 옷 봐 드리기, 날씨, 얼굴 확인, 일정은 자신 있어요. 뭐부터 해 볼까요?';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 규칙으로 답할 수 있는 말이면 답, 아니면 null.
String? smallTalk(String text, {DateTime? now}) {
  final s = text.replaceAll(RegExp(r'[\s?.!,~]+'), '');
  if (s.isEmpty) return null;
  bool has(String pattern) => RegExp(pattern).hasMatch(s);
  final t = now ?? DateTime.now();

  if (has(r'몇시|지금시간|시간알려')) {
    final half = t.hour < 12 ? '오전' : '오후';
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '지금은 $half $h12시 ${t.minute}분이에요.';
  }
  if (has(r'며칠|몇일|날짜|무슨요일|몇월')) {
    return '오늘은 ${t.month}월 ${t.day}일 ${_weekdays[t.weekday - 1]}요일이에요.';
  }
  if (has(r'바보|멍청|멍텅|못생')) return '에이, 서운해요. 그래도 더 잘 도와드리게 열심히 할게요.';
  if (has(r'고마|감사|땡큐')) return '별말씀을요, 저도 기뻐요. 또 필요하면 언제든 불러 주세요.';
  if (has(r'잘자|잘있어|안녕히|다음에봐')) return '네, 푹 쉬세요. 또 불러 주시면 금방 올게요.';
  if (has(r'누구야|누구세요|누구니|너는뭐|넌뭐|이름이뭐|이름뭐')) {
    return '저는 옷 입는 걸 곁에서 같이 챙겨 드리는 친구예요. 오늘 뭐 입을지 같이 봐요.';
  }
  if (has(r'잘지냈|기분어때|뭐해|심심')) return '저는 잘 지내요, 물어봐 주셔서 고마워요. 오늘은 뭘 같이 해 볼까요?';
  if (has(r'안녕|반가|하이|좋은아침')) return '안녕하세요, 반가워요. 오늘은 뭘 같이 해 볼까요?';
  return null;
}
