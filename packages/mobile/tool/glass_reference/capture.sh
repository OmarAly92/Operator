#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/build/captures}"
SCENES="${SCENES:-rest sheet}"
mkdir -p "$OUT"
DEVICE="$("$HERE/device.sh")"
export GLASS_DEVICE="$DEVICE"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
for SCENE in $SCENES; do
  BUILT_THIS_SCENE=0
  for APPEARANCE in light dark; do
    xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
    "$HERE/run.sh" "$SCENE"
    sleep 4
    xcrun simctl io "$DEVICE" screenshot "$OUT/native_${APPEARANCE}_${SCENE}.png" >/dev/null
    SKIP_BUILD=$BUILT_THIS_SCENE "$HERE/run_lab.sh" "$SCENE"
    BUILT_THIS_SCENE=1
    sleep 8
    xcrun simctl io "$DEVICE" screenshot "$OUT/lab_${APPEARANCE}_${SCENE}.png" >/dev/null
    echo "$APPEARANCE/$SCENE: $(python3 "$HERE/compare.py" "$OUT/native_${APPEARANCE}_${SCENE}.png" "$OUT/lab_${APPEARANCE}_${SCENE}.png" "$OUT/compare_${APPEARANCE}_${SCENE}.png")"
  done
done
echo "$OUT"
