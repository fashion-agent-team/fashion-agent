# 서비스 간 약속 (인터페이스)

레포를 나눠 각자 만들기 전에 정하는 약속입니다. 여기 적힌 모양대로 만들면 마지막에 그대로 붙습니다. 바꾸고 싶으면 **코드보다 이 문서를 먼저 PR로 고치고** 담당자끼리 확인합니다.

| 파일 | 내용 |
| --- | --- |
| [README.md](README.md) (이 문서) | 공통 규칙, 서비스·포트, 인증, 오류, MCP 도구 목록, DB 나누기 |
| [openapi.yaml](openapi.yaml) | 앱 ↔ 게이트웨이 REST API (요청·응답 JSON 스키마) |
| [mcp-tools.md](mcp-tools.md) | agent ↔ MCP 서버 도구 이름과 입출력 |
| [../infra/docker-compose.yml](../infra/docker-compose.yml) | 전체를 한 번에 띄우는 뼈대 |
| [../infra/.env.example](../infra/.env.example) | 필요한 비밀 값 목록 (값은 넣지 않음) |

## 아직 안 정한 것

이 문서의 나머지는 정해 둔 초안입니다. 아래만 팀이 정하면 됩니다.

- [ ] Spring Boot·Spring AI·Spring Cloud 버전 (1절 표)
- [ ] 레포별 담당자
- [ ] 배포할 서버(VM)와 도메인. helper의 가족 답장 링크 주소(`HELPER_PUBLIC_BASE_URL`)도 이걸로 정해짐
- [ ] Apple 개발자 계정: Apple 로그인, 푸시 알림(APNs), 실기기 배포에 필요 (유료, 누구 계정으로 할지)
- [ ] Firebase 프로젝트 만들 사람, 문자 발신 번호 등록(helper)
- [ ] 사용량 제한 수치(4절), 얼룩 확신도 기준 0.7(학습 후 조정)

## 1. 공통 규칙

- 언어·버전: Java 21, Spring Boot 3.x, Spring AI. **정확한 버전은 첫날 게이트웨이 담당이 하나로 정해 아래 표에 적고 모두 같은 버전을 씁니다.**

  | 항목 | 버전 |
  | --- | --- |
  | Spring Boot | (첫날 기입) |
  | Spring AI (BOM) | (첫날 기입) |
  | Spring Cloud | (첫날 기입) |

- JSON 필드 이름은 camelCase, enum 값은 소문자 영어(`top`, `smart`), 사람에게 읽어 줄 문장은 한국어.
- 시간은 ISO-8601에 시간대까지: `2026-11-20T14:00:00+09:00`. 서버 기본 시간대는 `Asia/Seoul`.
- 사진은 JPEG를 base64로 JSON에 넣습니다(지금 비전 서버와 같음). 한 장 최대 약 6MB. **사진은 어떤 서비스도 저장하지 않습니다.** 예외는 mcp-helper가 가족에게 보낼 때 R2에 24시간 두는 것 하나뿐입니다.
- 위치는 앱이 `lat`, `lon`으로 보냅니다. 권한이 없으면 서울(37.5665, 126.9780)로 보내고 `locationFallback: true`.
- 모든 서비스는 `GET /actuator/health`로 살아 있는지 알려 줍니다.
- 로그에 사진 base64, 토큰, 전화번호를 찍지 않습니다.

## 2. 서비스와 포트

로컬과 Docker Compose에서 같은 포트를 씁니다. 앱이 부르는 곳은 게이트웨이(8080) 하나뿐입니다.

| 서비스 | 레포 | 포트 | 앱에서 보이는 경로 | 비고 |
| --- | --- | --- | --- | --- |
| gateway (+ account·회원정보) | fashion-agent-gateway | 8080 | `/api/v1/auth/**`, `/api/v1/me/**` | JWT 발급·검증, 사용량 제한 |
| agent | fashion-agent-agent | 8081 | `/api/v1/agent/**` | 게이트웨이 뒤에만 있음 |
| mcp-weather | mcp-weather | 8091 | (없음) | MCP 엔드포인트 `/mcp` |
| mcp-schedule | mcp-schedule | 8092 | `/api/v1/schedules/**` (선택) | MCP `/mcp`, 알림 스케줄러 |
| mcp-clothes-state | mcp-clothes-state | 8093 | (없음) | MCP `/mcp` |
| mcp-face-check | mcp-face-check | 8094 | (없음) | MCP `/mcp` |
| mcp-closet | mcp-closet | 8095 | (없음) | MCP `/mcp` |
| mcp-helper | mcp-helper | 8096 | `/h/**` (가족 답장 웹 페이지, 로그인 없음) | MCP `/mcp` |
| postgres (+ pgvector) | - | 5432 | - | 서비스마다 스키마 하나 |
| redis | - | 6379 | - | 게이트웨이 사용량 제한, agent 대화 상태 |

MCP 서버는 Streamable HTTP로 `http://<서비스>:<포트>/mcp`를 엽니다. 서로 직접 부르지 않고, 부르는 쪽은 agent뿐입니다.

## 3. 인증

```
앱 ──Firebase 로그인(Apple·구글)──▶ Firebase ID 토큰
앱 ──POST /api/v1/auth/login {idToken}──▶ gateway: Firebase Admin으로 확인 → 우리 JWT 발급
앱 ──Authorization: Bearer <JWT>──▶ gateway: JWT 확인 → X-User-Id 헤더를 붙여 agent 등으로 전달
```

- JWT는 게이트웨이만 만들고 확인합니다(HS256, 비밀 값 `JWT_SECRET`). 액세스 토큰 1시간, 리프레시 토큰 30일.
- 클레임: `sub`(우리 사용자 id, UUID), `provider`(`apple`·`google`·`dev`), `iat`, `exp`.
- 게이트웨이는 앱이 보낸 `X-User-Id`를 **지우고** 자기가 확인한 값으로 다시 붙입니다. 뒤쪽 서비스는 `X-User-Id`를 믿고, 외부에 포트를 열지 않습니다.
- Firebase 설정 전에도 같이 개발할 수 있게 `POST /api/v1/auth/dev {deviceId}`를 둡니다. `APP_ENV=dev`일 때만 켜지고 발표 빌드에서는 꺼집니다.
- **userId는 Gemini가 정하지 않습니다.** agent가 MCP 도구를 부를 때 `X-User-Id` 값으로 덮어써서 넣습니다. 다른 사람의 옷장·일정을 읽는 일을 막기 위해서입니다.

## 4. 오류 응답

모든 서비스가 같은 모양을 씁니다(지금 비전 서버와 같음).

```json
{ "error": { "code": "image_too_large", "message": "사진이 6MB를 넘어요." } }
```

| 상태 | code 예시 | 언제 |
| --- | --- | --- |
| 400 | `bad_request`, `no_image`, `bad_image` | 요청 형식이 틀림 |
| 401 | `unauthorized`, `token_expired` | 토큰 없음·틀림·만료 (앱은 `token_expired`면 refresh 후 한 번 다시 시도) |
| 403 | `forbidden` | 남의 데이터 |
| 404 | `not_found` | 없는 일정·옷·요청 |
| 413 | `image_too_large` | 사진이 약 6MB 넘음 |
| 429 | `rate_limited` | 사용량 제한 (사용자당 분당 30회, 사진 요청은 분당 10회로 시작) |
| 502 | `upstream_failed` | Gemini·카카오·문자 등 바깥 서비스 실패 |
| 504 | `upstream_timeout` | 25초 안에 답 없음 |

앱은 200이 아니면 `message`를 읽지 않고, 정해진 한국어 안내("지금은 분석하지 못했어요. 다시 해 볼까요?")를 말합니다. `message`는 개발자용입니다.

## 5. 기능 구분과 agent 처리 방법

에이전트의 중심 기능은 **옷 추천(옷 검사)** 하나이고, 나머지는 따로 부르는 기능입니다.

| 구분 | 기능 | 쓰는 MCP 서버 | 부르는 방법 |
| --- | --- | --- | --- |
| 중심 기능 | 옷 추천 (말로 추천 → 카메라로 확인) | clothes-state, weather, schedule, closet(선택) | "오늘 뭐 입지?" → 추천을 듣고 옷을 카메라에 보여 줌 |
| 개별 기능 | 날씨 묻기 | weather | "오늘 날씨 어때?" |
| 개별 기능 | 일정 등록·확인 | schedule | "토요일 두 시에 결혼식 넣어 줘" |
| 개별 기능 | 얼굴 확인 | face-check | "얼굴 확인해 줘" → 사진 |
| 개별 기능 | 가족·친구에게 확인 요청 | helper | "엄마한테 이 옷 괜찮은지 물어봐 줘" → 사진 |

**MCP 서버는 데이터만 돌려주고, 판단과 추천은 agent가 Gemini에 맡깁니다.** 얼룩·찢어짐을 찾는 것(clothes-state 모델)까지는 데이터이고, "이 옷이 오늘 결혼식·날씨에 맞는가, 두 벌 중 무엇이 나은가"는 Gemini가 판단합니다. 데이터를 모으는 순서는 코드로 정해져 있어서(Gemini가 도구를 고르지 않음) 발표 때 매번 같게 동작합니다.

### 5-1. 옷 추천 흐름 (2단계)

사용자는 사진을 찍지 않습니다. **먼저 말로 추천을 듣고, 꺼낸 옷을 카메라에 보여 주면 알아서 판단해 줍니다.**

```
[1단계: 말로 추천]  "오늘 뭐 입지?" / "옷 추천해 줘"
  agent ─ 동시에 ─┬─ weather_today(lat, lon)
                  ├─ schedule_list(userId, 오늘)
                  └─ closet_search(userId, 상황)      ※ 선택, 옷장에 옷이 쌓인 뒤
  agent → Gemini(추천 모드) → "오늘은 체감 9도에 오전 면접이 있어요. 어두운 슬랙스에 셔츠, 겉옷을 추천드려요.
                               옷을 꺼내서 카메라에 한 벌씩 보여 주시거나, 두 벌을 나란히 놓아 주세요."
  agent: 날씨·일정·추천 내용을 세션(Redis)에 저장, 응답 next = camera_live

[2단계: 카메라 켜 두면 자동 판단]
  앱(폰 안, 실시간): ML Kit 물체 인식으로 매 순간 확인
     ├─ 옷이 없거나 잘림 → 앱이 바로 말함 "옷이 안 보여요. 폰을 조금 왼쪽으로"  (서버 안 감)
     └─ 옷이 잘 들어오고 1초 멈춤 → 그 순간 한 장을 자동 전송 (사용자는 버튼 안 누름)
  agent: clothes_inspect(image)
     └─ 어둡거나 잘렸으면 바로 다시 안내
  agent → Gemini(확인 모드): 세션의 날씨·일정·추천 + 지금 본 옷 + 앞서 본 옷들
     → 한 벌: "이 남색 셔츠는 면접에 좋아요. 겉옷도 보여 주세요."
     → 두 벌: "왼쪽 흰 셔츠가 오른쪽 체크 셔츠보다 면접에 더 단정해요."
  응답 next = camera_live (계속) … 사용자가 "이걸로 할게" / "됐어"
  agent: closet_save + closet_wear (입은 옷 기록) → 마무리 안내, next = done
```

**앱의 자동 전송 규칙** (서버 비용과 말 겹침을 막기 위해)
- 옷 박스가 화면 안에 다 들어오고 1초 동안 거의 움직이지 않을 때만 보냅니다.
- 보낸 뒤에는 서버 답을 다 읽어 줄 때까지 보내지 않고, 화면이 바뀐 뒤(옷이 빠지거나 다른 옷이 들어옴)에만 다음 장을 보냅니다. 최소 3초 간격.
- 사진은 저장하지 않습니다. 보낸 한 장도 판단이 끝나면 버립니다.

**왼쪽·오른쪽 기준: 모두 바라보는 사람(사진) 기준 하나**
- 옷은 내려놓고 위에서 비추므로, 폰 뒷면 카메라가 옷을 향하면 **사진의 왼쪽 = 사용자의 왼쪽**입니다. 옷끼리 비교(`position`)도, 얼룩 위치(`where`)도 이 기준 하나만 씁니다.
- 비교할 때는 위치만 말하지 않고 색·종류를 붙입니다("왼쪽 흰 셔츠"). 사용자가 만져 보고 한 번 더 확인할 수 있게 하기 위해서입니다.

**얼룩·찢어짐은 "어디"보다 "어떻게 할지"를 말합니다**
- 시각장애인이 위치를 듣고 얼룩을 직접 지우기는 어렵습니다. 그래서 안내는 **할 일 먼저**: "흰 셔츠에 얼룩이 있어요. 오늘은 다른 셔츠로 바꾸고, 이건 빨래하는 게 좋겠어요."
- 할 일(`action`): 얼룩 → `wash`(빨기) + 다른 옷으로 바꾸기, 찢어짐 → `repair`(수선) + 바꾸기, 보풀 → `ok`(입어도 됨, 신경 쓰이면 보풀 제거), 확실하지 않음 → `check`("얼룩일 수도 있어요. 중요한 자리면 다른 옷이 안전해요").
- 1단계에서 추천한 옷이나 옷장에 대신 입을 만한 옷이 있으면 같이 말합니다("옷장의 남색 셔츠로 바꾸면 좋겠어요").
- 위치는 기본으로 말하지 않고, 사용자가 "어디야?"라고 물을 때만 말합니다(가족에게 부탁하거나 찢어진 곳을 손으로 찾을 때 필요). agent가 직전 판단의 `where`를 세션에 들고 있습니다.

**Gemini 판단 기준** (두 모드 공통, 시스템 프롬프트, 앱의 `lib/styling/` 규칙을 옮긴 것)
- 자리: 장례(검정·무채색, 화려한 무늬 피하기), 결혼식(흰색 상의 피하기, 단정하게), 면접·발표(formal·smart), 회의·출근(sporty 피하기), 운동(sporty).
- 날씨: 체감 20도 미만이면 겉옷, 일교차 10도 이상이면 겉옷 챙기기, 강수 50% 이상이면 우산, 더운 날 두꺼운 소재 주의.
- 얼룩·찢어짐: 확신도 0.7 이상은 할 일(빨기·수선·바꾸기)과 대신 입을 옷을 말하고, 0.7 미만은 `check`(확실하지 않으니 중요한 자리면 바꾸기). 위치는 묻기 전엔 말하지 않기.
- 옷장 추천은 `closetCandidates` 안의 옷만. 없는 옷을 지어내지 않기.
- 말투: 존댓말, 이유를 붙여서, 3문장 이내(듣는 중에 옷을 바꾸므로 짧게).
- 구조화 출력(responseSchema)으로 받고 `temperature`는 0.2.

**1단계 Gemini 입력 → 출력 (추천 모드)**

```json
// 입력 (사진 없음)
{ "weather": { "apparentTemperature": 9.5, "dailyRange": 11, "precipitationProbability": 10, "condition": "맑음" },
  "events": [{ "title": "면접", "start": "2026-11-04T10:00:00+09:00", "placeCategory": "회사", "occasion": "formal" }],
  "closetCandidates": [{ "garmentId": "c_21", "category": "outer", "name": "자켓", "colorName": "회색", "formality": "smart" }],
  "styleNotes": ["면접에는 어두운 색 슬랙스와 셔츠, 단정한 자켓이 무난하다"],
  "profile": { "job": "대학생" } }

// 출력
{ "suggestions": [
    { "category": "top",    "text": "셔츠나 단정한 니트",  "reason": "면접이라 단정한 상의가 좋아요." },
    { "category": "bottom", "text": "어두운 색 슬랙스",    "reason": "청바지보다 격식 있어 보여요." },
    { "category": "outer",  "text": "자켓",               "reason": "일교차가 11도라 겉옷이 필요해요." } ],
  "closetPicks": [{ "garmentId": "c_21", "reason": "옷장에 있는 회색 자켓이 잘 맞아요." }],
  "speech": "오늘은 체감 9도에 오전 면접이 있어요. 어두운 슬랙스에 셔츠, 겉옷으로 옷장의 회색 자켓을 추천드려요. 옷을 꺼내서 카메라에 보여 주세요." }
```

**2단계 Gemini 입력 → 출력 (확인 모드)**

```json
// 입력: 세션에 저장한 1단계 입력·출력 + 아래
{ "now": [Garment(position 포함), ...],
  "seenBefore": [{ "garmentId": "g_s1", "name": "슬랙스", "colorName": "남색", "verdict": "good" }] }

// 출력
{ "verdicts": [
    { "inputId": "g1", "position": "left",  "fit": "good", "notes": ["면접에 단정해 보여요."] },
    { "inputId": "g2", "position": "right", "fit": "bad",  "notes": ["체크무늬는 면접에 조금 가벼워 보여요."] } ],
  "comparison": { "betterInputId": "g1", "reason": "흰 셔츠가 면접에 더 단정해요." },
  "damage": [{ "inputId": "g1", "kind": "stain", "action": "wash", "where": "오른쪽 소매 끝", "say": "흰 셔츠에 얼룩이 있어요. 오늘은 체크 말고 다른 셔츠로 바꾸고, 흰 셔츠는 빨래하는 게 좋겠어요." }],
  "stillMissing": ["outer"],
  "speech": "왼쪽 흰 셔츠가 오른쪽 체크 셔츠보다 면접에 더 단정해요. 그런데 흰 셔츠에 얼룩이 있어서 빨래하는 게 좋겠어요. 다른 단정한 셔츠가 있으면 보여 주세요." }
```
`fit`: good | ok | bad. 한 벌만 보이면 `comparison`은 null.

Gemini가 실패하거나 25초 안에 답이 없으면 agent는 `clothes_inspect` 결과만으로 짧게 말합니다("흰 셔츠가 보여요. 지금은 판단을 못 했어요. 다시 보여 주세요.").

### 5-2. 개별 기능

- 얼굴 확인도 같은 방식(카메라 켜 두면 앱이 얼굴 구도를 실시간 안내, 잘 들어오면 한 장 자동 전송) → `face_check` → Gemini가 안내 문장 작성.
- 그 밖의 말(날씨 묻기, 일정 등록, 가족에게 묻기)은 **Gemini가 도구를 고릅니다.** 옷 추천 흐름과 섞지 않습니다.
- 가족에게 묻기는 사용자가 원할 때만 합니다. 사진은 직전에 자동 전송된 한 장을 agent가 Redis에 10분 들고 있다가 넘깁니다.

### 5-3. 공통

- 사진 base64는 Gemini 대화에 넣지 않고 agent가 도구에 직접 넘깁니다. Gemini에는 도구가 돌려준 JSON만 들어갑니다.

## 6. MCP 도구 목록

자세한 입출력은 [mcp-tools.md](mcp-tools.md)에 있습니다. 이름은 `<서버>_<동작>`으로 짓습니다.

| 서버 | 도구 | 한 줄 설명 | 쓰는 곳 |
| --- | --- | --- | --- |
| mcp-clothes-state | `clothes_inspect` | 사진 → 옷 종류·색·격식·위치(left·center·right)·얼룩/찢어짐 | 옷 추천 2단계 |
| mcp-weather | `weather_today` | 오늘 기온·체감·일교차·강수 | 옷 추천 1단계, 날씨 묻기 |
| mcp-schedule | `schedule_list` | 날짜별 일정과 장소 종류 | 옷 추천 1단계, 일정 |
| | `schedule_add` | 일정 추가 (장소 종류를 카카오 로컬로 찾음) | 일정 |
| | `schedule_delete` | 일정 삭제 | 일정 |
| mcp-closet | `closet_search` | 상황에 맞는 내 옷 후보 + 코디 지식 검색 (RAG의 검색 단계) | 옷 추천 1단계(선택) |
| | `closet_save` | 본 옷을 옷장에 기록 (같은 옷이면 합침) | 옷 추천 마무리 |
| | `closet_wear` | 입은 날 기록 | 옷 추천 마무리 ("이걸로 할게") |
| mcp-face-check | `face_check` | 사진 → 화장 대칭, 이에 낀 것 | 얼굴 확인 |
| mcp-helper | `helper_contacts` | 등록한 가족·친구 목록 | 가족에게 묻기 |
| | `helper_ask` | 사진과 질문을 문자로 보내기 | 가족에게 묻기 |
| | `helper_answer` | 답이 왔는지 확인 | 가족에게 묻기 |

## 7. DB 나누기

PostgreSQL 하나에 **서비스마다 스키마 하나**를 둡니다. 다른 서비스 스키마를 직접 읽지 않습니다. 필요하면 그 서비스의 도구나 API를 부릅니다. 모든 테이블에 `user_id uuid`, `created_at`, `updated_at`을 둡니다.

| 스키마 | 주인 | 테이블 (초안) |
| --- | --- | --- |
| `account` | gateway | `users`(id, firebase_uid, provider), `profiles`(이름·생년월일·성별·직업·키·몸무게·agent_name, 모두 null 가능), `push_tokens` |
| `schedule` | mcp-schedule | `events`(title, start_at, place, place_category, occasion, notified_at) |
| `closet` | mcp-closet | `garments`(설명 JSONB, embedding vector(384), first_seen, last_seen), `wears`(garment_id, worn_on), `style_docs`(코디 지식 문서, embedding) |
| `helper` | mcp-helper | `contacts`(name, phone, relation), `requests`(contact_id, question, image_key, token, status, answer, expires_at) |

agent는 DB를 쓰지 않고, 대화 상태(직전 질문, 직전 사진 10분 등)를 Redis에 30분 둡니다.

## 8. 첫날 체크리스트

- [ ] 이 문서와 openapi.yaml, mcp-tools.md를 같이 읽고 고칠 곳 PR로 고치기
- [ ] 버전 표 채우기
- [ ] 담당자 정하기 (README 레포 구성 표에 이름 적기)
- [ ] 각 레포에 `GET /actuator/health`만 있는 Spring Boot 뼈대 올리고 docker-compose로 같이 띄워 보기
- [ ] 학습용 옷 사진 찍기 시작 (얼룩·찢어짐·보풀, 사진마다 위치 라벨)
