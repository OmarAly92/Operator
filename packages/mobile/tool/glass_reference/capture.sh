#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/build/captures}"
SCENES="${SCENES:-rest sheet}"
mkdir -p "$OUT"
DEVICE="$("$HERE/device.sh")"
export GLASS_DEVICE="$DEVICE"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
LAST_SCENE=""
for APPEARANCE in light dark; do
  xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
  for SCENE in $SCENES; do
    "$HERE/run.sh" "$SCENE"
    sleep 4
    xcrun simctl io "$DEVICE" screenshot "$OUT/native_${APPEARANCE}_${SCENE}.png" >/dev/null
    if [ "$SCENE" = "$LAST_SCENE" ]; then
      SKIP_BUILD=1 "$HERE/run_lab.sh" "$SCENE"
    else
      SKIP_BUILD=0 "$HERE/run_lab.sh" "$SCENE"
    fi
    LAST_SCENE="$SCENE"
    sleep 8
    xcrun simctl io "$DEVICE" screenshot "$OUT/lab_${APPEARANCE}_${SCENE}.png" >/dev/null
    echo "$APPEARANCE/$SCENE: $(python3 "$HERE/compare.py" "$OUT/native_${APPEARANCE}_${SCENE}.png" "$OUT/lab_${APPEARANCE}_${SCENE}.png" "$OUT/compare_${APPEARANCE}_${SCENE}.png")"
  done
done
echo "$OUT"
