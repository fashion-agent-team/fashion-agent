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
    this.accountId,
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
        accountId: json['accountId'] as String?,
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

  /// 로그인한 계정 id. null이면 이 폰에만 저장된 상태다.
  final String? accountId;

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
    String? accountId,
  }) =>
      UserProfile(
        name: name ?? this.name,
        birthDate: birthDate ?? this.birthDate,
        gender: gender ?? this.gender,
        job: job ?? this.job,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        agentName: agentName ?? this.agentName,
        accountId: accountId ?? this.accountId,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'birthDate': birthDate?.toIso8601String(),
        'gender': gender,
        'job': job,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'agentName': agentName,
        'accountId': accountId,
      };
}
