#!/bin/zsh
set -e
UDID=708879DD-8B2A-4547-863F-F49EE1474D8B
VARIANT=$1
APPEARANCE=$2
BACKDROP=$3
OUT=$4
mkdir -p "$OUT/native/bare"
for b in dev.operator.iosliquidglass.example dev.operator.operatorMobile; do xcrun simctl terminate $UDID $b >/dev/null 2>&1 || true; done
xcrun simctl ui $UDID appearance $APPEARANCE
SIMCTL_CHILD_GLASS_LAB_SCENE=probe.hid.$VARIANT SIMCTL_CHILD_GLASS_LAB_BACKDROP=$BACKDROP SIMCTL_CHILD_GLASS_LAB_BARE=1 xcrun simctl launch --terminate-running-process $UDID dev.operator.glasslab >/dev/null
sleep 3
xcrun simctl io $UDID screenshot "$OUT/native/bare/ready.png" >/dev/null 2>&1
SIMCTL_CHILD_GLASS_LAB_SCENE=probe.hid.$VARIANT SIMCTL_CHILD_GLASS_LAB_BACKDROP=$BACKDROP SIMCTL_CHILD_GLASS_LAB_BARE=0 xcrun simctl launch --terminate-running-process $UDID dev.operator.glasslab >/dev/null
sleep 3
xcrun simctl io $UDID screenshot "$OUT/native/ready.png" >/dev/null 2>&1
echo prepared $OUT
