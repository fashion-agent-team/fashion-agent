/// 한 번의 코디 확인 세션이 지나는 단계. 화면은 하나이고 단계에 따라 안내만 바뀐다.
enum SessionStep {
  /// 앱을 막 열었을 때.
  idle,

  /// 오늘 날씨를 읽어 주는 중.
  briefing,

  /// 고른 옷을 펼쳐 놓고 찍기를 기다리는 중.
  capturingOutfit,

  /// 사진을 분석하는 중.
  analyzing,

  /// 고른 옷의 피드백을 들려준 뒤.
  feedback,

  /// 날씨에 맞는 겉옷을 안내한 뒤.
  outerAdvice,

  /// 끝.
  done,

  /// 대안을 찾으려고 옷장 찍기를 기다리는 중.
  capturingCloset,

  /// 옷장에서 찾은 대안을 안내한 뒤.
  alternative,

  /// 꺼낸 옷을 들고 찍기를 기다리는 중.
  checkingPicked,
}
