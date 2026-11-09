import '../models/user_profile.dart';
import '../services/account_service.dart';
import '../services/listen_service.dart';
import '../services/permission_service.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../styling/korean.dart';
import 'agent_speech.dart';
import 'answer_parsing.dart';
import 'wake_word.dart';

/// 처음 설치했을 때의 음성 대화. 버튼 없이 묻고 듣기만 한다.
///
/// 순서: 인사 → 권한 창(마이크·음성 인식·카메라·위치를 한 번에) → 다른 폰에서 쓰던 계정 확인 → 에이전트 이름 짓기 → 사용자 정보 → 재확인
/// → 계정 연결 → 기능 설명.
class OnboardingFlow {
  OnboardingFlow({
    required this.speech,
    required this.listen,
    required this.profiles,
    required this.account,
    this.permissions,
    this.onSay,
  });

  final SpeechService speech;
  final ListenService listen;
  final ProfileStore profiles;
  final AccountService account;

  /// 권한 창을 처음에 한 번에 띄운다. null이면 건너뛴다(테스트).
  final PermissionService? permissions;

  /// 화면에 마지막 안내를 보여 주려고 쓴다. [AgentController]가 채운다.
  void Function(String text)? onSay;

  /// 한 질문을 못 알아들었을 때 다시 묻는 횟수.
  static const retries = 2;

  Future<UserProfile> run() async {
    await _say(firstGreeting);
    final consent = await askConsent();

    final restored = await _restoreFromOtherPhone();
    if (restored != null) {
      if (consent == null) return restored;
      final withConsent = restored.copyWith(consent: consent);
      await profiles.save(withConsent);
      return withConsent;
    }

    var profile =
        UserProfile(agentName: await _askAgentName(), consent: consent);
    await _say('좋아요, 이제 제 이름은 ${agentNameWithIda(profile.agentName!)}. '
        '더 잘 챙겨 드리고 싶어서 몇 가지만 여쭤볼게요. '
        '말하기 싫은 건 건너뛰기라고 하시면 돼요. 전혀 괜찮아요.');

    for (final field in _Field.values) {
      profile = await _askField(profile, field);
    }
    profile = await _confirm(profile);
    final call = await _pickCallName(profile);
    if (call != null) profile = profile.copyWith(callName: call);
    await _say('알려 주셔서 고마워요. 이제 더 잘 맞춰서 도와드릴게요.');

    profile = await _connectAccount(profile);
    await profiles.save(profile);

    await _say('$featureIntro $homeHint $askFeature');
    return profile;
  }

  /// 처음 켤 때 동의받을 것을 한 번에 읽고, 권한 창을 띄운 뒤 "동의해"를 듣는다.
  ///
  /// 2026-11-09 진행 님: 앱을 처음 깔면 동의할 것(권한, 서버 음성 인식, 사진 판단, GPT 확인·학습 저장)을
  /// 한 번에 전부 띄워 동의받고 시작한다. 말로 답하려면 마이크가 있어야 해서 권한 창을 먼저 띄운다.
  /// 동의하면 동의 판([consentVersion]), 끝내 동의하지 않거나 마이크를 막으면 null.
  Future<String?> askConsent() async {
    await _say(consentIntro);
    final p = permissions;
    if (p != null) {
      await _say(permissionIntro);
      final result = await p.requestAll();
      if (!result.canListen) {
        await _say(permissionDeniedListen);
        return null;
      }
    }
    for (var i = 0; i <= retries; i++) {
      final heard = await listen.listen(waitFor: const Duration(seconds: 10));
      final answer = heard == null ? null : parseConsent(heard);
      if (answer == true) {
        await _say('동의해 주셔서 고마워요.');
        return consentVersion;
      }
      if (heard != null && RegExp(r'다시').hasMatch(heard)) {
        await _say(consentIntro);
        continue;
      }
      if (i < retries) await _say(consentRequired);
    }
    await _say(consentDeclined);
    return null;
  }

  Future<UserProfile?> _restoreFromOtherPhone() async {
    final usedBefore =
        await _ask('혹시 다른 폰에서 저를 쓰신 적이 있나요? 네 또는 아니요로 말씀해 주세요.', parseYesNo);
    if (usedBefore != true) return null;

    await _say('쓰시던 계정으로 로그인할게요. $signInGuide');
    final id = await account.signIn();
    final saved = id == null ? null : await account.restore(id);
    if (saved == null || !saved.isOnboarded) {
      await _say('이전 정보를 찾지 못했어요. 처음부터 함께 정해 볼게요.');
      return null;
    }
    final profile = saved.copyWith(accountId: id);
    await profiles.save(profile);
    await _say(
        '다시 만나서 정말 반가워요. 저는 ${agentNameWithIda(profile.agentName!)}. $askFeature');
    return profile;
  }

  Future<String> _askAgentName() async {
    final name = await _pickAgentName(askAgentName);
    if (name != null) return name;
    const fallback = defaultAgentName;
    await _say('이름은 나중에 바꿀 수 있어요. 우선 $fallback라고 불러 주세요.');
    return fallback;
  }

  /// 이름을 듣고 맞는지 되묻는다. [first]가 있으면 묻지 않고 그 이름부터 확인한다. 끝내 못 정하면 null.
  ///
  /// 2026-11-09 진행 님 폰 확인: "심청이"라고 해도 음성 인식이 자꾸 "신청"으로 적었다.
  /// 그래서 많이 쓰는 이름과 소리가 한 끗 차이면 "혹시 심청이 말씀이세요?"라고 먼저 묻고,
  /// 아니라고 하면 다음에는 한 글자씩 끊어서 말해 달라고 한다(인식기가 낱말로 바꿔 적지 않게).
  Future<String?> _pickAgentName(String question, {String? first}) async {
    var heard = first;
    var ask = question;
    for (var i = 0; i <= retries; i++) {
      final said = heard ?? await _ask(ask, parseName);
      heard = null;
      if (said == null) return null;
      final name = joinSpelled(said);
      final guess = knownNameLike(name);
      if (guess != null) {
        final ok = await _ask('혹시 $guess, 이렇게 부르시려는 건가요?', parseYesNo);
        if (ok == true) return guess;
      }
      final ok = await _ask('제 이름을 $name, 이렇게 부르시면 될까요?', parseYesNo);
      if (ok == true) return name;
      ask = spellNameAsk;
    }
    return null;
  }

  /// 사용자를 어떻게 부를지 묻는다. 건너뛰면 null(따로 부르지 않음).
  Future<String?> _pickCallName(UserProfile p, {String? first}) async {
    final example = suggestedCallName(p) ?? '진행 님';
    final question = '제가 어떻게 불러 드릴까요? 예를 들어 $example처럼 말씀해 주세요.';
    var heard = first;
    for (var i = 0; i <= retries; i++) {
      final call =
          heard ?? await _ask(question, parseCallName, skippable: true);
      heard = null;
      if (call == null) return null;
      final ok = await _ask('앞으로 $call, 이렇게 불러 드릴까요?', parseYesNo);
      if (ok == true) return call;
    }
    return null;
  }

  // ---- 온보딩 뒤에 말로 바꾸기 ("네 이름 바꿔 줘", "나를 진행 님이라고 불러 줘", "내 키 바꿔 줘") ----

  /// 에이전트 이름을 바꾼다. [said]에 새 이름이 있으면("이름을 코디로 바꿔 줘") 바로 확인한다.
  /// 바꾸지 않았으면 null.
  Future<UserProfile?> changeAgentName(UserProfile p,
      {String said = ''}) async {
    final name = await _pickAgentName('새 이름을 말씀해 주세요.', first: newNameIn(said));
    if (name == null) {
      await _say(
          '이름은 그대로 ${agentNameWithIda(p.agentName ?? defaultAgentName)}.');
      return null;
    }
    await _say('좋아요, 이제 제 이름은 ${agentNameWithIda(name)}.');
    return p.copyWith(agentName: name);
  }

  /// 사용자를 부르는 말(호칭)을 바꾼다. 바꾸지 않았으면 null.
  Future<UserProfile?> changeCallName(UserProfile p, {String said = ''}) async {
    final call = await _pickCallName(p, first: newCallNameIn(said));
    if (call == null) {
      await _say('호칭은 바꾸지 않았어요.');
      return null;
    }
    await _say('알겠어요, $call. 앞으로 이렇게 불러 드릴게요.');
    return p.copyWith(callName: call);
  }

  /// 사용자 정보 중 한 항목을 바꾼다. [said]에 항목이 있으면("내 키 바꿔 줘") 그 항목을 바로 묻는다.
  /// 바꾸지 않았으면 null.
  Future<UserProfile?> editProfile(UserProfile p, {String said = ''}) async {
    final field = _Field.match(said) ??
        await _ask(
            '지금 정보는 ${summarize(p)} 어느 항목을 고칠까요? 이름, 생년월일, 성별, 직업, 키, 몸무게 중에서 말씀해 주세요.',
            _Field.match);
    if (field == null) {
      await _say('정보는 바꾸지 않았어요.');
      return null;
    }
    final edited = await _askField(_clear(p, field), field);
    if (!field.isSet(edited)) {
      await _say('${eunNeun(field.label)} 그대로 둘게요.');
      return null;
    }
    await _say('바꿨어요. ${summarize(edited)}');
    return edited;
  }

  Future<UserProfile> _askField(UserProfile p, _Field field) async {
    switch (field) {
      case _Field.name:
        final v = await _ask('성함이 어떻게 되세요?', parseName, skippable: true);
        return v == null ? p : p.copyWith(name: v);
      case _Field.birthDate:
        final v = await _ask(
            '생년월일을 말씀해 주세요. 예를 들면 1990년 3월 5일처럼요.', parseBirthDate,
            skippable: true);
        return v == null ? p : p.copyWith(birthDate: v);
      case _Field.gender:
        final v = await _ask('성별을 말씀해 주세요. 남성 또는 여성으로 말씀해 주세요.', parseGender,
            skippable: true);
        return v == null ? p : p.copyWith(gender: v);
      case _Field.job:
        final v =
            await _ask('어떤 일을 하세요? 직업을 말씀해 주세요.', parseJob, skippable: true);
        return v == null ? p : p.copyWith(job: v);
      case _Field.height:
        final v = await _ask(
            '키는 몇 센티미터인가요?', (t) => parseMeasure(t, min: 80, max: 230),
            skippable: true);
        return v == null ? p : p.copyWith(heightCm: v);
      case _Field.weight:
        final v = await _ask(
            '몸무게는 몇 킬로그램인가요?', (t) => parseMeasure(t, min: 20, max: 250),
            skippable: true);
        return v == null ? p : p.copyWith(weightKg: v);
    }
  }

  /// 받은 정보를 읽어 주고 맞는지 묻는다. 틀리면 고칠 항목을 물어 다시 받는다.
  Future<UserProfile> _confirm(UserProfile p) async {
    for (var round = 0; round < 3; round++) {
      final ok = await _ask(
          '말씀해주신 정보를 읽어 드릴게요. ${summarize(p)} 말씀해주신 정보와 일치할까요?', parseYesNo);
      if (ok != false) return p;

      final field = await _ask(
          '어느 항목을 고칠까요? 이름, 생년월일, 성별, 직업, 키, 몸무게 중에서 말씀해 주세요.', _Field.match);
      if (field == null) return p;
      p = await _askField(_clear(p, field), field);
    }
    return p;
  }

  Future<UserProfile> _connectAccount(UserProfile p) async {
    await _say('폰을 바꿔도 이어서 쓸 수 있게 계정에 연결할게요. $signInGuide');
    final id = await account.signIn();
    if (id == null) {
      await _say('지금은 계정 연결 없이 이 폰에만 저장할게요.');
      return p;
    }
    final linked = p.copyWith(accountId: id);
    await account.upload(id, linked);
    await _say('계정에 연결했어요.');
    return linked;
  }

  /// [question]을 읽고 답을 듣는다. 못 알아들으면 [retries]번 더 묻고, 그래도 안 되면 null.
  /// [skippable]이면 "건너뛰기"에 바로 null을 돌려준다.
  Future<T?> _ask<T>(String question, T? Function(String) parse,
      {bool skippable = false}) async {
    var prompt = question;
    for (var i = 0; i <= retries; i++) {
      await _say(prompt);
      // 이름·직업처럼 흔치 않은 말이 많아서 서버 음성 인식으로 받아 적는다.
      final heard = await listen.listen(server: true);
      if (heard != null) {
        if (skippable && isSkip(heard)) {
          await _say('네, 그건 건너뛸게요.');
          return null;
        }
        final value = parse(heard);
        if (value != null) return value;
      }
      prompt =
          heard == null ? '제가 잘 못 들었어요. $question' : '제가 잘 못 알아들었어요. $question';
    }
    if (skippable) await _say('괜찮아요, 우선 넘어갈게요.');
    return null;
  }

  Future<void> _say(String text) async {
    onSay?.call(text);
    await speech.speak(text);
  }
}

/// 재확인 때 읽어 주는 문장. 건너뛴 항목은 "건너뜀"으로 읽는다.
String summarize(UserProfile p) {
  String or(String? v) => v ?? '건너뜀';
  final parts = [
    '이름 ${or(p.name)}',
    '생년월일 ${or(p.birthDate == null ? null : spokenDate(p.birthDate!))}',
    '성별 ${or(p.gender)}',
    '직업 ${or(p.job)}',
    '키 ${or(p.heightCm == null ? null : '${spokenNumber(p.heightCm!)}센티미터')}',
    '몸무게 ${or(p.weightKg == null ? null : '${spokenNumber(p.weightKg!)}킬로그램')}',
  ];
  return '${parts.join(', ')}.';
}

/// "민수" → "민수예요", "하늘" → "하늘이에요".
String agentNameWithIda(String name) => ieyo(name);

/// 이름을 정하지 못했을 때 쓰는 에이전트 이름.
const defaultAgentName = '패션 에이전트';

/// "동의해", "네 동의합니다", "응 좋아" → true. "아니", "싫어", "동의 안 해" → false. 모르면 null.
bool? parseConsent(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'동의(안|하지않|못|를안)|비동의|아니|아뇨|싫').hasMatch(t)) return false;
  if (RegExp(r'동의|동이|동희').hasMatch(t)) return true;
  return parseYesNo(text);
}

/// 이름을 잘못 들었을 때 다시 묻는 말.
const spellNameAsk =
    '제가 잘 못 알아들었나 봐요. 이름을 한 글자씩 천천히 끊어서 말씀해 주실래요? 예를 들면 심, 청, 이처럼요.';

/// 에이전트 이름으로 많이 쓸 만한 이름. 음성 인식이 비슷한 낱말("신청")로 적으면 이 이름인지 먼저 묻는다.
const knownAgentNames = [
  '심청이', '심청', '지니', '코디', '하늘이', '하늘', '봄이', '별이', '누리', '다솜', '미소', '소리',
  '루나', '토리', //
];

/// [name]이 [knownAgentNames]의 이름과 소리가 한 끗 차이면 그 이름. 똑같거나 멀면 null.
String? knownNameLike(String name) {
  final n = name.replaceAll(RegExp(r'\s+'), '');
  if (n.length < 2 || knownAgentNames.contains(n)) return null;
  for (final k in knownAgentNames) {
    if (k.length == n.length && soundDistance(n, k) == 1) return k;
  }
  return null;
}

/// "심 청 이"처럼 한 글자씩 끊어 말했으면 붙인다. 아니면 그대로.
String joinSpelled(String text) {
  final parts =
      text.trim().split(RegExp(r'[\s,.]+')).where((p) => p.isNotEmpty);
  return parts.length > 1 && parts.every((p) => p.length == 1)
      ? parts.join()
      : text.trim();
}

/// 호칭 예시. "이진행" → "진행 님", "민수" → "민수 님". 이름이 없으면 null.
String? suggestedCallName(UserProfile p) {
  final name = p.name?.replaceAll(' ', '');
  if (name == null || name.isEmpty) return null;
  final hangul3 =
      name.length == 3 && name.runes.every((c) => c >= 0xAC00 && c <= 0xD7A3);
  return '${hangul3 ? name.substring(1) : name} 님';
}

enum _Field {
  name,
  birthDate,
  gender,
  job,
  height,
  weight;

  /// 말할 때 쓰는 항목 이름.
  String get label => switch (this) {
        name => '이름',
        birthDate => '생년월일',
        gender => '성별',
        job => '직업',
        height => '키',
        weight => '몸무게',
      };

  bool isSet(UserProfile p) => switch (this) {
        name => p.name != null,
        birthDate => p.birthDate != null,
        gender => p.gender != null,
        job => p.job != null,
        height => p.heightCm != null,
        weight => p.weightKg != null,
      };

  static _Field? match(String text) {
    if (text.contains('생년') || text.contains('생일') || text.contains('날짜')) {
      return birthDate;
    }
    if (text.contains('이름') || text.contains('성함')) return name;
    if (text.contains('성별')) return gender;
    if (text.contains('직업') || text.contains('일')) return job;
    if (text.contains('키')) return height;
    if (text.contains('몸무게') || text.contains('체중')) return weight;
    return null;
  }
}

UserProfile _clear(UserProfile p, _Field field) => UserProfile(
      name: field == _Field.name ? null : p.name,
      birthDate: field == _Field.birthDate ? null : p.birthDate,
      gender: field == _Field.gender ? null : p.gender,
      job: field == _Field.job ? null : p.job,
      heightCm: field == _Field.height ? null : p.heightCm,
      weightKg: field == _Field.weight ? null : p.weightKg,
      agentName: p.agentName,
      callName: p.callName,
      accountId: p.accountId,
    );
