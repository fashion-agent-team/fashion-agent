# Tasks: 데이터베이스 통합 설계와 구축

**Input**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md), [research.md](research.md), [contracts/](contracts/)

표기: `[P]` 다른 파일이라 동시에 해도 됨, `[US1]` 관련 user story. ✅는 이 PR에서 끝난 것.

## Phase 1: Setup

- [x] T001 지금까지의 요구사항 모으기: specs 001~004, `docs/contracts/`, PR #14 `docs/infra/DB.md`·`schema.sql`, mcp-schedule `V1__init.sql`, agent 세션 코드 → [spec.md](spec.md) "요구사항을 모은 출처"
- [x] T002 구조 바꾸기: 문서 전체 Gemini → GPT(OpenAI) (`docs/ARCHITECTURE.md`, `docs/contracts/`, `README.md`, constitution 1.1.0, `.env.example`)

## Phase 2: Foundational

- [x] T003 서비스별 마이그레이션 폴더와 규칙 `docs/infra/db/README.md`, [contracts/migrations.md](contracts/migrations.md)
- [x] T004 `docs/infra/db/build-schema.sh` (서비스별 V*.sql → `docs/infra/schema.sql`)

## Phase 3: User Story 1 - 서비스 담당자가 자기 스키마를 바로 띄운다 (P1)

- [x] T005 [P] [US1] `docs/infra/db/account/V1__init.sql`
- [x] T006 [P] [US1] `docs/infra/db/schedule/V1__init.sql` (mcp-schedule#3 그대로 복사)
- [x] T007 [P] [US1] `docs/infra/db/closet/V1__init.sql` (garments HNSW 제거, style_docs를 PgVectorStore 모양으로)
- [x] T008 [P] [US1] `docs/infra/db/helper/V1__init.sql`
- [x] T009 [US1] PostgreSQL 16 + pgvector에서 파일마다 search_path 하나로 실행, `schema.sql` 한 번에 실행 → 표 10개

## Phase 4: User Story 2 - 사용자 데이터가 섞이지 않고 쌓인다 (P1)

- [x] T010 [US2] `docs/infra/db/checks.sql` 검사 32개 (FR-A·S·C·H·X) 통과
- [x] T011 [US2] `docs/infra/db/seed-dev.sql` 개발용 예시 데이터, 두 번 실행해도 같음

## Phase 5: 각 서비스 레포 (담당자)

- [ ] T012 [P] [US1] fashion-agent-gateway: `account/V1__init.sql` 복사 + Flyway 설정, JPA 엔티티 `ddl-auto: validate`로 뜨는지
- [ ] T013 [P] [US1] mcp-closet: `closet/V1__init.sql` 복사, PgVectorStore `schema-validation: true`로 Spring AI 2.0.2 표 모양 확인(다르면 closet V2, research R4)
- [ ] T014 [P] [US2] mcp-closet: `embedding IS NULL`인 옷을 뜰 때·저장할 때 채우기, 같은 옷 기준값 정하기(spec 003 SC-001·002)
- [ ] T015 [P] [US1] mcp-helper: `helper/V1__init.sql` 복사 + Flyway 설정
- [ ] T016 [US1] mcp-schedule: 변경 없음(이미 같음). 이후 V2가 생기면 이 레포에도 PR
- [ ] T017 [US3] agent: 세션 필드가 바뀌면 [contracts/redis-keys.md](contracts/redis-keys.md) 갱신

## Phase 6: Polish

- [x] T018 탈퇴는 만들지 않기로 확정(FR-X5, research R7, 2026-11-04)
- [ ] T019 모든 서비스가 붙은 뒤 docker compose DB에서 `checks.sql` 다시 돌리기(quickstart)
- [ ] T020 예비 옷 분석 서버(Cloudflare Worker)를 Gemini에서 GPT 비전으로 옮기기(구조 변경의 남은 부분, DB와 무관)

## Dependencies

- T005~T008은 서로 독립. T009·T010은 T004~T008 뒤.
- T012~T015는 이 PR 머지 뒤 각 레포에서 동시에.
