#!/usr/bin/env bash
# 아이폰에 최신 develop 앱을 깔아 실행한다. 폰을 케이블로 맥에 연결하고 잠금을 풀어 둔 채로:
#   ./scripts/ios-install.sh            # 연결된 아이폰 하나에 설치
#   ./scripts/ios-install.sh <기기 id>   # 여러 대면 flutter devices의 id로 지정
# 서버: GATEWAY_URL(기본 https://simcheong.java21.net). 서버 목소리(CLOUD_TTS)는 앱 기본값으로 켜져 있다.
# FAKE_CAMERA 같은 시뮬레이터 옵션은 넣지 않는다(실기기에서 얼굴을 못 찾던 원인).
set -euo pipefail
cd "$(dirname "$0")/.."

GATEWAY_URL="${GATEWAY_URL:-https://simcheong.java21.net}"
DEVICE="${1:-}"

echo "▶ develop 최신 받기"
git fetch origin develop
# 로컬 서명 설정(ios/Runner.xcodeproj 등) 변경은 그대로 두고 받는다.
git stash push -q -m ios-install-local || true
git checkout -q develop
git pull -q --no-rebase origin develop
if git stash list | grep -q ios-install-local; then
  git stash pop -q || {
    echo "✖ 로컬 변경과 충돌했어요. 'git status'로 확인해 주세요(서명 설정은 Xcode에서 다시 골라도 돼요)."
    exit 1
  }
fi
echo "  $(git log -1 --oneline)"

if [[ -z "$DEVICE" ]]; then
  DEVICE=$(flutter devices --machine 2>/dev/null |
    python3 -c 'import json,sys
d=[x for x in json.load(sys.stdin) if x.get("targetPlatform","").startswith("ios") and not x.get("emulator")]
print(d[0]["id"] if d else "")')
fi
if [[ -z "$DEVICE" ]]; then
  echo "✖ 연결된 아이폰을 못 찾았어요. 케이블로 연결하고 잠금을 풀어 주세요."
  exit 1
fi

echo "▶ 설치·실행 (기기 $DEVICE, 서버 $GATEWAY_URL)"
flutter pub get
flutter run --release -d "$DEVICE" --dart-define=GATEWAY_URL="$GATEWAY_URL"
