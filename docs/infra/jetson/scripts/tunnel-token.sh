#!/usr/bin/env bash
# Cloudflare Tunnel 토큰을 맥북 .env와 젯슨 .env에 넣습니다(화면에 안 보임).
# 그다음 젯슨에서: docker compose --profile tunnel up -d cloudflared
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=${JETSON_HOST:-team4}
DEST=${JETSON_DIR:-fashion-servers}
read -rsp "CLOUDFLARE_TUNNEL_TOKEN: " TOKEN; echo
[ -n "$TOKEN" ] || { echo "비어 있습니다"; exit 1; }
set_key() {  # $1 = .env 경로 (stdin으로 토큰)
  python3 -c '
import sys,os
p=sys.argv[1]; tok=sys.stdin.read().strip()
lines=[l for l in open(p).read().splitlines() if not l.startswith("CLOUDFLARE_TUNNEL_TOKEN=")]
lines.append("CLOUDFLARE_TUNNEL_TOKEN="+tok)
open(p,"w").write("\n".join(lines)+"\n"); os.chmod(p,0o600)' "$1"
}
printf %s "$TOKEN" | set_key .env
printf %s "$TOKEN" | ssh "$HOST" "cd ~/$DEST/jetson-deploy && python3 -c '
import sys,os
p=\".env\"; tok=sys.stdin.read().strip()
lines=[l for l in open(p).read().splitlines() if not l.startswith(\"CLOUDFLARE_TUNNEL_TOKEN=\")]
lines.append(\"CLOUDFLARE_TUNNEL_TOKEN=\"+tok)
open(p,\"w\").write(\"\n\".join(lines)+\"\n\"); os.chmod(p,0o600)'"
echo "맥북·젯슨 .env에 저장함. 켜기: ssh $HOST 'cd ~/$DEST/jetson-deploy && docker compose --profile tunnel up -d cloudflared'"
