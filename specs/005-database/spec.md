# Feature Specification: 데이터베이스 통합 설계와 구축

**Feature Branch**: `(브랜치 없음, claude/project-thread-845dxs에서 docs 정리)`

**Created**: 2026-11-04

**Status**: Draft (팀 리뷰 대기)

**Input**: User description: "구조 바꾸고 db설계도 지금까지 요구사항 통합해서 speckit으로 데이터베이스 구축해줘" + "gemini 빼버리고 gpt로 가자"

**주인 서비스**: gateway(`account`), mcp-schedule(`schedule`), mcp-closet(`closet`), mcp-helper(`helper`), agent·gateway(Redis) · 근거: `docs/contracts/` 7절, specs 001~004, `docs/infra/DB.md`(PR #14), mcp-schedule `V1__init.sql`(mcp-schedule#3)

## 이 spec이 하는 일

지금까지 흩어져 있던 요구사항(온보딩·계정, 일정, 옷장·개인화, 가족 확인, 옷 추천 2단계의 대화 상태, GPT 전환)을 **저장 관점에서 하나로 모으고**, 서비스마다 바로 넣을 수 있는 마이그레이션 SQL로 만든다. 기능 자체의 동작은 001~004 spec이 맡고, 이 spec은 "무엇을 어디에 어떤 규칙으로 저장하는가"만 다룬다.

## 요구사항을 모은 출처

| 날짜 | 요구사항 | 저장에 주는 영향 |
| --- | --- | --- |
| 10-30 | 음성 온보딩: 이름·생년월일·성별·직업·키·몸무게, 민감한 항목은 건너뛰기, 에이전트 이름 짓기 | `account.profiles` 모두 null 가능, `agent_name`이 있으면 온보딩 끝 |
| 10-30 | Firebase + Apple(아이폰)·구글(안드로이드) 로그인, 계정 연결로 기기 이전 | `account.users.firebase_uid` 하나로 같은 사람. 기기 이전에 서버 데이터 이동 없음 |
| 10-30 | 별도 옷 등록 없음, 쓸수록 사용자별 옷 데이터가 쌓여 개인화(학습 아님) | `closet.garments`(본 옷 자동 기록, 같은 옷 합치기), `closet.wears`(입은 날) |
| 10-30 | 일정에 맞는 옷, 당일 알림 | `schedule.events`(자리 종류, 알림 보낸 시각), `account.push_tokens` |
| 11-04 | 사진은 저장하지 않음(가족 확인 사진만 24시간) | 사진 컬럼 없음. `helper.requests.image_key`는 R2 키만 |
| 11-04 | 서비스마다 스키마 하나, 다른 스키마 직접 읽기 금지 | 스키마를 넘는 FK 없음, `user_id`는 값만 같음 |
| 11-04 | mcp-closet은 RAG(pgvector + multilingual-e5) | `vector(384)`, 코디 지식은 Spring AI VectorStore 표 모양 |
| 11-04 | 옷 추천 2단계: 1단계 추천을 들고 2단계에서 보여 준 옷 판단, 직전 사진 10분 | agent는 DB 없이 Redis 세션 30분 |
| 11-04 | 일정 자리 종류는 제목 → 장소 → 평상 (앱 PR #15) | `occasion_source`에 title·place·default 기록 |
| 11-04 | 판단 LLM을 Gemini에서 GPT로 전부 바꿈 | DB 변화 없음. 임베딩은 서버 안 e5 모델이라 LLM과 무관 (research R5) |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 서비스 담당자가 자기 스키마를 바로 띄운다 (Priority: P1)

mcp-closet 담당자가 `docs/infra/db/closet/V1__init.sql`을 레포에 복사하고 Flyway 설정 세 줄을 넣으면, 서비스가 처음 뜰 때 `closet` 스키마와 표가 만들어진다.

**Why this priority**: 표가 없으면 일정·옷장·가족 확인 어느 것도 저장할 수 없다. 담당자마다 따로 만들면 이름과 규칙이 어긋난다.

**Independent Test**: 빈 PostgreSQL에서 search_path를 그 스키마 하나로만 두고 V1을 실행해 성공하는지 본다.

**Acceptance Scenarios**:

1. **Given** 빈 DB, **When** 각 서비스의 V1을 따로 실행하면, **Then** 다른 서비스 파일 없이도 성공한다.
2. **Given** 네 서비스의 V1, **When** 한 DB에 모두 실행하면, **Then** 표 10개가 생기고 스키마를 넘는 FK는 0개다.
3. **Given** 이미 머지된 V1, **When** 표를 바꿔야 하면, **Then** V1을 고치지 않고 V2를 더한다.

---

### User Story 2 - 사용자의 데이터가 섞이지 않고 쌓인다 (Priority: P1)

시각장애인 사용자가 옷 추천을 여러 번 쓰면 본 옷과 입은 날이 쌓이고, 다음 추천에서 "옷장의 회색 자켓"처럼 내 옷으로 추천받는다. 다른 사람의 옷·일정·연락처는 어떤 경로로도 섞이지 않는다.

**Why this priority**: 개인화 추천이 이 앱의 차별점이고, 남의 데이터가 섞이면 안내가 틀린다.

**Independent Test**: 두 사용자에게 같은 셔츠를 넣고 한 사용자로 옷장 검색 → 그 사용자 옷만 나오는지 본다(`checks.sql`).

**Acceptance Scenarios**:

1. **Given** 같은 셔츠를 다른 날 두 번 봄, **When** 마무리하면, **Then** 옷장에 한 벌로 남고 마지막으로 본 시각만 바뀐다.
2. **Given** 오늘 이미 입은 기록이 있는 옷, **When** 다시 기록하면, **Then** 하루 한 번만 남는다.
3. **Given** 사용자 A·B, **When** A로 일정·옷장·연락처를 찾으면, **Then** B의 데이터는 0건이다.

---

### User Story 3 - 대화 중 상태는 잠깐만 들고 있는다 (Priority: P2)

"오늘 뭐 입지?"로 1단계 추천을 들은 뒤 옷을 카메라에 보여 주면, agent가 1단계 내용을 기억해 판단한다. 30분 동안 말이 없으면 잊는다. 직전 사진은 10분만 가족에게 보낼 수 있다.

**Why this priority**: 2단계 판단과 "엄마한테 물어봐 줘"가 이것에 기대지만, DB에 남길 필요가 없는 일시 데이터다.

**Independent Test**: 세션을 만든 뒤 31분 지나 다시 부르면 새 세션으로 시작하는지 본다(agent 테스트).

**Acceptance Scenarios**:

1. **Given** 1단계를 마친 세션, **When** 10분 뒤 옷을 보여 주면, **Then** 1단계 날씨·일정·추천을 써서 판단한다.
2. **Given** 사진을 보낸 지 11분, **When** 가족에게 물어봐 달라고 하면, **Then** 사진이 없다고 안내하고 다시 보여 달라고 한다.

---

### User Story 4 - 일정 알림과 가족 답장 알림이 한 번씩 간다 (Priority: P3)

일정 당일 아침 8시에 알림이 한 번, 가족이 답하면 알림이 한 번 간다.

**Independent Test**: 8시 작업을 두 번 돌려도 같은 일정에 알림이 한 번만 잡히는지 본다(`checks.sql` FR-S4).

**Acceptance Scenarios**:

1. **Given** 오늘 일정 2개 중 1개는 이미 알림을 보냄, **When** 8시 작업이 돌면, **Then** 나머지 1개만 잡힌다.
2. **Given** 가족이 링크로 두 번 답함, **When** 저장하면, **Then** 첫 답만 남는다.

### Edge Cases

- 계정 연결(Apple로 가입 → 구글 연결)은 Firebase가 같은 uid로 묶는다. 서버는 `firebase_uid`로만 찾으므로 표를 바꿀 일이 없다. `provider`는 처음 가입한 방법으로만 남는다.
- 장소를 못 찾은 일정은 `place_category`가 null이고 자리 종류는 제목 또는 `casual`.
- 옷 임베딩을 만들기 전(모델 준비 전)에도 옷 저장은 된다(`embedding` null 허용). 그 옷은 검색 후보에서 빠진다.
- 탈퇴 기능은 만들지 않는다(FR-X5).

## Requirements *(mandatory)*

### Functional Requirements

공통
- **FR-X1**: System MUST 서비스마다 PostgreSQL 스키마 하나만 쓰고, 스키마를 넘는 FK를 두지 않아야 한다.
- **FR-X2**: System MUST 사용자 데이터 표마다 `user_id uuid NOT NULL`을 두어야 한다. 예외는 `account.users` 자신과 공용 코디 지식 `closet.style_docs`뿐이다.
- **FR-X3**: System MUST 시각은 모두 `timestamp with time zone`으로 저장하고, 날짜 경계는 Asia/Seoul로 계산해야 한다.
- **FR-X4**: System MUST 사진 원본을 DB에 저장하지 않아야 한다.
- **FR-X5**: 탈퇴 시 다른 스키마 데이터 삭제는 발표 범위에서 뺀다. 나중에 하려면 gateway가 각 서비스에 삭제를 요청하고, 각 서비스는 `user_id` 인덱스로 지운다. (2026-11-04 진행 님 확정: 탈퇴 기능은 만들지 않음)
- **FR-F1**: System MUST 표 변경을 서비스별 Flyway 마이그레이션으로만 하고, 머지된 파일은 고치지 않아야 한다.

계정(account) · 근거 001
- **FR-A1**: 같은 Firebase 계정은 한 사용자. 로그인 방법은 apple·google·dev, apple·google은 `firebase_uid` 필수.
- **FR-A2**: dev 로그인은 기기 id 필수.
- **FR-A3**: 회원정보 7개 항목은 각각 비울 수 있고, 에이전트 이름은 비우거나 글자가 있어야 한다(공백만은 안 됨).
- **FR-A4**: 키 50~250cm, 몸무게 10~300kg 밖은 거부.
- **FR-A5**: 한 사용자가 폰 여러 대, 한 폰은 주인 한 명.
- **FR-A6**: 갱신 토큰은 해시만 저장하고 같은 해시는 한 번만.

일정(schedule) · 근거 002
- **FR-S1**: 제목은 비면 안 된다.
- **FR-S2**: 자리 종류 6개 중 하나, 근거(title·place·default) 함께. 기본은 casual/default.
- **FR-S3**: 사용자별·서울 날짜별 일정을 시작 순서로 빠르게 찾는다.
- **FR-S4**: 아침 알림은 일정마다 한 번(`notified_at`).

옷장(closet) · 근거 003
- **FR-C1**: 옷마다 종류·이름·색 이름·색 계열·톤·격식(정해진 값)과 전체 설명(JSON 객체), 384차원 임베딩.
- **FR-C2**: 같은 옷 찾기는 내 옷 중 종류·색 계열이 같은 것에서 코사인 유사도로.
- **FR-C3**: 처음·마지막으로 본 시각.
- **FR-C4**: 입은 날은 옷마다 하루 한 번.
- **FR-C5**: 옷장 후보 검색은 내 옷만, 정확한 거리 순(근사 인덱스로 남의 옷 사이에서 거르지 않음).
- **FR-C6**: 제외 목록과 최대 개수를 지킨다.
- **FR-C7**: 코디 지식은 Spring AI PgVectorStore 표 모양으로 두고, 출처·자리 종류는 metadata로 거른다.

가족 확인(helper) · 근거 004
- **FR-H1**: 같은 사용자는 같은 번호를 한 번만, 번호는 숫자만.
- **FR-H2**: 링크 토큰은 요청마다 고유.
- **FR-H3**: 상태는 pending·answered·expired, answered면 답과 시각 필수.
- **FR-H4**: 만료되면 expired로 바꾸고 사진 키를 지운다.
- **FR-H5**: 첫 답만 인정한다.

일시 상태(Redis) · 근거 contracts 5·7절
- **FR-R1**: agent 대화 세션은 `agent:session:{userId}:{sessionId}`에 30분(TTL), 직전 사진은 세션 안에서 10분만 쓴다.
- **FR-R2**: 게이트웨이 사용량 제한은 Redis에 두고 DB에 남기지 않는다.

### Key Entities

- account: 사용자, 회원정보, 알림 토큰, 갱신 토큰
- schedule: 일정
- closet: 옷, 입은 날, 코디 지식
- helper: 연락처, 확인 요청
- Redis: 대화 세션, 사용량 제한 카운터

자세한 컬럼과 ERD는 [data-model.md](data-model.md).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 네 서비스 V1이 빈 PostgreSQL 16 + pgvector에서 각각, 그리고 한 번에 실패 없이 실행된다.
- **SC-002**: `docs/infra/db/checks.sql`의 검사가 모두 통과한다(FR 번호별).
- **SC-003**: 한 사용자 옷 100벌에서 후보 5개 찾기가 10ms 안이다(정확한 거리, `user_id` 인덱스).
- **SC-004**: 사용자 A로 조회했을 때 B의 데이터가 나오는 쿼리 경로가 0개다.
- **SC-005**: mcp-schedule의 실제 마이그레이션과 `docs/infra/db/schedule/V1__init.sql`이 한 글자도 다르지 않다.

## Assumptions

- PostgreSQL 16 + pgvector(`pgvector/pgvector:pg16` 이미지) 한 대를 모든 서비스가 같이 쓴다.
- 임베딩 모델은 multilingual-e5-small(384차원)이다. 바꾸면 closet V2로 차원을 바꾼다.
- 일정 알림 통로는 gateway 내부 API `POST /internal/push`로 제안한 상태다(DB 설계와는 무관, 001 FR-011).
- 옷 직접 수정·삭제, 반복 일정, 일정 수정은 발표 범위 밖이다.
