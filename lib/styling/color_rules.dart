import '../models/garment.dart';
import '../models/outfit_feedback.dart';
import 'korean.dart';

/// 두 옷의 색이 어울리는지와 그 이유.
class ColorMatch {
  const ColorMatch(this.verdict, this.reason);

  final Verdict verdict;
  final String reason;
}

/// 다른 색과 대부분 잘 어울리는 무채색·기본색.
const neutralFamilies = {
  ColorFamily.black,
  ColorFamily.white,
  ColorFamily.gray,
  ColorFamily.navy,
  ColorFamily.beige,
};

/// 함께 입으면 부딪히기 쉬운 색 쌍.
const _clashingPairs = [
  {ColorFamily.red, ColorFamily.green},
  {ColorFamily.red, ColorFamily.pink},
  {ColorFamily.red, ColorFamily.orange},
  {ColorFamily.orange, ColorFamily.pink},
  {ColorFamily.orange, ColorFamily.purple},
  {ColorFamily.green, ColorFamily.purple},
  {ColorFamily.yellow, ColorFamily.purple},
];

/// 두 옷의 색 조합을 판단한다. 이유 문장은 사용자에게 그대로 읽어 준다.
ColorMatch matchColors(Garment a, Garment b) {
  final fa = a.colorFamily, fb = b.colorFamily;
  final names = '${gwaWa(a.colorName)} ${b.colorName}';

  if (fa == ColorFamily.unknown || fb == ColorFamily.unknown) {
    return const ColorMatch(Verdict.unsure, '색을 확실히 알아보지 못했어요.');
  }
  if (_clashingPairs.any((pair) => pair.containsAll({fa, fb}) && fa != fb)) {
    return ColorMatch(Verdict.clash, '${eunNeun(names)} 서로 부딪혀 보일 수 있어요.');
  }
  if (fa == fb) {
    if (a.tone != b.tone) {
      return const ColorMatch(Verdict.good, '같은 계열에 밝기가 달라서 차분하게 어울려요.');
    }
    return ColorMatch(
        Verdict.okay, '둘 다 ${ira(a.colorName)} 한 덩어리처럼 보일 수 있어요.');
  }
  final aNeutral = neutralFamilies.contains(fa);
  final bNeutral = neutralFamilies.contains(fb);
  if (aNeutral && bNeutral) {
    return ColorMatch(Verdict.good, '${eunNeun(names)} 기본색끼리라 무난하게 잘 어울려요.');
  }
  if (aNeutral || bNeutral) {
    final neutral = aNeutral ? a : b;
    return ColorMatch(
        Verdict.good, '${eunNeun(neutral.colorName)} 대부분의 색과 잘 어울려요.');
  }
  return ColorMatch(
      Verdict.okay, '${eunNeun(names)} 둘 다 눈에 띄는 색이라 조금 튈 수 있어요.');
}

/// 색 외의 겹침 주의. 무늬, 같은 소재 등.
List<String> overlapWarnings(Garment a, Garment b) {
  final warnings = <String>[];
  if (a.hasPattern && b.hasPattern) {
    warnings.add(
        '${gwaWa(a.pattern!)} ${euro(b.pattern!)} 무늬가 둘 다 있어서 복잡해 보일 수 있어요.');
  }
  if (_isDenim(a) && _isDenim(b)) {
    warnings.add('청 소재가 위아래로 겹쳐요.');
  }
  return warnings;
}

bool _isDenim(Garment g) =>
    (g.material ?? '').contains('데님') || g.name.contains('청');
