import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/agent/intent_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// 말을 듣고 어떤 기능·설정·명령인지 고른다.
void main() {
  group('말에서 기능 고르기(routeIntent)', () {
    const cases = {
      '오늘 일정 알려 줘': Intent.schedule,
      '오늘 날씨 어때': Intent.weather,
      '겉옷 챙겨야 해?': Intent.weather,
      '날씨에 맞게 입었는지 옷 검사해 줘': Intent.outfitCheck,
      // 2026-11-09 리허설: "옷 검사"가 얼굴 확인으로 넘어갔다.
      '옷검사 해 줘': Intent.outfitCheck,
      '머리부터 옷 검사해 줘': Intent.outfitCheck,
      '이에 뭐 꼈는지 봐 줘': Intent.faceCheck,
      '머리 정돈됐는지 봐 줘': Intent.faceCheck,
      '뭐 할 수 있어?': Intent.help,
    };
    cases.forEach((said, intent) {
      test('"$said" → ${intent.name}', () => expect(routeIntent(said), intent));
    });

    test('비정상: 기능과 상관없는 "안녕" → unknown',
        () => expect(routeIntent('안녕'), Intent.unknown));
  });

  group('설정 말 고르기', () {
    const settings = {
      '네 이름 바꿔 줘': Setting.agentName,
      '이름을 코디로 바꿔 줘': Setting.agentName,
      '에이전트 이름 변경': Setting.agentName,
      '나를 진행 님이라고 불러 줘': Setting.callName,
      '호칭 바꿔 줘': Setting.callName,
      '저를 어떻게 부를지 정하고 싶어': Setting.callName,
      '내 키 바꿔 줘': Setting.profile,
      '제 정보 수정할래': Setting.profile,
      '생일 바꿔 줘': Setting.profile,
      '내 정보 알려 줘': Setting.readProfile,
    };
    settings.forEach((said, setting) {
      test('"$said" → ${setting.name}',
          () => expect(routeSetting(said), setting));
    });

    test('설정과 상관없는 말은 설정으로 고르지 않는다', () {
      expect(routeSetting('오늘 뭐 입지'), isNull);
      expect(routeSetting('날씨 어때'), isNull);
    });

    test('옷 이야기는 "바꿔"가 있어도 설정으로 고르지 않는다', () {
      expect(routeSetting('옷 바꿔 입을까'), isNull);
      expect(routeSetting('내 키에 맞는 옷 골라 줘'), isNull);
      expect(routeSetting('이 옷 이름이 뭐야'), isNull);
    });

    test('날씨 말에 "친구"가 있어도 설정으로 고르지 않는다', () {
      expect(routeSetting('오늘 날씨에 친구 불러도 될까'), isNull);
    });
  });

  group('"처음으로"·"첫 화면" 명령(isHomeCommand)', () {
    for (final said in ['처음으로', '처음으로 가 줘', '첫 화면', '첫화면으로 가 줘', '처음 화면']) {
      test('"$said" → 첫 화면으로', () => expect(isHomeCommand(said), isTrue));
    }
    test('비정상: 상관없는 "오늘 날씨 어때"는 아니다',
        () => expect(isHomeCommand('오늘 날씨 어때'), isFalse));
    test('비정상: "처음으로 입어 보는 옷이야"의 "처음으로"는 명령이 아니다',
        () => expect(isHomeCommand('처음으로 입어 보는 옷이야'), isFalse));
  });

  test('"기능 설명"과 기능별 "자세히 알려 줘"', () {
    expect(isFeatureExplainCommand('기능 설명'), isTrue);
    expect(
        featureDetailFor('이물질 확인 자세히 알려줘'),
        '이~ 하고 찍은 사진으로 이에 이물질이 끼었나 확인해드려요. 눈부터 턱까지 화면에 들어오게 폰을 들면 '
        '"입을 조금 더 벌려 주세요"처럼 안내해 드리고, 잘 보이면 알아서 찍어요. 안심하고 웃으실 수 있을거예요.');
    expect(featureDetailFor('옷 추천 자세히 알려 줘'),
        '일정과 날씨를 토대로 어떤 옷을 입으면 좋을지 종합적으로 판단해서 패션을 추천해드려요.');
    expect(
        featureDetailFor('원하는 옷 확인 자세히'),
        '옷 사진을 찍어서 그 옷이 그 날에 잘 어울리는 옷인지 판단해서 알려드려요. '
        '옷 사진은 내려놓고 찍는 방식과 입고 한 바퀴 도는 방식 중에 선택하실 수 있어요. '
        '또한 옷에 묻은 얼룩이나 찢어진 부분이 있는지도 같이 확인해드려요. '
        '찍을 때는 "폰을 조금 왼쪽으로"처럼 말로 위치를 안내해 드리고, 잘 들어오면 알아서 찍어요.');
    expect(
        featureDetailFor('일정 추가 설명해 줘'),
        '일정을 추가하실 수 있어요. 날짜와 시간 일정을 알려 주시면 일정에 맞는 패션을 추천해드려요. '
        '당일에 알림으로 리마인드 해드려요. 알림을 누르시면 그날 입을 옷 추천으로 바로 이어져요.');
  });

  test('비정상: "자세히"가 없는 "날씨 알려 줘"는 기능 설명이 아니다(null)', () {
    expect(featureDetailFor('날씨 알려 줘'), isNull);
  });
}
