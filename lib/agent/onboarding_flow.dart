import '../models/user_profile.dart';
import '../services/account_service.dart';
import '../services/listen_service.dart';
import '../services/permission_service.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../styling/korean.dart';
import 'agent_speech.dart';
import 'answer_parsing.dart';
import 'voice_picker.dart';
import 'wake_word.dart';

/// 처음 설치했을 때의 음성 대화. 버튼 없이 묻고 듣기만 한다.
///
/// 순서: 인사 → 허용 창(마이크·음성 인식·카메라·위치를 한 번에, 허용하면 동의) → 구글 로그인
/// → 전에 쓴 정보가 있으면 말 빠르기까지 불러와 바로 시작, 없으면 말 빠르기 → 에이전트 이름 → 사용자 정보 → 재확인 → 호칭 → 기능 설명.
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
    // 2026-11-10 진행 님 순서: 인사 → 허용(허용하면 동의) → 구글 로그인
    // → 전에 썼으면 이름·정보·말 빠르기를 불러와 묻지 않고 바로 시작(옷장·일정은 서버에 계정별로 있다)
    // → 처음이면 말 빠르기 → 이름 → 정보.
    // "다른 폰에서 쓴 적 있나요?"는 묻지 않는다. 로그인하면 서버에 정보가 있는지로 안다.
    await _say(firstGreeting);
    final consent = await askConsent();
    if (consent == null) return const UserProfile();

    final id = await _signIn();
    final saved = id == null ? null : await account.restore(id);
    if (saved != null && saved.isOnboarded) {
      final rate = saved.speechRate;
      if (rate != null) await speech.setRate(rate);
      final restored = saved.copyWith(accountId: id, consent: consent);
      await profiles.save(restored);
      await _say(restoredAccount);
      await _say(
          restoredGreeting(restored.agentName!, callName: restored.callName));
      return restored;
    }
    if (id != null) await _say(newUserHello);

    await askSpeed();
    await askVoice();
    final agentName = await _askFirstAgentName();
    var profile =
        UserProfile(agentName: agentName, consent: consent, accountId: id);
    await _say(profileIntro);

    for (final field in _Field.values) {
      profile = await _askField(profile, field);
    }
    profile = await _confirm(profile);
    final call = await _pickCallName(profile);
    if (call != null) {
      profile = profile.copyWith(callName: call);
      await _say(niceToMeetCall(call));
    }

    profile = profile.copyWith(speechRate: speech.rate);
    if (id != null) await account.upload(id, profile);
    await profiles.save(profile);

    await _say(firstFeatureGuide);
    return profile;
  }

  /// 무엇을 하는지 알리고 허용 창을 띄운다. 허용하면 동의로 보고 동의 판([consentVersion])을 돌려준다.
  ///
  /// 2026-11-10 진행 님: 음성으로 "동의해"를 받지 않는다. 허용하면 동의로 본다.
  /// 마이크나 음성 인식을 막으면 안내하고 null(들을 수 없어서 더 진행하지 않는다).
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
    await _say(permissionThanks);
    return consentVersion;
  }

  /// 말 빠르기를 묻는다. "천천히"/"빠르게"면 바꾸고 다시 묻고, "괜찮아"거나 대답이 없으면 그대로 다음으로 간다.
  Future<void> askSpeed() async {
    var prompt = speedQuestion;
    for (var i = 0; i < 6; i++) {
      await _say(prompt);
      final heard = await listen.listen(waitFor: const Duration(seconds: 10));
      final answer = heard == null ? null : parseSpeed(heard);
      if (answer == null || answer == 0) return;
      await speech.changeRate(answer);
      prompt = speedChanged;
    }
  }

  /// 목소리가 마음에 드는지 묻는다. "바꾸고 싶어"면 하나씩 들려주고 "좋아"로 고른다.
  /// "괜찮아"거나 대답이 없으면 그대로 다음으로 간다.
  Future<void> askVoice() async {
    await _say(voiceQuestion);
    final heard = await listen.listen(waitFor: const Duration(seconds: 10));
    if (heard == null || !_wantsOtherVoice(heard)) return;
    await VoicePicker(speech: speech, listen: listen, intro: voicePickIntro)
        .run(_say);
  }

  static bool _wantsOtherVoice(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'안바꿔|안바꿀|바꾸지').hasMatch(t)) return false;
    return RegExp(r'바꾸|바꿔|바꿀|별로|싫|다른|안좋|맘에안|마음에안|들려').hasMatch(t);
  }

  /// 처음 이름은 [firstAgentName]. "좋아"거나 대답이 없으면 그대로, 다른 이름을 말하면 맞는지 확인한다.
  Future<String> _askFirstAgentName() async {
    var ask = askAgentName;
    for (var i = 0; i <= retries; i++) {
      await _say(ask);
      final heard = await listen.listen(server: true);
      if (heard == null || _keepsName(heard)) break;
      final said = parseName(heard);
      if (said == null) break;
      final name = joinSpelled(said);
      final candidates =
          [knownNameLike(name), name].whereType<String>().toSet();
      for (final c in candidates) {
        final ok = await _ask('제 이름이 $c, 맞나요?', parseYesNo);
        if (ok == true) {
          await _say('좋아요, 이제 제 이름은 ${agentNameWithIda(c)}.');
          return c;
        }
      }
      ask = spellNameAsk;
    }
    await _say(keepAgentName);
    return firstAgentName;
  }

  /// "좋아", "이대로", "심청이 좋아"처럼 처음 이름을 그대로 쓰겠다는 말.
  static bool _keepsName(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^(좋아|좋아요|좋네|괜찮|그대로|이대로|네|응|예|그래)').hasMatch(t) ||
        RegExp(r'이대로|그대로').hasMatch(t) ||
        t == firstAgentName ||
        t.startsWith('$firstAgentName좋');
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

  /// 사용자를 어떻게 부를지 묻는다. 이름이 있으면 그 이름("진행 님")을 먼저 제안한다. 건너뛰면 null(따로 부르지 않음).
  Future<String?> _pickCallName(UserProfile p, {String? first}) async {
    final suggestion = suggestedCallName(p);
    final question = suggestion == null
        ? '제가 어떻게 불러 드릴까요? 불리고 싶은 호칭을 말씀해 주세요.'
        : '제가 어떻게 불러 드릴까요? ${euro(suggestion)} 불러드리면 될까요? 아니라면 불리고 싶은 호칭을 말씀해 주세요.';
    var heard = first;
    for (var i = 0; i <= retries; i++) {
      String? call;
      if (heard != null) {
        call = heard;
        heard = null;
      } else {
        var said = await _askRaw(question, skippable: true);
        if (said == null) return null;
        final yes = suggestion == null ? null : parseYesNo(said);
        if (yes == true) return suggestion;
        if (yes == false) {
          // "아니요, 민수라고 불러 줘"면 뒤 호칭만, "아니요"뿐이면 호칭을 다시 듣는다("아니"를 호칭으로 받지 않게).
          said = said
              .replaceFirst(RegExp(r'^\s*(아니요|아니에요|아니|아뇨)[\s,.]*'), '')
              .trim();
          if (said.isEmpty) {
            said = await _askRaw('불리고 싶은 호칭을 말씀해 주세요.', skippable: true);
            if (said == null) return null;
          }
        }
        call = parseCallName(said);
        if (call == null) continue;
      }
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
      if (ok == true) return p;
      // 못 알아들었으면 맞다고 치지 않고 다시 묻는다(2026-11-10: 대답 없이 "고마워요"로 넘어갔다).
      if (ok == null) continue;

      final field = await _ask(
          '어느 항목을 고칠까요? 이름, 생년월일, 성별, 직업, 키, 몸무게 중에서 말씀해 주세요.', _Field.match);
      if (field == null) return p;
      p = await _askField(_clear(p, field), field);
    }
    return p;
  }

  /// 구글로 로그인한다. 취소하거나 안 되면 이 폰에만 저장하고 null.
  Future<String?> _signIn() async {
    await _say('$signInIntro $signInGuide');
    final id = await account.signIn();
    if (id == null) await _say(signInSkipped);
    return id;
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

  /// [question]을 읽고 들은 말을 그대로 돌려준다(건너뛰기·못 들음은 [_ask]와 같다).
  Future<String?> _askRaw(String question, {bool skippable = false}) =>
      _ask(question, (t) => t.trim().isEmpty ? null : t, skippable: skippable);

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
const defaultAgentName = firstAgentName;

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
