# 서비스 간 약속 (인터페이스)

레포를 나눠 각자 만들기 전에 정하는 약속입니다. 여기 적힌 모양대로 만들면 마지막에 그대로 붙습니다. 바꾸고 싶으면 **코드보다 이 문서를 먼저 PR로 고치고** 담당자끼리 확인합니다.

| 파일 | 내용 |
| --- | --- |
| [README.md](README.md) (이 문서) | 공통 규칙, 서비스·포트, 인증, 오류, MCP 도구 목록, DB 나누기 |
| [openapi.yaml](openapi.yaml) | 앱 ↔ 게이트웨이 REST API (요청·응답 JSON 스키마) |
| [mcp-tools.md](mcp-tools.md) | agent ↔ MCP 서버 도구 이름과 입출력 |
| [../infra/docker-compose.yml](../infra/docker-compose.yml) | 전체를 한 번에 띄우는 뼈대 |
| [../infra/.env.example](../infra/.env.example) | 필요한 비밀 값 목록 (값은 넣지 않음) |

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

## 5. agent가 한 번의 대화를 처리하는 방법

- **옷 검사·얼굴 확인처럼 사진이 오는 요청은 정해진 순서(코드)로** 도구를 부릅니다. 발표에서 매번 같은 결과가 나와야 하기 때문입니다.
  - 옷 검사: `clothes_inspect` → (다시 찍어야 하면 바로 안내) → `closet_save` → `weather_check_outfit` + `schedule_check_outfit` → Gemini가 결과 JSON으로 안내 문장 작성
  - 얼굴 확인: `face_check` → Gemini가 안내 문장 작성
- **그 밖의 말("내일 결혼식 일정 넣어 줘", "뭐 입지?")은 Gemini가 도구를 고릅니다.**
- 사진 base64는 Gemini 대화에 넣지 않고 agent가 도구에 직접 넘깁니다. Gemini에는 도구가 돌려준 JSON만 들어갑니다.
- 확신도가 낮은 결함이 있으면 agent가 "가족에게 물어볼까요?"라고 묻고(`next: listen`), "응"이면 `helper_ask`를 부릅니다.

## 6. MCP 도구 목록

자세한 입출력은 [mcp-tools.md](mcp-tools.md)에 있습니다. 이름은 `<서버>_<동작>`으로 짓습니다.

| 서버 | 도구 | 한 줄 설명 |
| --- | --- | --- |
| mcp-weather | `weather_today` | 오늘 날씨·체감 온도·일교차·옷차림 힌트 |
| | `weather_check_outfit` | 이 옷들이 오늘 날씨에 맞는지 |
| mcp-schedule | `schedule_add` | 일정 추가 (장소 종류를 카카오 로컬로 찾아 자리 종류 결정) |
| | `schedule_list` | 날짜별 일정 |
| | `schedule_delete` | 일정 삭제 |
| | `schedule_check_outfit` | 이 옷들이 그날 일정에 맞는지 |
| mcp-clothes-state | `clothes_inspect` | 사진 → 옷 종류·색·격식·얼룩/찢어짐 위치 |
| mcp-face-check | `face_check` | 사진 → 화장 대칭, 이에 낀 것 |
| mcp-closet | `closet_save` | 본 옷을 옷장에 기록 (같은 옷이면 합침) |
| | `closet_wear` | 입은 날 기록 |
| | `closet_recommend` | 상황에 맞는 옷을 내 옷장에서 RAG로 추천 |
| mcp-helper | `helper_contacts` | 등록한 가족·친구 목록 |
| | `helper_ask` | 사진과 질문을 문자로 보내기 |
| | `helper_answer` | 답이 왔는지 확인 |

## 7. DB 나누기

PostgreSQL 하나에 **서비스마다 스키마 하나**를 둡니다. 다른 서비스 스키마를 직접 읽지 않습니다. 필요하면 그 서비스의 도구나 API를 부릅니다. 모든 테이블에 `user_id uuid`, `created_at`, `updated_at`을 둡니다.

| 스키마 | 주인 | 테이블 (초안) |
| --- | --- | --- |
| `account` | gateway | `users`(id, firebase_uid, provider), `profiles`(이름·생년월일·성별·직업·키·몸무게·agent_name, 모두 null 가능), `push_tokens` |
| `schedule` | mcp-schedule | `events`(title, start_at, place, place_category, occasion, notified_at) |
| `closet` | mcp-closet | `garments`(설명 JSONB, embedding vector(384), first_seen, last_seen), `wears`(garment_id, worn_on), `style_docs`(코디 지식 문서, embedding) |
| `helper` | mcp-helper | `contacts`(name, phone, relation), `requests`(contact_id, question, image_key, token, status, answer, expires_at) |

agent는 DB를 쓰지 않고, 대화 상태(직전 질문, 가족에게 물을지 기다리는 중 등)를 Redis에 30분 둡니다.

## 8. 첫날 체크리스트

- [ ] 이 문서와 openapi.yaml, mcp-tools.md를 같이 읽고 고칠 곳 PR로 고치기
- [ ] 버전 표 채우기
- [ ] 담당자 정하기 (README 레포 구성 표에 이름 적기)
- [ ] 각 레포에 `GET /actuator/health`만 있는 Spring Boot 뼈대 올리고 docker-compose로 같이 띄워 보기
- [ ] 학습용 옷 사진 찍기 시작 (얼룩·찢어짐·보풀, 사진마다 위치 라벨)
