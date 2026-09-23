#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOBILE="$(cd "$HERE/../.." && pwd)"
DEVICE="${GLASS_DEVICE:-$("$HERE/device.sh")}"
SCENE="${1:-rest}"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  (cd "$MOBILE" && flutter build ios --simulator --debug --dart-define=GLASS_LAB_SCENE="$SCENE" >/dev/null)
fi
xcrun simctl install "$DEVICE" "$MOBILE/build/ios/iphonesimulator/Runner.app"
xcrun simctl terminate "$DEVICE" dev.operator.operatorMobile >/dev/null 2>&1 || true
xcrun simctl launch "$DEVICE" dev.operator.operatorMobile >/dev/null
