# 계정 연결 (폰을 바꿔도 이어 쓰기)

앱은 **구글 로그인 → Firebase → 게이트웨이 로그인** 순서로 계정을 연결하고, 회원정보는 게이트웨이(`/api/v1/me/profile`)에 둡니다.
구현은 `lib/services/firebase_account_service.dart`, 토큰 관리는 `lib/services/gateway_auth.dart`입니다.

## 왜 이 방식인가

- 시각장애인이 아이디·비밀번호를 입력하는 건 어렵습니다. 구글 로그인은 폰에 이미 있는 계정을 고르기만 하면 됩니다.
- **발표까지는 아이폰·안드로이드 모두 구글 로그인만 씁니다.** Apple 로그인은 유료 Apple Developer 계정(연 129,000원)이 있어야 켤 수 있어서, 앱스토어에 올릴 때 붙입니다. 앱스토어는 다른 소셜 로그인이 있으면 Apple 로그인도 요구합니다.
- 이름·생년월일로 ID를 만들지 않습니다. 겹칠 수 있고, 남이 알기 쉬운 정보라 보안상 위험합니다.
- 계정 연결이 실패하거나 사용자가 취소해도 앱은 그대로 씁니다. 정보는 폰에 남고 나중에 연결할 수 있습니다.

## 흐름

1. `GoogleSignIn.authenticate()`로 구글 ID 토큰을 받는다.
2. `FirebaseAuth.signInWithCredential`로 Firebase에 로그인하고 Firebase ID 토큰을 받는다.
3. 게이트웨이 `POST /api/v1/auth/login {idToken}` → access·refresh 토큰. 키체인/키스토어(`flutter_secure_storage`)에 둔다.
4. 이후 요청은 `GatewayAuth.send`로 보낸다. 만료 1분 전이면 미리, 401이면 한 번 `POST /api/v1/auth/refresh`로 갱신하고 다시 보낸다. 갱신도 거절되면 토큰을 지운다(다시 로그인).
5. 온보딩이 끝나면 `PUT /api/v1/me/profile`, 새 폰에서 로그인하면 `GET /api/v1/me/profile`로 이어 쓴다.

## 실행

게이트웨이 주소를 주면 구글 로그인을 쓰고, 안 주면 로그인 없이 이 폰에만 저장합니다.

```
# 노트북에서 docker compose로 게이트웨이를 띄우고, 같은 와이파이의 폰에서
flutter run --dart-define=GATEWAY_URL=http://192.168.0.10:8080
```

- 노트북 IP는 macOS `ipconfig getifaddr en0`로 확인한다.
- 개발용 http 허용: 아이폰은 Info.plist `NSAllowsLocalNetworking`, 안드로이드는 debug 매니페스트 `usesCleartextTraffic`(릴리스에는 안 들어감).

## Firebase 설정 (한 번만, 이미 함)

- 프로젝트 ID `fashion-agent-7631d`. 게이트웨이 `.env`의 `FIREBASE_PROJECT_ID`와 같아야 한다.
- Authentication → 로그인 방법에서 **Google**을 켠다.
- 앱 설정값은 `lib/firebase_options.dart`에 있다. `GoogleService-Info.plist`·`google-services.json`에서 옮긴 공개 설정이라 비밀이 아니다. 앱을 다시 등록하면 `flutterfire configure`로 새로 만든다.
- 아이폰: Info.plist에 `GIDClientID`(plist의 `CLIENT_ID`)와 URL Types(`REVERSED_CLIENT_ID`)를 넣어 두었다.

## 안드로이드에서 구글 로그인하려면 (남은 일)

안드로이드 구글 로그인은 Firebase 콘솔에 앱 서명 키의 **SHA-1**이 등록돼 있어야 합니다. 지금은 Android SDK가 없어 등록하지 못했습니다.

1. Android Studio를 설치하고 한 번 실행해 SDK를 받는다.
2. `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1`
3. Firebase 콘솔 → 프로젝트 설정 → Android 앱 → 디지털 지문 추가에 붙여 넣는다.
4. `google-services.json`을 다시 받아 `android/app/`에 덮어쓴다.

## 테스트

- `test/gateway_auth_test.dart`: 로그인·갱신·동시 401·만료 직전 갱신·갱신 거절 시 로그아웃·회원정보 모양.
- 온보딩은 `test/agent_test.dart`의 `FakeAccount`처럼 가짜 계정으로 돌린다.

## 저장하는 것

`UserProfile`(이름, 생년월일, 성별, 직업, 키, 몸무게, 에이전트 이름)만 올립니다. 사진은 올리지 않습니다.
키·몸무게처럼 민감한 항목은 온보딩에서 "건너뛰기"로 빼둘 수 있습니다.
