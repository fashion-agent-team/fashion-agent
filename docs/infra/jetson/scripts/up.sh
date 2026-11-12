#!/usr/bin/env bash
# 젯슨에서 실행. 이미지를 하나씩 빌드하고(메모리 아끼려고 동시에 안 함) 전부 띄웁니다.
#   ./scripts/up.sh            빌드 + 실행
#   NO_BUILD=1 ./scripts/up.sh 빌드 없이 실행
#   ./scripts/up.sh gateway    그 서비스만 다시 빌드해서 띄움
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo ".env가 없습니다 (scripts/make-env.sh)"; exit 1; }
BUILDS=(${@:-edge-tts gateway agent mcp-weather mcp-schedule mcp-clothes-state mcp-face-check mcp-closet mcp-helper})
if [ "${NO_BUILD:-}" != 1 ]; then
  for s in "${BUILDS[@]}"; do echo "→ build $s"; docker compose build "$s"; done
fi
if [ $# -gt 0 ]; then docker compose up -d --no-deps "$@"; else docker compose up -d; fi
docker compose ps
echo "상태 확인: docker compose ps / docker stats --no-stream / curl -s localhost/actuator/health"
