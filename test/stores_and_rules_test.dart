import 'package:fashion_agent/models/garment.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/services/schedule_store.dart';
import 'package:fashion_agent/services/voices.dart';
import 'package:fashion_agent/services/wardrobe_store.dart';
import 'package:fashion_agent/styling/schedule_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Garment _g(
  String name, {
  GarmentCategory category = GarmentCategory.top,
  ColorFamily family = ColorFamily.navy,
  String colorName = '남색',
  Tone tone = Tone.dark,
  Formality formality = Formality.smart,
}) =>
    Garment(
      id: name,
      category: category,
      name: name,
      colorName: colorName,
      colorFamily: family,
      tone: tone,
      formality: formality,
    );

ScheduleEvent _event(String title) =>
    ScheduleEvent(title: title, start: DateTime(2026, 11, 24, 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('옷 정보 JSON 주고받기', () {
    test('toJson으로 저장한 옷을 fromJson으로 그대로 되살린다', () {
      const original = Garment(
        id: 'g1',
        category: GarmentCategory.outer,
        name: '코트',
        colorName: '베이지',
        colorFamily: ColorFamily.beige,
        tone: Tone.light,
        pattern: '체크',
        material: '울 같음',
        notes: '약간 구김 있음',
        formality: Formality.formal,
        defects: [
          GarmentDefect(
              kind: DefectKind.stain, where: '왼쪽 소매 끝', confidence: 0.8),
        ],
        box: GarmentBox(0.1, 0.2, 0.4, 0.6),
        confidence: 0.9,
      );

      final back = Garment.fromJson(original.toJson());

      expect(back.id, 'g1');
      expect(back.category, GarmentCategory.outer);
      expect(back.colorFamily, ColorFamily.beige);
      expect(back.tone, Tone.light);
      expect(back.pattern, '체크');
      expect(back.material, '울 같음');
      expect(back.notes, '약간 구김 있음');
      expect(back.formality, Formality.formal);
      expect(back.defects.single.kind, DefectKind.stain);
      expect(back.defects.single.where, '왼쪽 소매 끝');
      expect(back.defects.single.confidence, 0.8);
      expect(back.box!.x, 0.1);
      expect(back.box!.h, 0.6);
      expect(back.confidence, 0.9);
      expect(back.spokenName, '베이지 체크 코트');
    });

    test('옷 상자의 가운데 좌표를 계산한다', () {
      const box = GarmentBox(0.2, 0.1, 0.4, 0.6);
      expect(box.centerX, closeTo(0.4, 1e-9));
      expect(box.centerY, closeTo(0.4, 1e-9));
      expect(box.toJson(), {'x': 0.2, 'y': 0.1, 'w': 0.4, 'h': 0.6});
    });

    test('모르는 값·빈 글자는 기본값으로 바꾼다', () {
      final g = Garment.fromJson({
        'id': 'x',
        'category': 'hat',
        'colorFamily': 'teal',
        'tone': '??',
        'pattern': '  ',
        'formality': null,
        'defects': [
          {'kind': 'burn'}
        ],
      });
      expect(g.category, GarmentCategory.other);
      expect(g.name, '옷');
      expect(g.colorName, '알 수 없는 색');
      expect(g.colorFamily, ColorFamily.unknown);
      expect(g.tone, Tone.mid);
      expect(g.pattern, isNull);
      expect(g.hasPattern, isFalse);
      expect(g.formality, Formality.unknown);
      expect(g.defects.single.kind, DefectKind.other);
      expect(g.defects.single.confidence, 0);
      expect(g.box, isNull);
      expect(g.confidence, 0);
    });
  });

  group('일정에 맞는 옷차림(scheduleFit)', () {
    test('결혼식: 흰 원피스와 청바지는 고칠 점으로 알려 준다', () {
      final fit = scheduleFit(_event('친구 결혼식'), [
        _g('원피스',
            category: GarmentCategory.dress,
            family: ColorFamily.white,
            colorName: '흰색',
            tone: Tone.light),
        _g('청바지', category: GarmentCategory.bottom),
      ]);
      expect(fit.ok, isFalse);
      expect(fit.notes, hasLength(2));
      expect(fit.notes[0], contains('신부 옷과 겹쳐'));
      expect(fit.notes[1], contains('너무 편해 보여요'));
    });

    test('결혼식: 단정한 옷이면 괜찮다고 한다', () {
      final fit = scheduleFit(_event('사촌 결혼식'), [_g('셔츠')]);
      expect(fit.ok, isTrue);
      expect(fit.notes.single, '사촌 결혼식에 어울리는 옷차림이에요.');
    });

    test('장례식: 밝은 색·편한 옷을 둘 다 짚는다', () {
      final fit = scheduleFit(_event('장례식 조문'), [
        _g('티셔츠',
            family: ColorFamily.yellow,
            colorName: '노란색',
            tone: Tone.light,
            formality: Formality.casual),
      ]);
      expect(fit.ok, isFalse);
      expect(fit.notes[0], contains('밝아 보일 수 있어요'));
      expect(fit.notes[1], contains('편한 옷이라'));
    });

    test('장례식: 검은 정장이면 차분하다고 한다', () {
      final fit = scheduleFit(_event('장례식'), [
        _g('정장',
            family: ColorFamily.black,
            colorName: '검은색',
            formality: Formality.formal),
      ]);
      expect(fit.ok, isTrue);
      expect(fit.notes, ['장례식에 맞는 차분한 옷차림이에요.']);
    });

    test('면접: 편한 옷이면 종류에 맞는 대안을 말한다', () {
      final fit = scheduleFit(_event('회사 면접'), [
        _g('맨투맨', formality: Formality.casual),
        _g('조거팬츠',
            category: GarmentCategory.bottom, formality: Formality.sporty),
        _g('운동화', category: GarmentCategory.shoes, formality: Formality.casual),
        _g('패딩', category: GarmentCategory.outer, formality: Formality.casual),
      ]);
      expect(fit.ok, isFalse);
      expect(fit.notes[0], contains('셔츠나 블라우스가'));
      expect(fit.notes[1], contains('슬랙스나 정장 바지'));
      expect(fit.notes[2], contains('구두가'));
      expect(fit.notes[3], contains('단정한 옷이'));
    });

    test('면접: 단정하면 통과', () {
      expect(scheduleFit(_event('면접'), [_g('셔츠')]).ok, isTrue);
    });

    test('회의: 운동복만 짚고 나머지는 무난하다', () {
      final bad = scheduleFit(
          _event('거래처 미팅'), [_g('트레이닝복', formality: Formality.sporty)]);
      expect(bad.ok, isFalse);
      expect(bad.notes.single, contains('운동복이라'));

      final good =
          scheduleFit(_event('팀 회의'), [_g('니트', formality: Formality.casual)]);
      expect(good.ok, isTrue);
      expect(good.notes, ['팀 회의에 무난한 옷차림이에요.']);
    });

    test('운동: 격식 있는 옷은 불편할 수 있다고 한다', () {
      final bad =
          scheduleFit(_event('등산'), [_g('정장 재킷', formality: Formality.formal)]);
      expect(bad.ok, isFalse);
      expect(bad.notes.single, contains('불편할 수 있어요'));

      final good =
          scheduleFit(_event('요가'), [_g('레깅스', formality: Formality.sporty)]);
      expect(good.ok, isTrue);
      expect(good.notes, ['요가 하기 편한 옷차림이에요.']);
    });

    test('그 밖의 일정은 지금 옷차림도 괜찮다', () {
      final fit = scheduleFit(_event('친구랑 영화'), [_g('후드티')]);
      expect(fit.ok, isTrue);
      expect(fit.notes, ['친구랑 영화에는 지금 옷차림도 괜찮아요.']);
    });

    test('일정이 여러 개면 가장 격식 있는 자리, 지난 일정은 뺀다', () {
      final now = DateTime(2026, 11, 24, 12);
      final events = [
        ScheduleEvent(title: '점심 약속', start: DateTime(2026, 11, 24, 13)),
        ScheduleEvent(title: '오전 장례식', start: DateTime(2026, 11, 24, 8)),
        ScheduleEvent(title: '오후 면접', start: DateTime(2026, 11, 24, 15)),
      ];
      expect(eventToDressFor(events, now)!.title, '오후 면접');
      expect(eventToDressFor([events[1]], now), isNull);
    });
  });

  group('폰에 저장하는 옷장·일정·목소리', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('옷장: 본 옷을 쌓아 두고 다시 읽는다(빈 목록은 저장 안 함)', () async {
      final store = LocalWardrobeStore();
      await store.addAll([]);
      expect(await store.all(), isEmpty);

      await store.addAll([_g('셔츠')]);
      await store.addAll([_g('바지', category: GarmentCategory.bottom)]);

      final all = await store.all();
      expect(all.map((g) => g.name), ['셔츠', '바지']);
      expect(all.last.category, GarmentCategory.bottom);
    });

    test('메모리 옷장은 복사본을 돌려준다', () async {
      final store = InMemoryWardrobeStore();
      await store.addAll([_g('셔츠')]);
      final list = await store.all();
      list.clear();
      expect(await store.all(), hasLength(1));
    });

    test('일정: 저장한 일정을 날짜별로 시간순으로 꺼낸다', () async {
      final store = LocalScheduleStore();
      expect(await store.all(), isEmpty);

      await store.add(ScheduleEvent(
          title: '저녁 약속', start: DateTime(2026, 11, 24, 19), place: '강남'));
      await store
          .add(ScheduleEvent(title: '면접', start: DateTime(2026, 11, 24, 10)));
      await store.add(
          ScheduleEvent(title: '다음날 회의', start: DateTime(2026, 11, 25, 9)));

      final day = await store.on(DateTime(2026, 11, 24));
      expect(day.map((e) => e.title), ['면접', '저녁 약속']);
      expect(day.last.place, '강남');

      final again = await LocalScheduleStore().all();
      expect(again, hasLength(3));
    });

    test('메모리 일정 저장소도 같은 규칙으로 꺼낸다', () async {
      final store = InMemoryScheduleStore();
      await store
          .add(ScheduleEvent(title: '운동', start: DateTime(2026, 11, 24, 7)));
      expect((await store.on(DateTime(2026, 11, 24))).single.title, '운동');
      expect(await store.on(DateTime(2026, 11, 23)), isEmpty);
    });

    test('목소리: 고른 목소리를 폰과 메모리에 기억한다', () async {
      final local = LocalVoiceStore();
      expect(await local.load(), isNull);
      await local.save('JiMin');
      expect(await LocalVoiceStore().load(), 'JiMin');

      final memory = MemoryVoiceStore('YuJin');
      expect(await memory.load(), 'YuJin');
      await memory.save('InJoon');
      expect(await memory.load(), 'InJoon');
    });
  });

  group('폰 목소리 설명(Voice.fromDevice)', () {
    test('프리미엄 여성 목소리는 아주 자연스럽다고 소개한다', () {
      final v = Voice.fromDevice({
        'name': 'Yuna',
        'identifier': 'com.apple.voice.premium.ko-KR.Yuna',
        'quality': 'Premium',
        'gender': 'female',
      });
      expect(v.id, 'device:com.apple.voice.premium.ko-KR.Yuna');
      expect(v.description, '폰에 들어 있는, 아주 자연스러운 여성 목소리 Yuna');
      expect(v.device, isTrue);
      expect(v.rank, 3);
    });

    test('향상됨 남성 목소리, 보통 목소리를 구분한다', () {
      final enhanced = Voice.fromDevice(
          {'name': 'Minsu', 'quality': 'enhanced', 'gender': 'male'});
      expect(enhanced.rank, 2);
      expect(enhanced.id, 'device:Minsu');
      expect(enhanced.description, '폰에 들어 있는, 자연스러운 남성 목소리 Minsu');

      final plain = Voice.fromDevice({'name': 'ko-kr-x-ism-local'});
      expect(plain.rank, 0);
      expect(plain.description, '폰에 들어 있는 목소리 ko-kr-x-ism-local');

      final korean = Voice.fromDevice({'name': '유나', 'quality': 'high'});
      expect(korean.description, '폰에 들어 있는, 자연스러운 목소리');
    });

    test('같은 id면 같은 목소리로 본다', () {
      const a = Voice('YuJin', '설명 1');
      const b = Voice('YuJin', '설명 2');
      expect(a, b);
      expect({a, b}, hasLength(1));
      expect(a == deviceVoice, isFalse);
    });
  });
}
