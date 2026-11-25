import 'package:fashion_agent/agent/answer_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사용자 대답에서 값을 읽는 함수들(lib/agent/answer_parsing.dart).
void main() {
  test('네/아니요', () {
    expect(parseYesNo('네 맞아요'), isTrue);
    expect(parseYesNo('응'), isTrue);
    expect(parseYesNo('아니요'), isFalse);
    expect(parseYesNo('다시 할게요'), isFalse);
    expect(parseYesNo('글쎄'), isNull);
  });

  group('생년월일', () {
    final today = DateTime(2026, 10, 30);

    test('여러 말투를 받는다', () {
      for (final said in [
        '1990년 3월 5일',
        '1990.3.5',
        '1990-03-05',
        '19900305',
        '천구백구십년 삼월 오일',
        '구십년 삼월 오일',
      ]) {
        expect(parseBirthDate(said, today: today), DateTime(1990, 3, 5),
            reason: said);
      }
    });

    test('미래 날짜는 받지 않는다', () {
      expect(parseBirthDate('2030년 1월 1일', today: today), isNull);
      expect(parseBirthDate('2026년 11월 1일', today: today), isNull);
    });

    test('없는 날짜는 받지 않는다', () {
      expect(parseBirthDate('1990년 2월 30일', today: today), isNull);
    });
  });

  group('키·몸무게', () {
    test('숫자나 한글 수로 받는다', () {
      expect(parseMeasure('백칠십 센티요', min: 50, max: 250), 170);
      expect(parseMeasure('62.5킬로', min: 10, max: 300), 62.5);
    });

    test('범위 밖이면 받지 않는다', () {
      expect(parseMeasure('3', min: 50, max: 250), isNull);
    });
  });

  test('이름·성별·직업', () {
    expect(parseName('제 이름은 김민수예요'), '김민수');
    expect(parseName('하늘이라고 불러줘'), '하늘');
    expect(parseGender('남자요'), '남성');
    expect(parseGender('여성입니다'), '여성');
    expect(parseJob('저는 회사원이에요'), '회사원');
    expect(isSkip('건너뛸게요'), isTrue);
  });

  test('말에서 새 이름·호칭을 꺼낸다', () {
    expect(newNameIn('이름을 코디로 바꿔 줘'), '코디');
    expect(newNameIn('네 이름 하늘이라고 해'), '하늘');
    expect(newNameIn('네 이름 바꿔 줘'), isNull);
    expect(newCallNameIn('나를 진행 님이라고 불러 줘'), '진행 님');
    expect(newCallNameIn('저를 대표님으로 불러 주세요'), '대표님');
    expect(newCallNameIn('호칭 바꿔 줘'), isNull);
    expect(parseCallName('진행 님이요'), '진행 님');
    expect(parseCallName('그냥 진행이라고 불러'), '그냥 진행');
  });

  test('말 빠르기 대답과 "천천히 말해 줘"를 읽는다', () {
    expect(parseSpeed('괜찮아요'), 0);
    expect(parseSpeed('더 빠르게'), 1);
    expect(speedCommand('천천히 말해 줘'), -1);
    expect(speedCommand('말 좀 빠르게 해 줘'), 1);
    expect(speedCommand('빨리 옷 추천해 줘'), isNull);
  });

  test('"다시 말해 줘"를 알아듣고, "다시 찍어 줘"는 아니다', () {
    expect(isRepeatRequest('다시 말해 줘'), isTrue);
    expect(isRepeatRequest('뭐라고?'), isTrue);
    expect(isRepeatRequest('다시 찍어 줘'), isFalse);
  });
}
