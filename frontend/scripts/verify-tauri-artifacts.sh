#!/usr/bin/env bash
#
# verify-tauri-artifacts.sh --dist <dir> [options]
#
# The one canonical pre-release check for Tauri release artifacts. It fails
# closed like the Phase 0 evidence tooling: every requirement that cannot be
# verified RIGHT NOW is reported by name, never silently skipped.
#
# Ledger classes (three tiers):
#   PASS        verified green.
#   FAIL        structural violation (missing artifact, missing resources,
#               wrong contents), or a trust check ATTEMPTED AND FAILED here.
#               Any FAIL exits 1 after reporting ALL findings. Under
#               --strict-trust a FAILED delegated macOS seal/notarization/
#               staple trio is this class too.
#   GATE        unverifiable WITHOUT CONDUCTOR-HELD MATERIAL even on a fully
#               equipped CI host: Authenticode validation evidence, rpm -K
#               against the conductor-imported key, the NSIS silent-smoke
#               install, NSIS payload license listing, macOS notarization
#               status ahead of the conductor, tooling absent on this host.
#               Recorded BY NAME, never fatal -- the in-workflow trust
#               OPERATIONS (signtool signing, notarytool/stapler steps)
#               already fail their own workflow steps naturally; re-validating
#               them afterwards is conductor-side evidence, not a build-host
#               duty. Never fatal even under --strict-trust.
#   SCOPE-SKIP  artifact-class absence caused by MATRIX TOPOLOGY: this
#               invocation was never handed the sibling arch/platform's
#               artifacts. Declared explicitly via --arch; printed as an INFO
#               line, never a ledger row (neither PASS nor GATE nor FAIL).
#
# Scoping: --arch arm64|x64 (comma-separated) declares which arches THIS dist
# must carry; absence checks (updater archives, ditto zips, dmgs, NSIS exe,
# AppImage/deb/rpm, .sig sidecars) apply only to the declared platform+arch
# set. Unscoped runs keep the legacy posture: arm64 demanded, sibling-arch
# absence gated.
#
# Sibling layouts: --extra-dist <dir> (repeatable) registers directories where
# collected artifact classes may live beside the primary --dist. Every class-
# absence check consults primary first, then each extra dir in declaration
# order; a class found in an extra dir is inspected THERE with full checks
# exactly as if it were primary (hdiutil mount for dmgs, dpkg-deb/rpm listing,
# ...), and only absence from ALL declared dirs can fail. Composes with --arch
# scoping. --expect-aliases opts into the version-free alias layout (primary
# dist carries operator-darwin-arm64.zip-style names): the filename version
# grep then passes with a note instead of failing. Embedded-metadata version
# assertions stay fully active either way -- CFBundleShortVersionString is
# still compared against --expect-version inside EVERY inspected bundle form.
#
# --strict-trust means exactly: every check applicable to the DECLARED SCOPE
# that is executable on this host ran and PASSED; anything not executable here
# is a named GATE, never fatal. The ONE exception is the macOS
# codesign/spctl/staple trio delegated to verify-mac-artifact.sh: failing it
# under --strict-trust fails the run, because trust must be able to fail a
# release.
#
# macOS package inspection covers the .app bundle, the ditto zip, the Tauri
# updater archive (.app.tar.gz) and the DMG, extracting each with its
# seal-preserving tool (ditto -x -k for zips per AGENTS.md; tar for the
# updater archive; hdiutil for DMGs) and checking the bundled daemon,
# agent-browser, ACP runtime, licenses and icon inside EVERY one of them.
#
# Exit codes: 0 all checks applicable to the declared scope passed (gates
# recorded), 1 any FAIL (including a trust failure under --strict-trust),
# 2 usage error.

set -uo pipefail

usage() {
	cat >&2 <<'EOF'
usage: verify-tauri-artifacts.sh --dist <dir> [--platform darwin|win32|linux]
       [--arch arm64,x64] [--extra-dist <dir>]... [--expect-aliases]
       [--expect-version <x.y.z>] [--mode release|testing] [--strict-trust]
       [--emit-gates <file.json>]

Structural artifacts, resource contents and signature sidecars are checked
in-place; --arch scopes absence checks to the declared arch set (matrix
topology: an out-of-scope class is skipped with an INFO line, not a ledger
row), and each repeatable --extra-dist is consulted for a class before its
absence can fail (found classes are inspected there in full). --expect-aliases
declares the version-free alias layout: the filename version grep passes with
a note; the version is still asserted against embedded bundle metadata.
Trust checks run when this host can run them; gaps that need conductor-held
material are recorded as named GATEs and never fatal, even under
--strict-trust. Only structural failures -- and the macOS
seal/notarization/staple trio failing under --strict-trust -- exit 1.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIST=""
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$PLATFORM" in
darwin) PLATFORM="darwin" ;;
linux) PLATFORM="linux" ;;
*) PLATFORM="win32" ;;
esac
EXPECT_VERSION=""
STRICT_TRUST=0
EMIT_GATES=""
MODE="release"
ARCHES=""
SCOPED=0
EXPECT_ALIASES=0
declare -a EXTRA_DISTS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dist)
		DIST="${2:-}"
		shift 2
		;;
	--platform)
		PLATFORM="${2:-}"
		shift 2
		;;
	--arch)
		ARCHES="${2:-}"
		shift 2
		;;
	--extra-dist)
		EXTRA_DISTS+=("${2:-}")
		shift 2
		;;
	--expect-aliases)
		EXPECT_ALIASES=1
		shift
		;;
	--expect-version)
		EXPECT_VERSION="${2:-}"
		shift 2
		;;
	--strict-trust)
		STRICT_TRUST=1
		shift
		;;
	--emit-gates)
		EMIT_GATES="${2:-}"
		shift 2
		;;
	--mode)
		MODE="${2:-}"
		shift 2
		;;
	-h | --help)
		usage
		exit 2
		;;
	*)
		echo "verify-tauri-artifacts: unknown option: $1" >&2
		usage
		exit 2
		;;
	esac
done

if [[ -z "$DIST" || ! -d "$DIST" ]]; then
	echo "verify-tauri-artifacts: --dist must be an existing directory" >&2
	usage
	exit 2
fi
case "$PLATFORM" in
darwin | win32 | linux) ;;
*)
	echo "verify-tauri-artifacts: --platform must be darwin, win32 or linux" >&2
	exit 2
	;;
esac
case "$MODE" in
release | testing) ;;
*)
	echo "verify-tauri-artifacts: --mode must be release or testing" >&2
	exit 2
	;;
esac

# Sibling collection dirs (dmgs, deb/rpm, ...) consulted before any class-
# absence failure. A DECLARED dir that does not exist is a caller error, not
# an empty dir: refuse it instead of silently searching nothing.
if [[ ${#EXTRA_DISTS[@]} -gt 0 ]]; then
	for extra in "${EXTRA_DISTS[@]}"; do
		[[ -n "$extra" ]] || {
			echo "verify-tauri-artifacts: --extra-dist needs a directory argument" >&2
			usage
			exit 2
		}
		if [[ ! -d "$extra" ]]; then
			echo "verify-tauri-artifacts: --extra-dist '$extra' is not an existing directory" >&2
			usage
			exit 2
		fi
	done
fi

# Scope declaration: which arches THIS dist is expected to carry. Unscoped
# runs keep the legacy posture (arm64 demanded, sibling-arch absence gated).
declare -a ARCH_LIST=()
if [[ -n "$ARCHES" ]]; then
	SCOPED=1
	IFS=',' read -r -a ARCH_LIST <<<"$ARCHES"
	for token in "${ARCH_LIST[@]}"; do
		case "$token" in
		arm64 | x64) ;;
		*)
			echo "verify-tauri-artifacts: --arch must be a comma-separated list drawn from: arm64, x64 (got '$token')" >&2
			usage
			exit 2
			;;
		esac
	done
fi

# in_scope decides whether an artifact class for <arch> applies to THIS
# invocation: unscoped means everything applies; scoped means only declared
# arches. Out-of-scope classes are matrix topology, not defects.
in_scope() {
	if [[ "$SCOPED" -eq 0 ]]; then
		return 0
	fi
	local wanted
	for wanted in "${ARCH_LIST[@]}"; do
		[[ "$wanted" == "$1" ]] && return 0
	done
	return 1
}

# scope_skip records an out-of-scope class as an INFO line. Deliberately NOT
# a ledger row: absence caused by matrix topology is neither PASS, GATE nor
# FAIL, and must not pollute the gate ledger or the emitted JSON.
scope_skip() {
	echo "INFO (out of declared scope, no ledger row): $1"
}

PASS_COUNT=0
declare -a FAILURES=()
declare -a GATES=()

pass() {
	PASS_COUNT=$((PASS_COUNT + 1))
	echo "PASS: $1"
}

fail() {
	FAILURES+=("$1")
	echo "FAIL: $1"
}

gate() {
	GATES+=("$1")
	echo "GATE (conductor-side material needed, recorded): $1"
}

require_file() {
	require_file_in "$DIST" "$1" "$2" ""
}

require_file_in() {
	local dir="$1" pattern="$2" label="$3" from="${4:-}"
	local hits
	hits=$(cd "$dir" && ls -1 $pattern 2>/dev/null | wc -l | tr -d ' ')
	if [[ "$hits" -ge 1 ]]; then
		pass "$label present ($(cd "$dir" && ls -1 $pattern | head -n1))$from"
	else
		fail "$label missing from $dir (no match for $pattern)"
	fi
}

# from_suffix renders provenance for classes found in an --extra-dist, so the
# ledger shows WHERE an inspected artifact actually lived.
from_suffix() {
	if [[ "$1" == "$DIST" ]]; then
		printf ''
	else
		printf ' [from %s]' "$(basename "$1")"
	fi
}

# find_across_dists searches the primary dist first, then each --extra-dist in
# declaration order, for the given globs. On a hit it sets FIND_DIR and
# FIND_NAME and returns 0; absence from ALL declared dirs returns 1 (the
# caller's cue to fail). This is what lets a conductor build keep version-free
# aliases in dist-artifact while dmgs/deb/rpm live in their sibling dirs.
FIND_DIR=""
FIND_NAME=""
find_across_dists() {
	FIND_DIR=""
	FIND_NAME=""
	local pattern hit extra
	for pattern in "$@"; do
		hit=$(cd "$DIST" && ls -1 $pattern 2>/dev/null | head -n1 || true)
		if [[ -n "$hit" ]]; then
			FIND_DIR="$DIST"
			FIND_NAME="$hit"
			return 0
		fi
	done
	for extra in "${EXTRA_DISTS[@]:-}"; do
		[[ -n "$extra" ]] || continue
		for pattern in "$@"; do
			hit=$(cd "$extra" && ls -1 $pattern 2>/dev/null | head -n1 || true)
			if [[ -n "$hit" ]]; then
				FIND_DIR="$extra"
				FIND_NAME="$hit"
				return 0
			fi
		done
	done
	return 1
}

check_sig_sidecar() {
	local archive="$1/$2"
	local label="$2$(from_suffix "$1")"
	if [[ ! -f "${archive}.sig" ]]; then
		if [[ "$MODE" == "testing" ]]; then
			gate ".sig sidecar for ${label} absent (unsigned testing builds ship no updater signature)"
		else
			fail "missing .sig sidecar for ${label}"
		fi
		return
	fi
	local decoded
	if ! decoded=$(openssl base64 -d -A <"${archive}.sig" 2>/dev/null); then
		fail ".sig for ${label} is not a base64 minisign blob"
		return
	fi
	if [[ "$(printf '%s' "$decoded" | head -c 18)" != "untrusted comment:" ]]; then
		fail ".sig for ${label} does not decode to a minisign signature"
		return
	fi
	if printf '%s' "$decoded" | grep -qi "encrypted secret key"; then
		fail ".sig for ${label} carries private-key material"
		return
	fi
	pass ".sig sidecar for ${label} is a minisign signature blob"
}

check_bundle_resources() {
	local bundle="$1" origin="$2"
	for resource in daemon agent-browser acp-runtime; do
		if [[ -d "$bundle/Contents/Resources/$resource" ]] &&
			[[ -n "$(ls -A "$bundle/Contents/Resources/$resource" 2>/dev/null)" ]]; then
			pass "$origin bundles Resources/$resource"
		else
			fail "$origin is missing Resources/$resource (daemon/agent-browser/ACP runtime are not droppable)"
		fi
	done
	# License notices ship inside the bundled resources (e.g.
	# agent-browser/LICENSE-*) and are mandatory in every base artifact; a
	# package form without them is a structural failure like any other.
	local licenses
	licenses="$(find "$bundle/Contents/Resources" -maxdepth 2 -name 'LICENSE*' -type f 2>/dev/null | head -n1)"
	if [[ -n "$licenses" ]]; then
		pass "$origin bundles licenses (${licenses#"$bundle/Contents/Resources/"})"
	else
		fail "$origin bundles no licenses (license notices are required in every base artifact)"
	fi
	local exe
	exe="$(plutil -extract CFBundleExecutable raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
	if [[ -n "$exe" && -f "$bundle/Contents/MacOS/$exe" ]]; then
		pass "$origin bundles executable $exe"
	else
		fail "$origin has no Contents/MacOS executable matching CFBundleExecutable"
	fi
	if ls "$bundle/Contents/Resources/"*.icns >/dev/null 2>&1 || [[ -d "$bundle/Contents/Resources/icons" ]]; then
		pass "$origin bundles an icon"
	else
		fail "$origin is missing its icon (no .icns or Resources/icons)"
	fi
	local plist_version
	plist_version="$(plutil -extract CFBundleShortVersionString raw -o - "$bundle/Contents/Info.plist" 2>/dev/null || true)"
	if [[ -z "$EXPECT_VERSION" ]]; then
		pass "$origin reports version ${plist_version:-unknown} (--expect-version not set)"
	elif [[ "$plist_version" == "$EXPECT_VERSION" ]]; then
		pass "$origin reports version $plist_version"
	else
		fail "$origin reports version '$plist_version', expected '$EXPECT_VERSION'"
	fi
}

WORKDIR=""
cleanup() {
	if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
		if [[ -n "${DMG_MOUNT:-}" ]]; then
			hdiutil detach "$DMG_MOUNT" -quiet >/dev/null 2>&1 || true
		fi
		rm -rf "$WORKDIR"
	fi
}
trap cleanup EXIT
WORKDIR="$(mktemp -d)"

echo "== verify-tauri-artifacts: dist=$DIST platform=$PLATFORM arch=${ARCHES:-all (unscoped)} version=${EXPECT_VERSION:-unspecified} strict=$STRICT_TRUST"

if [[ -n "$EXPECT_VERSION" ]]; then
	if [[ "$EXPECT_ALIASES" -eq 1 ]]; then
		# Version-free alias layout: the pinned artifact names carry no version
		# by contract, so a filename grep would always come up empty. The
		# version assertion does NOT disappear -- it moves entirely to the
		# embedded metadata checks (CFBundleShortVersionString vs
		# --expect-version) that run inside every inspected bundle form.
		pass "version-free alias layout; filename version check skipped (--expect-aliases), version asserted via embedded bundle metadata"
	else
		COUNT=$(cd "$DIST" && ls -1 | grep -c -- "$EXPECT_VERSION" || true)
		if [[ "$COUNT" -ge 1 ]]; then
			pass "artifacts carry version $EXPECT_VERSION"
		else
			fail "no artifact name in $DIST mentions $EXPECT_VERSION"
		fi
	fi
fi

# mac_updater_glob echoes the filename globs an updater archive for <arch>
# carries (Tauri names them per-arch; the .sig sidecars never match these).
mac_updater_globs() {
	case "$1" in
	arm64) echo "*aarch64*.app.tar.gz" "*arm64*.app.tar.gz" ;;
	x64) echo "*darwin-x64*.app.tar.gz" "*x86_64*.app.tar.gz" ;;
	esac
}

find_app_bundle() {
	find "$1" -maxdepth "${2:-3}" -name '*.app' -type d | head -n1
}

inspect_mac_zip() {
	local zip="$1/$2"
	local label="$2$(from_suffix "$1")"
	local dest="$WORKDIR/zip-$RANDOM"
	mkdir -p "$dest"
	ditto -x -k "$zip" "$dest" || {
		fail "ditto -x -k could not extract ${label}"
		return
	}
	local bundle
	bundle=$(find_app_bundle "$dest")
	if [[ -z "$bundle" ]]; then
		fail "${label} extracts to no .app bundle"
		return
	fi
	check_bundle_resources "$bundle" "${label}"
}

inspect_updater_archive() {
	local tarball="$1/$2"
	local label="$2$(from_suffix "$1")"
	local dest="$WORKDIR/tar-$RANDOM"
	mkdir -p "$dest"
	tar -xzf "$tarball" -C "$dest" || {
		fail "tar -xzf could not extract ${label}"
		return
	}
	local bundle
	bundle=$(find_app_bundle "$dest")
	if [[ -z "$bundle" ]]; then
		fail "${label} extracts to no .app bundle"
		return
	fi
	check_bundle_resources "$bundle" "${label}"
}

inspect_dmg() {
	local dmg="$1/$2"
	local label="$2$(from_suffix "$1")"
	local mount="$WORKDIR/dmg-$RANDOM"
	mkdir -p "$mount"
	hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg" >/dev/null || {
		fail "hdiutil could not mount ${label}"
		return
	}
	DMG_MOUNT="$mount"
	local bundle
	bundle=$(find_app_bundle "$mount")
	if [[ -z "$bundle" ]]; then
		fail "${label} mounts to no .app bundle"
	else
		check_bundle_resources "$bundle" "${label}"
	fi
	hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true
	DMG_MOUNT=""
}

mac_trust_checks() {
	local target="$1"
	# The delegated seal/notarization/staple trio is the ONE strict-fatal trust
	# check: when the tooling exists and the check FAILS, --strict-trust must
	# be able to fail the release. Tooling ABSENT stays a tier-2 named gate.
	if command -v codesign >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
		if "$SCRIPT_DIR/verify-mac-artifact.sh" "$target" >/dev/null 2>&1; then
			pass "seal/notarization/staple verified for $(basename "$target")"
		else
			gate "codesign/spctl/stapler did not pass for $(basename "$target") (expected for an unsigned local build; hard-fails signed CI via --strict-trust)"
			[[ "$STRICT_TRUST" -eq 1 ]] && fail "--strict-trust: $(basename "$target") failed seal/notarization/staple"
		fi
	else
		gate "macOS trust tooling unavailable on this host for $(basename "$target") (conductor-side evidence)"
	fi
}

declare -a TRUST_TARGETS=()

if [[ "$PLATFORM" == "darwin" ]]; then
	APP_BUNDLE=$(find_app_bundle "$DIST" 1)
	if [[ -n "$APP_BUNDLE" ]]; then
		check_bundle_resources "$APP_BUNDLE" "Operator.app"
		TRUST_TARGETS+=("$APP_BUNDLE")
	else
		gate "no unpacked Operator.app in dist (checking packaged forms instead)"
	fi

	# Updater archives, scoped: --arch declares which arches THIS dist must
	# carry. An undeclared arch's absence is matrix topology (SCOPE-SKIP), not
	# a defect: the sibling leg builds and verifies it on its own runner.
	for arch in arm64 x64; do
		if ! in_scope "$arch"; then
			scope_skip "mac $arch updater archive (--arch '$ARCHES' does not declare $arch)"
			continue
		fi
		find_across_dists $(mac_updater_globs "$arch") || true
		if [[ -z "$FIND_NAME" ]]; then
			if [[ "$arch" == "x64" && "$SCOPED" -eq 0 ]]; then
				gate "no mac x64 updater archive in dist (Intel leg builds on its own runner)"
			elif [[ "$MODE" == "testing" ]]; then
				gate "no mac $arch updater archive (*.app.tar.gz) in dist (expected for unsigned testing builds)"
			else
				fail "no mac $arch updater archive (*.app.tar.gz) in $DIST or any --extra-dist"
			fi
			continue
		fi
		require_file_in "$FIND_DIR" "$FIND_NAME" "mac $arch updater archive" "$(from_suffix "$FIND_DIR")"
		check_sig_sidecar "$FIND_DIR" "$FIND_NAME"
		inspect_updater_archive "$FIND_DIR" "$FIND_NAME"
	done

	# Permanent ditto zips and dmgs. Unscoped runs keep the legacy single-glob
	# posture; scoped runs demand one zip + dmg per DECLARED arch. Both consult
	# the --extra-dist siblings before declaring a class absent, and inspect a
	# sibling-resident artifact there with full checks.
	if [[ "$SCOPED" -eq 0 ]]; then
		if find_across_dists "operator-darwin-*.zip"; then
			require_file_in "$FIND_DIR" "$FIND_NAME" "ditto mac zip" "$(from_suffix "$FIND_DIR")"
			inspect_mac_zip "$FIND_DIR" "$FIND_NAME"
			TRUST_TARGETS+=("$FIND_DIR/$FIND_NAME")
		else
			fail "no operator-darwin-*.zip in $DIST or any --extra-dist (latest-mac.yml would lose its target)"
		fi

		if find_across_dists "*.dmg"; then
			require_file_in "$FIND_DIR" "$FIND_NAME" "mac dmg" "$(from_suffix "$FIND_DIR")"
			inspect_dmg "$FIND_DIR" "$FIND_NAME"
			TRUST_TARGETS+=("$FIND_DIR/$FIND_NAME")
		else
			fail "no .dmg in $DIST or any --extra-dist"
		fi
	else
		for arch in arm64 x64; do
			in_scope "$arch" || {
				scope_skip "ditto mac zip / dmg for $arch (--arch '$ARCHES' does not declare $arch)"
				continue
			}
			case "$arch" in
			arm64)
				zip_globs=("operator-darwin-arm64*.zip")
				dmg_globs=("operator-darwin-arm64*.dmg" "*aarch64*.dmg" "*arm64*.dmg")
				;;
			x64)
				zip_globs=("operator-darwin-x64*.zip")
				dmg_globs=("operator-darwin-x64*.dmg" "*x86_64*.dmg" "*darwin-x64*.dmg")
				;;
			esac
			if find_across_dists "${zip_globs[@]}"; then
				require_file_in "$FIND_DIR" "$FIND_NAME" "ditto mac zip ($arch)" "$(from_suffix "$FIND_DIR")"
				inspect_mac_zip "$FIND_DIR" "$FIND_NAME"
				TRUST_TARGETS+=("$FIND_DIR/$FIND_NAME")
			else
				fail "no operator-darwin-${arch}*.zip in $DIST or any --extra-dist (--arch $arch declared; latest-mac.yml would lose its target)"
			fi

			if find_across_dists "${dmg_globs[@]}"; then
				require_file_in "$FIND_DIR" "$FIND_NAME" "mac dmg ($arch)" "$(from_suffix "$FIND_DIR")"
				inspect_dmg "$FIND_DIR" "$FIND_NAME"
				TRUST_TARGETS+=("$FIND_DIR/$FIND_NAME")
			else
				fail "no dmg matching *$arch* in $DIST or any --extra-dist (--arch $arch declared)"
			fi
		done
	fi

	for trust_target in "${TRUST_TARGETS[@]:-}"; do
		[[ -n "$trust_target" && -e "$trust_target" ]] || continue
		mac_trust_checks "$trust_target"
	done
fi

if [[ "$PLATFORM" == "win32" ]]; then
	find_across_dists "*-setup.exe" "*.exe" || true
	NSIS_EXE="$FIND_NAME"
	NSIS_DIR="$FIND_DIR"
	if [[ -n "$NSIS_EXE" ]]; then
		require_file_in "$NSIS_DIR" "$NSIS_EXE" "windows nsis installer" "$(from_suffix "$NSIS_DIR")"
		if [[ "$NSIS_EXE" != *x64* && "$NSIS_EXE" != *x86_64* && "$NSIS_EXE" != *win32* ]]; then
			fail "nsis installer '$NSIS_EXE' does not carry an x64 architecture token"
		fi
		check_sig_sidecar "$NSIS_DIR" "$NSIS_EXE"
		if command -v file >/dev/null 2>&1; then
			if file "$NSIS_DIR/$NSIS_EXE" | grep -q "x86-64\|PE32+"; then
				pass "nsis installer is an x86-64 PE binary"
			else
				fail "nsis installer is not an x86-64 PE binary: $(file "$NSIS_DIR/$NSIS_EXE")"
			fi
		else
			gate "'file' unavailable; PE machine type unverified for $NSIS_EXE"
		fi
		# License notices ride inside the installer payload next to the bundled
		# resources. Listing an NSIS payload is BEST-EFFORT (7z): a confirmed
		# listing that shows license entries passes; no listing tool, or a
		# listing that surfaces none, is recorded as a named gate for the
		# conductor's smoke-install evidence -- never a structural failure
		# (tier 2: fragile archive parsing must not brick a good release).
		NSIS_LISTING=""
		if command -v 7z >/dev/null 2>&1; then
			NSIS_LISTING="$(7z l "$NSIS_DIR/$NSIS_EXE" 2>/dev/null || true)"
		elif command -v 7zz >/dev/null 2>&1; then
			NSIS_LISTING="$(7zz l "$NSIS_DIR/$NSIS_EXE" 2>/dev/null || true)"
		fi
		if printf '%s' "$NSIS_LISTING" | grep -qi "license"; then
			pass "nsis installer packages licenses"
		elif [[ -z "$NSIS_LISTING" ]]; then
			gate "nsis installer license notices unverified here (no NSIS listing tool on this host; conductor verifies with the smoke install)"
		else
			gate "nsis installer listing surfaced no license entries; conductor verifies licenses with the smoke-install evidence"
		fi
	else
		fail "no windows nsis installer (.exe) in $DIST or any --extra-dist"
	fi
	# Tier-2 gates: the signtool signing step in this workflow already fails
	# its own step if signing breaks; post-hoc re-validation of Authenticode
	# and a clean-machine smoke install are conductor-side evidence, never a
	# build-host duty and never fatal -- even under --strict-trust.
	gate "Authenticode verification requires a Windows runner (signtool / Get-AuthenticodeSignature); record evidence there"
	gate "NSIS silent-install smoke requires a clean Windows runner"
fi

if [[ "$PLATFORM" == "linux" ]]; then
	find_across_dists "*.AppImage" || true
	APPIMAGE="$FIND_NAME"
	APPIMAGE_DIR="$FIND_DIR"
	if [[ -n "$APPIMAGE" ]]; then
		require_file_in "$APPIMAGE_DIR" "$APPIMAGE" "linux appimage" "$(from_suffix "$APPIMAGE_DIR")"
		if [[ "$APPIMAGE" != *x86_64* && "$APPIMAGE" != *amd64* && "$APPIMAGE" != *x64* ]]; then
			fail "appimage '$APPIMAGE' does not carry an x86-64 architecture token"
		fi
		check_sig_sidecar "$APPIMAGE_DIR" "$APPIMAGE"
	else
		fail "no linux appimage in $DIST or any --extra-dist"
	fi

	find_across_dists "*.deb" || true
	if [[ -n "$FIND_NAME" ]]; then
		DEB_DIR="$FIND_DIR"
		DEB_NAME="$FIND_NAME"
		require_file_in "$DEB_DIR" "*.deb" "linux deb" "$(from_suffix "$DEB_DIR")"
	else
		fail "no .deb in $DIST or any --extra-dist"
	fi
	find_across_dists "*.rpm" || true
	if [[ -n "$FIND_NAME" ]]; then
		RPM_DIR="$FIND_DIR"
		RPM_NAME="$FIND_NAME"
		require_file_in "$RPM_DIR" "*.rpm" "linux rpm" "$(from_suffix "$RPM_DIR")"
	else
		fail "no .rpm in $DIST or any --extra-dist"
	fi

	if [[ -z "${DEB_NAME:-}" ]]; then
		: # absence already failed above; nothing left to inspect
	elif command -v dpkg-deb >/dev/null 2>&1; then
		LISTING=$(dpkg-deb -c "$DEB_DIR/$DEB_NAME")
		for member in "usr/bin/operator" "daemon" "agent-browser" "acp-runtime" "LICENSE"; do
			if printf '%s' "$LISTING" | grep -q "$member"; then
				pass "deb packages $member"
			else
				fail "deb is missing $member"
			fi
		done
	else
		gate "dpkg-deb unavailable; deb contents unverified here"
	fi
	if [[ -z "${RPM_NAME:-}" ]]; then
		: # absence already failed above; nothing left to inspect
	elif command -v rpm >/dev/null 2>&1; then
		RPM_LISTING="$(rpm -qlp "$RPM_DIR/$RPM_NAME" 2>/dev/null || true)"
		if printf '%s' "$RPM_LISTING" | grep -q "usr/bin/operator"; then
			pass "rpm packages usr/bin/operator"
		else
			fail "rpm is missing usr/bin/operator"
		fi
		if printf '%s' "$RPM_LISTING" | grep -q "LICENSE"; then
			pass "rpm packages licenses"
		else
			fail "rpm is missing license notices"
		fi
		# Tier-2: rpm -K needs the conductor-imported signing key; the content
		# listing above is the build-host's share of rpm verification.
		gate "rpm signature check (rpm -K against the signing key) runs on the signing infrastructure"
	else
		gate "rpm unavailable; rpm contents and signature unverified here"
	fi
fi

echo ""
echo "== summary: $PASS_COUNT passed, ${#FAILURES[@]} failed, ${#GATES[@]} gated"
for item in "${FAILURES[@]:-}"; do
	[[ -n "$item" ]] && echo "FAIL: $item"
done
for item in "${GATES[@]:-}"; do
	[[ -n "$item" ]] && echo "GATE: $item"
done

if [[ -n "$EMIT_GATES" ]]; then
	{
		echo "{"
		echo "  \"dist\": \"$DIST\","
		echo "  \"platform\": \"$PLATFORM\","
		echo "  \"passed\": $PASS_COUNT,"
		echo "  \"findings\": ["
		first=1
		for item in "${FAILURES[@]:-}"; do
			[[ -z "$item" ]] && continue
			[[ $first -eq 0 ]] && echo ","
			printf '    {"status": "fail", "check": "%s"}' "$item"
			first=0
		done
		for item in "${GATES[@]:-}"; do
			[[ -z "$item" ]] && continue
			[[ $first -eq 0 ]] && echo ","
			printf '    {"status": "gate", "check": "%s"}' "$item"
			first=0
		done
		[[ $first -eq 0 ]] && echo ""
		echo "  ]"
		echo "}"
	} >"$EMIT_GATES"
	echo "gates ledger written to $EMIT_GATES"
fi

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
	echo "verify-tauri-artifacts: FAILED (${#FAILURES[@]} failure(s); includes trust checks attempted and failed here)" >&2
	exit 1
fi
echo "verify-tauri-artifacts: OK (every check applicable to the declared scope that is executable on this host passed; GATEs above need conductor-held material and are recorded, never skipped)"
