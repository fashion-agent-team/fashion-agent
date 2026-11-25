# 앱 테스트 읽는 법

`flutter test`로 전부 돌리고, `flutter test --coverage`로 줄 커버리지(80% 이상 유지)를 본다.

## 폴더

`test/` 아래 폴더는 `lib/`와 같다(`agent/`, `services/`, `screens/`, `session/`, `styling/`, `models/`). 접근성 검사는 `a11y/`.
예: `lib/agent/answer_parsing.dart` → `test/agent/answer_parsing_test.dart`.

## 가짜 객체는 `test/helpers/`에만 둔다

테스트 파일끼리 서로 import하지 않는다. 함께 쓰는 가짜 객체는 모두 `helpers/fakes.dart` 하나로 가져온다.

| 파일 | 들어 있는 것 | 대신하는 것 |
| --- | --- | --- |
| `fake_speech.dart` | `FakeSpeech`, `saidLine…` 매처 | 소리 내어 말하기(TTS). 말한 문장을 `said`에 모은다 |
| `fake_listen.dart` | `ScriptedListen` | 마이크(음성 인식). 정해 둔 답을 차례로 듣는다 |
| `fake_account.dart` | `FakeAccount` | 계정 로그인·프로필 올리기 |
| `fake_weather.dart` | `FakeWeatherService`, `clearMildWeather` | 날씨 서버. 정해 둔 날씨를 준다 |
| `fake_turn_api.dart` | `FakeTurnApi`, `reply()` | 서버 agent 대화. 보낸 것을 적고 정해 둔 답을 준다 |
| `agent_setup.dart` | `onboardingWith()`, `sampleAnswers`, `agentWith()`, `busanLocation`, `settle()` | 에이전트 테스트 준비 코드 |
| `session_setup.dart` | `controllerWith()`, `coolWeather` | 옷 검사 세션 테스트 준비 코드 |

한 파일에서만 쓰는 가짜(예: `_SequenceMouthFinder`)는 그 파일 아래쪽에 `_`로 시작하는 이름으로 둔다.

## 앱이 한 말 검사하기

```dart
expect(speech, saidLine('지금은 계정 연결 없이 이 폰에만 저장할게요.')); // 이 문장을 말했다
expect(speech, saidLineStartingWith('좋아요, 이제 제 이름은'));       // 이렇게 시작하는 문장을 말했다
expect(speech, saidLineContaining('일교차'));                          // 이 말이 들어간 문장을 말했다
expect(speech, neverSaidLineStartingWith('앗'));                       // 이렇게 시작하는 문장은 말하지 않았다
expect(speech.said, [weather, tapToTalk]);                             // 말한 순서 전체가 중요할 때
expect(speech.countLinesContaining('키는 몇 센티미터인가요?'), 2);     // 같은 질문을 몇 번 했는지
```

`expect(speech.said, contains(startsWith(...)))`처럼 매처를 겹쳐 쓰지 않는다. 실패 메시지도 매처 이름대로 나온다.

## 테스트 하나는 한 가지만 본다

- 이름만 읽어도 무엇을 넣으면 무엇이 나와야 하는지 알 수 있게 쓴다. 예: `"구십년 삼월 오일"`, `비정상: 달력에 없는 날짜 "1990년 2월 30일"`.
- 정상 입력과 비정상 입력(null·false·오류가 나와야 하는 경우)은 한 `test` 안에 섞지 않고 `group('정상: …')` / `group('비정상: …')` 또는 따로 `test`로 나눈다.
- 여러 말투를 같은 규칙으로 볼 때는 `for`나 `Map.forEach`로 말투마다 `test`를 하나씩 만든다. 하나가 실패하면 어느 말투인지 이름에 바로 나온다.
- 날짜·시각은 `today:`나 `clock:`으로 고정한다(예: `DateTime(2026, 10, 30)`). 실제 오늘 날짜에 따라 결과가 바뀌면 안 된다.
- 사용자 이야기(US) 테스트는 `Given … When … Then …` 이름을 쓴다.
