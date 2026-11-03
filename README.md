# 패션 에이전트 (Fashion Agent)

시각장애인을 위한 음성 AI 에이전트입니다. 버튼으로 묻지 않고, 에이전트가 말로 묻고 사용자가 말로 답합니다.

## 지금 쓸 수 있는 기능

화면은 위·아래 두 개의 큰 버튼뿐입니다. 위쪽은 **말하기**, 아래쪽은 **다시 듣기**입니다. VoiceOver를 켜도 화면 어디를 눌러도 버튼이 잡힙니다.

### 처음 실행 (음성 온보딩)

1. 에이전트가 먼저 인사합니다. "안녕하세요, 저는 눈이 불편한 사람들을 돕기 위해 제작된 에이전트입니다."
2. "다른 폰에서 쓰신 적 있나요?"라고 묻습니다. 아직은 계정 연결 전이라 "아니요"로 넘어갑니다.
3. 에이전트 이름을 지어 달라고 하고, 맞는지 한 번 더 확인합니다.
4. 이름, 생년월일, 성별, 직업, 키, 몸무게를 차례로 묻습니다.
   - "건너뛰기"라고 말하면 넘어갑니다.
   - 못 알아들으면 두 번 더 묻습니다.
   - 생년월일은 "1990년 3월 5일"이나 "구십년 삼월 오일"처럼 말해도 됩니다.
5. 받은 정보를 읽어 주고 "말씀해주신 정보와 일치할까요?"라고 묻습니다. "아니요"라고 하면 고칠 항목만 다시 묻습니다.
6. 기능 4가지를 설명한 뒤 원하는 기능을 듣습니다.

정보는 이 폰에만 저장됩니다. 다시 실행하면 "반갑습니다. 오늘 하루도 좋은 하루 되세요. 당신의 에이전트 ○○입니다…"라고 인사하고 바로 듣습니다.

### 말로 부르는 기능

| 이렇게 말하면 | 하는 일 | 상태 |
| --- | --- | --- |
| "날씨 어때", "우산 챙겨야 해?", "겉옷 필요해?" | 오늘 날씨, 기온·체감 온도, 강수 확률, 옷차림 힌트를 알려 줍니다. 일교차가 10도 이상이면 겉옷을 챙기라고 합니다. | ✅ 사용 가능 |
| "옷 검사해 줘", "얼룩 있는지 봐 줘" | 옷 검사 화면이 열립니다. 아래 설명을 보세요. | ✅ 사용 가능 (비전 AI는 아직 가짜 응답) |
| "무슨 기능 있어?" | 기능 4가지를 다시 설명합니다. | ✅ 사용 가능 |
| "얼굴 확인해 줘", "이에 뭐 꼈어?" | 이에 낀 것, 화장 대칭, 머리 정돈을 봅니다. | 🚧 "준비 중"이라고 답함 |
| "일정 등록해 줘", "오늘 일정 뭐야?" | 일정을 만들고, 일정에 맞는 옷을 추천하고, 그날 일정을 안내합니다. | 🚧 "준비 중"이라고 답함 |

### 옷 검사

입을 옷을 침대나 바닥에 펼쳐 놓고 폰을 위에서 비춘 뒤 위쪽 버튼을 누릅니다. 한 번 찍으면 아래 세 가지를 이유와 함께 알려 줍니다.

- **일정에 맞는지**: 오늘 일정이 면접, 결혼식, 장례식, 회의, 운동 중 무엇인지에 따라 봅니다. 예를 들어 "면접에는 청바지보다 슬랙스가 좋아요"처럼 말합니다. 일정 등록 기능이 아직 없어서 지금은 "오늘 등록된 일정은 없어요"라고 나옵니다.
- **날씨에 맞는지**: 체감 온도와 일교차를 봅니다. 겉옷이 안 보이면 챙기라고 하고, 더운 날 니트 같은 소재 문제도 알려 줍니다.
- **얼룩·찢어짐**: "오른쪽 소매 끝에 얼룩이 있어요"처럼 위치까지 말합니다. AI가 확실하지 않으면 "손으로 한번 확인해 보세요"라고만 말합니다.

다른 안내도 있습니다.
- 어두우면 불을 켜 달라고 하고, 옷이 잘리면 폰을 어느 쪽으로 옮길지 알려 줍니다.
- 뒷면은 옷을 뒤집어서 한 번 더 검사합니다.
- 본 옷의 설명(색, 종류 등)만 폰에 쌓이고, 사진은 저장하지 않습니다.

### 아직 안 되는 것

- **일정 등록**: 일정 저장소와 판단 규칙은 있지만, 말로 등록하는 기능이 없습니다.
- **얼굴 확인**: 아직 없습니다.
- **계정 연결**: Apple·구글 로그인으로 폰을 바꿔도 이어 쓰는 기능은 아직 없습니다. 연결 방법은 [docs/ACCOUNT.md](docs/ACCOUNT.md)에 있습니다.
- **실기기 확인**: 음성 인식은 아직 실제 아이폰에서 확인하지 않았습니다.

## 로드맵

| 버전 | 목표 |
| --- | --- |
| v0.1 초기 모델 | 음성 온보딩·에이전트 이름, 날씨(일교차), 옷 검사(일정·날씨·얼룩/찢어짐), 본 옷 설명을 폰에 저장 |
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
- 옷 분석: 비전 LLM (앱 → [mcp-clothes-state](https://github.com/fashion-agent-team/mcp-clothes-state) 서버 → Gemini)
- 저장: shared_preferences (옷 설명만, 사진은 저장 안 함)

## 구조

```
lib/
  agent/      온보딩 대화, 기능 고르기(키워드), 에이전트 홈
  models/     UserProfile, Garment, ClothesScan, OutfitCheck, ScheduleEvent, Weather
  services/   말하기·듣기, 날씨, 카메라, 비전 AI(진짜/가짜), 옷·사용자·일정 저장, 계정
  styling/    일정·날씨·손상 규칙, 색 조합 규칙(일정 맞춤 추천용) — AI가 아닌 규칙으로 판단
  session/    옷 검사 단계별 흐름(상태 머신)
  screens/    에이전트 홈(말하기/다시 듣기), 옷 검사 화면. 모두 위·아래 두 개의 큰 버튼
```

화면은 상태만 그리고, 판단은 `styling/` 규칙이 합니다. 비전 AI는 옷의 색·무늬 같은 사실만 돌려줍니다.

## 시작하기

```bash
git clone https://github.com/fashion-agent-team/fashion-agent.git
cd fashion-agent
git checkout develop
flutter pub get
flutter run                                  # 배포된 비전 서버(Gemini)로 실행
flutter run --dart-define=FAKE_VISION=true   # 서버 없이 예시 응답으로 실행
flutter run --dart-define=FAKE_CAMERA=true   # 카메라 없는 시뮬레이터
flutter run --dart-define=VISION_URL=http://localhost:8787   # 로컬 서버
flutter test
```

## 레포 구성

이 레포는 **앱(프론트)** 입니다. 서버 쪽은 기능별 레포로 나뉘어 있습니다.

| 레포 | 하는 일 |
| --- | --- |
| [fashion-agent](https://github.com/fashion-agent-team/fashion-agent) | 앱 (Flutter) |
| [fashion-agent-gateway](https://github.com/fashion-agent-team/fashion-agent-gateway) | API Gateway (REST), 계정·회원정보 |
| [fashion-agent-agent](https://github.com/fashion-agent-team/fashion-agent-agent) | agent, Gemini로 기능 고르기·맞춤 추천 |
| [mcp-weather](https://github.com/fashion-agent-team/mcp-weather) | 날씨, 날씨에 맞는 옷 두께·재질 |
| [mcp-schedule](https://github.com/fashion-agent-team/mcp-schedule) | 일정 기록·알림, 일정에 맞는 옷차림 |
| [mcp-clothes-state](https://github.com/fashion-agent-team/mcp-clothes-state) | 옷 사진으로 얼룩·찢어짐 확인 (옛 `server/`, 배포된 비전 서버) |
| [mcp-face-check](https://github.com/fashion-agent-team/mcp-face-check) | 얼굴 사진으로 화장 대칭·이에 낀 것 확인 |
| [mcp-closet](https://github.com/fashion-agent-team/mcp-closet) | 찍은 옷을 DB에 기록해 옷장 만들기·추천 |

## 브랜치 전략

GitFlow를 사용합니다. 자세한 규칙은 [docs/GITFLOW.md](docs/GITFLOW.md)를 보세요.
