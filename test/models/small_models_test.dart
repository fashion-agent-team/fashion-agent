import 'package:fashion_agent/models/outfit_check.dart';
import 'package:fashion_agent/services/shortcut_ask.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 작은 모델·서비스: 옷 검사 결과(OutfitCheck)와 시리 단축어가 남긴 말 꺼내기.
void main() {
  group('OutfitCheck.allGood', () {
    test('일정·날씨 맞고 손상 없고 판단했으면 true', () {
      expect(const OutfitCheck(garments: []).allGood, isTrue);
    });

    test('하나라도 걸리면 false', () {
      expect(
          const OutfitCheck(garments: [], scheduleOk: false).allGood, isFalse);
      expect(
          const OutfitCheck(garments: [], weatherOk: false).allGood, isFalse);
      expect(const OutfitCheck(garments: [], damaged: true).allGood, isFalse);
    });

    test('판단할 수 없으면(unsure) false이고 옷은 비고 이유를 담는다', () {
      const c = OutfitCheck.unsure('옷이 잘 안 보여요.');
      expect(c.allGood, isFalse);
      expect(c.garments, isEmpty);
      expect(c.unsure, '옷이 잘 안 보여요.');
    });
  });

  group('takeShortcutAsk', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('시리가 남긴 말을 한 번만 꺼내고 지운다', () async {
      SharedPreferences.setMockInitialValues({shortcutAskKey: '오늘 뭐 입지'});

      expect(await takeShortcutAsk(), '오늘 뭐 입지');
      expect(await takeShortcutAsk(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(shortcutAskKey), isFalse);
    });

    test('남긴 말이 없으면 null이고 다른 값은 건드리지 않는다', () async {
      SharedPreferences.setMockInitialValues({'other': 'x'});

      expect(await takeShortcutAsk(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('other'), 'x');
    });

    test('키 이름은 iOS AppDelegate가 쓰는 flutter.siri.ask에서 flutter.를 뺀 것', () {
      expect(shortcutAskKey, 'siri.ask');
    });
  });
}
