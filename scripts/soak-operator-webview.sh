#!/bin/bash
set -euo pipefail
pid="${1:?usage: soak-operator-webview.sh <WebContent pid> [minutes]}"
minutes="${2:-120}"
echo "minute,rss_kb,cpu_pct"
for ((m = 0; m <= minutes; m++)); do
	ps -o rss=,%cpu= -p "$pid" | awk -v m="$m" '{ printf "%d,%s,%s\n", m, $1, $2 }'
	sleep 60
done
