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
PBX=ios/Runner.xcodeproj/project.pbxproj
SIGNING=ios/signing.local   # 각자 맥의 서명 값(팀·번들 ID). .gitignore라 커밋되지 않는다.
DEFAULT_BUNDLE=com.fashionagent.fashionAgent

# 지금 서명 값을 ios/signing.local에 적어 둔다(처음 한 번, 또는 Xcode에서 바꾼 뒤).
team=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$PBX" | awk '{print $3}' || true)
bundle=$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = [^;]*' "$PBX" | awk '{print $3}' | grep -v RunnerTests | head -1 || true)
if [[ -n "$team" && "$bundle" != "$DEFAULT_BUNDLE" ]]; then
  printf 'TEAM=%s\nBUNDLE_ID=%s\n' "$team" "$bundle" > "$SIGNING"
fi

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

# 합치는 중에 서명 설정이 빠졌으면 ios/signing.local 값으로 다시 넣는다.
if [[ -f "$SIGNING" ]]; then
  # shellcheck disable=SC1090
  source "$SIGNING"
  if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;" "$PBX"; then
    echo "  서명 설정이 빠져 있어서 다시 넣어요 (팀 $TEAM, 번들 $BUNDLE_ID)"
    python3 - "$PBX" "$TEAM" "$BUNDLE_ID" "$DEFAULT_BUNDLE" <<'PY'
import sys
path, team, bundle, default = sys.argv[1:]
out = []
for line in open(path).read().split("\n"):
    if line.strip() == f"PRODUCT_BUNDLE_IDENTIFIER = {default};":
        indent = line[: len(line) - len(line.lstrip())]
        block = []
        for prev in reversed(out):  # 같은 buildSettings 블록 안만 본다
            if "buildSettings = {" in prev:
                break
            block.append(prev)
        if not any("DEVELOPMENT_TEAM" in l for l in block):
            out.append(f"{indent}DEVELOPMENT_TEAM = {team};")
        line = f"{indent}PRODUCT_BUNDLE_IDENTIFIER = {bundle};"
    out.append(line)
open(path, "w").write("\n".join(out))
PY
  fi
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
if ! flutter run --release -d "$DEVICE" --dart-define=GATEWAY_URL="$GATEWAY_URL"; then
  echo "✖ 실행에 실패했어요. 앱이 깔렸는데 안 열리면 폰에서"
  echo "  설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 → '신뢰'를 누른 뒤 앱 아이콘을 눌러 주세요."
  exit 1
fi
