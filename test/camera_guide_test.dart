import 'package:fashion_agent/screens/camera_turn_screen.dart' show splitGuide;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('안내는 첫 문장(마침표 뺌)과 나머지로 나눈다', () {
    const guide = '한 걸음 뒤로 가 주세요. 몸이 다 보이면 멈췄을 때 알아서 찍어요.';
    const rest = '몸이 다 보이면 멈췄을 때 알아서 찍어요.';
    expect(splitGuide(guide), ('한 걸음 뒤로 가 주세요', rest));
    expect(splitGuide('잠깐 멈춰 주세요.'), ('잠깐 멈춰 주세요', ''));
    expect(splitGuide('오늘은 14.5도예요'), ('오늘은 14.5도예요', ''));
    expect(splitGuide('어디야? 왼쪽이에요.'), ('어디야?', '왼쪽이에요.'));
  });
}
