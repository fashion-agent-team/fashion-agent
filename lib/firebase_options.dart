// Firebase 콘솔의 앱 설정값. `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`에서 옮겼다.
// 이 값들은 앱에 들어가는 공개 설정이라 비밀이 아니다. 앱을 다시 등록하면 `flutterfire configure`로 새로 만든다.
// ignore_for_file: lines_longer_than_80_chars

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('이 앱은 아이폰과 안드로이드만 지원합니다.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDsVYtEBl7g1CwkMi4J1DgV8Zw6ZczAYJE',
    appId: '1:156130892918:android:0b8a1f7278b18c5dc61357',
    messagingSenderId: '156130892918',
    projectId: 'fashion-agent-7631d',
    storageBucket: 'fashion-agent-7631d.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBekO8xv3-4ykh8JCqEb1RW8i3bsphFf4M',
    appId: '1:156130892918:ios:26bbad85485427a3c61357',
    messagingSenderId: '156130892918',
    projectId: 'fashion-agent-7631d',
    storageBucket: 'fashion-agent-7631d.firebasestorage.app',
    iosClientId:
        '156130892918-5v0e3nr35atra7clpu1b1rbksdrk1aeo.apps.googleusercontent.com',
    iosBundleId: 'com.fashionagent.fashionAgent',
  );

  /// 구글 로그인이 서버(Firebase)용 ID 토큰을 받을 때 쓰는 웹 클라이언트 id. 안드로이드에 필요하다.
  static const String googleServerClientId =
      '156130892918-58g62rvfnbu8l3ul8kve778s4thv6vdk.apps.googleusercontent.com';
}
