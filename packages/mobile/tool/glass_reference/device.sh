#!/usr/bin/env bash
set -euo pipefail
UDID="$(xcrun simctl list devices available -j | python3 -c '
import sys, json
devs = json.load(sys.stdin)["devices"]
for rt in sorted((r for r in devs if "iOS-26" in r), reverse=True):
    for d in devs[rt]:
        if d["name"] == "iPhone 17 Pro":
            print(d["udid"])
            sys.exit(0)
sys.exit("no iPhone 17 Pro on an iOS 26 runtime")
')"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "$UDID"
