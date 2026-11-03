import '../models/user_profile.dart';
import '../services/account_service.dart';
import '../services/listen_service.dart';
import '../services/profile_store.dart';
import '../services/speech_service.dart';
import '../styling/korean.dart';
import 'agent_speech.dart';
import 'answer_parsing.dart';

/// 처음 설치했을 때의 음성 대화. 버튼 없이 묻고 듣기만 한다.
///
/// 순서: 인사 → 다른 폰에서 쓰던 계정 확인 → 에이전트 이름 짓기 → 사용자 정보 → 재확인
/// → 계정 연결 → 기능 설명.
class OnboardingFlow {
  OnboardingFlow({
    required this.speech,
    required this.listen,
    required this.profiles,
    required this.account,
    this.onSay,
  });

  final SpeechService speech;
  final ListenService listen;
  final ProfileStore profiles;
  final AccountService account;

  /// 화면에 마지막 안내를 보여 주려고 쓴다. [AgentController]가 채운다.
  void Function(String text)? onSay;

  /// 한 질문을 못 알아들었을 때 다시 묻는 횟수.
  static const retries = 2;

  Future<UserProfile> run() async {
    await _say(firstGreeting);

    final restored = await _restoreFromOtherPhone();
    if (restored != null) return restored;

    var profile = UserProfile(agentName: await _askAgentName());
    await _say('좋아요, 이제 제 이름은 ${agentNameWithIda(profile.agentName!)}. '
        '더 잘 도와드리기 위해 몇 가지 여쭤볼게요. '
        '말하고 싶지 않은 건 건너뛰기라고 말씀해 주세요.');

    for (final field in _Field.values) {
      profile = await _askField(profile, field);
    }
    profile = await _confirm(profile);
    await _say('말씀해주신 정보를 바탕으로 도와드릴게요.');

    profile = await _connectAccount(profile);
    await profiles.save(profile);

    await _say('$featureIntro $askFeature');
    return profile;
  }

  Future<UserProfile?> _restoreFromOtherPhone() async {
    final usedBefore =
        await _ask('혹시 다른 폰에서 저를 쓰신 적이 있나요? 네 또는 아니요로 말씀해 주세요.', parseYesNo);
    if (usedBefore != true) return null;

    await _say('쓰시던 계정으로 로그인할게요.');
    final id = await account.signIn();
    final saved = id == null ? null : await account.restore(id);
    if (saved == null || !saved.isOnboarded) {
      await _say('이전 정보를 찾지 못했어요. 처음부터 함께 정해 볼게요.');
      return null;
    }
    final profile = saved.copyWith(accountId: id);
    await profiles.save(profile);
    await _say(
        '다시 만나서 반가워요. 저는 ${agentNameWithIda(profile.agentName!)}. $askFeature');
    return profile;
  }

  Future<String> _askAgentName() async {
    for (var i = 0; i <= retries; i++) {
      final name = await _ask(askAgentName, parseName);
      if (name == null) break;
      final ok = await _ask('제 이름을 $name, 이렇게 부르시면 될까요?', parseYesNo);
      if (ok == true) return name;
    }
    const fallback = '패션 에이전트';
    await _say('이름은 나중에 바꿀 수 있어요. 우선 $fallback라고 불러 주세요.');
    return fallback;
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
    await _say('폰을 바꿔도 이어서 쓸 수 있게 계정에 연결할게요.');
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
      final heard = await listen.listen();
      if (heard != null) {
        if (skippable && isSkip(heard)) {
          await _say('네, 건너뛸게요.');
          return null;
        }
        final value = parse(heard);
        if (value != null) return value;
      }
      prompt =
          heard == null ? '잘 듣지 못했어요. $question' : '잘 이해하지 못했어요. $question';
    }
    if (skippable) await _say('우선 넘어갈게요.');
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

enum _Field {
  name,
  birthDate,
  gender,
  job,
  height,
  weight;

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
      accountId: p.accountId,
    );
