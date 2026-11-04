<!--
Sync Impact Report
- Version: (template) → 1.0.0
- Added: 원칙 I~V, 기술 제약, 작업 방식, 거버넌스 (모두 새로 작성)
- Source: docs/contracts/README.md (PR #12), docs/GITFLOW.md, docs/infra/DB.md
- Templates: plan/spec/tasks 템플릿은 그대로 사용 (수정 불필요)
-->

# 패션 에이전트 Constitution

시각장애인이 혼자서 오늘 입을 옷을 고르고 확인할 수 있게 돕는 음성 코디 도우미의 팀 원칙입니다. 모든 spec과 설계는 이 문서를 먼저 따릅니다.

## Core Principles

### I. 음성으로 끝까지 쓸 수 있어야 한다 (NON-NEGOTIABLE)

- 사용자는 화면을 보지 않는다고 가정한다. 모든 기능은 말로 시작하고 말로 결과를 듣는 흐름만으로 끝까지 쓸 수 있어야 한다.
- 사람에게 읽어 줄 문장은 한국어 존댓말, 한 번에 3문장 이내, 이유를 붙인다.
- 실패해도 사용자는 항상 무언가를 듣는다. 바깥 서비스가 실패하면 정해진 안내 문장이나 규칙 기반 판단으로 대신한다.

### II. 약속 문서가 먼저다

- 서비스 사이의 API, MCP 도구 이름과 입출력, DB 나누기는 `docs/contracts/`에 먼저 적고 PR로 합의한 뒤에 코드를 바꾼다.
- spec과 약속 문서가 다르면 약속 문서를 기준으로 하고, spec을 고치거나 약속 문서 변경 PR을 낸다.

### III. 서비스 경계를 지킨다

- 서비스마다 DB 스키마 하나를 가진다. 다른 서비스의 스키마를 직접 읽지 않고, 그 서비스의 API나 MCP 도구를 부른다.
- MCP 서버는 데이터만 돌려준다. "이 옷이 오늘 맞는가" 같은 판단과 추천은 agent가 Gemini에 맡긴다.
- 앱이 부르는 곳은 게이트웨이 하나뿐이다. 뒤쪽 서비스는 밖에 포트를 열지 않는다.

### IV. 개인정보를 최소로 다룬다

- 사진은 어떤 서비스도 저장하지 않는다. 유일한 예외는 가족 확인 요청 사진을 24시간 동안만 두는 것이다.
- 사용자 id는 게이트웨이가 확인한 값만 쓴다. Gemini나 앱이 보낸 값을 믿지 않는다(남의 일정·옷장 접근 차단).
- 로그에 사진, 토큰, 전화번호를 남기지 않는다. 비밀 값은 레포에 넣지 않는다.

### V. 발표에서 매번 같게 동작한다

- 발표(2026-11-20)까지 범위를 지킨다. 새 기능보다 정해진 흐름이 안정적으로 도는 것이 먼저다.
- 데이터를 모으는 순서는 코드로 정한다(옷 추천 흐름에서는 Gemini가 도구를 고르지 않는다).
- 가장 단순한 방법을 먼저 쓴다. 필요가 증명되기 전에는 서비스·테이블·설정을 늘리지 않는다.

## 기술 제약

- 서버: Java 21, Spring Boot 4.0.9, Spring Cloud Gateway 2025.1.4, Spring AI 2.0.2(MCP 서버는 Streamable HTTP `/mcp`).
- 저장소: PostgreSQL 16 + pgvector 하나(서비스마다 스키마), Redis(사용량 제한, 대화 상태). 설계는 `docs/infra/DB.md`.
- AI: Gemini(구조화 출력, temperature 0.2). 앱: Flutter(iOS·Android).
- 시간은 시간대까지 적은 ISO-8601, 서버 기본 시간대 Asia/Seoul. 오류 응답은 `{"error":{"code","message"}}`.

## 작업 방식

- GitFlow: `develop`에서 `feature/…` 브랜치를 따서 PR로 합친다(`docs/GITFLOW.md`). 리뷰 1명 이상.
- spec은 `specs/NNN-이름/spec.md`에 둔다. 기능마다 브랜치를 새로 만들지 않아도 된다.
- 결정이 필요한 부분은 spec에 `[NEEDS CLARIFICATION]`으로 남기고, 팀이 정하면 spec과 약속 문서를 함께 고친다.

## Governance

- 이 문서는 다른 규칙보다 우선한다. 바꾸려면 PR로 이유를 적고 팀원 확인을 받는다.
- 버전: 원칙을 빼거나 뜻을 바꾸면 MAJOR, 원칙·절을 더하면 MINOR, 문구만 고치면 PATCH.
- 리뷰할 때 spec과 코드가 원칙 I~V를 어기지 않는지 확인한다.

**Version**: 1.0.0 | **Ratified**: 2026-11-04 | **Last Amended**: 2026-11-04
