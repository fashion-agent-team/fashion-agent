# 패션 에이전트 아키텍처

2026-11-04 기준. 그림은 [architecture.pdf](architecture.pdf)(4쪽: 구조도, 요청 흐름, 레포별 기술, 시작 순서)를 보세요.

앱은 HTTPS로 API Gateway 하나만 부릅니다. 백엔드는 Java · Spring Boot이고, agent가 Gemini로 할 일을 골라 기능별 MCP 서버를 부릅니다. 사진 분석(옷 상태, 얼굴 확인)은 우리가 학습한 모델과 이미 학습된 모델을 서버에서 직접 돌려 호출 비용을 줄이고, 옷장 추천은 RAG로 합니다.

```
앱 (Flutter: 음성·카메라·ML Kit 얼굴 윤곽)
  └─ HTTPS · REST · JWT ─▶ API Gateway (Spring Cloud Gateway + Redis 사용량 제한)
                            ├─ account · 회원정보 (Spring Security, Firebase 토큰 검증, JPA)
                            └─ agent (Spring AI ChatClient + MCP 클라이언트, Gemini 3.5 Flash)
                                 ├─ mcp-weather        Open-Meteo
                                 ├─ mcp-schedule       카카오 로컬 API, FCM
                                 ├─ mcp-clothes-state  YOLO(자체 학습) + FashionCLIP, ONNX / 애매하면 Gemini
                                 ├─ mcp-face-check     윤곽점 대칭 규칙 + 치아 분류 모델(자체 학습)
                                 ├─ mcp-closet         RAG: pgvector + e5 임베딩 + Gemini 답변
                                 └─ mcp-helper         문자 + 답장용 웹 링크, R2 임시 사진
DB: PostgreSQL + pgvector (계정, 회원정보, 일정, 옷장, 지인, 확인 요청 기록, RAG 벡터)
배포: Docker Compose, VM 한 대
```

## 레포별 기술 스택

| 구성요소 | 레포 | 기술 스택 | 고른 이유 | 대안 |
| --- | --- | --- | --- | --- |
| 앱 | fashion-agent | Flutter, speech_to_text, flutter_tts, camera, Firebase Auth SDK, FCM, ML Kit 얼굴 인식 | 이미 동작 중. 기기 음성은 무료이고 VoiceOver 목소리와 같음 | Google Cloud STT/TTS, 네이버 CLOVA |
| API Gateway | fashion-agent-gateway | Spring Cloud Gateway, Redis 사용량 제한 | 라우팅·JWT 필터·사용량 제한을 설정으로 처리 | Nginx, 발표 전엔 agent에 Spring Security만 |
| account · 회원정보 | fashion-agent-gateway | Spring Security, Firebase Admin(ID 토큰 검증), Spring Data JPA | Apple·구글 로그인과 기기 이전용 계정 연결은 Firebase가, 서버는 확인만 ([ACCOUNT.md](ACCOUNT.md)) | OAuth2 + 자체 JWT, Keycloak |
| agent | fashion-agent-agent | Spring AI ChatClient, MCP 클라이언트, Gemini 3.5 Flash, ChatMemory | MCP 서버와 같은 프레임워크, 서버 목록만 적으면 도구가 붙음 | LangChain4j, Google Gen AI Java SDK |
| MCP 공통 | mcp-* | Spring AI MCP Server (Streamable HTTP, `@Tool`) | 메서드에 어노테이션만 붙이면 도구가 됨 | MCP Java SDK 직접 |
| weather | mcp-weather | Open-Meteo, RestClient, Caffeine 캐시 | 키 없음, 앱에서 이미 검증 | 기상청 단기예보 API, OpenWeatherMap |
| schedule | mcp-schedule | 카카오 로컬 API, FCM, `@Scheduled` | 국내 장소 카테고리(예식장·장례식장)가 정확, 알림 무료 | 네이버 지역 검색 + 폰 로컬 알림, Google Places |
| clothes_state | mcp-clothes-state | 얼룩·찢어짐·보풀: YOLO 파인튜닝 / 종류·격식: FashionCLIP / 색: 픽셀 평균 → 색 이름 규칙 / 실행: ONNX Runtime Java / 폴백: Gemini | 호출 비용 없이 서버 CPU로 동작, 결함 위치가 박스로 나옴 | Python FastAPI 추론 서버, 앱 안 Core ML·TFLite |
| face_check | mcp-face-check | 앱 ML Kit 윤곽점 → 대칭 규칙(눈썹·입술 위치, 볼·입술 색 좌우 비교) + 치아 이물질 분류(MobileNet 파인튜닝, ONNX) | 대칭은 계산, 학습은 치아 분류 하나 | MediaPipe Face Landmarker(Python), 전부 앱 안 TFLite |
| closet | mcp-closet | RAG: Spring AI VectorStore + pgvector, multilingual-e5-small(ONNX) 임베딩, Gemini Flash 답변. 검색 대상은 내 옷 설명 + 코디 지식 문서 | 가진 옷 안에서만, 근거를 붙여 추천. 같은 옷 중복 찾기도 같은 벡터로 | Gemini 임베딩 API, Qdrant·Chroma |
| helper | mcp-helper | 문자(NHN Cloud SMS 또는 솔라피), 답장용 웹 링크, Cloudflare R2(24시간 뒤 삭제) | 가족은 앱 설치 없이 링크로 답함, 카카오 심사 불필요 | 카카오 알림톡, 같은 앱 도우미 모드 + FCM |
| 모델 학습 | 각 mcp 레포 `training/` | Python, Ultralytics YOLO, Roboflow 라벨링, Google Colab GPU, ONNX 내보내기 | 학습은 Python이 표준, ONNX면 Java에서 그대로 실행 | 개인 GPU, SageMaker |
| DB | (공용) | PostgreSQL + pgvector | 관계 데이터와 RAG 벡터를 한 DB에 | MySQL + 별도 벡터 DB |
| 배포 | (공용) | Docker Compose, VM 한 대(8GB 이상), Nginx/Caddy HTTPS | 서비스 전부를 파일 하나로 | Cloud Run, Kubernetes(발표 후) |

비밀 값(Gemini 키, DB 비밀번호, 문자 키)은 서버 환경 변수(.env, 커밋 금지)에만 둡니다.

**학습 데이터**: 공개 원단 결함 데이터(AITEX 등)는 공장 원단 사진이라 펼쳐 놓은 옷과 다릅니다. 우리 옷 사진을 직접 찍어 라벨링합니다(결함 종류마다 수백 장 목표). 모델이 준비될 때까지 지금 배포된 Gemini 옷 분석 서버를 데모용 예비로 둡니다. Ultralytics는 AGPL 라이선스라 상용화 전에 다시 확인합니다.

## "옷 검사해 줘" 요청 흐름

1. 앱이 말을 글자로 바꾸고(STT), 펼쳐 놓은 옷을 찍습니다.
2. `POST /outfit-check`로 글자·사진·토큰을 보내면 게이트웨이가 토큰과 사용량을 확인하고 agent로 넘깁니다.
3. agent가 Gemini에 도구 목록을 주고 고르게 합니다(예: weather, schedule, clothes_state).
4. MCP 서버들이 오늘 날씨, 오늘 일정과 장소 종류, 옷 상태(YOLO가 찾은 얼룩 위치 포함)를 돌려줍니다.
5. 우리 모델의 확신도가 낮으면 그 사진만 Gemini에 다시 묻고, 그래도 애매하면 가족에게 물을지 묻습니다(mcp-helper).
6. agent가 결과를 한국어 문장으로 정리하면 앱이 읽어 줍니다.

## 시작 순서 (제안)

한 명이 레포 하나씩 맡되, 데모 경로부터 시작합니다.

| 기간 | 단계 | 할 일 |
| --- | --- | --- |
| 11/4 – 11/5 | 0. 약속 정하기 | 앱 ↔ 게이트웨이 API 모양, MCP 도구 이름·입출력, JWT에 담을 값, Docker Compose 뼈대, 학습용 사진 찍기·라벨링 시작 |
| 11/6 – 11/12 | 1. 데모 경로 | 게이트웨이 + account, agent + mcp-weather, clothes-state 모델 1차 학습 + MCP 서버, 앱 연결 주소를 게이트웨이로 |
| 11/13 – 11/17 | 2. 기능 넓히기 | mcp-schedule(음성 일정 등록), mcp-closet RAG, face-check, 모델 2차 학습, 얼룩 위치 왼쪽·오른쪽 기준 |
| 11/18 – 11/19 | 3. 리허설 | 실제 아이폰으로 처음부터 끝까지, 예비 서버 전환 확인, 발표 시나리오 녹화 |

인터페이스는 [contracts/](contracts/README.md)에 정해 두었습니다(앱 API는 [openapi.yaml](contracts/openapi.yaml), MCP 도구는 [mcp-tools.md](contracts/mcp-tools.md), 전체 실행 뼈대는 [infra/](infra/docker-compose.yml)). 요약:

```
POST /outfit-check   Authorization: Bearer <JWT>
{ "utterance": "옷 검사해 줘", "image": "<base64 JPEG>" }
→ { "speech": "면접이라 슬랙스가 좋아요. ...", "garments": [ ...ClothesScan... ], "needsHelper": false }

weather.today(lat, lon)          → { feelsLike, min, max, rainProb }
schedule.today(uid)              → [{ title, time, placeType }]
clothes_state.inspect(image)     → ClothesScan + source: model|gemini
closet.recommend(uid, situation) → [{ garmentId, reason }]
helper.ask(uid, imageRef, q)     → { requestId }
```
