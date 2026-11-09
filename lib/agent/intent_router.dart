/// 사용자가 말한 기능.
enum Intent { schedule, weather, faceCheck, outfitCheck, help, unknown }

/// 말에서 원하는 기능을 고른다. 지금은 키워드로 고르고, 나중에 LLM으로 바꾼다.
///
/// 순서가 중요하다. "날씨에 맞는지 옷 검사해 줘"는 옷 검사, "겉옷 챙겨야 해?"는 날씨다.
Intent routeIntent(String text) {
  bool has(String pattern) => RegExp(pattern).hasMatch(text);

  if (has(r'일정|스케줄|약속|미팅|회의')) return Intent.schedule;
  // "옷 검사해 줘"가 얼굴 확인으로 가던 문제(2026-11-09 리허설). 옷 이야기면 얼굴 말보다 먼저 본다.
  if (has(r'옷\s*(검사|확인|봐|체크|상태)|입은\s*(옷|거|모습)|옷차림')) {
    return Intent.outfitCheck;
  }
  if (has(r'얼굴|화장|메이크업|머리\s*(모양|정돈|상태|확인|봐)|헤어|치아|이빨|이에\s*(뭐|낀|꼈|묻)|고춧가루')) {
    return Intent.faceCheck;
  }
  if (has(r'검사|코디|입은|옷차림|어울려|어울리|얼룩|찢어|구멍')) {
    return Intent.outfitCheck;
  }
  if (has(r'날씨|기온|온도|우산|비 와|비와|비가|눈 와|일교차|춥|더워|덥|겉옷')) {
    return Intent.weather;
  }
  if (has(r'옷|뭐 ?입|뭘 ?입|입을까|입지')) return Intent.outfitCheck;
  // "할 줄 아는 거 말해 봐"도 알아듣게 (2026-11-06 폰 확인)
  const helpWords = r'기능|할 ?줄|할 ?수 ?있|뭐 ?할|뭘 ?할|무엇을 ?할|뭐 ?해 ?줄|뭘 ?해 ?줄'
      r'|도움|도와|설명|능력|소개|사용법|어떻게 ?써';
  if (has(helpWords)) return Intent.help;
  return Intent.unknown;
}

/// 폰 안에서 바로 바꾸는 설정. 에이전트 서버로 보내지 않는다.
enum Setting {
  /// 에이전트 이름 바꾸기.
  agentName,

  /// 사용자를 부르는 말(호칭) 바꾸기.
  callName,

  /// 사용자 정보(이름·생년월일·성별·직업·키·몸무게) 바꾸기.
  profile,

  /// 사용자 정보 읽어 주기.
  readProfile,
}

const _change = r'바꾸|바꿔|바꿀|변경|수정|고치|고쳐|고칠|새로 ?지|다시 ?지|다시 ?정';

/// 설정을 바꾸려는 말이면 그 설정을, 아니면 null.
///
/// "나를 진행 님이라고 불러 줘" → 호칭, "네 이름 바꿔 줘" → 에이전트 이름, "내 키 바꿔 줘" → 사용자 정보.
Setting? routeSetting(String text) {
  bool has(String pattern) => RegExp(pattern).hasMatch(text);
  final change = has(_change);

  if (has(r'호칭') ||
      has(r'(^|\s)(저|나|날|절)(를|을)?\s.*((이)?라고|(으)?로)\s*(불러|부르)') ||
      has(r'(^|\s)(저를|나를|날|절)\s*(.*(이라고|라고|으로|로))?\s*(불러|부르)') ||
      has(r'(어떻게|뭐라고)\s*(불러|부르|부를)')) {
    return Setting.callName;
  }
  final info = has(r'(내|제|나의|저의|사용자|회원|개인)\s*정보|프로필');
  final mine = has(r'(내|제|나의|저의)\s*(이름|성함|생년월일|생일|성별|직업|키|몸무게|체중)');
  if (change && (info || mine)) return Setting.profile;
  if (info && has(r'알려|읽어|말해|뭐|확인|어떻게')) return Setting.readProfile;
  if (change && has(r'생년월일|생일|성별|직업|몸무게|체중|(^|\s)키(를|가|는)?\s')) {
    return Setting.profile;
  }
  if (has(r'이름') && (change || has(r'이름(을|은)?.*(으로|로|이라고|라고)\s*(해|할|불러)'))) {
    return Setting.agentName;
  }
  return null;
}
