#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${GLASS_DEVICE:-$("$HERE/device.sh")}"
SCENE="${1:-rest}"
APP="$HERE/build/GlassReference.app"
mkdir -p "$APP"
cp "$HERE/Info.plist" "$APP/Info.plist"
xcrun -sdk iphonesimulator swiftc -parse-as-library -target arm64-apple-ios26.0-simulator "$HERE/GlassReference.swift" -o "$APP/GlassReference"
codesign -s - --force "$APP" >/dev/null 2>&1
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" dev.operator.glassreference >/dev/null 2>&1 || true
SIMCTL_CHILD_GLASS_LAB_SCENE="$SCENE" xcrun simctl launch "$DEVICE" dev.operator.glassreference >/dev/null
