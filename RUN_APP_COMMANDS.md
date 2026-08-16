# Run the app

Commands to run Operator's frontend and backend locally.

> **The usual case is one command.** `npm run dev` from `frontend/` starts Electron,
> which builds and supervises the loopback daemon for you. You only start the backend
> yourself for CLI-only work — see [Backend on its own](#backend-on-its-own).

Full context: [`docs/development.md`](docs/development.md).

## Prerequisites

| Tool | Minimum version |
| --- | --- |
| Go | 1.25.7 |
| Node.js | 20.19.0 |
| npm | 10 |

Plus `git`, and at least one agent CLI (Claude Code, Codex, Aider, …) on your PATH for
the daemon to drive. `nix develop` drops you into a shell with all of it.

## Run everything (normal path)

```bash
cd frontend && npm install
```

```bash
cd frontend && npm run dev
```

`predev` builds the daemon binary, prepares the browser runtime and builds the ACP
runtime before Electron Forge starts, so the first run is slower than later ones. The
Electron main process then starts and supervises the daemon on `127.0.0.1` — do not
start the backend separately for this.

### Renderer only, no Electron

```bash
cd frontend && npm run dev:web
```

Vite serves the renderer with `VITE_NO_ELECTRON=1`. Fast for UI iteration, but it
launches no Electron and no daemon, so anything that talks to the backend is dead.
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
cd frontend && npm run package
```

`npm run make` creates distributables instead, but needs platform packaging tools that
a minimal setup and `nix develop` do not provide — on a fresh Linux machine prefer
`npm run package`.

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
