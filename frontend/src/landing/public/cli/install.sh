#!/bin/sh
# Operator CLI installer
#
# Usage:
#   curl -fsSL https://operator.example.com/cli/install.sh | sh
#
# Installs the `opr` CLI via the Homebrew tap. For the desktop app, download it
# from https://github.com/OmarAly92/operator/releases/latest.

set -eu

BOLD='\033[1m'
GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

info() { printf "${GREEN}==>${RESET} %s\n" "$1" >&2; }
error() { printf "${RED}error:${RESET} %s\n" "$1" >&2; exit 1; }

RELEASES_URL="https://github.com/OmarAly92/operator/releases/latest"

main() {
    printf "${BOLD}Installing Operator${RESET}\n\n"

    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew is required. Install it from https://brew.sh, or download the desktop app from ${RELEASES_URL}"
    fi

    info "Installing via Homebrew"
    brew install omaraly92/tap/operator

    printf "\n${GREEN}${BOLD}Installed!${RESET}\n"
    printf "Run ${BOLD}opr${RESET} to get started.\n"
}

main "$@"
