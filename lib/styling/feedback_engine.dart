import '../models/garment.dart';
import '../models/outfit_feedback.dart';
import '../models/weather.dart';
import 'color_rules.dart';
import 'weather_rules.dart';

/// 이 값보다 확신이 낮은 옷은 판단에 쓰지 않고 다시 비춰 달라고 한다.
const minConfidence = 0.6;

/// 고른 옷(상의·하의)의 어울림과 날씨 적합성을 판단한다.
///
/// AI가 준 사실([Garment])만 받아서 규칙으로 판단하므로, 같은 입력이면 늘 같은 결과가 나온다.
OutfitFeedback evaluateOutfit(List<Garment> garments, {Weather? weather}) {
  final unsure = garments.where((g) => g.confidence < minConfidence).toList();
  if (unsure.isNotEmpty) {
    return OutfitFeedback(
      verdict: Verdict.unsure,
      garments: garments,
      reasons: ['${unsure.first.name}의 색이 확실하지 않아요. 불을 켜고 다시 비춰 주세요.'],
    );
  }

  final top = _first(garments, GarmentCategory.top);
  final bottom = _first(garments, GarmentCategory.bottom);
  final dress = _first(garments, GarmentCategory.dress);

  final warnings = <String>[
    if (weather != null) ...weatherWarnings(weather, garments),
  ];

  if (dress != null && top == null && bottom == null) {
    return OutfitFeedback(
      verdict: Verdict.good,
      garments: [dress],
      reasons: const ['원피스 한 벌이라 색 조합 걱정은 없어요.'],
      warnings: warnings,
    );
  }
  if (top == null || bottom == null) {
    return OutfitFeedback(
      verdict: Verdict.unsure,
      garments: garments,
      reasons: [
        top == null ? '상의를 찾지 못했어요.' : '하의를 찾지 못했어요.',
        '상의와 하의를 함께 펼쳐 놓고 다시 비춰 주세요.',
      ],
    );
  }

  final match = matchColors(top, bottom);
  return OutfitFeedback(
    verdict: match.verdict,
    garments: [top, bottom],
    reasons: [match.reason],
    warnings: [...overlapWarnings(top, bottom), ...warnings],
  );
}

/// 옷장 사진에서 [keep]과 어울리는 대안을 어울리는 순서로 찾는다.
///
/// [replace]는 바꾸려는 옷이다. 같은 종류의 옷만 후보로 본다.
List<Garment> findAlternatives({
  required Garment keep,
  required Garment replace,
  required List<Garment> closet,
}) {
  final candidates = closet
      .where((g) =>
          g.category == replace.category &&
          g.confidence >= minConfidence &&
          g.colorFamily != replace.colorFamily)
      .map((g) => (garment: g, match: matchColors(keep, g)))
      .where((c) =>
          c.match.verdict == Verdict.good || c.match.verdict == Verdict.okay)
      .toList()
    ..sort((a, b) => _rank(a.match.verdict).compareTo(_rank(b.match.verdict)));
  return [for (final c in candidates) c.garment];
}

/// 꺼낸 옷이 안내한 옷과 같아 보이는지. 확신이 낮으면 null.
bool? isSameGarment(Garment expected, Garment seen) {
  if (seen.confidence < minConfidence) return null;
  return seen.category == expected.category &&
      seen.colorFamily == expected.colorFamily;
}

int _rank(Verdict v) => v == Verdict.good ? 0 : 1;

Garment? _first(List<Garment> garments, GarmentCategory category) {
  for (final g in garments) {
    if (g.category == category) return g;
  }
  return null;
}
