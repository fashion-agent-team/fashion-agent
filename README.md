# 패션 에이전트 (Fashion Agent)

시각장애인을 위한 음성 AI 에이전트입니다. 처음 실행하면 에이전트가 먼저 말을 걸어 이름을 지어 달라고 하고, 사용자 정보를 말로 받아 재확인합니다. 그다음부터는 원하는 기능을 말하면 됩니다.

| 기능 | 내용 | 상태 |
| --- | --- | --- |
| 옷 검사 | 고른 옷을 비추면 색·무늬·날씨 적합성을 이유와 함께 피드백, 안 어울리면 옷장에서 대안과 위치 안내 | 동작(비전 AI는 가짜) |
| 날씨 | 오늘 날씨, 일교차가 크면 겉옷 안내 | 동작 |
| 얼굴 확인 | 이에 낀 것, 화장 대칭, 머리 정돈 | 준비 중 |
| 일정 | 일정 만들기, 일정에 맞는 옷 추천, 그날 일정 안내 | 준비 중 |

## 로드맵

| 버전 | 목표 |
| --- | --- |
| v0.1 초기 모델 | 음성 온보딩·에이전트 이름, 날씨(일교차), 옷 검사(색·무늬·날씨, 옷장 대안, 꺼낸 옷 확인), 본 옷 설명을 폰에 저장 |
| v0.1+ | 얼굴 확인, 일정, Apple·구글 로그인으로 폰 바꿔도 이어 쓰기([docs/ACCOUNT.md](docs/ACCOUNT.md)) |
| v0.2 | 쌓인 옷 목록으로 바로 추천, 같은 옷 합치기, 말 알아듣기를 LLM으로 |
| v0.3 | 사람 위치 인식으로 거리 안내("한 발짝 뒤로 가주세요"), 접근성 개선 |
| 이후 | 홈캠·펫캠 연동, NFC 옷걸이 태그 |

발표 마감: 2026-11-20

## 기술 스택

- 앱: Flutter (아이폰 우선, Android·웹은 이후)
- 음성 안내: flutter_tts / 음성 인식: speech_to_text (iOS Speech, 한국어)
- 카메라: camera
- 날씨: Open-Meteo (API 키 없음)
- 옷 분석: 비전 LLM (앱 → `server/` 프록시 → LLM, 형식은 [server/README.md](server/README.md))
- 저장: shared_preferences (옷 설명만, 사진은 저장 안 함)

## 구조

```
lib/
  agent/      온보딩 대화, 기능 고르기(키워드), 에이전트 홈
  models/     UserProfile, Garment, ClothesScan, OutfitFeedback, Weather
  services/   말하기·듣기, 날씨, 카메라, 비전 AI(진짜/가짜), 옷·사용자 저장, 계정
  styling/    색 조합·날씨·위치 규칙 (AI가 아닌 규칙으로 판단)
  session/    옷 검사 단계별 흐름(상태 머신)
  screens/    에이전트 홈(말하기/다시 듣기), 옷 검사 화면. 모두 위·아래 두 개의 큰 버튼
server/       비전 프록시 (API 키 보관)
```

화면은 상태만 그리고, 판단은 `styling/` 규칙이 합니다. 비전 AI는 옷의 색·무늬 같은 사실만 돌려줍니다.

## 시작하기

```bash
git clone https://github.com/fashion-agent-team/fashion-agent.git
cd fashion-agent
git checkout develop
flutter pub get
flutter run                                  # 가짜 비전 AI로 실행
flutter run --dart-define=FAKE_CAMERA=true   # 카메라 없는 시뮬레이터
flutter run --dart-define=VISION_URL=https://<프록시 주소>
flutter test
```

## 브랜치 전략

GitFlow를 사용합니다. 자세한 규칙은 [docs/GITFLOW.md](docs/GITFLOW.md)를 보세요.
