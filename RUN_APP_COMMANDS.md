# Run the app

Commands to run Operator's frontend and backend locally.

> **The usual case is one command.** `npm run tauri:dev` from `frontend/` starts the
> Tauri desktop shell, which builds and supervises the loopback daemon for you. You
> only start the backend yourself for CLI-only work — see
> [Backend on its own](#backend-on-its-own).

Full context: [`docs/development.md`](docs/development.md).

## Prerequisites

| Tool | Minimum version |
| --- | --- |
| Go | 1.25.7 |
| Node.js | 20.19.0 |
| npm | 10 |

Plus `git`, the Rust toolchain pinned in `frontend/rust-toolchain.toml`, and at least
one agent CLI (Claude Code, Codex, Aider, …) on your PATH for the daemon to drive.
`nix develop` drops you into a shell with all of it.

## Run everything (normal path)

```bash
cd frontend && npm install
```

```bash
cd frontend && npm run tauri:dev
```

`tauri:dev` runs the Tauri app against a Vite dev server (`dev:web`) on `127.0.0.1:5173`.
Build the sidecars once before the first run so the packaged resources exist:

```bash
cd frontend && npm run build:daemon && npm run browser-runtime:prepare && npm run build:acp-runtime
```

### Renderer only, no desktop shell

```bash
cd frontend && npm run dev:web
```

Vite serves the renderer with `VITE_RENDERER_PREVIEW=1`. Fast for UI iteration, but it
launches no desktop shell and no daemon, so anything that talks to the backend is dead.
This is also what the Playwright renderer E2E suite drives.

## Backend on its own

For CLI-only usage, in two terminals.

**Terminal 1 — the daemon** (loopback HTTP on `127.0.0.1`):

```bash
cd backend && go run .
```

**Terminal 2 — talk to it while it runs:**

```bash
cd backend && go run ./cmd/opr status
```

```bash
cd backend && go run ./cmd/opr --help
```

## Mobile client

The Flutter app in `packages/mobile` is a thin client: it runs no agents and needs a
daemon it can reach over the network, which the loopback listener is not. Pair it
against a daemon with the LAN listener enabled ("Connect Mobile").

```bash
cd packages/mobile && flutter run
```

## Build

```bash
cd backend && go build ./...
```

The frontend has no plain `build` script — packaging is the build. For the current
platform:

```bash
cd frontend && npm run tauri:build
```

`npm run tauri:release` builds with the release updater configuration instead; it needs
the signing key material that a minimal setup and `nix develop` do not provide — on a
fresh machine prefer `npm run tauri:build`.

## Checks

```bash
npm run lint
```

```bash
npm run frontend:typecheck
```

```bash
cd frontend && npm run test
```

```bash
cd packages/mobile && flutter analyze && flutter test
```

## After changing the API

The OpenAPI spec and the frontend TypeScript types are generated. Edit the Go source,
then regenerate from the repo root and commit both artifacts with your change:

```bash
npm run api
```
