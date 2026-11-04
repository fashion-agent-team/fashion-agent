# Research: 데이터베이스 통합 설계

## R1. 서비스마다 스키마 하나, 스키마를 넘는 FK 없음

- **Decision**: PostgreSQL 한 대, 스키마 4개(account·schedule·closet·helper). `user_id`는 값만 같고 FK 없음.
- **Rationale**: 약속 문서 7절과 constitution III. 레포·담당이 나뉘어 있어 서로의 표 변경에 묶이지 않아야 함. DB 한 대라 발표용 VM 하나에 올리기 쉬움.
- **Alternatives**: 서비스마다 DB 따로(연결·백업이 4배), 공유 스키마 하나(경계가 무너짐).

## R2. 서비스별 Flyway, 파일 안에서는 스키마 이름을 붙이지 않음

- **Decision**: `spring.flyway.schemas/default-schema/create-schemas`로 그 서비스 스키마에서 실행. 이력 표(`flyway_schema_history`)도 그 스키마 안.
- **Rationale**: mcp-schedule#3이 이미 이 방식으로 동작 중. 서비스가 뜰 때 자기 표를 만들어서 따로 DB 작업을 할 사람이 필요 없음.
- **Alternatives**: 공용 `schema.sql`을 docker 초기화에 넣기(서비스와 버전이 따로 놂, 표 변경 이력 없음). Liquibase(팀이 처음 씀, XML·YAML 부담).

## R3. 내 옷 검색에는 벡터 근사 인덱스(HNSW)를 두지 않음

- **Decision**: `closet.garments`에는 `(user_id, category)`, `(user_id, last_seen_at)` 인덱스만 두고, 거리 정렬은 내 옷만 골라 정확하게 계산.
- **Rationale**: pgvector 문서상 근사 인덱스(HNSW·IVFFlat)는 인덱스에서 가까운 후보(`hnsw.ef_search` 기본 40개)를 먼저 뽑은 뒤 WHERE 조건으로 거릅니다. 사용자가 많아지면 그 40개에 내 옷이 없어 결과가 비거나 모자랄 수 있습니다. 한 사람 옷은 100벌 안팎이라 정확한 계산이 오히려 빠릅니다. 로컬 측정(PostgreSQL 16, pgvector 0.6, 2만 행 중 한 사람 50벌, 384차원): `user_id` 인덱스로 골라 정렬하는 데 0.05ms.
- **Alternatives**: HNSW + pgvector 0.8 반복 스캔(`hnsw.iterative_scan`, 버전 의존), 사용자별 부분 인덱스(사용자 수만큼 인덱스).
- 공용 코디 지식(`style_docs`)은 사용자 필터가 없어 HNSW를 그대로 둡니다.

## R4. 코디 지식은 Spring AI PgVectorStore 표 모양으로

- **Decision**: `closet.style_docs(id uuid, content text, metadata json, embedding vector(384))`, 설정은 `schema-name=closet, table-name=style_docs, dimensions=384, initialize-schema=false`.
- **Rationale**: 아키텍처가 "Spring AI VectorStore + pgvector"인데, PR #14 초안의 컬럼(source, chunk_no, occasion)은 PgVectorStore가 읽지 못합니다. 표 모양을 맞추면 문서 넣기(`add`)와 찾기(`similaritySearch` + metadata 필터)를 코드 없이 씁니다. 출처·자리 종류는 metadata로 옮겼고 `metadata::jsonb @@ '$.occasion == "formal"'`로 거르는 것을 확인했습니다.
- **Alternatives**: 초안 모양 유지 + JdbcTemplate로 직접 쿼리(가능하지만 VectorStore를 안 쓰는 셈).
- **확인할 것**: Spring AI 2.0.2의 PgVectorStore 컬럼 이름이 이와 같은지 mcp-closet 담당이 첫 실행 때 확인(tasks T013). 다르면 closet V2로 맞춤.
- 옷(`garments`)은 사용자별 필터와 같은 옷 합치기 규칙이 있어 VectorStore 대신 JdbcTemplate 쿼리(data-model 3절)로 씁니다.

## R5. Gemini → GPT 전환이 DB에 주는 영향

- **Decision**: 표 변화 없음. 임베딩은 서버에서 도는 multilingual-e5-small(ONNX, 384차원)을 그대로 씀.
- **Rationale**: GPT로 바뀌는 곳은 agent 판단·도구 선택, closet 답변 문장, clothes-state 폴백으로 모두 저장과 무관. 임베딩을 OpenAI(text-embedding-3-small, 1536차원)로 바꾸면 호출 비용이 생기고 벡터 차원과 기존 데이터가 바뀌어 closet V2가 필요합니다. 발표 전에는 바꿀 이유가 없습니다.
- 계약 문서의 `clothes_inspect.source` 값만 `gemini` → `gpt`로 바꿨습니다(DB 아님).

## R6. agent는 DB 없이 Redis

- **Decision**: 대화 세션은 Redis 문자열 `agent:session:{userId}:{sessionId}`(JSON), TTL 30분. 직전 사진은 세션 안에 넣고 10분 지나면 쓰지 않음.
- **Rationale**: agent 코드(`RedisSessionStore`, `AgentSession.PHOTO_TTL_MS`)가 이미 이렇게 동작. 대화 내용은 오래 남길 이유가 없고(개인정보 최소, constitution IV), 남길 결과(본 옷·입은 날)는 closet이 맡음.
- **Alternatives**: 세션을 PostgreSQL에(만료 정리 작업이 필요, 사진을 DB에 두게 됨).

## R7. 탈퇴

- **Decision(제안)**: 발표 범위에서 뺌. 나중에는 gateway가 탈퇴 때 각 서비스의 삭제 API를 부르고, 각 서비스는 `user_id`로 지움. 모든 사용자 표에 `user_id` 인덱스가 있어 바로 가능.
- **Rationale**: FK가 없어 DB가 자동으로 지우지 못함(R1의 대가). 지금 표 설계로 나중에 바꿀 일은 없음.
- 팀 확인 필요(spec FR-X5).
