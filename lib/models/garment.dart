/// 옷 종류. 비전 AI 응답의 `category` 값과 이름이 같다.
enum GarmentCategory { top, bottom, outer, dress, shoes, other }

/// 색 조합 규칙에 쓰는 색 계열. 비전 AI 응답의 `colorFamily` 값과 이름이 같다.
enum ColorFamily {
  black,
  white,
  gray,
  navy,
  beige,
  brown,
  khaki,
  blue,
  red,
  pink,
  orange,
  yellow,
  green,
  purple,
  unknown,
}

/// 밝기 톤.
enum Tone { light, mid, dark }

/// 옷의 격식. 비전 AI 응답의 `formality` 값과 이름이 같다. 일정에 맞는지 판단하는 데 쓴다.
enum Formality {
  /// 정장, 블라우스, 구두처럼 격식 있는 옷.
  formal,

  /// 셔츠, 니트, 슬랙스처럼 단정한 옷.
  smart,

  /// 티셔츠, 청바지, 맨투맨처럼 편한 옷.
  casual,

  /// 트레이닝복, 운동복.
  sporty,
  unknown,
}

/// 얼룩·찢어짐 같은 옷의 손상. 비전 AI 응답의 `defects` 항목이다.
class GarmentDefect {
  const GarmentDefect({required this.kind, this.where, this.confidence = 1});

  factory GarmentDefect.fromJson(Map<String, dynamic> json) => GarmentDefect(
        kind: _byName(DefectKind.values, json['kind'], DefectKind.other),
        where: _blankToNull(json['where']),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );

  final DefectKind kind;

  /// "오른쪽 소매 끝"처럼 손으로 찾아갈 수 있는 위치.
  final String? where;

  /// 0~1. 낮으면 단정하지 않고 손으로 확인해 보라고 한다.
  final double confidence;

  Map<String, dynamic> toJson() =>
      {'kind': kind.name, 'where': where, 'confidence': confidence};
}

enum DefectKind {
  /// 얼룩
  stain,

  /// 찢어짐·구멍
  tear,

  /// 보풀·먼지
  lint,
  other,
}

/// 사진 속 옷의 위치. 사진 크기를 1로 본 비율 좌표다.
class GarmentBox {
  const GarmentBox(this.x, this.y, this.w, this.h);

  factory GarmentBox.fromJson(Map<String, dynamic> json) => GarmentBox(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['w'] as num).toDouble(),
        (json['h'] as num).toDouble(),
      );

  final double x;
  final double y;
  final double w;
  final double h;

  double get centerX => x + w / 2;
  double get centerY => y + h / 2;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

/// 사진에서 알아낸 옷 한 벌. AI가 본 사실만 담고, 어울림 판단은 담지 않는다.
class Garment {
  const Garment({
    required this.id,
    required this.category,
    required this.name,
    required this.colorName,
    required this.colorFamily,
    required this.tone,
    this.pattern,
    this.material,
    this.notes,
    this.formality = Formality.unknown,
    this.defects = const [],
    this.box,
    this.confidence = 1,
  });

  factory Garment.fromJson(Map<String, dynamic> json) => Garment(
        id: json['id'] as String,
        category: _byName(
            GarmentCategory.values, json['category'], GarmentCategory.other),
        name: json['name'] as String? ?? '옷',
        colorName: json['colorName'] as String? ?? '알 수 없는 색',
        colorFamily: _byName(
            ColorFamily.values, json['colorFamily'], ColorFamily.unknown),
        tone: _byName(Tone.values, json['tone'], Tone.mid),
        pattern: _blankToNull(json['pattern']),
        material: _blankToNull(json['material']),
        notes: _blankToNull(json['notes']),
        formality:
            _byName(Formality.values, json['formality'], Formality.unknown),
        defects: (json['defects'] as List? ?? const [])
            .map((d) => GarmentDefect.fromJson(d as Map<String, dynamic>))
            .toList(),
        box: json['box'] == null
            ? null
            : GarmentBox.fromJson(json['box'] as Map<String, dynamic>),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final GarmentCategory category;

  /// "셔츠", "면바지"처럼 AI가 부른 옷 이름.
  final String name;

  /// "남색"처럼 사용자에게 읽어 줄 색 이름.
  final String colorName;
  final ColorFamily colorFamily;
  final Tone tone;

  /// "줄무늬", "체크" 등. 무늬가 없으면 null.
  final String? pattern;

  /// "니트 같음"처럼 사진으로 추정한 재질. 확실하지 않으므로 보조로만 쓴다.
  final String? material;

  /// "약간 구김 있음" 같은 그 밖의 상태.
  final String? notes;
  final Formality formality;

  /// 얼룩·찢어짐. 없으면 빈 목록.
  final List<GarmentDefect> defects;
  final GarmentBox? box;

  /// 0~1. 낮으면 추천에서 빼고 다시 비춰 달라고 한다.
  final double confidence;

  bool get hasPattern => pattern != null;

  /// "남색 줄무늬 셔츠"
  String get spokenName =>
      [colorName, if (pattern != null) pattern, name].join(' ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'name': name,
        'colorName': colorName,
        'colorFamily': colorFamily.name,
        'tone': tone.name,
        'pattern': pattern,
        'material': material,
        'notes': notes,
        'formality': formality.name,
        'defects': [for (final d in defects) d.toJson()],
        'box': box?.toJson(),
        'confidence': confidence,
      };
}

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

String? _blankToNull(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

/// 화면 "오늘의 색동"에 쌓는 순서: 겉옷, 상의, 원피스, 하의, 신발, 그 밖.
const outfitOrder = [
  GarmentCategory.outer,
  GarmentCategory.top,
  GarmentCategory.dress,
  GarmentCategory.bottom,
  GarmentCategory.shoes,
  GarmentCategory.other,
];

/// 지금까지 본 옷([before])에 새로 본 옷([seen])을 더한다. 종류마다 한 벌만 남기고 새로 본 것이 이긴다.
/// 한 장에 같은 종류가 여럿이면(왼쪽·오른쪽 비교) 앞의 것을 쓴다.
List<Garment> mergeOutfit(List<Garment> before, List<Garment> seen) {
  if (seen.isEmpty) return before;
  final byCategory = {for (final g in before) g.category: g};
  final fresh = <GarmentCategory>{};
  for (final g in seen) {
    if (fresh.add(g.category)) byCategory[g.category] = g;
  }
  final order = outfitOrder.where(byCategory.containsKey);
  return [for (final c in order) byCategory[c]!];
}

/// "상의", "하의"처럼 화면에 쓰는 종류 이름.
String categoryLabel(GarmentCategory c) => switch (c) {
      GarmentCategory.top => '상의',
      GarmentCategory.bottom => '하의',
      GarmentCategory.outer => '겉옷',
      GarmentCategory.dress => '원피스',
      GarmentCategory.shoes => '신발',
      GarmentCategory.other => '소품',
    };
