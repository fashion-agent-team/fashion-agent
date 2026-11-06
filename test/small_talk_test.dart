import 'package:fashion_agent/agent/intent_router.dart';
import 'package:fashion_agent/agent/small_talk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('할 줄 아는 거를 물으면 기능 설명', () {
    expect(routeIntent('할 줄 아는 거 말해봐'), Intent.help);
    expect(routeIntent('너 뭐 할 수 있어'), Intent.help);
    expect(routeIntent('뭘 해 줄 수 있어?'), Intent.help);
    expect(routeIntent('사용법 알려 줘'), Intent.help);
    expect(routeIntent('날씨 어때'), Intent.weather);
  });

  test('인사·고맙다·시간에는 대화하듯 답한다', () {
    final at = DateTime(2026, 11, 6, 15, 7);
    expect(smallTalk('안녕', now: at), contains('안녕하세요'));
    expect(smallTalk('고마워', now: at), contains('천만에요'));
    expect(smallTalk('지금 몇 시야?', now: at), '지금은 오후 3시 7분이에요.');
    expect(smallTalk('오늘 며칠이야', now: at), '오늘은 11월 6일 금요일이에요.');
    expect(smallTalk('너 누구야', now: at), contains('에이전트'));
  });

  test('모르는 말은 null이라 할 수 있는 일을 안내한다', () {
    expect(smallTalk('노래 틀어 줘'), isNull);
    expect(unknownSpeech, contains('할 수 없는'));
  });
}
