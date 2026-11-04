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
- 카메라: camera (이미지 스트림) + ML Kit 물체 인식으로 구도 실시간 안내·자동 전송 (예정)
- 날씨: Open-Meteo (API 키 없음)
- 옷 분석: 지금은 비전 LLM (앱 → [mcp-clothes-state](https://github.com/fashion-agent-team/mcp-clothes-state) 서버 → Gemini). 자체 학습 모델로 바꾸는 중
- 저장: shared_preferences (옷 설명만, 사진은 저장 안 함)
- 백엔드 언어: **Java** (2026-11-04 확정)
- API Gateway: **Spring Cloud Gateway** (2026-11-04 확정)
- agent · MCP 서버: Spring AI (ChatClient + MCP 클라이언트 / Spring AI MCP Server)
- 옷 상태·얼굴 확인: **자체 학습 모델**(YOLO·분류 모델을 ONNX로 서버에서 실행), 애매할 때만 Gemini (2026-11-04 확정)
- 옷장 추천: **RAG** (pgvector + 임베딩 + Gemini 답변) (2026-11-04 확정)
- DB: PostgreSQL + pgvector / 배포: Docker Compose

레포별 기술과 고른 이유는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)에 있습니다.

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

| 레포 | 하는 일 | 포트 | 기술 | 담당 |
| --- | --- | --- | --- | --- |
| [fashion-agent](https://github.com/fashion-agent-team/fashion-agent) | 앱 (Flutter) | - | Flutter, ML Kit, Firebase Auth, FCM | 미정 |
| [fashion-agent-gateway](https://github.com/fashion-agent-team/fashion-agent-gateway) | 입구: 로그인 확인·JWT·사용량 제한, 계정·회원정보 | 8080 | Spring Cloud Gateway, Spring Security, Redis | 미정 |
| [fashion-agent-agent](https://github.com/fashion-agent-team/fashion-agent-agent) | 대화, MCP에서 데이터 모아 Gemini로 판단·추천 | 8081 | Spring AI(ChatClient, MCP 클라이언트), Gemini | 이진행 |
| [mcp-weather](https://github.com/fashion-agent-team/mcp-weather) | 오늘 날씨·일교차 데이터 | 8091 | Spring AI MCP 서버, Open-Meteo | 박창근 |
| [mcp-schedule](https://github.com/fashion-agent-team/mcp-schedule) | 일정 저장·조회, 장소 종류 | 8092 | Spring AI MCP 서버, 카카오 로컬, PostgreSQL | 정지원 |
| [mcp-clothes-state](https://github.com/fashion-agent-team/mcp-clothes-state) | 옷 사진에서 종류·색·얼룩·찢어짐 찾기 | 8093 | YOLO+FashionCLIP(ONNX Runtime Java), Gemini 폴백 | 미정 |
| [mcp-face-check](https://github.com/fashion-agent-team/mcp-face-check) | 얼굴 화장 대칭·이에 낀 것 확인 | 8094 | ML Kit 윤곽점 규칙, 치아 분류 모델 | 미정 |
| [mcp-closet](https://github.com/fashion-agent-team/mcp-closet) | 내 옷 기록, 비슷한 옷·코디 찾기(RAG) | 8095 | pgvector, multilingual-e5 임베딩 | 미정 |
| [mcp-helper](https://github.com/fashion-agent-team/mcp-helper) | 사용자가 원할 때 가족·친구에게 사진 확인 요청 | 8096 | 문자 API, 웹 답장 링크, FCM | 미정 |

1차는 agent·mcp-weather·mcp-schedule이고(2026-11-04), 끝나면 나머지를 다시 나눕니다. weather·schedule 담당은 임시 배정이라 서로 바꿔도 됩니다. 서버끼리 주고받는 약속은 [docs/contracts/](docs/contracts/README.md)에 있고, 팀이 정할 것은 [docs/contracts/README.md](docs/contracts/README.md)의 "아직 안 정한 것"에 모아 두었습니다.

서버 레포는 모두 2026-11-03에 만들었고 public, `main`·`develop` 브랜치로 GitFlow를 씁니다. 아직 README와 할 일만 있고, 코드가 있는 곳은 mcp-clothes-state(옛 `server/`, 기록째 이전)뿐입니다.

## 아키텍처

```
앱 (Flutter: 음성·카메라)
  └─ REST ─▶ API Gateway (Spring Cloud Gateway)
               ├─ account: 기존 회원 / Apple·구글 로그인
               ├─ 회원정보: 이름·생년월일·성별·직업·키·몸무게 (건너뛰기 가능)
               └─ agent (Gemini가 어떤 기능을 쓸지 고름)
                    ├─ MCP weather       날씨, 옷 두께·재질
                    ├─ MCP schedule      일정, 장소 분위기
                    ├─ MCP clothes_state 옷 이물질·이염·찢어짐 (자체 학습 YOLO, 애매하면 Gemini)
                    ├─ MCP face_check    화장 대칭, 이에 낀 음식물 (윤곽점 규칙 + 치아 분류 모델)
                    ├─ MCP closet        전용 옷장, RAG로 추천
                    └─ MCP helper        지인 확인 요청
DB: 계정, 회원정보, 일정, 옷장 (PostgreSQL + pgvector)
```

레포별 기술 스택, 요청 흐름, 시작 순서는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)와 [docs/architecture.pdf](docs/architecture.pdf)를 보세요.

서비스 간 약속(앱 API, MCP 도구 입출력, 인증, 오류, 포트, DB 스키마)은 [docs/contracts/](docs/contracts/README.md)에 있습니다. 각 레포는 이 약속대로 만들고, 바꿀 때는 이 문서를 먼저 고칩니다.

## 지금까지 진행 상황 (2026-11-04 기준)

### 정한 것

| 날짜 | 결정 |
| --- | --- |
| 2026-10-27 | Jetson은 당분간 쓰지 않고, 옷 분석은 클라우드 AI(Gemini API, 학습 없이 프롬프트)로 |
| 2026-11-03 | 기능별 MCP 구조로 가고, 기능마다 레포를 따로 나눔(위 [레포 구성](#레포-구성)) |
| 2026-11-04 | API Gateway는 **Spring Cloud Gateway** |
| 2026-11-04 | 백엔드 언어는 **Java** |
| 2026-11-04 | 옷 상태·얼굴 확인은 비용 때문에 Gemini 직접 분석 대신 **자체 학습/사전 학습 모델**로 (10-27 결정 변경, Gemini는 폴백) |
| 2026-11-04 | 옷장 추천(mcp-closet)은 **RAG**로 |
| 2026-11-04 | 한 명이 레포 하나씩 맡아 진행 |
| 2026-11-04 | 중심 기능은 옷 추천: MCP 서버(옷 상태·날씨·일정·옷장)가 데이터를 주고 Gemini가 판단·추천. 얼굴 확인과 가족 확인 요청은 개별 기능 |
| 2026-11-04 | 옷 추천은 2단계: 날씨·일정으로 먼저 말로 추천 → 사용자가 꺼낸 옷을 카메라에 보여 주면 자동 판단(사진 찍기 버튼 없음, 폰이 구도를 실시간 안내하고 잘 들어오면 한 장 자동 전송). 두 벌을 나란히 놓으면 "왼쪽이 더 나아요"처럼 비교 |

아직 안 정한 것: 담당자 배정, 레포별 추천 기술 최종 확인([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)의 추천 기준), 학습 데이터 수집 방법.

### develop에 머지된 PR

| PR | 내용 |
| --- | --- |
| #1 | 플랫폼 폴더(android·ios·web) 생성, 초기 세팅 |
| #2 | 오늘 날씨·기온 음성 안내 (Open-Meteo) |
| #3 | 음성 AI 에이전트 뼈대: 음성 온보딩, 기능 고르기, 계정 자리 |
| #4 | 옷 검사 방향 변경: 일정·날씨 적합성, 얼룩·찢어짐 안내 (색 조합 안내 제거) |
| #5 | Gemini 비전 프록시 서버 뼈대 (Cloudflare Workers), 응답에 격식·손상 추가 |
| #6 | 기본 Gemini 모델을 gemini-3.5-flash로 변경 |
| #7 | 앱 기본 비전 서버를 배포된 Cloudflare Worker로 연결 |
| #8 | Gemini 오류 응답에 이유를 함께 담기 |
| #9 | 옷 이름과 메모를 짧게 받도록 프롬프트 조정 |
| #10 | 서버 코드(`server/`)를 mcp-clothes-state 레포로 옮기고 앱 레포로 정리 |

### 다음 할 일

- 첫날: [docs/contracts/](docs/contracts/README.md) 약속 같이 읽고 확정, 버전·담당자 정하기, 학습용 옷 사진 찍기·라벨링 시작
- 데모 경로 먼저: fashion-agent-gateway, fashion-agent-agent(+mcp-weather), mcp-clothes-state(모델 학습 + Spring AI MCP)
- 앱이 비전 서버를 직접 부르던 것을 Gateway → agent 경유로 바꾸기
- 그다음 mcp-schedule, mcp-closet(RAG), mcp-face-check, mcp-helper

## 브랜치 전략

GitFlow를 사용합니다. 자세한 규칙은 [docs/GITFLOW.md](docs/GITFLOW.md)를 보세요.
