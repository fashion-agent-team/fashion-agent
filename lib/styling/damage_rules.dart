import '../models/garment.dart';
import 'korean.dart';

/// 이 값보다 확신이 낮은 손상은 단정하지 않고 손으로 확인해 보라고 한다.
const sureDefect = 0.7;

/// 얼룩·찢어짐 안내. 손상이 없으면 그렇다고 한 문장으로 말한다.
List<String> damageNotes(List<Garment> garments) {
  final notes = <String>[];
  for (final g in garments) {
    for (final d in g.defects) {
      final what = switch (d.kind) {
        DefectKind.stain => '얼룩',
        DefectKind.tear => '찢어진 곳',
        DefectKind.lint => '보풀이나 먼지',
        DefectKind.other => '눈에 띄는 자국',
      };
      final where = d.where == null ? '' : '${d.where}에 ';
      notes.add(d.confidence >= sureDefect
          ? '${g.spokenName} $where${iGa(what)} 있어요.'
          : '${g.spokenName} $where$what 같은 게 보여요. 손으로 한번 확인해 보세요.');
    }
  }
  if (notes.isEmpty) return const ['얼룩이나 찢어진 곳은 보이지 않아요.'];
  return notes;
}

bool hasDamage(List<Garment> garments) =>
    garments.any((g) => g.defects.any((d) => d.confidence >= sureDefect));
