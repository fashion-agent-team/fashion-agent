import 'garment.dart';

/// 사진 한 장을 비전 AI로 분석한 결과. 프록시 `/describe-clothes` 응답과 같은 모양이다.
class ClothesScan {
  const ClothesScan({
    required this.garments,
    this.framing,
    this.isDark = false,
  });

  factory ClothesScan.fromJson(Map<String, dynamic> json) => ClothesScan(
        garments: (json['garments'] as List? ?? const [])
            .map((g) => Garment.fromJson(g as Map<String, dynamic>))
            .toList(),
        framing: json['framing'] as String?,
        isDark: json['lighting'] == 'dark',
      );

  final List<Garment> garments;

  /// 구도가 맞지 않을 때 AI가 주는 교정 안내. 예: "폰을 오른쪽으로 조금 옮겨 주세요."
  final String? framing;

  /// 너무 어두워서 색을 믿기 어려운지.
  final bool isDark;

  /// 다시 찍어야 하는지.
  bool get needsRetake => isDark || framing != null || garments.isEmpty;
}
