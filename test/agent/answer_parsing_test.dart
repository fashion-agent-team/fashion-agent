import 'package:fashion_agent/agent/answer_parsing.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사용자 대답에서 값을 읽는 함수들(lib/agent/answer_parsing.dart).
///
/// 테스트 하나에 말투 하나. 정상(값을 읽음)과 비정상(null·false로 다시 묻게 함)을 나눈다.
void main() {
  group('네/아니요(parseYesNo)', () {
    for (final said in ['네 맞아요', '응']) {
      test('"$said" → 네(true)', () => expect(parseYesNo(said), isTrue));
    }
    for (final said in ['아니요', '다시 할게요']) {
      test('"$said" → 아니요(false)', () => expect(parseYesNo(said), isFalse));
    }
    test('비정상: 네인지 아니요인지 모를 "글쎄" → null',
        () => expect(parseYesNo('글쎄'), isNull));
  });

  group('생년월일(parseBirthDate)', () {
    // 오늘을 고정해야 "미래 날짜" 판단이 날마다 바뀌지 않는다.
    final today = DateTime(2026, 10, 30);

    group('정상: 1990년 3월 5일을 여러 말투로 말해도 같은 날짜로 읽는다', () {
      for (final said in [
        '1990년 3월 5일',
        '1990.3.5',
        '1990-03-05',
        '19900305',
        '천구백구십년 삼월 오일',
        '구십년 삼월 오일', // 앞 두 자리를 빼고 말한 경우
      ]) {
        test('"$said"', () {
          expect(parseBirthDate(said, today: today), DateTime(1990, 3, 5));
        });
      }
    });

    group('비정상: 오늘(2026-10-30)보다 뒤인 날짜는 null', () {
      for (final said in ['2030년 1월 1일', '2026년 11월 1일']) {
        test('"$said"',
            () => expect(parseBirthDate(said, today: today), isNull));
      }
    });

    test('비정상: 달력에 없는 날짜 "1990년 2월 30일" → null', () {
      expect(parseBirthDate('1990년 2월 30일', today: today), isNull);
    });
  });

  group('키·몸무게(parseMeasure)', () {
    test('정상: 한글 수 "백칠십 센티요" → 170', () {
      expect(parseMeasure('백칠십 센티요', min: 50, max: 250), 170);
    });

    test('정상: 소수 "62.5킬로" → 62.5', () {
      expect(parseMeasure('62.5킬로', min: 10, max: 300), 62.5);
    });

    test('비정상: 범위(50~250) 밖의 "3" → null', () {
      expect(parseMeasure('3', min: 50, max: 250), isNull);
    });
  });

  group('이름·성별·직업·건너뛰기', () {
    test('이름: "제 이름은 김민수예요" → 김민수',
        () => expect(parseName('제 이름은 김민수예요'), '김민수'));
    test('이름: "하늘이라고 불러줘" → 하늘', () => expect(parseName('하늘이라고 불러줘'), '하늘'));
    test('성별: "남자요" → 남성', () => expect(parseGender('남자요'), '남성'));
    test('성별: "여성입니다" → 여성', () => expect(parseGender('여성입니다'), '여성'));
    test('직업: "저는 회사원이에요" → 회사원', () => expect(parseJob('저는 회사원이에요'), '회사원'));
    test('건너뛰기: "건너뛸게요"는 건너뛰기', () => expect(isSkip('건너뛸게요'), isTrue));
  });

  group('말에서 새 이름 꺼내기(newNameIn)', () {
    test('"이름을 코디로 바꿔 줘" → 코디', () => expect(newNameIn('이름을 코디로 바꿔 줘'), '코디'));
    test('"네 이름 하늘이라고 해" → 하늘', () => expect(newNameIn('네 이름 하늘이라고 해'), '하늘'));
    test('비정상: 새 이름 없이 "네 이름 바꿔 줘" → null(이름을 따로 묻는다)',
        () => expect(newNameIn('네 이름 바꿔 줘'), isNull));
  });

  group('말에서 호칭 꺼내기(newCallNameIn·parseCallName)', () {
    test('"나를 진행 님이라고 불러 줘" → 진행 님',
        () => expect(newCallNameIn('나를 진행 님이라고 불러 줘'), '진행 님'));
    test('"저를 대표님으로 불러 주세요" → 대표님',
        () => expect(newCallNameIn('저를 대표님으로 불러 주세요'), '대표님'));
    test('비정상: 호칭 없이 "호칭 바꿔 줘" → null(호칭을 따로 묻는다)',
        () => expect(newCallNameIn('호칭 바꿔 줘'), isNull));
    test(
        '호칭 대답 "진행 님이요" → 진행 님', () => expect(parseCallName('진행 님이요'), '진행 님'));
    test('호칭 대답 "그냥 진행이라고 불러" → 그냥 진행',
        () => expect(parseCallName('그냥 진행이라고 불러'), '그냥 진행'));
  });

  group('말 빠르기(parseSpeed·speedCommand)', () {
    test('처음 물을 때 "괜찮아요" → 그대로(0)', () => expect(parseSpeed('괜찮아요'), 0));
    test('처음 물을 때 "더 빠르게" → 한 칸 빠르게(1)', () => expect(parseSpeed('더 빠르게'), 1));
    test(
        '"천천히 말해 줘" → 한 칸 느리게(-1)', () => expect(speedCommand('천천히 말해 줘'), -1));
    test('"말 좀 빠르게 해 줘" → 한 칸 빠르게(1)',
        () => expect(speedCommand('말 좀 빠르게 해 줘'), 1));
    test('비정상: "빨리 옷 추천해 줘"의 "빨리"는 빠르기 명령이 아니다(null)',
        () => expect(speedCommand('빨리 옷 추천해 줘'), isNull));
  });

  group('다시 말해 달라는 말(isRepeatRequest)', () {
    for (final said in ['다시 말해 줘', '뭐라고?']) {
      test('"$said" → 다시 말하기', () => expect(isRepeatRequest(said), isTrue));
    }
    test('비정상: "다시 찍어 줘"는 다시 말하기가 아니다',
        () => expect(isRepeatRequest('다시 찍어 줘'), isFalse));
  });
}
