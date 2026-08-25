#!/usr/bin/env bash
#
# package-tauri-mac-zip.sh <path-to-Operator.app> <output.zip>
#
# Archives the SIGNED macOS app for release and for the permanent Electron
# compatibility feed (latest-mac.yml points at this zip). Exactly one archive
# command is allowed, per AGENTS.md:
#
#   ditto -c -k --sequesterRsrc --keepParent
#
# Plain `zip` drops AppleDouble metadata and breaks the code seal on extract;
# `ditto` without --sequesterRsrc loses resource forks; --keepParent keeps
# Operator.app at the top of the archive so a plain `ditto -x -k` restore lands
# the bundle correctly. Do not add or "simplify" flags here.
#
# Exit codes: 0 archived, 1 archive failure, 2 usage error.

set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: package-tauri-mac-zip.sh <path-to-.app> <output.zip>

Archives a signed macOS .app with exactly:
  ditto -c -k --sequesterRsrc --keepParent <app> <output.zip>
and prints the archive's sha256 and byte size.
EOF
}

if [[ $# -ne 2 ]]; then
	usage
	exit 2
fi

case "${1:-}" in
-h | --help)
	usage
	exit 2
	;;
esac

APP="$1"
OUT="$2"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "package-tauri-mac-zip: macOS only (ditto); host is $(uname -s)" >&2
	exit 2
fi

if [[ ! -d "$APP" || "$APP" != *.app ]]; then
	echo "package-tauri-mac-zip: expected an .app bundle directory, got: $APP" >&2
	exit 2
fi

if [[ -z "$OUT" || "$OUT" != *.zip ]]; then
	echo "package-tauri-mac-zip: output must be a .zip path, got: $OUT" >&2
	exit 2
fi

APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
mkdir -p "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

if [[ "$OUT_ABS" == "$APP_ABS" || "$OUT_ABS" == "$APP_ABS"/* ]]; then
	echo "package-tauri-mac-zip: refusing to write the archive inside the app bundle: $OUT" >&2
	exit 2
fi

echo "==> archiving with ditto (-c -k --sequesterRsrc --keepParent): $APP"
ditto -c -k --sequesterRsrc --keepParent "$APP_ABS" "$OUT_ABS"

BYTES=$(stat -f %z "$OUT")
DIGEST=$(shasum -a 256 "$OUT" | awk '{print $1}')
echo "==> wrote $OUT ($BYTES bytes)"
echo "sha256: $DIGEST"
