# Development Guide

How to set up, build, run, and test Operator locally.

The desktop shell is **Tauri + React**; the Electron/Forge app this page once
described was removed with Task 21 of the Tauri port. `npm run tauri:dev` is the
normal dev loop and it supervises the daemon for you.

## Prerequisites

| Tool       | Version            | Notes                                                                                                     |
| ---------- | ------------------ | ---------------------------------------------------------------------------------------------------------- |
| Go         | 1.25.7+            | Pinned in `backend/go.mod` (`go version` to check; [go.dev](https://go.dev/dl/))                          |
| Rust       | 1.96.0             | Pinned in `frontend/rust-toolchain.toml`; rustup selects it automatically, CI also exports `RUSTUP_TOOLCHAIN=1.96.0` |
| Node.js    | 22.x recommended   | No `engines` pin; CI runs the frontend checks on Node 24 (`.github/workflows/frontend.yml`) and release/build legs on Node 22. Local verification for this document used v22.23.2. |
| npm        | 10                 | Ships with Node.js                                                                                        |
| Flutter    | 3.44.5             | Mobile client only (`packages/mobile`); same version CI pins in `.github/workflows/mobile-flutter.yml`    |
| Nix (opt.) | -                  | `nix develop` drops you into a shell with all deps; see `../flake.nix`                                    |

Additional runtime dependencies for the daemon:

- **git** (for worktree creation and agent integration)
- **A running agent CLI** (Claude Code, Codex, Aider, etc.) — see
  [the installation guide](https://opr-agents.com/docs/installation)

## Project Layout

```text
operator/
  backend/              # Go daemon (Cobra CLI, HTTP API, services, storage)
    cmd/opr/             # CLI entry point
    internal/           # All library code
      cli/              # CLI command implementations
      httpd/            # HTTP controllers, apispec, middleware
      service/          # Business logic layer
      domain/           # Domain types
      ports/            # Port interfaces (contracts)
      storage/          # SQLite migrations, queries, generated code
  frontend/             # Tauri + React desktop app
    src/                # Renderer + shared modules
    src-tauri/          # Rust shell: daemon supervision, native integrations, updater
    e2e/                # Playwright renderer E2E tests
    e2e-tauri/          # WebdriverIO tests against the real Tauri binary
    perf/               # Benchmark harness, parity ledger, checked-in results
  packages/
    mobile/             # Flutter mobile companion app
    opr/                # Legacy npm CLI package (frozen)
  docs/                 # Architecture, ADRs, benchmarks, status
  CONTRIBUTING.md       # Contribution guide
```

## Getting the code

```bash
git clone https://github.com/OmarAly92/operator.git
cd operator
npm ci
```

### Branching

```bash
git checkout -b my-feature-branch
```

Keep your branch up to date by rebasing on master:

```bash
git fetch origin
git rebase origin/master
```

### Committing

Keep commits atomic - one logical change per commit. Stage related changes and commit with a conventional message:

```bash
git add <files>
```

Commit message tags:

| Tag        | When to use                           |
| ---------- | ------------------------------------- |
| `feat`     | New feature                           |
| `fix`      | Bug fix                               |
| `docs`     | Documentation only                    |
| `test`     | Adding or fixing tests                |
| `refactor` | Code change with no functional change |
| `chore`    | Maintenance, tooling, dependencies    |

Use **trailers** to provide additional context:

```bash
git commit -m "fix: handle nil pointer in session lookup

The session resolver panicked when the store returned a nil session
without an error. Return ErrNotFound instead.

Signed-off-by: Your Name <your.email@example.com>
Co-authored-by: Contributor Name <contributor@example.com>"
```

## Backend

### Build

```bash
cd backend
go build ./...
```

### Run the daemon

```bash
cd backend
# Start the daemon (loopback HTTP server on 127.0.0.1)
go run .
```

The CLI is built with Cobra. From `backend/`, run `go run ./cmd/opr --help` for
available commands.

### Run tests

```bash
cd backend
go test ./...              # all tests
go test -race ./...        # with race detection
go test -v ./internal/cli/ # a specific package
```

### Lint

```bash
npm run lint               # from repo root: go test ./... + golangci-lint v2.12.2
```

### Code generation

```bash
# Regenerate sqlc code after editing queries or schema
npm run sqlc

# Regenerate OpenAPI spec and frontend TypeScript types
npm run api
```

## Frontend (Tauri desktop)

### Install dependencies

```bash
cd frontend
npm install
```

### Run in development mode

```bash
cd frontend
npm run tauri:dev     # Tauri desktop shell + Vite dev server + supervised daemon
```

`tauri:dev` starts the Vite dev server on `127.0.0.1:5173` (`devUrl` in
`src-tauri/tauri.conf.json`) and opens the Tauri shell against it. The Rust side
supervises the loopback daemon for you. Before the first run, build the packaged
sidecars so the resources exist:

```bash
cd frontend
npm run build:daemon              # Go daemon binary into ../daemon/
npm run browser-runtime:prepare   # checksum-pinned agent-browser into ../agent-browser/
npm run build:acp-runtime         # Node 22.23.2 ACP runtime into ../resources/acp-runtime/
```

### Renderer only, no desktop shell

```bash
cd frontend
npm run dev:web       # Vite with VITE_RENDERER_PREVIEW=1; no shell, no daemon
```

Fast for UI iteration; anything that talks to the backend stays dead unless you
start a daemon yourself. This is also what the Playwright renderer E2E suite drives.

### Build platform artifacts

```bash
cd frontend
npm run tauri:build   # unsigned bundle for the current OS (app+dmg on macOS)
```

`bundle.targets` in `src-tauri/tauri.conf.json` covers every release form:
macOS `.app` + `.dmg`, Windows NSIS `.exe`, Linux AppImage/deb/rpm. Every bundle
carries the Go daemon, agent-browser, the ACP runtime, licenses, and icons.
`npm run tauri:release` builds with `src-tauri/tauri.release.conf.json`, which
enables signed updater artifacts and bakes the production feed base URL; it
needs the minisign signing key material a minimal setup does not have. Release
pipelines are documented in [`frontend/docs/desktop-release.md`](../frontend/docs/desktop-release.md).

### State roots

All state lives under `~/.operator` (overridable via `OPERATOR_DATA_DIR` /
`OPERATOR_RUN_FILE`). The Tauri webview's data directory is pinned to
`~/.operator/webview`; the updater stages under `~/.operator/updater/`, and the
managed browser engine plus per-session browser profiles live under the state
root as well. Never read or write OS-default app-data locations.

### Managed browser first use

Browser automation is owned by the daemon through the packaged `agent-browser`
binary. Development prepares it with `npm run browser-runtime:prepare`; at
runtime the daemon resolves (and, when missing, installs) the pinned engine on
first automation use under the operator state root. Each session gets an
isolated Chromium profile that is discarded when the session ends. See
[`docs/architecture.md`](architecture.md), "Standalone Browser Runtime".

### External preview

Previews open outside the shell: `opr preview <target>` publishes a validated
preview target that opens once in the user's default browser, and
`opr preview clear` removes the target without opening anything. The former
embedded Browser panel was removed with the Tauri port.

### Updater channels

Update settings live in the Go settings store (`PATCH /api/v1/settings/updates`).
Channels are `latest` (stable), `nightly`, and per-PR feature channels (`pr<N>`);
feeds are generated by `frontend/scripts/tauri-feed.mjs`. The first-run opt-in
prompt keeps updates disabled until accepted.

## Tests and gates

### Frontend

```bash
cd frontend
npm run test                   # Vitest unit suite
npm run typecheck              # tsc --noEmit
npm run check:desktop-parity   # parity ledger (perf/parity-ledger.json) covers every desktop surface
node --test scripts/no-electron.test.mjs   # proves no Electron import/package/config remains
npm run test:e2e:renderer      # Playwright @T0/@P0 renderer suite (drives dev:web)
npm run typecheck:e2e          # Playwright suite types
npm run test:e2e:tauri         # builds the debug shell with the e2e Cargo feature, runs WebdriverIO against the real binary
npm run typecheck:e2e-tauri    # WDIO suite types
```

Or from repo root: `npm run frontend:typecheck`.

### Phase 0 evidence and benchmarks

The Phase 0 decision tooling derives its verdict from verified raw evidence;
until native-runner artifacts land it exits 1 with `stop-port`, naming every
missing evidence file:

```bash
cd frontend
node scripts/phase0-decision.mjs --results perf/results   # stop-port until native evidence lands
npm run bench:terminal                     # terminal throughput/input harness
npm run test:tauri-state                   # state-audit regression suite; the audit itself
                                           # (npm run audit:tauri-state) runs per-OS inside the Phase 0 workflow
node scripts/route-bundle-report.mjs --label after    # initial-route parse-bytes report -> perf/results/route-graph/
node scripts/heap-summary.mjs --label after --probe empty-board   # RSS probes -> perf/results/heap/
```

`scripts/benchmark-shell.mjs` still supports only the Electron shell; warm-start
and idle-memory comparisons need native runners. The measurement contract,
binding gates, and honest scope of local probes live in
[`docs/benchmarks/tauri-port-baseline.md`](benchmarks/tauri-port-baseline.md).

### Verify packaged artifacts

```bash
cd frontend
./scripts/verify-tauri-artifacts.sh --dist dist --mode testing   # structural inspection; unsigned gates recorded, never fatal
./scripts/verify-mac-artifact.sh <file.zip|.app|.dmg|.app.tar.gz>  # seal/notarization/staple check for one macOS artifact
```

## Mobile companion app

The mobile companion app lives at `packages/mobile` (Flutter). See
`packages/mobile/README.md` and `docs/mobile-parity-ledger.md` for setup and
history — the latter records where the retired React Native prototype's
behavior went. Until a tracked contributor guide lands, use the desktop/backend
workflow above and check open issues/PRs for current mobile-specific setup
notes.

## Running end-to-end

1. Start the desktop app with `npm run tauri:dev` from `frontend/`.
2. The Tauri shell resolves the login-shell environment, spawns, and supervises
   the loopback daemon.
3. Use `npm run dev:web` only for renderer-only development; it launches no
   shell and no daemon.

For CLI-only usage, open two terminals:

**Terminal 1 -- start the daemon:**

```bash
cd backend
go run .
```

**Terminal 2 -- interact while the daemon is running:**

```bash
cd backend
go run ./cmd/opr status
go run ./cmd/opr --help
```

## Testing tips

### Backend

- Backend tests use `httptest.Server` and injected fakes - no real daemon
  required.
- Run the narrowest relevant test suite first (e.g. `go test ./internal/cli/`),
  then the full suite.

### Frontend

- Unit tests use Vitest and run in a simulated renderer environment.
- Playwright renderer tests drive the web renderer started by `dev:web`; they
  do not launch the desktop shell.
- WebdriverIO tests (`test:e2e:tauri`) build the real debug shell with the
  `e2e` Cargo feature — the only configuration in which the embedded WebDriver
  plugins compile in — and exercise the actual binary end to end.
- After changing API types, run `npm run api` from root to regenerate
  `frontend/src/api/schema.ts`.

## Troubleshooting

### Backend build / test failures

| Symptom                              | Likely cause                               | Fix                                                                                                                                                                                                                                                                               |
| ------------------------------------ | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `go: go.mod requires go >= 1.25`     | Wrong Go version                           | `go version`; install Go 1.25.7+ from [go.dev]                                                                                                                                                                                                                                    |
| `sqlc generate` produces errors      | Query SQL syntax or schema migration issue | Check `backend/internal/storage/sqlite/queries/` for SQL syntax, placeholder counts, and referenced columns/tables; if you changed the schema, add a new migration in `backend/internal/storage/sqlite/migrations/` instead of editing an existing one, then rerun `npm run sqlc` |
| `openapi.yaml` is stale              | Changed DTOs without regenerating          | Run `npm run api` from repo root                                                                                                                                                                                                                                                  |
| `golangci-lint` failures             | Linter version mismatch                    | Install v2.12.2 or use `npm run lint` from root                                                                                                                                                                                                                                   |
| Tests fail with "connection refused" | Test tries real daemon                     | Tests should use `httptest`; check for `go test ./...` without a live daemon                                                                                                                                                                                                      |

### Frontend build / test failures

| Symptom                                   | Likely cause                    | Fix                                                                        |
| ----------------------------------------- | ------------------------------- | -------------------------------------------------------------------------- |
| `npm run typecheck` has type errors       | API types out of sync           | Run `npm run api` from repo root to regenerate                             |
| `cargo build` uses the wrong toolchain    | rustup did not pick up the pin  | Confirm `frontend/rust-toolchain.toml` exists; run `rustup toolchain install 1.96.0` |
| `tauri:dev` cannot find sidecar resources | Sidecars not built              | Run `build:daemon`, `browser-runtime:prepare`, `build:acp-runtime` once     |
| `npm install` or `npm ci` fails           | Node.js version too old         | Use Node 20.19+ (CI pins 24 for checks / 22 for build legs)                |

### Code generation drift

If CI fails on the `api-drift` check, the OpenAPI-generated files are out of sync with source. Regenerate them locally and commit the updated files:

```bash
npm run api
```

If regeneration introduces unexpected diffs beyond your changes, check that your local tool versions match CI (Go 1.25.7+, Node 20.19+, npm 10+).

## OpenAPI spec and generated types

The API is defined in Go controller DTOs and operation registrations. Edit
these source files, then regenerate:

```bash
npm run api
```

The generated artifacts are:

- `backend/internal/httpd/apispec/openapi.yaml`
- `frontend/src/api/schema.ts`

Both must be committed together with the Go changes. CI verifies they are
in sync.
