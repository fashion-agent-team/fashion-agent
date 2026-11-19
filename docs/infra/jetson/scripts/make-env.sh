#!/usr/bin/env bash
# jetson-deploy/.env를 만듭니다. DB 비밀번호·JWT_SECRET은 새로 만들고, API 키는 직접 붙여 넣습니다(화면에 안 보임).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ] && [ "${FORCE:-}" != 1 ]; then echo ".env가 이미 있습니다. 덮어쓰려면 FORCE=1"; exit 1; fi
read -rsp "OPENAI_API_KEY: " OPENAI; echo
read -rsp "KAKAO_REST_API_KEY (없으면 엔터): " KAKAO; echo
umask 077
sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -hex 32)|" \
    -e "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI}|" \
    -e "s|^KAKAO_REST_API_KEY=.*|KAKAO_REST_API_KEY=${KAKAO}|" \
    .env.example > .env
chmod 600 .env
echo ".env 만듦 (권한 600). 채워진 키: $(grep -oE '^[A-Z_]+=.+' .env | cut -d= -f1 | tr '\n' ' ')"
