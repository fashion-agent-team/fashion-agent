# Quickstart: DB 만들어 보고 검사하기

## Docker Compose (서비스와 함께)

```bash
cd docs/infra
cp .env.example .env            # POSTGRES_PASSWORD 등 채우기
docker compose up -d postgres redis
# 각 서비스가 뜰 때 Flyway가 자기 스키마 표를 만듭니다.
docker compose up -d gateway mcp-schedule mcp-closet mcp-helper
docker compose exec -T postgres psql -U fashion -d fashion -v ON_ERROR_STOP=1 < db/checks.sql
```

`checks.sql`은 네 서비스 표가 모두 있어야 돌아갑니다. 아직 없는 서비스가 있으면 아래 "DB만" 방법을 쓰세요.

## DB만 (서비스 없이)

```bash
cd docs/infra/db
docker run -d --name fa-pg -e POSTGRES_USER=fashion -e POSTGRES_PASSWORD=pw -p 5432:5432 pgvector/pgvector:pg16
export PGHOST=localhost PGUSER=fashion PGPASSWORD=pw
createdb fashion_check
psql -v ON_ERROR_STOP=1 -d fashion_check -f ../schema.sql
psql -v ON_ERROR_STOP=1 -d fashion_check -f checks.sql      # 끝: checks: all passed
psql -v ON_ERROR_STOP=1 -d fashion_check -f seed-dev.sql    # 선택
```

## 내 서비스에 넣기

[docs/infra/db/README.md](../../docs/infra/db/README.md)의 "각 서비스에 넣는 법"을 따르세요.

## 결과 예 (2026-11-04, PostgreSQL 16.15 + pgvector 0.6.0)

```
PASS  FR-A1 같은 Firebase 계정은 한 사용자
…
PASS  FR-X4 사진 원본을 담을 bytea 컬럼 0개
checks: all passed
```
