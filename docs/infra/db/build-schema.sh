#!/usr/bin/env bash
# 서비스별 V*.sql을 이어 붙여 ../schema.sql(전체 그림, 한 번에 실행 가능)을 다시 만듭니다.
# 각 서비스의 Flyway처럼 search_path를 그 스키마로 바꾼 뒤 그 서비스 파일을 실행합니다.
#   ./build-schema.sh            # ../schema.sql 다시 만들기
set -euo pipefail
cd "$(dirname "$0")"
out=../schema.sql
{
  echo "-- ====================================================================="
  echo "-- 패션 에이전트 전체 DB (PostgreSQL 16 + pgvector). 손으로 고치지 마세요."
  echo "-- docs/infra/db/build-schema.sh 가 docs/infra/db/<서비스>/V*.sql 을 이어 붙여 만듭니다."
  echo "-- 설계: specs/005-database/data-model.md, 실행 확인: docs/infra/db/README.md"
  echo "-- ====================================================================="
  echo
  echo "CREATE EXTENSION IF NOT EXISTS vector SCHEMA public;"
  for s in account schedule closet helper; do
    echo
    echo "-- ---------------------------------------------------------------------"
    echo "-- schema: $s"
    echo "-- ---------------------------------------------------------------------"
    echo "CREATE SCHEMA IF NOT EXISTS $s;"
    echo "SET search_path TO $s, public;"
    for f in $(ls "$s"/V*__*.sql | sort -V); do
      echo
      echo "-- >>> $f"
      cat "$f"
    done
  done
  echo
  echo "RESET search_path;"
} > "$out"
echo "wrote $(cd .. && pwd)/schema.sql"
