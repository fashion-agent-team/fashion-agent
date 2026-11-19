import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시리 단축어가 남긴 말을 꺼내고 지운다(2026-11-13 진행 님: "시리야, 심청이한테 오늘 뭐 입지").
///
/// iOS의 AskOutfitIntent(ios/Runner/AppDelegate.swift)가 UserDefaults의 `flutter.siri.ask`에 말을 넣고 앱을 연다.
/// shared_preferences는 앞에 `flutter.`를 붙여 저장하므로 여기서는 `siri.ask`로 읽는다.
/// 앱이 이미 켜져 있었으면 읽어 둔 값이 옛것이라 다시 읽는다(reload).
Future<String?> takeShortcutAsk() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ask = prefs.getString(shortcutAskKey);
    if (ask != null) await prefs.remove(shortcutAskKey);
    return ask;
  } on Object catch (e) {
    debugPrint('시리 단축어 읽기 실패: $e');
    return null;
  }
}

const shortcutAskKey = 'siri.ask';
