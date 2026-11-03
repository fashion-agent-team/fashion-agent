import '../models/garment.dart';

/// 사진 속 위치를 "왼쪽 위, 왼쪽에서 두 번째"처럼 읽기 좋게 바꾼다.
///
/// 폰을 든 사용자를 기준으로 한 방향이다. [all]은 같은 사진에 있는 옷 전부.
String describePosition(Garment garment, List<Garment> all) {
  final box = garment.box;
  if (box == null) return '';

  final horizontal = box.centerX < 1 / 3
      ? '왼쪽'
      : box.centerX < 2 / 3
          ? '가운데'
          : '오른쪽';
  final vertical = box.centerY < 0.5 ? '위' : '아래';

  final placed = all.where((g) => g.box != null).toList()
    ..sort((a, b) => a.box!.centerX.compareTo(b.box!.centerX));
  final order = placed.indexOf(garment) + 1;
  final ordinal = order <= _ordinals.length ? _ordinals[order - 1] : '$order';

  return '$horizontal $vertical, 왼쪽에서 $ordinal 번째';
}

const _ordinals = ['첫', '두', '세', '네', '다섯', '여섯', '일곱', '여덟', '아홉', '열'];
