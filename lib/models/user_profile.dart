/// 처음 켤 때 받는 동의 내용의 판. 내용(agent_speech.dart consentIntro)을 바꾸면 올린다.
/// 2026-11-10부터 허용 창을 허용하면 동의로 본다. GPT 확인·학습 저장은 따로 묻는다(GptConsentStore).
const consentVersion = '2026-11-09';

/// 첫 실행 때 음성으로 받은 사용자 정보와 에이전트 이름.
///
/// 키·몸무게 같은 민감한 항목은 건너뛸 수 있으므로 모두 null을 허용한다.
class UserProfile {
  const UserProfile({
    this.name,
    this.birthDate,
    this.gender,
    this.job,
    this.heightCm,
    this.weightKg,
    this.agentName,
    this.callName,
    this.accountId,
    this.consent,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] as String?,
        birthDate: json['birthDate'] == null
            ? null
            : DateTime.parse(json['birthDate'] as String),
        gender: json['gender'] as String?,
        job: json['job'] as String?,
        heightCm: (json['heightCm'] as num?)?.toDouble(),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        agentName: json['agentName'] as String?,
        callName: json['callName'] as String?,
        accountId: json['accountId'] as String?,
        consent: json['consent'] as String?,
      );

  final String? name;
  final DateTime? birthDate;

  /// "남성" 또는 "여성".
  final String? gender;
  final String? job;
  final double? heightCm;
  final double? weightKg;

  /// 사용자가 지어 준 에이전트 이름.
  final String? agentName;

  /// 에이전트가 사용자를 부르는 말(호칭). 예: "진행 님". null이면 따로 부르지 않는다.
  final String? callName;

  /// 로그인한 계정 id. null이면 이 폰에만 저장된 상태다.
  final String? accountId;

  /// 처음 켤 때 받은 동의(권한, 서버에서 말·사진 살펴보기)의 판([consentVersion]). null이면 아직.
  final String? consent;

  /// 지금 동의 내용에 동의했는지. 동의 내용을 바꾸면 [consentVersion]을 올려 다시 묻는다.
  bool get consented => consent == consentVersion;

  /// 온보딩을 마쳤는지. 에이전트 이름까지 정해야 끝난 것으로 본다.
  bool get isOnboarded => agentName != null;

  UserProfile copyWith({
    String? name,
    DateTime? birthDate,
    String? gender,
    String? job,
    double? heightCm,
    double? weightKg,
    String? agentName,
    String? callName,
    String? accountId,
    String? consent,
  }) =>
      UserProfile(
        name: name ?? this.name,
        birthDate: birthDate ?? this.birthDate,
        gender: gender ?? this.gender,
        job: job ?? this.job,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        agentName: agentName ?? this.agentName,
        callName: callName ?? this.callName,
        accountId: accountId ?? this.accountId,
        consent: consent ?? this.consent,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'birthDate': birthDate?.toIso8601String(),
        'gender': gender,
        'job': job,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'agentName': agentName,
        'callName': callName,
        'accountId': accountId,
        'consent': consent,
      };
}
