#!/usr/bin/env bash
# 맥북 PostgreSQL의 fashion DB(account·closet·helper·schedule 스키마)를 젯슨 postgres 컨테이너로 옮깁니다.
# 맥북에서 실행. 젯슨 쪽 앱 컨테이너는 복원하는 동안 멈추고(postgres만 켬), 끝나면 up.sh로 다시 켜세요.
# 젯슨 DB의 같은 스키마 내용은 맥북 것으로 바뀝니다.
# (원격 스크립트를 stdin으로 넘기므로 docker compose 명령은 </dev/null로 stdin을 먹지 않게 함)
set -euo pipefail
HOST=${JETSON_HOST:-team4}
DEST=${JETSON_DIR:-fashion-servers}
PG_BIN=${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}
APPS="nginx gateway agent mcp-weather mcp-schedule mcp-clothes-state mcp-face-check mcp-closet mcp-helper"

DUMP=$(mktemp -t fashion).dump
trap 'rm -f "$DUMP"' EXIT
echo "→ 맥북에서 덤프"
"$PG_BIN/pg_dump" -h localhost -U fashion -d fashion -Fc --no-owner --no-acl \
  -n account -n closet -n helper -n schedule -f "$DUMP"
ls -lh "$DUMP" | awk '{print "  " $5}'

echo "→ 젯슨으로 복사"
scp -q "$DUMP" "$HOST:/tmp/fashion.dump"

echo "→ 젯슨에서 복원"
ssh "$HOST" bash -s -- "$DEST" "$APPS" <<'REMOTE'
set -euo pipefail
cd ~/"$1"/jetson-deploy
docker compose stop $2 </dev/null >/dev/null 2>&1 || true
docker compose up -d postgres </dev/null
for i in $(seq 1 30); do docker compose exec -T postgres pg_isready -U fashion -d fashion </dev/null >/dev/null 2>&1 && break; sleep 2; done
docker compose exec -T postgres pg_restore -U fashion -d fashion \
  --clean --if-exists --no-owner --no-acl --single-transaction --exit-on-error < /tmp/fashion.dump
rm -f /tmp/fashion.dump
docker compose exec -T postgres psql -U fashion -d fashion -Atc \
  "select schemaname, count(*) from pg_tables where schemaname in ('account','closet','helper','schedule') group by 1 order by 1" </dev/null
REMOTE
echo "끝. 젯슨에서 ./scripts/up.sh"
