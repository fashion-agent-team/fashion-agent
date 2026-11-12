#!/usr/bin/env bash
# 아이폰에 최신 develop 앱을 깔아 실행한다. 폰을 케이블로 맥에 연결하고 잠금을 풀어 둔 채로:
#   ./scripts/ios-install.sh            # 연결된 아이폰 하나에 설치
#   ./scripts/ios-install.sh <기기 id>   # 여러 대면 flutter devices의 id로 지정
# 서버: GATEWAY_URL(기본 젯슨 Funnel https://team4.tail2d734d.ts.net, 2026-11-12: 강사님 프록시를 거치면 요청마다 1~1.5초 더 걸려서 바로 붙음). 서버 목소리(CLOUD_TTS)는 앱 기본값으로 켜져 있다.
# FAKE_CAMERA 같은 시뮬레이터 옵션은 넣지 않는다(실기기에서 얼굴을 못 찾던 원인).
set -euo pipefail
cd "$(dirname "$0")/.."

GATEWAY_URL="${GATEWAY_URL:-https://team4.tail2d734d.ts.net}"
DEVICE="${1:-}"

echo "▶ develop 최신 받기"
# 지금 브랜치에 develop을 합친다. 브랜치를 바꾸거나 변경을 치우지 않아서
# 각자 맥의 서명 설정(팀·번들 ID, 커밋했든 안 했든)이 그대로 남는다.
# 커밋 안 한 변경은 --autostash가 잠깐 치웠다가 바로 되돌린다.
if ! git pull -q --no-rebase --autostash origin develop; then
  echo "✖ develop을 합치다 충돌했어요. 'git status'로 확인해 주세요."
  echo "  서명 설정 충돌이면 develop 쪽을 고른 뒤 Xcode에서 팀만 다시 골라도 돼요."
  exit 1
fi
echo "  $(git log -1 --oneline)"
if ! git merge-base --is-ancestor origin/develop HEAD; then
  echo "✖ develop 최신이 들어오지 않았어요."
  exit 1
fi

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
