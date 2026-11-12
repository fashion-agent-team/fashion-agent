#!/usr/bin/env bash
# 맥북 → 젯슨으로 레포 8개, jetson-deploy, FashionSigLIP 모델을 보냅니다.
# 레포는 작업 폴더가 아니라 DEPLOY_REF(기본 origin/develop)를 git archive로 보내서
# .git·build가 안 가고, 맥북에서 어떤 브랜치를 열어 두었든 같은 코드가 갑니다.
set -euo pipefail
HOST=${JETSON_HOST:-team4}
DEST=${JETSON_DIR:-fashion-servers}          # 젯슨 홈 아래
REF=${DEPLOY_REF:-origin/develop}
SIGLIP=${SIGLIP_SRC:-$HOME/Downloads/fashion-siglip/marqo-fashionSigLIP-vision.onnx}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
REPOS=(fashion-agent-gateway fashion-agent-agent mcp-weather mcp-schedule mcp-clothes-state mcp-face-check mcp-closet mcp-helper)

ssh "$HOST" "mkdir -p ~/$DEST/models"
for r in "${REPOS[@]}"; do
  git -C "$ROOT/$r" fetch -q origin develop
  echo "→ $r  $(git -C "$ROOT/$r" log -1 --format='%h %s' "$REF")"
  git -C "$ROOT/$r" archive --format=tar "$REF" \
    | ssh "$HOST" "set -e; rm -rf ~/$DEST/$r.new; mkdir -p ~/$DEST/$r.new; tar -x -C ~/$DEST/$r.new; rm -rf ~/$DEST/$r; mv ~/$DEST/$r.new ~/$DEST/$r"
done

echo "→ jetson-deploy"
[ -f "$ROOT/jetson-deploy/.env" ] || echo "  (주의) .env가 없습니다. scripts/make-env.sh 먼저"
rsync -az --exclude '*.dump' "$ROOT/jetson-deploy/" "$HOST:$DEST/jetson-deploy/"

if [ -f "$SIGLIP" ]; then
  echo "→ FashionSigLIP 모델"
  rsync -az "$SIGLIP" "$HOST:$DEST/models/"
  ssh "$HOST" "chmod 644 ~/$DEST/models/$(basename "$SIGLIP")"
else
  echo "  (건너뜀) $SIGLIP 없음. .env의 CLOTHES_EMBED_MODEL을 비우세요"
fi
echo "끝. 젯슨에서: cd ~/$DEST/jetson-deploy && ./scripts/up.sh"
