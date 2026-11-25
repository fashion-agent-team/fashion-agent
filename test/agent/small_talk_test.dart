import 'package:fashion_agent/agent/intent_router.dart';
import 'package:fashion_agent/agent/small_talk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('할 줄 아는 거를 물으면 기능 설명(help)', () {
    for (final said in [
      '할 줄 아는 거 말해봐',
      '너 뭐 할 수 있어',
      '뭘 해 줄 수 있어?',
      '사용법 알려 줘'
    ]) {
      test('"$said" → help', () => expect(routeIntent(said), Intent.help));
    }
  });

  group('비슷하지만 기능 설명이 아닌 말은 제 기능으로 간다', () {
    test('"날씨 어때" → weather',
        () => expect(routeIntent('날씨 어때'), Intent.weather));
    for (final said in ['오늘 뭐입지', '뭐 입을까']) {
      test('"$said" → outfitCheck',
          () => expect(routeIntent(said), Intent.outfitCheck));
    }
  });

  group('인사·고맙다·시간에는 대화하듯 답한다', () {
    // 2026-11-06(금) 오후 3시 7분으로 고정
    final at = DateTime(2026, 11, 6, 15, 7);

    test('"안녕" → 인사', () {
      expect(smallTalk('안녕', now: at), contains('안녕하세요'));
    });
    test('"고마워" → 별말씀을요', () {
      expect(smallTalk('고마워', now: at), contains('별말씀을요'));
    });
    test('"지금 몇 시야?" → 지금 시각', () {
      expect(smallTalk('지금 몇 시야?', now: at), '지금은 오후 3시 7분이에요.');
    });
    test('"오늘 며칠이야" → 오늘 날짜와 요일', () {
      expect(smallTalk('오늘 며칠이야', now: at), '오늘은 11월 6일 금요일이에요.');
    });
    test('"너 누구야" → 친구라고 소개', () {
      expect(smallTalk('너 누구야', now: at), contains('친구'));
    });
    test('"바보야~" → 서운해요', () {
      expect(smallTalk('바보야~', now: at), contains('서운해요'));
    });
  });

  test('모르는 말은 null이라 할 수 있는 일을 안내한다', () {
    expect(smallTalk('노래 틀어 줘'), isNull);
    expect(unknownSpeech, contains('못 하는 일'));
  });
}
