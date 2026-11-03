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

  /// "약간 구김 있음", "소매에 얼룩" 같은 상태.
  final String? notes;
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
