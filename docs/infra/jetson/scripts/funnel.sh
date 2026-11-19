#!/usr/bin/env bash
# 젯슨에서 실행. Tailscale Funnel로 https://<젯슨>.ts.net → 127.0.0.1:80(nginx)를 공개합니다.
# 처음이면 sudo 없이 쓰게 한 번: sudo tailscale set --operator=$USER
# 젯슨이 속한 tailnet 관리자 정책에서 이 기기에 funnel 권한이 있어야 합니다.
#   ./scripts/funnel.sh       켜기
#   ./scripts/funnel.sh off   끄기
set -euo pipefail
if [ "${1:-}" = off ]; then tailscale funnel reset; else tailscale funnel --bg 80; fi
tailscale funnel status
