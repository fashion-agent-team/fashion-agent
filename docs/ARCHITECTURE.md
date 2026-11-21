# 패션 에이전트 아키텍처

2026-11-21 기준. 두 젯슨에 떠 있는 서버와 각 레포 `develop`(2026-11-20)을 대조해 고쳤습니다. 그림은 [조직 프로필의 아키텍처 그림](https://github.com/fashion-agent-team/.github/blob/main/profile/images/architecture-v8.png)을 보세요. 예전 [architecture.pdf](architecture.pdf)는 2026-11-04 계획 때 그림이라 지금과 다릅니다.

앱은 HTTPS로 gateway 하나만 부릅니다. 백엔드는 Java 21 · Spring Boot 4.0.9 · Spring AI 2.0.2이고, agent가 기능별 MCP 서버 다섯에서 데이터를 모아 GPT로 판단합니다. 옷 종류·색·무늬·얼룩과 얼굴·치아는 우리가 학습한 모델(ONNX)을 서버에서 직접 돌리고, 옷장 추천은 RAG로 합니다.

```
앱 (Flutter: 음성·카메라·ML Kit 물체·포즈·얼굴)
  └─ HTTPS · REST · JWT
     simcheong.java21.net → Tailscale Funnel → Nginx
       └─ gateway (Spring Cloud Gateway Web MVC, 우리 JWT 발급·검증, 메모리 사용량 제한)
           ├─ account · 회원정보 (Firebase ID 토큰을 구글 공개 키로 확인, JdbcClient + Flyway)
           ├─ /stt  OpenAI gpt-4o-mini-transcribe
           ├─ /tts  Azure Speech 4목소리 + edge-tts 3목소리 (옆 컨테이너)
           ├─ /schedules → mcp-schedule (일정 화면 REST)
           └─ agent (Spring AI ChatClient + MCP 클라이언트, gpt-5.4-mini, Redis 대화 상태)
                ├─ mcp-weather        Open-Meteo, 안 되면 MET Norway
                ├─ mcp-schedule       카카오 로컬 API, JPA + Flyway
                ├─ mcp-clothes-state  YOLO26n·색 CNN·FashionSigLIP(+LoRA), ONNX / 애매하면 허락받고 gpt-4.1-mini
                │    └─ so400m-embed  옷 종류가 아주 애매할 때만 (SigLIP2 So400m, GPU)
                ├─ mcp-face-check     BiSeNet 얼굴 분할 + 좌우 비교 모델 + 눈화장·치아 분류
                └─ mcp-closet         RAG: pgvector + multilingual-e5-small + FashionSigLIP 사진 벡터
DB: PostgreSQL 17 + pgvector (스키마 account, schedule, closet), Redis 7
배포: 젯슨 오린 나노 8GB 두 대, 각각 Docker Compose
```

## 배포: 젯슨 두 대

| 기기 | 올라간 것 | 메모리 상한 합 |
| --- | --- | --- |
| 앱 서버 젯슨 | nginx, gateway, edge-tts, agent, mcp-schedule, mcp-closet, so400m-embed, PostgreSQL, Redis | 약 5.3GB |
| 모델 서버 젯슨 | mcp-clothes-state, mcp-face-check, mcp-weather, 모델 학습 | 서버 약 3.3GB, 나머지는 학습 |

- 처음엔 한 대에 다 올렸는데 8GB에 다 들어가지 않아 2026-11-13쯤 무거운 사진 모델과 학습을 다른 젯슨으로 옮겼습니다. agent는 MCP 서버를 주소로만 불러서 `MCP_*_URL` 환경 변수만 바꿨습니다.
- 두 젯슨은 Tailscale 사설망으로 이어집니다. 바깥에서는 `simcheong.java21.net`(리버스 프록시) → Tailscale Funnel → 앱 서버 젯슨의 Nginx(:80)로 들어옵니다.
- 이미지는 GHCR에서 받지 않고 각 젯슨에서 레포를 받아 arm64로 직접 빌드합니다. 자세한 순서는 [infra/jetson/README.md](infra/jetson/README.md)에 있습니다. 젯슨에 있는 compose 파일이 기준이고, 이 레포의 `infra/jetson/docker-compose.yml`에는 아직 so400m-embed와 모델 서버 분리가 반영되지 않았습니다.
- 비밀 값(OpenAI 키, Azure 키, 카카오 키, DB 비밀번호 등)은 젯슨의 `.env`에만 둡니다. 레포와 앱에는 넣지 않습니다.

## 레포별 기술 스택

| 구성요소 | 레포 | 기술 스택 | 고른 이유 |
| --- | --- | --- | --- |
| 앱 | fashion-agent | Flutter, speech_to_text, flutter_tts, audioplayers, record, camera, ML Kit 물체·포즈·얼굴, Firebase Auth + google_sign_in, flutter_local_notifications, geolocator | 화면보다 소리로 쓰는 앱. 구도 안내와 자동 촬영은 폰 안에서 바로 |
| gateway | fashion-agent-gateway | Spring Cloud Gateway(Web MVC, 가상 스레드), Nimbus JOSE(JWT), JdbcClient + Flyway, 메모리 사용량 제한(1분에 요청 30번, 사진 10장) | 앱이 부르는 입구 하나에서 로그인·라우팅·제한을 처리 |
| account · 회원정보 | fashion-agent-gateway | Firebase ID 토큰을 구글 공개 키로 확인한 뒤 우리 JWT(1시간, 갱신 30일) 발급. 개발용 기기 로그인(`GATEWAY_DEV_LOGIN`) | Firebase Admin 없이 확인만. 자세한 건 [ACCOUNT.md](ACCOUNT.md) |
| 음성 | fashion-agent-gateway | `/stt` OpenAI gpt-4o-mini-transcribe, `/tts` Azure Speech(유진·지민·서현·순복) + edge-tts(선희·인준·현수). 안 되면 앱이 폰 TTS로 | 목소리를 서버에서 고르게 해 기기마다 같게 |
| agent | fashion-agent-agent | Spring AI ChatClient(OpenAI gpt-5.4-mini, reasoning none), MCP 클라이언트 5개, Redis 대화 상태 | MCP 서버와 같은 프레임워크. 서버 주소만 적으면 도구가 붙음 |
| MCP 공통 | mcp-* | Spring AI MCP Server 2.0.2 (Streamable HTTP, `@Tool`, schedule만 `@McpTool`) | 메서드에 어노테이션만 붙이면 도구가 됨 |
| weather | mcp-weather | Open-Meteo, 실패하면 MET Norway, RestClient, Caffeine 캐시 30분 | 둘 다 키 없음 |
| schedule | mcp-schedule | 카카오 로컬 API, Spring Data JPA + Flyway(V5), `@Scheduled` 아침 작업(지금은 서버 로그만 남기고, 폰 알림은 앱이 띄움) | 국내 장소 종류(예식장·장례식장)가 정확 |
| clothes-state | mcp-clothes-state | ONNX Runtime Java. 얼룩·찢어짐 YOLO26n v6, 옷 종류 12 YOLO26n, 색 20가지 CNN(K-Fashion), 무늬 8 FashionSigLIP+LoRA와 YOLO26n을 7:3, 입은 모습 YOLO26n(뒤집힘·단추·택), FashionSigLIP 옷 벡터. 애매한 얼룩·무늬는 사용자가 허락했을 때만 그 부분을 잘라(얼굴 가림) gpt-4.1-mini로 확인 | 호출 비용 없이 서버에서 동작, 결함 위치가 박스로 나옴 |
| so400m-embed | mcp-clothes-state/so400m-embed | Python, open_clip SigLIP2 So400m, CUDA fp16. 옷 종류 확신이 낮을 때만 0.8초 안에 다시 물음 | 애매한 옷 종류 정답률을 올림. 학습에 DeepFashion2를 써서 학교 프로젝트 전용 |
| face-check | mcp-face-check | 앱 ML Kit 윤곽점 + BiSeNet ResNet34 얼굴 분할, 좌우 비교 모델(눈썹 길이·두께, 입술 너비, 볼; CelebA로 학습, FFHQ 실사진 기준), 눈화장 ResNet18 세 개 앙상블, 치아 MobileNetV3-Small | 얼굴·치아 사진은 외부 AI로 보내지 않음 |
| closet | mcp-closet | Spring AI VectorStore + pgvector(공용 코디 지식만 HNSW), multilingual-e5-small(ONNX) 글 벡터, FashionSigLIP 사진·글 벡터, 옷 부분 작은 사진(64KB 이하) | 가진 옷 안에서만 근거를 붙여 추천. 같은 옷 합치기도 같은 벡터로 |
| 모델 학습 | 각 mcp 레포 `training/` | Python, PyTorch, Ultralytics, 모델 서버 젯슨과 맥북에서 학습해 ONNX로 내보냄 | ONNX면 Java에서 그대로 실행. 학습 사진은 외부 AI로 보내지 않음 |
| DB | (공용) | PostgreSQL 17 + pgvector. 서비스마다 스키마 하나, 스키마끼리 FK 없음 | 관계 데이터와 벡터를 한 DB에. 표 구조는 [infra/DB.md](infra/DB.md)와 조직 프로필 ERD |

Ultralytics는 AGPL 라이선스라 상용화 전에 다시 확인합니다.

## 기능 구분

중심 기능은 **옷 추천과 옷 확인**입니다. MCP 서버들은 데이터만 돌려주고, "이 옷이 오늘 맞는가" 같은 판단은 agent가 GPT로 합니다.

agent는 말을 먼저 의도로 나눕니다(`flow/Intent`). 옷 추천, 옷 확인, 색 조합, 옷장 읽기·지우기·기록 찾기, 날씨, 오늘 일정, 얼굴 확인은 키워드로 골라 정해진 순서(코드)로 도구를 부릅니다. 발표 때 매번 같게 동작하고 GPT 없이도 빠르게 답하기 위해서입니다. 일정 넣기·지우기, 다른 날 일정처럼 나머지만 GPT가 도구를 고릅니다.

## 옷 추천 흐름 (2단계)

사용자는 사진 찍기 버튼을 누르지 않습니다. 먼저 말로 추천을 듣고, 자기 방식대로 꺼낸 옷을 카메라에 보여 주면 알아서 판단해 줍니다.

**1단계: 말로 추천** ("오늘 뭐 입지?")
1. agent가 데이터를 모읍니다: 오늘 날씨(`weather_today`), 오늘 일정과 자리·장소 종류(`schedule_list`), 내 옷장 후보와 코디 지식(`closet_search`).
2. GPT가 "오늘은 체감 9도에 오전 면접이 있어요. 어두운 슬랙스에 셔츠, 겉옷을 추천드려요."처럼 추천하고, 앱은 카메라를 켭니다.

**2단계: 카메라를 켜 두면 자동 판단**
1. 앱이 폰 안에서 ML Kit로 옷이 잘 보이는지 보고 "조금 왼쪽으로" 같은 구도 안내를 바로 합니다(서버 안 감).
2. 옷이 잘 들어와 멈추면 그 순간 한 장을 자동으로 보냅니다. 사진은 갤러리에 저장하지 않습니다.
3. agent가 `clothes_inspect`로 옷 한 벌마다 종류·색·무늬·얼룩·찢어짐을 받고, 1단계 추천과 앞서 본 옷까지 GPT에 넘깁니다. 고른 옷끼리 색은 `outfit_color_check`로 따로 봅니다.
4. GPT가 한 벌이면 "이 남색 셔츠는 면접에 좋아요. 겉옷도 보여 주세요.", 두 벌을 나란히 놓으면 "왼쪽 흰 셔츠가 더 단정해요."처럼 답합니다.
5. "이걸로 할게"라고 하면 본 옷과 입은 날을 옷장에 기록(`closet_save`, `closet_wear`)합니다. `closet_save`가 같은 옷일 수 있다고 돌려주면 agent가 옷 부분 작은 사진 두 장을 GPT로 비교해 `closet_merge`로 합칩니다.

왼쪽·오른쪽은 바라보는 사람(사진) 기준 하나입니다. 얼룩·찢어짐은 위치보다 할 일을 먼저 말하고, 위치는 사용자가 물을 때만 말합니다. GPT 입력·출력 모양은 [contracts/README.md 5절](contracts/README.md#5-기능-구분과-agent-처리-방법)과 [AGENT_TURN.md](AGENT_TURN.md)에 있습니다.

## 일정 알림

일정을 넣을 때 알림을 받을지, 며칠 전(0~14일, 기본 전날)·몇 시에 알릴지 물어 `schedule_set_reminder`로 저장합니다(V5 `remind_time`, 비면 아침 8시). 알림은 앱이 폰의 로컬 알림으로 띄웁니다. 당일 알림은 아침 8시, 첫 일정이 9시보다 이르면 1시간 전입니다. 격식 있는 일정은 등록할 때와 3일 전 아침에 드라이클리닝을 챙겨 줍니다.

## 인터페이스

인터페이스는 [contracts/](contracts/README.md)에 정해 두었습니다(앱 API는 [openapi.yaml](contracts/openapi.yaml), MCP 도구는 [mcp-tools.md](contracts/mcp-tools.md)). 요약:

```
POST /api/v1/agent/turn   Authorization: Bearer <JWT>
1단계 { "utterance": "오늘 뭐 입지?", "location": {…} }
      → { "speech": "…추천드려요…", "next": "camera_outfit", "result": { "type": "outfit_advice", … } }
2단계 { "sessionId": "s_42", "imageKind": "outfit", "image": "<자동 전송 한 장>", "autoCaptured": true }
      → { "speech": "왼쪽 흰 셔츠가…", "next": "camera_outfit", "result": { "type": "outfit_check", … } }

MCP 도구 (배포 서버의 tools/list, 2026-11-21)
weather        weather_today, weather_forecast
schedule       schedule_add, schedule_list, schedule_delete, schedule_briefing, schedule_set_reminder
clothes-state  clothes_inspect, outfit_color_check
face-check     face_makeup_check, teeth_check
closet         closet_save, closet_wear, closet_search, closet_list, closet_outfits, closet_remove, closet_merge
```

## 개발 일정 (기록)

2026-11-04에 정한 계획입니다. 약속 정하기(11/4–11/5) → 1차 레포(agent, weather, schedule, 11/6–11/12) → 기능 넓히기(closet RAG, gateway 연결, face-check, 모델 2차 학습, 11/13–11/17) → 리허설(11/18–11/19) 순서로 진행했습니다. 그때 있던 mcp-helper는 배포에서 빠져 레포를 보관(archived)했습니다.
