import 'garment.dart';

enum Verdict {
  /// 잘 어울린다.
  good,

  /// 무난하다.
  okay,

  /// 색이 부딪히는 등 다시 생각해 볼 만하다.
  clash,

  /// 상의·하의를 다 찾지 못했거나 확신이 낮아 판단하지 않는다.
  unsure,
}

/// 고른 옷에 대한 피드백. 판정과 함께 그 이유를 꼭 담는다.
class OutfitFeedback {
  const OutfitFeedback({
    required this.verdict,
    required this.garments,
    this.reasons = const [],
    this.warnings = const [],
  });

  final Verdict verdict;

  /// 피드백 대상이 된 옷 (보통 상의와 하의).
  final List<Garment> garments;

  /// "남색과 베이지라서 잘 어울려요" 같은 근거.
  final List<String> reasons;

  /// "무늬가 둘 다 있어서 복잡해 보일 수 있어요" 같은 주의.
  final List<String> warnings;

  Garment? get top =>
      _first(GarmentCategory.top) ?? _first(GarmentCategory.dress);
  Garment? get bottom => _first(GarmentCategory.bottom);

  Garment? _first(GarmentCategory category) {
    for (final g in garments) {
      if (g.category == category) return g;
    }
    return null;
  }

  String toSpeech() {
    final buffer = StringBuffer();
    switch (verdict) {
      case Verdict.good:
        buffer.write('잘 어울리는 조합이에요. ');
      case Verdict.okay:
        buffer.write('무난한 조합이에요. ');
      case Verdict.clash:
        buffer.write('조금 다시 생각해 볼 만한 조합이에요. ');
      case Verdict.unsure:
        break;
    }
    for (final reason in reasons) {
      buffer.write('$reason ');
    }
    for (final warning in warnings) {
      buffer.write('$warning ');
    }
    return buffer.toString().trim();
  }
}
