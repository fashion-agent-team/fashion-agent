# Implementation Plan: 데이터베이스 통합 설계와 구축

**Branch**: `claude/project-thread-845dxs` | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-database/spec.md`

## Summary

흩어진 요구사항(001~004 spec, 약속 문서, PR #14 초안, mcp-schedule 실제 마이그레이션, 옷 추천 2단계, GPT 전환)을 저장 관점에서 하나로 모았다. 결과는 서비스별 Flyway `V1__init.sql` 네 개(account·schedule·closet·helper), 이를 이어 붙인 `schema.sql`, 검사 SQL(`checks.sql`), 개발용 예시 데이터(`seed-dev.sql`)이고, 실제 PostgreSQL 16 + pgvector에서 실행해 확인했다. agent는 DB 없이 Redis 세션을 쓴다.

## Technical Context

**Language/Version**: SQL(PostgreSQL 16), 서비스는 Java 21 · Spring Boot 4.0.9 · Spring AI 2.0.2

**Primary Dependencies**: Flyway(Spring Boot 기본 연동), pgvector, Spring AI PgVectorStore(closet 코디 지식), Spring Data JPA(`ddl-auto: validate`)

**Storage**: PostgreSQL 16 + pgvector(`pgvector/pgvector:pg16`) 한 대, 서비스마다 스키마. Redis 7(세션·사용량 제한)

**Testing**: `docs/infra/db/checks.sql`(psql, ROLLBACK). 서비스별로는 mcp-schedule처럼 H2 또는 Testcontainers(`pgvector/pgvector:pg16`, closet은 pgvector가 필요해 Testcontainers만 가능)

**Target Platform**: Docker Compose, VM 한 대

**Project Type**: 마이크로서비스(레포 9개) 공용 DB 설계

**Performance Goals**: 하루 일정 조회·옷장 후보 찾기 각각 10ms 안(사용자당 일정 수십 개, 옷 100벌 안팎)

**Constraints**: 사진 저장 금지, 스키마를 넘는 FK 금지, 발표(2026-11-20)까지 표 변경 최소

**Scale/Scope**: 발표용 사용자 수십 명, 표 10개

## Constitution Check

| 원칙 | 확인 | 결과 |
| --- | --- | --- |
| I. 음성으로 끝까지 | DB가 실패를 만들지 않게: 임베딩 없이도 옷 저장, 장소 못 찾아도 일정 저장 | 통과 |
| II. 약속 문서가 먼저 | 약속 문서 7절 표 목록과 같고, 바뀐 점(style_docs 모양)은 7절도 함께 고침 | 통과 |
| III. 서비스 경계 | 스키마 4개, 교차 FK 0개(`checks.sql` FR-X1), agent는 DB 없음 | 통과 |
| IV. 개인정보 최소 | 사진 컬럼 없음(FR-X4), 갱신 토큰 해시만, 전화번호는 helper 안에만, 세션 30분 | 통과 |
| V. 발표에서 같게, 단순하게 | 표 10개 그대로(초안보다 늘지 않음), 트리거·공용 함수 없음, 근사 인덱스 하나만 | 통과 |

설계 뒤 다시 확인: 통과. 위반 없음(Complexity Tracking 비움).

## Project Structure

### Documentation (this feature)

```text
specs/005-database/
├── spec.md              # 요구사항 통합
├── plan.md              # 이 문서
├── research.md          # 결정과 이유 R1~R7
├── data-model.md        # ERD, 표·컬럼 규칙, 자주 쓰는 쿼리
├── quickstart.md        # 로컬에서 만들어 보고 검사하기
├── contracts/
│   ├── migrations.md    # Flyway 규칙(파일 이름, 설정, 바꾸는 법)
│   └── redis-keys.md    # Redis 키·값·TTL
├── checklists/requirements.md
└── tasks.md             # 할 일 (이 레포에서 끝난 것 + 각 서비스 레포 할 일)
```

### Source Code (repository root)

```text
docs/infra/
├── db/
│   ├── README.md
│   ├── account/V1__init.sql     # → fashion-agent-gateway
│   ├── schedule/V1__init.sql    # = mcp-schedule (이미 들어감)
│   ├── closet/V1__init.sql      # → mcp-closet
│   ├── helper/V1__init.sql      # → mcp-helper
│   ├── build-schema.sh          # 위 네 개 → ../schema.sql
│   ├── checks.sql               # 검사 34개
│   └── seed-dev.sql             # 개발용 예시 데이터
├── schema.sql                   # 생성 파일 (손으로 고치지 않음)
├── init-schemas.sql             # docker 첫 실행: 확장 + 빈 스키마
└── DB.md                        # 요약 + 링크
```

**Structure Decision**: 설계 원본은 앱 레포 `docs/infra/db/`에 두고(모든 팀원이 한 곳에서 리뷰), 실행본은 각 서비스 레포의 `src/main/resources/db/migration/`에 같은 내용으로 복사한다. mcp-schedule은 이미 같다.

## Complexity Tracking

(위반 없음)
