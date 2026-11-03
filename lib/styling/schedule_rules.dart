import '../models/garment.dart';
import '../models/schedule_event.dart';
import 'korean.dart';

/// 일정의 성격. 일정 이름의 낱말로 고른다.
enum Occasion {
  /// 장례식, 조문
  mourning,

  /// 결혼식 하객
  wedding,

  /// 면접, 발표, 상견례처럼 격식 있는 자리
  formal,

  /// 회의, 출근, 미팅
  business,

  /// 운동, 등산
  active,

  /// 그 밖의 일정
  casual,
}

const _keywords = <Occasion, List<String>>{
  Occasion.mourning: ['장례', '조문', '빈소', '추도'],
  Occasion.wedding: ['결혼식', '웨딩', '예식'],
  Occasion.formal: ['면접', '발표', '상견례', '시상', '졸업식', '입학식', '세미나'],
  Occasion.business: ['회의', '미팅', '출근', '회사', '거래처', '수업', '강의'],
  Occasion.active: [
    '운동',
    '헬스',
    '등산',
    '산책',
    '러닝',
    '조깅',
    '요가',
    '필라테스',
    '축구',
    '농구'
  ],
};

Occasion occasionOf(ScheduleEvent event) {
  for (final MapEntry(key: occasion, value: words) in _keywords.entries) {
    if (words.any(event.title.contains)) return occasion;
  }
  return Occasion.casual;
}

/// 오늘 일정 중 옷차림을 맞춰야 할 일정. 이미 끝났을 법한(시작 2시간 지난) 일정은 뺀다.
/// 여러 개면 가장 격식 있는 자리에 맞춘다.
ScheduleEvent? eventToDressFor(List<ScheduleEvent> today, DateTime now) {
  final upcoming = today
      .where((e) => e.start.isAfter(now.subtract(const Duration(hours: 2))))
      .toList();
  if (upcoming.isEmpty) return null;
  upcoming.sort((a, b) {
    final byStrictness = occasionOf(a).index.compareTo(occasionOf(b).index);
    return byStrictness != 0 ? byStrictness : a.start.compareTo(b.start);
  });
  return upcoming.first;
}

/// 일정에 맞는 옷차림인지. 맞으면 이유 한 문장, 아니면 고칠 점들을 돌려준다.
({bool ok, List<String> notes}) scheduleFit(
    ScheduleEvent event, List<Garment> garments) {
  final occasion = occasionOf(event);
  final title = event.title;
  final notes = <String>[];

  bool isOneOf(Garment g, Set<Formality> f) => f.contains(g.formality);
  const bright = {
    ColorFamily.red,
    ColorFamily.pink,
    ColorFamily.orange,
    ColorFamily.yellow,
    ColorFamily.green,
    ColorFamily.purple,
  };

  switch (occasion) {
    case Occasion.mourning:
      for (final g in garments) {
        if (bright.contains(g.colorFamily) || g.tone == Tone.light) {
          notes.add('${eunNeun(g.spokenName)} $title에 밝아 보일 수 있어요. '
              '검은색이나 남색, 짙은 회색이 좋아요.');
        }
        if (isOneOf(g, {Formality.casual, Formality.sporty})) {
          notes.add('${eunNeun(g.name)} 편한 옷이라 $title에는 정장이나 단정한 옷이 좋아요.');
        }
      }
      if (notes.isEmpty) return (ok: true, notes: ['$title에 맞는 차분한 옷차림이에요.']);
    case Occasion.wedding:
      for (final g in garments) {
        if (g.colorFamily == ColorFamily.white &&
            (g.category == GarmentCategory.dress ||
                g.category == GarmentCategory.outer)) {
          notes.add('${eunNeun('흰색 ${g.name}')} 신부 옷과 겹쳐 보일 수 있어서 피하는 게 좋아요.');
        }
        if (isOneOf(g, {Formality.sporty}) || g.name.contains('청바지')) {
          notes.add('${eunNeun(g.name)} $title에는 너무 편해 보여요.');
        }
      }
      if (notes.isEmpty) return (ok: true, notes: ['$title에 어울리는 옷차림이에요.']);
    case Occasion.formal:
      for (final g in garments) {
        if (isOneOf(g, {Formality.casual, Formality.sporty})) {
          notes.add('${eunNeun(g.spokenName)} 편한 옷이라 $title에는 '
              '${_formalAlternative(g.category)} 좋아요.');
        }
      }
      if (notes.isEmpty) return (ok: true, notes: ['$title에 맞게 단정한 옷차림이에요.']);
    case Occasion.business:
      for (final g in garments) {
        if (isOneOf(g, {Formality.sporty})) {
          notes.add('${eunNeun(g.spokenName)} 운동복이라 $title에는 맞지 않아 보여요.');
        }
      }
      if (notes.isEmpty) return (ok: true, notes: ['$title에 무난한 옷차림이에요.']);
    case Occasion.active:
      for (final g in garments) {
        if (isOneOf(g, {Formality.formal})) {
          notes.add('${eunNeun(g.spokenName)} 격식 있는 옷이라 $title 하기엔 불편할 수 있어요.');
        }
      }
      if (notes.isEmpty) return (ok: true, notes: ['$title 하기 편한 옷차림이에요.']);
    case Occasion.casual:
      return (ok: true, notes: ['$title에는 지금 옷차림도 괜찮아요.']);
  }
  return (ok: false, notes: notes);
}

String _formalAlternative(GarmentCategory c) => switch (c) {
      GarmentCategory.top => '셔츠나 블라우스가',
      GarmentCategory.bottom => '슬랙스나 정장 바지, 단정한 치마가',
      GarmentCategory.shoes => '구두가',
      _ => '단정한 옷이',
    };
