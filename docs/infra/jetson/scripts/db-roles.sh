#!/usr/bin/env bash
# 서버마다 DB 계정을 나눕니다(2026-11-25 보안 점검). 젯슨 jetson-deploy 폴더에서 실행.
#   gateway  → gateway_app  (account 스키마만)
#   schedule → schedule_app (schedule 스키마만)
#   closet   → closet_app   (closet 스키마만)
# 각 계정은 자기 스키마와 그 안의 표·시퀀스 주인이 되어 Flyway 마이그레이션도 그대로 돌고, 다른 스키마는 못 봅니다.
# 관리자 계정(fashion)은 그대로 남습니다(백업·복원용). 되돌리려면 .env의 *_DB_USER·*_DB_PASSWORD 줄을 비우고 서버를 다시 만들면 됩니다.
#
# 순서: 1) 백업(이 스크립트가 /tmp에 덤프) 2) 계정·권한 3) .env에 계정·비밀번호 추가(이미 있으면 그대로)
# 그다음 직접: docker compose up -d --no-deps --no-build gateway mcp-schedule mcp-closet
set -euo pipefail
cd "$(dirname "$0")/.."

psql() { docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U fashion -d fashion "$@" </dev/stdin; }

backup="/tmp/fashion-before-roles-$(date +%Y%m%d-%H%M%S).dump"
echo "→ 백업 $backup"
docker compose exec -T postgres pg_dump -U fashion -d fashion -Fc </dev/null >"$backup"
ls -lh "$backup" | awk '{print "  " $5}'

touch .env
chmod 600 .env
for svc in GATEWAY SCHEDULE CLOSET; do
  user_var="${svc}_DB_USER"
  pass_var="${svc}_DB_PASSWORD"
  lower=$(echo "$svc" | tr 'A-Z' 'a-z')
  if ! grep -qE "^${user_var}=.+" .env; then
    sed -i "/^${user_var}=/d" .env
    echo "${user_var}=${lower}_app" >>.env
  fi
  if ! grep -qE "^${pass_var}=.+" .env; then
    sed -i "/^${pass_var}=/d" .env
    echo "${pass_var}=$(openssl rand -hex 24)" >>.env
  fi
done

val() { grep -E "^$1=" .env | tail -1 | cut -d= -f2-; }

for pair in "GATEWAY:account" "SCHEDULE:schedule" "CLOSET:closet"; do
  svc=${pair%%:*}
  schema=${pair##*:}
  role=$(val "${svc}_DB_USER")
  pass=$(val "${svc}_DB_PASSWORD")
  echo "→ $role ← $schema"
  psql -q -v role="$role" -v pass="$pass" -v schema="$schema" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pass')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE', :'role', :'pass') \gexec
SELECT format('ALTER ROLE %I SET search_path = %I, public', :'role', :'schema') \gexec
SELECT format('GRANT CONNECT ON DATABASE fashion TO %I', :'role') \gexec
SELECT format('ALTER SCHEMA %I OWNER TO %I', :'schema', :'role') \gexec
SELECT format('REVOKE ALL ON SCHEMA %I FROM PUBLIC', :'schema') \gexec
-- 표·시퀀스·뷰 주인을 바꿔야 나중 마이그레이션(ALTER TABLE)도 됨. 시퀀스는 표에 딸린 것도 따라감.
SELECT format('ALTER TABLE %I.%I OWNER TO %I', n.nspname, c.relname, :'role')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = :'schema' AND c.relkind IN ('r', 'p', 'v', 'm', 'f') \gexec
SELECT format('ALTER SEQUENCE %I.%I OWNER TO %I', n.nspname, c.relname, :'role')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = :'schema' AND c.relkind = 'S'
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype IN ('a', 'i')) \gexec
SELECT format('ALTER FUNCTION %I.%I(%s) OWNER TO %I', n.nspname, p.proname,
              pg_get_function_identity_arguments(p.oid), :'role')
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = :'schema' AND p.prokind = 'f' \gexec
SQL
done

# public 스키마(pgvector 확장)는 읽기만. 남이 public에 표를 만들지 못하게.
psql -q <<'SQL'
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO PUBLIC;
SQL

echo "→ 확인"
psql -At <<'SQL'
SELECT n.nspname || ' 주인=' || r.rolname FROM pg_namespace n JOIN pg_roles r ON r.oid = n.nspowner
 WHERE n.nspname IN ('account', 'schedule', 'closet') ORDER BY 1;
SQL
echo "끝. 이제 docker compose up -d --no-deps --no-build gateway mcp-schedule mcp-closet"
echo "문제가 생기면: .env의 GATEWAY_/SCHEDULE_/CLOSET_DB_USER·PASSWORD 줄을 지우고 같은 명령으로 다시 만들기(백업: $backup)"
