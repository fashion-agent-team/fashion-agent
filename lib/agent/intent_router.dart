/// 사용자가 말한 기능.
enum Intent { schedule, weather, faceCheck, outfitCheck, help, unknown }

/// 말에서 원하는 기능을 고른다. 지금은 키워드로 고르고, 나중에 LLM으로 바꾼다.
///
/// 순서가 중요하다. "날씨에 맞는지 옷 검사해 줘"는 옷 검사, "겉옷 챙겨야 해?"는 날씨다.
Intent routeIntent(String text) {
  bool has(String pattern) => RegExp(pattern).hasMatch(text);

  if (has(r'일정|스케줄|약속|미팅|회의')) return Intent.schedule;
  if (has(r'얼굴|화장|메이크업|머리|헤어|치아|이빨|이에|고춧가루')) return Intent.faceCheck;
  if (has(r'검사|코디|입은|옷차림|어울려|어울리')) return Intent.outfitCheck;
  if (has(r'날씨|기온|온도|우산|비 와|비와|비가|눈 와|일교차|춥|더워|덥|겉옷')) {
    return Intent.weather;
  }
  if (has(r'옷')) return Intent.outfitCheck;
  if (has(r'기능|뭐 할 수|무엇을 할|도움|도와|설명')) return Intent.help;
  return Intent.unknown;
}
