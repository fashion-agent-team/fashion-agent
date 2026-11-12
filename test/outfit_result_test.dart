import 'package:fashion_agent/models/garment.dart';
import 'package:fashion_agent/screens/camera_turn_screen.dart' show splitGuide;
import 'package:fashion_agent/screens/palette.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter/material.dart' show HSLColor;
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _g(String id, String category, String name,
        String colorName, String family, String tone) =>
    {
      'id': id,
      'category': category,
      'name': name,
      'colorName': colorName,
      'colorFamily': family,
      'tone': tone,
    };

Garment _garment(String id, GarmentCategory c, String colorName) => Garment(
    id: id,
    category: c,
    name: '옷',
    colorName: colorName,
    colorFamily: ColorFamily.gray,
    tone: Tone.mid);

void main() {
  test('옷 검사 답에서 garments를 읽는다', () {
    final reply = TurnReply.fromJson({
      'sessionId': 's1',
      'speech': '아이보리 니트네요.',
      'next': 'camera_worn',
      'result': {
        'type': 'outfit_check',
        'outfitCheck': {
          'garments': [
            _g('g1', 'top', '니트', '아이보리', 'white', 'light'),
            _g('g2', 'bottom', '슬랙스', '남색', 'navy', 'dark'),
            {'category': 'shoes'}, // id 없음 → 건너뜀
          ],
        },
      },
    });
    expect(reply.garments.map((g) => g.colorName), ['아이보리', '남색']);
  });

  test('garments가 없거나 모양이 달라도 대화는 그대로', () {
    expect(
        TurnReply.fromJson({'sessionId': 's', 'speech': '', 'next': 'listen'})
            .garments,
        isEmpty);
    expect(
        TurnReply.fromJson({
          'sessionId': 's',
          'speech': '',
          'next': 'listen',
          'result': {'type': 'weather', 'outfitCheck': 'x'},
        }).garments,
        isEmpty);
  });

  test('종류마다 한 벌, 새로 본 것이 이기고 상의·하의·신발 순서', () {
    var outfit = mergeOutfit(const [], [
      _garment('s', GarmentCategory.shoes, '갈색'),
      _garment('t1', GarmentCategory.top, '흰색'),
      _garment('t2', GarmentCategory.top, '검정'),
    ]);
    expect(outfit.map((g) => g.colorName), ['흰색', '갈색']);
    outfit = mergeOutfit(outfit, [
      _garment('b', GarmentCategory.bottom, '남색'),
      _garment('t3', GarmentCategory.top, '아이보리'),
    ]);
    expect(outfit.map((g) => g.colorName), ['아이보리', '남색', '갈색']);
  });

  test('안내는 첫 문장(마침표 뺌)과 나머지로 나눈다', () {
    expect(splitGuide('한 걸음 뒤로 가 주세요. 몸이 다 보이면 멈췄을 때 알아서 찍어요.'),
        ('한 걸음 뒤로 가 주세요', '몸이 다 보이면 멈췄을 때 알아서 찍어요.'));
    expect(splitGuide('잠깐 멈춰 주세요.'), ('잠깐 멈춰 주세요', ''));
    expect(splitGuide('오늘은 14.5도예요'), ('오늘은 14.5도예요', ''));
    expect(splitGuide('어디야? 왼쪽이에요.'), ('어디야?', '왼쪽이에요.'));
  });

  test('색 띠가 쪽빛 바탕에 묻히지 않는다', () {
    final navy = swatchFor(ColorFamily.navy, Tone.dark);
    expect(HSLColor.fromColor(navy).lightness, greaterThanOrEqualTo(0.219));
    expect(swatchFor(ColorFamily.white, Tone.dark),
        swatchFor(ColorFamily.white, Tone.light));
  });
}
