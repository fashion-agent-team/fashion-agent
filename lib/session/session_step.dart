/// 옷 검사 한 번이 지나는 단계. 화면은 하나이고 단계에 따라 안내만 바뀐다.
enum SessionStep {
  /// 화면을 막 열었을 때.
  idle,

  /// 날씨와 오늘 일정을 가져오는 중.
  preparing,

  /// 옷을 펼쳐 놓고 찍기를 기다리는 중.
  capturing,

  /// 사진을 분석하는 중.
  analyzing,

  /// 검사 결과를 들려준 뒤.
  result,
}
