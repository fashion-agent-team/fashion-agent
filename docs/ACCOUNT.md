# 계정 연결 (폰을 바꿔도 이어 쓰기)

지금 앱은 `DeviceOnlyAccountService`로 돌아서 정보가 이 폰에만 저장됩니다.
아래 순서대로 Firebase를 붙이고 `FirebaseAccountService`를 만들어 `lib/main.dart`에서 바꿔 끼우면 됩니다.

## 왜 이 방식인가

- 시각장애인이 아이디·비밀번호를 입력하는 건 어렵습니다. 아이폰은 **Sign in with Apple**(Face ID 한 번), 안드로이드는 **구글 로그인**(폰에 이미 로그인된 계정 선택)으로 입력 없이 가입합니다.
- 아이폰에서도 구글 로그인을 고를 수 있게 둡니다. Firebase가 두 로그인을 한 사용자(uid)로 묶어 주므로, 아이폰 → 안드로이드로 바꿔도 같은 정보를 씁니다.
- 이름·생년월일로 ID를 만들지 않습니다. 겹칠 수 있고, 남이 알기 쉬운 정보라 보안상 위험합니다.
- 계정 연결이 실패하거나 사용자가 취소해도 앱은 그대로 씁니다. 정보는 폰에 남고 나중에 연결할 수 있습니다.

## 1. Firebase 프로젝트

1. https://console.firebase.google.com 에서 프로젝트를 만든다.
2. `dart pub global activate flutterfire_cli` 후 저장소 루트에서 `flutterfire configure`를 실행해 iOS·Android 앱을 등록한다. `lib/firebase_options.dart`가 생긴다.
3. Authentication → 로그인 방법에서 **Apple**과 **Google**을 켠다.
4. Authentication → 설정 → 사용자 계정 연결에서 "같은 이메일이면 계정 연결"을 켠다.
5. Firestore Database를 만들고 규칙을 아래처럼 둔다. 자기 문서만 읽고 쓸 수 있다.

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## 2. 패키지

```
flutter pub add firebase_core firebase_auth cloud_firestore sign_in_with_apple google_sign_in
```

## 3. iOS 설정

- Xcode → Runner → Signing & Capabilities → **+ Capability → Sign in with Apple**.
- Apple Developer 계정에서 App ID에 Sign in with Apple을 켠다(팀원 중 개발자 계정 보유자가 한 번만).
- 구글 로그인용으로 `GoogleService-Info.plist`의 `REVERSED_CLIENT_ID`를 Info.plist의 URL Types에 넣는다.

## 4. Android 설정

- `flutterfire configure`가 만든 `google-services.json`이 `android/app/`에 있는지 확인한다.
- Firebase 콘솔의 Android 앱에 디버그·릴리스 키의 SHA-1을 등록한다 (`cd android && ./gradlew signingReport`).

## 5. 구현할 것 (`lib/services/firebase_account_service.dart`)

| 메서드 | 할 일 |
|---|---|
| `signIn()` | 아이폰이면 Apple, 안드로이드면 구글로 로그인 → `FirebaseAuth.signInWithCredential` → `uid` 반환. 취소·실패면 `null`. |
| `restore(uid)` | Firestore `users/{uid}` 문서를 읽어 `UserProfile.fromJson`. 없으면 `null`. |
| `upload(uid, profile)` | `users/{uid}`에 `profile.toJson()`을 저장. |

- 아이폰에서 구글로 로그인하는 선택지는 온보딩에서 "구글로 할게요"라고 말하면 쓰도록 `signIn({provider})`로 늘리면 된다.
- 이미 Apple로 가입한 사용자가 구글을 추가하려면 `currentUser.linkWithCredential`로 연결한다.
- 테스트는 `test/agent_test.dart`의 `FakeAccount`처럼 가짜로 돌린다.

## 저장하는 것

`UserProfile`(이름, 생년월일, 성별, 직업, 키, 몸무게, 에이전트 이름)만 올립니다. 사진은 올리지 않습니다.
키·몸무게처럼 민감한 항목은 온보딩에서 "건너뛰기"로 빼둘 수 있습니다.
