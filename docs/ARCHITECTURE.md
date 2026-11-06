# 패션 에이전트 아키텍처

2026-11-04 기준. 그림은 [architecture.pdf](architecture.pdf)(4쪽: 구조도, 요청 흐름, 레포별 기술, 시작 순서)를 보세요.

앱은 HTTPS로 API Gateway 하나만 부릅니다. 백엔드는 Java · Spring Boot이고, agent가 GPT로 할 일을 골라 기능별 MCP 서버를 부릅니다. 사진 분석(옷 상태, 얼굴 확인)은 우리가 학습한 모델과 이미 학습된 모델을 서버에서 직접 돌려 호출 비용을 줄이고, 옷장 추천은 RAG로 합니다.

```
앱 (Flutter: 음성·카메라·ML Kit 얼굴 윤곽)
  └─ HTTPS · REST · JWT ─▶ API Gateway (Spring Cloud Gateway + Redis 사용량 제한)
                            ├─ account · 회원정보 (Spring Security, Firebase 토큰 검증, JPA)
                            └─ agent (Spring AI ChatClient + MCP 클라이언트, GPT · OpenAI)
                                 ├─ mcp-weather        Open-Meteo
                                 ├─ mcp-schedule       카카오 로컬 API, FCM
                                 ├─ mcp-clothes-state  YOLO(자체 학습) + FashionCLIP, ONNX / 애매하면 지인 확인(GPT 안 씀)
                                 ├─ mcp-face-check     윤곽점 대칭 규칙 + 치아 분류 모델(자체 학습)
                                 ├─ mcp-closet         RAG: pgvector + e5 임베딩 + GPT 답변
                                 └─ mcp-helper         문자 + 답장용 웹 링크, R2 임시 사진
DB: PostgreSQL + pgvector (계정, 회원정보, 일정, 옷장, 지인, 확인 요청 기록, RAG 벡터)
배포: Docker Compose, VM 한 대
```

## 레포별 기술 스택

| 구성요소 | 레포 | 기술 스택 | 고른 이유 | 대안 |
| --- | --- | --- | --- | --- |
| 앱 | fashion-agent | Flutter, speech_to_text, flutter_tts, camera(이미지 스트림), ML Kit 물체 인식(옷 구도 실시간 안내·자동 전송)·얼굴 인식, Firebase Auth SDK, FCM | 이미 동작 중. 기기 음성은 무료이고 VoiceOver 목소리와 같음 | Google Cloud STT/TTS, 네이버 CLOVA |
| API Gateway | fashion-agent-gateway | Spring Cloud Gateway, Redis 사용량 제한 | 라우팅·JWT 필터·사용량 제한을 설정으로 처리 | Nginx, 발표 전엔 agent에 Spring Security만 |
| account · 회원정보 | fashion-agent-gateway | Spring Security, Firebase Admin(ID 토큰 검증), Spring Data JPA | Apple·구글 로그인과 기기 이전용 계정 연결은 Firebase가, 서버는 확인만 ([ACCOUNT.md](ACCOUNT.md)) | OAuth2 + 자체 JWT, Keycloak |
| agent | fashion-agent-agent | Spring AI ChatClient(OpenAI), MCP 클라이언트, GPT, ChatMemory | MCP 서버와 같은 프레임워크, 서버 목록만 적으면 도구가 붙음. 모델만 바꿀 땐 설정 몇 줄 | LangChain4j, OpenAI Java SDK 직접 |
| MCP 공통 | mcp-* | Spring AI MCP Server (Streamable HTTP, `@Tool`) | 메서드에 어노테이션만 붙이면 도구가 됨 | MCP Java SDK 직접 |
| weather | mcp-weather | Open-Meteo, RestClient, Caffeine 캐시 | 키 없음, 앱에서 이미 검증 | 기상청 단기예보 API, OpenWeatherMap |
| schedule | mcp-schedule | 카카오 로컬 API, FCM, `@Scheduled` | 국내 장소 카테고리(예식장·장례식장)가 정확, 알림 무료 | 네이버 지역 검색 + 폰 로컬 알림, Google Places |
| clothes_state | mcp-clothes-state | 얼룩·찢어짐·보풀: YOLO 파인튜닝 / 종류·격식: FashionCLIP / 색: 픽셀 평균 → 색 이름 규칙 / 실행: ONNX Runtime Java / 애매하면(0.5~0.6) 지인 확인, 옷 사진은 GPT로 보내지 않음 | 호출 비용 없이 서버 CPU로 동작, 결함 위치가 박스로 나옴 | Python FastAPI 추론 서버, 앱 안 Core ML·TFLite |
| face_makeup_check, teeth_check (얼굴/치아 나눠 물음) | mcp-face-check | 앱 ML Kit 윤곽점 → 대칭 규칙(눈썹·입술 위치, 볼·입술 색 좌우 비교) + 치아 이물질 분류(MobileNet 파인튜닝, ONNX) | 대칭은 계산, 학습은 치아 분류 하나. 얼굴 사진은 외부 AI로 보내지 않음(애매하면 helper 제안) | MediaPipe Face Landmarker(Python), 전부 앱 안 TFLite |
| closet | mcp-closet | RAG: Spring AI VectorStore + pgvector, multilingual-e5-small(ONNX) 임베딩, GPT 답변. 검색 대상은 내 옷 설명 + 코디 지식 문서 | 가진 옷 안에서만, 근거를 붙여 추천. 같은 옷 중복 찾기도 같은 벡터로 | OpenAI 임베딩 API, Qdrant·Chroma |
| helper | mcp-helper | 문자(솔라피, 링크만 넣은 SMS), 답장용 웹 링크, Cloudflare R2(24시간 뒤 삭제) | 가족은 앱 설치 없이 링크로 답함, 카카오 심사 불필요, 개인 계정 가능, SMS 한 통 18원 | 네이버 클라우드 SENS·NHN Cloud SMS(사업자 회원만, 설정으로 바꿈), 카카오 알림톡, 같은 앱 도우미 모드 + FCM |
| 모델 학습 | 각 mcp 레포 `training/` | Python, Ultralytics YOLO, Roboflow 라벨링, Google Colab GPU, ONNX 내보내기 | 학습은 Python이 표준, ONNX면 Java에서 그대로 실행 | 개인 GPU, SageMaker |
| DB | (공용) | PostgreSQL + pgvector | 관계 데이터와 RAG 벡터를 한 DB에 | MySQL + 별도 벡터 DB |
| 배포 | (공용) | Docker Compose, VM 한 대(8GB 이상), Nginx/Caddy HTTPS | 서비스 전부를 파일 하나로 | Cloud Run, Kubernetes(발표 후) |

비밀 값(OpenAI 키, DB 비밀번호, 문자 키)은 서버 환경 변수(.env, 커밋 금지)에만 둡니다.

**학습 데이터**: 공개 원단 결함 데이터(AITEX 등)는 공장 원단 사진이라 펼쳐 놓은 옷과 다릅니다. 우리 옷 사진을 직접 찍어 라벨링합니다(결함 종류마다 수백 장 목표). 모델이 준비될 때까지 지금 배포된 옷 분석 서버(Cloudflare Worker)를 데모용 예비로 둡니다. 이 서버는 아직 Gemini를 부르므로 GPT 비전으로 옮겨야 합니다. Ultralytics는 AGPL 라이선스라 상용화 전에 다시 확인합니다.

## 기능 구분

중심 기능은 **옷 추천** 하나입니다. MCP 서버들은 데이터만 돌려주고, agent가 모은 데이터를 GPT에 넘겨 판단과 추천을 맡깁니다. 날씨 묻기, 일정 등록, 얼굴 확인(face-check), 가족·친구에게 확인 요청(helper)은 따로 부르는 개별 기능입니다.

## 옷 추천 흐름 (2단계)

사용자는 사진을 찍지 않습니다. 먼저 말로 추천을 듣고, 자기 방식대로 꺼낸 옷을 카메라에 보여 주면 알아서 판단해 줍니다.

**1단계: 말로 추천** ("오늘 뭐 입지?")
1. agent가 동시에 데이터를 모읍니다: 오늘 날씨(`weather_today`), 오늘 일정과 장소 종류(`schedule_list`), (선택) 내 옷장 후보와 코디 지식(`closet_search`, RAG 검색).
2. GPT가 "오늘은 체감 9도에 오전 면접이 있어요. 어두운 슬랙스에 셔츠, 겉옷을 추천드려요."처럼 추천하고, 앱은 카메라를 켭니다.

**2단계: 카메라 켜 두면 자동 판단**
1. 앱이 폰 안에서 ML Kit로 매 순간 옷이 잘 보이는지 확인하고 "조금 왼쪽으로" 같은 구도 안내를 바로 합니다(서버 안 감, 비용 없음).
2. 옷이 잘 들어와 1초 멈추면 그 순간 한 장을 자동으로 보냅니다. 사용자는 버튼을 누르지 않고, 사진은 저장하지 않습니다.
3. agent가 `clothes_inspect`로 옷 종류·색·격식·위치·얼룩을 받고, 1단계 추천과 앞서 본 옷까지 GPT에 넘깁니다.
4. GPT가 한 벌이면 "이 남색 셔츠는 면접에 좋아요. 겉옷도 보여 주세요.", 두 벌을 나란히 놓으면 "왼쪽 흰 셔츠가 더 단정해요."처럼 답합니다.
5. "이걸로 할게"라고 하면 본 옷과 입은 날을 옷장에 기록(`closet_save`, `closet_wear`)하고 마칩니다.

왼쪽·오른쪽은 바라보는 사람(사진) 기준 하나입니다. 얼룩·찢어짐은 위치보다 할 일을 먼저 말합니다("얼룩이 있어요. 다른 셔츠로 바꾸고 이건 빨래하세요"). 위치는 사용자가 물을 때만 말합니다. GPT 입력·출력 모양은 [contracts/README.md 5절](contracts/README.md#5-기능-구분과-agent-처리-방법)에 있습니다.

**나중에(발표 후)**: 학습한 얼룩 모델을 Core ML로 바꿔 폰 안에서 돌리면 얼룩 찾기까지 실시간이 됩니다.

## 시작 순서 (제안)

한 명이 레포 하나씩 맡습니다. 1차 배분(2026-11-04): agent 이진행, mcp-weather 박창근, mcp-schedule 정지원(임시, 바꿔도 됨). 끝나면 다음 레포를 나눕니다. agent는 게이트웨이 없이 `X-User-Id` 헤더로 직접 호출하며 개발합니다.

| 기간 | 단계 | 할 일 |
| --- | --- | --- |
| 11/4 – 11/5 | 0. 약속 정하기 | 앱 ↔ 게이트웨이 API 모양, MCP 도구 이름·입출력, JWT에 담을 값, Docker Compose 뼈대, 학습용 사진 찍기·라벨링 시작 |
| 11/6 – 11/12 | 1. 1차 레포 | agent + mcp-weather + mcp-schedule(일정 조회)로 1단계 말 추천 완성. 끝나는 대로 게이트웨이 + account, clothes-state 모델 1차 학습 + MCP 서버 |
| 11/13 – 11/17 | 2. 기능 넓히기 | mcp-closet RAG(옷 추천에 붙이기), 앱 연결 주소를 게이트웨이로, 개별 기능(face-check, helper), 모델 2차 학습 |
| 11/18 – 11/19 | 3. 리허설 | 실제 아이폰으로 처음부터 끝까지, 예비 서버 전환 확인, 발표 시나리오 녹화 |

인터페이스는 [contracts/](contracts/README.md)에 정해 두었습니다(앱 API는 [openapi.yaml](contracts/openapi.yaml), MCP 도구는 [mcp-tools.md](contracts/mcp-tools.md), 전체 실행 뼈대는 [infra/](infra/docker-compose.yml)). 요약:

```
POST /api/v1/agent/turn   Authorization: Bearer <JWT>
1단계 { "utterance": "오늘 뭐 입지?", "location": {…} }
      → { "speech": "…추천드려요…", "next": "camera_outfit", "result": { "type": "outfit_advice", … } }
2단계 { "sessionId": "s_42", "imageKind": "outfit", "image": "<자동 전송 한 장>", "autoCaptured": true }
      → { "speech": "왼쪽 흰 셔츠가…", "next": "camera_outfit", "result": { "type": "outfit_check", … } }

1단계 데이터: weather_today, schedule_list, closet_search(선택) → GPT(추천 모드) → { suggestions, closetPicks, speech }
2단계 데이터: clothes_inspect(한 장)                         → GPT(확인 모드) → { verdicts, comparison, damage, stillMissing, speech }

개별 기능
face_makeup_check(image, landmarks) 또는 teeth_check(image, mouthBox) / schedule_add(…) / helper_ask(userId, contactId, image, question)
```
