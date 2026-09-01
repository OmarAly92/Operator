#!/usr/bin/env bash
# Cross-compile the Go `opr` binary (backend/cmd/opr) for every supported
# platform and drop each into the matching platform package's bin/ dir.
#
# Run this from any cwd before `npm publish`. It is the ONLY way the binaries
# get into the platform packages; they are gitignored and produced here, then
# shipped in each npm tarball via that package's `files` entry.
#
# CGO-free build (modernc.org/sqlite driver) so cross-compilation needs no C
# toolchain. Prod build: no -ldflags, so cli.releaseRepo keeps its default
# (OmarAly92/operator).
set -euo pipefail

# Repo layout: this script lives at <repo>/packages/build-binaries.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
TERMINAL_DIR="${SCRIPT_DIR}/terminal"

# Rebuild the vt-host wasm module before the Go build, so the artifact
# embedded via vtwasm/embed.go can never drift from the source that produced
# it. Plain `cargo build`: the .cargo/config.toml pinned under TERMINAL_DIR
# supplies +bulk-memory,+simd128 automatically.
echo "Building vt-host wasm module from ${TERMINAL_DIR}"
(cd "${TERMINAL_DIR}" && cargo build --release -p vt-host --target wasm32-unknown-unknown)
cp "${TERMINAL_DIR}/target/wasm32-unknown-unknown/release/vt_host.wasm" \
  "${BACKEND_DIR}/internal/adapters/runtime/ptyhost/vtwasm/assets/vt_host.wasm"

# pkg_dir : npm_os : npm_arch : GOOS : GOARCH : bin_name
TARGETS=(
  "opr-darwin-arm64:darwin:arm64:darwin:arm64:opr"
  "opr-darwin-x64:darwin:x64:darwin:amd64:opr"
  "opr-win32-x64:win32:x64:windows:amd64:opr.exe"
  "opr-linux-x64:linux:x64:linux:amd64:opr"
)

echo "Building opr binaries from ${BACKEND_DIR}/cmd/opr"
for t in "${TARGETS[@]}"; do
  IFS=":" read -r pkg npm_os npm_arch goos goarch bin <<<"$t"
  out="${SCRIPT_DIR}/${pkg}/bin/${bin}"
  mkdir -p "${SCRIPT_DIR}/${pkg}/bin"
  echo "  -> ${pkg} (GOOS=${goos} GOARCH=${goarch}) -> bin/${bin}"
  (cd "${BACKEND_DIR}" && CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" \
    go build -o "${out}" ./cmd/opr)
  chmod 0755 "${out}"
done

echo "Done. Built binaries:"
for t in "${TARGETS[@]}"; do
  IFS=":" read -r pkg _ _ _ _ bin <<<"$t"
  file "${SCRIPT_DIR}/${pkg}/bin/${bin}"
done
