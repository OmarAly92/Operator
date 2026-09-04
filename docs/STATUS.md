# operator status

Current `codex/tauri-port` ships a working single-user local loop: the Go daemon
and the Tauri + React desktop shell both drive a live daemon over HTTP/SSE/WebSocket.
The core GitHub flow works end-to-end: add project → spawn session/orchestrator →
attach terminal → observe PR → merge. The Electron shell was removed with Task 21
of the Tauri port (`docs/benchmarks/tauri-port-baseline.md` records the port's
measurement contract and its still-open external gates).

This file tracks progress. For what the product _is_ and how to run it, see the
top-level [`README.md`](../README.md); for the backend mental model see
[`architecture.md`](architecture.md).

## Build & test

The local gate is the backend Go build and race-enabled test suite:

```bash
cd backend && go build ./... && go test -race ./...
```

`npm run lint` (from the repo root) runs `go test ./...` plus golangci-lint v2.12.2.
Frontend checks live under `frontend/` (`npm run typecheck`, `npm run tauri:build`,
Playwright renderer E2E, WebdriverIO native-shell E2E,
`npm run check:desktop-parity`, `node --test scripts/no-electron.test.mjs`).
See [`docs/development.md`](development.md) for the full command matrix and
[`AGENTS.md`](../AGENTS.md) for the regen workflow when touching the API
surface (`npm run sqlc`, `npm run api`).

## Shipped

### Backend (Go daemon)

- Loopback-only HTTP daemon (chi router, CORS, per-request timeout,
  `/healthz` / `/readyz` / `/shutdown`).
- SQLite store with goose migrations and sqlc-generated queries; DB
  trigger-based change-data-capture into `change_log`.
- CDC poller + broadcaster feeding in-process subscribers and the SSE stream
  at `GET /api/v1/events` (with `Last-Event-ID` replay).
- Full session lifecycle over HTTP: list, get, spawn, kill, restore, rename,
  rollback, cleanup, send, activity, PR claim/list. Orchestrator routes
  (list/spawn/get) are wired too.
- One session kind. Every session runs the agent's own terminal UI in the
  pty-host runtime; there is no chat controller to choose and no interface
  handoff. The ACP/chat subsystem is still in the tree but unreachable, and is
  deleted in Phase 4 of `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`.
- The dormant ACP/chat implementation and its schema remain compilable during
  the staged removal, but no spawn, route, desktop surface, or mobile surface can
  select it. Phase 4 removes it.
- Project CRUD plus per-project config (`PUT /projects/{id}/config`).
- PR action engine wired into the API: `POST /prs/{id}/merge` and
  `/prs/{id}/resolve-comments`.
- Review routes registered: `GET /reviews`, `POST /reviews/execute`,
  `POST /reviews/{id}/send`.
- Interactive reviewer panes for Aider, Agy, Amp, Auggie, Autohand,
  Claude Code, Cline, Codex, Continue, GitHub Copilot, Crush, Cursor, Devin,
  Droid, Goose, Grok, Kilo Code, Kimchi, Kiro, Kimi, OpenCode, Pi, Qwen, and Vibe. Pi uses an Operator-data-owned extension with built-in/project
  resources disabled, structured read-only inspection/reporting tools, and
  Escape-based turn cancellation. Kiro also uses its native Escape
  cancellation. Continue, Qwen, and Vibe also use Escape cancellation. Agy,
  Continue, Devin, Droid, Goose, Kimchi, Kimi, Qwen, and Vibe are explicitly experimental and host-trusted. Grok, Crush, Auggie, Cline, and Autohand are experimental user-approved reviewers that retain their native approval prompts instead of receiving broad unattended flags:
  native modes, autonomous settings, and prompts are not OS or network containment.
- The provider-neutral interactive-reviewer capability gateway and neutral
  Operator-owned working-directory contract are available. The experimental
  host-trusted adapters remain candidates for future contained execution once
  their documented sandbox, environment-replacement, broker, and gateway
  prerequisites are implemented.
- Durable dashboard notifications for `needs_input`, `ready_to_merge`,
  `pr_merged`, and `pr_closed_unmerged`: backend enrichment/persistence,
  cursor-paginated read/unread history, live notification stream, and read
  acknowledgement API.
- SCM observer (`internal/observe/scm`) wired into the daemon: GitHub provider,
  lazy/non-blocking auth, per-PR polling with ETag guards and semantic diffing,
  feeding PR facts into lifecycle, which sends agent nudges for CI failures,
  review feedback, and merge conflicts
  ([#75](https://github.com/OmarAly92/operator/issues/75),
  [#108](https://github.com/OmarAly92/operator/issues/108),
  [#109](https://github.com/OmarAly92/operator/issues/109)).
- Terminal mux over WebSocket (`/mux`): per-client pty-host attach stream on
  Darwin/Linux; conpty loopback pty-host on Windows.
- Durable shell blocks for standalone shells: a single capture tee writes a
  bounded journal independent of attached clients; the daemon adopts it after restart,
  persists exact raw replays in `terminal_blocks`, and exposes chronological history at
  `GET /api/v1/shell-terminals/{handleId}/blocks`. History retains the newest 100 blocks
  per terminal and 5,000 output lines per block (plus an 8 MiB raw-byte safety cap).
  Windows retains the raw ConPTY terminal and reports `durableBlocks: false`.
- Lifecycle reducer plus reaper (`internal/observe/reaper`).
- Agent adapter platform under `internal/adapters/agent/` (25 adapters) with a
  registry and `opr hooks` activity dispatch.
- OpenAPI spec generated from Go DTOs; frontend TS types generated from it and
  drift-checked in CI.

### Frontend (Tauri + React)

- Tauri 2 + React 19 + TanStack Router/Query + Tailwind + shadcn primitives.
  The Rust shell (`frontend/src-tauri`) supervises the daemon, owns native
  integrations, and pins every webview/state path under `~/.operator`. The
  Electron main process, preload, Forge pipeline, and broker were deleted with
  Task 21 of the Tauri port; `node --test scripts/no-electron.test.mjs` and the
  parity checker guard that absence.
- Desktop parity is ledgered row by row in `frontend/perf/parity-ledger.json`
  (102 entries; `npm run check:desktop-parity` verifies the live Tauri bridge
  against it and rejects reappearance of archived surfaces). WebdriverIO E2E
  drives the real binary through Tauri's embedded WebDriver (`npm run
  test:e2e:tauri`); Windows/Linux legs are authored but await their first
  native CI runs.
- Native integrations live in Rust behind narrow ACLs: window
  overlay/fullscreen/theme events, application menus and keyboard shortcuts
  (persisted through Go settings), tray with attention/session actions,
  notifications with attention/toast policy, clipboard including Linux primary
  selection, directory chooser, HTTP(S)-validated external opener plus
  mailto, and dropped-file staging under `<state-root>/terminal-drops`.
- Browser automation is owned by the Go daemon through the packaged
  checksum-pinned `agent-browser` binary — discovery, per-session isolated
  Chromium profiles under the state root, closed command policy, session
  teardown. Panel-only capabilities (DevTools control, network capture) have no
  standalone implementation and fail closed with stable error codes. See
  [`architecture.md`](architecture.md), "Standalone Browser Runtime".
- Previews are external: `opr preview` publishes a validated target that opens
  once in the user's default browser; `opr preview clear` removes it without
  opening anything. The embedded Browser panel was removed with the Tauri port
  (`docs/todo/browser-panel-webview.md` records the deferral).
- Updates: a pinned-plugin updater engine with staged downloads under
  `<state-root>/updater`, latest/nightly/feature channels, downgrade support,
  interrupted-download recovery, and first-run opt-in that keeps updates
  disabled until accepted. Applying an update still fails closed
  (`APPLY_DEFERRED_MESSAGE`) pending the project-owned verified-apply path — a
  release-gating follow-up.
- Real daemon wiring via the generated `openapi-fetch` typed client
  (`src/api/schema.ts`); mock data only in `VITE_RENDERER_PREVIEW` web-preview mode.
- Shell: sidebar (projects + sessions, add/remove project), sessions board,
  session view + inspector, project settings, pull-requests page,
  spawn-orchestrator flow.
- SessionView always renders the agent's live terminal. There is no desktop
  blocks view, Chat composer, interface picker, or interface-switch action.
- Desktop status and SCM summary V1: session status comes from
  `GET /api/v1/sessions`; visible/active PR context comes from
  `GET /api/v1/sessions/{sessionId}/pr`; `GET /api/v1/events` is kept open as
  an invalidation stream rather than a full PR payload stream.
- Concise PR summaries include PR identity, CI state with failing check names
  and links, human reviewer IDs/counts/links for unresolved review comments,
  and mergeability reasons. Raw CI logs and review comment bodies are
  intentionally not part of the desktop V1 API/UI.
- Terminal pane (xterm over WebGL where the platform allows) rides the mux
  WebSocket, with a live SSE events connection and port-rebind on daemon
  restart. Startup parse weight dropped ~34.5% via route-level code splitting;
  binding warm-start/idle-memory comparisons remain unmeasured pending native
  runners (`docs/benchmarks/tauri-port-baseline.md`).
- Shell-terminal history replays decoded raw bytes before its live mux attachment opens,
  preserving chronological block order across page reloads and daemon restarts.
- In-app notification center with click access, Unread/All filters, paginated
  REST catch-up, live notification stream updates, separate PR/session target
  actions, persistent read history, mark-read controls, and native app toasts
  while the app is running. Clicking a toast to focus the window needs real OS
  notification activation (UNUserNotificationCenter/WinRT) — implemented at the
  routing layer, release-gating follow-up for delivery.

### Mobile (Flutter)

- Connect Mobile pairs with the daemon's opt-in authenticated LAN listener; the
  loopback listener and its security model remain unchanged.
- Mobile spawns a terminal session with no interface choice and routes every
  session to the terminal screen, which opens in the blocks view for a covered
  harness and can be toggled to the raw terminal per session, remembered on the
  device.
- Mobile's blocks view is fed by two channels: agent hooks report status and the
  session's native transcript reports body. A per-session tailer projects Claude
  Code JSONL and Codex rollout records into assistant text, reasoning, full tool
  input, tool results, todo lists, the turn's model, compaction, and the options
  of a pending question. Precedence is fixed: transcript wins on body, hook wins
  on status, and a session whose transcript is unreadable degrades to the
  hook-only projection. Harnesses other than Claude Code and Codex contribute
  hook blocks only. Phase 3 adds deterministic terminal controls.

## In flight / not yet a runtime feature

- **Tauri release gates (external, native-runner work)**: Phase 0 still records
  `stop-port` because signed native artifacts, all-platform evidence, updater
  signing, and authorized-runner trust anchors are not yet supplied; warm-start,
  first-run, idle-memory, download-size, and installed-footprint comparisons are
  unmeasured pending native runners; Windows/Linux WebdriverIO legs await their
  first native runs. Release-gating follow-ups that must land before any release
  ships: the project-owned verified-apply updater path (updates currently fail
  closed at apply) and real OS toast-click activation. See
  [`docs/benchmarks/tauri-port-baseline.md`](benchmarks/tauri-port-baseline.md)
  for the measurement contract and gate table. The complete release-blocker and
  deferred-work ledger is
  [`docs/todo/tauri-port-release-and-follow-ups.md`](todo/tauri-port-release-and-follow-ups.md).
- **Release sign-off ledger**: recorded here so release sign-off is auditable
  without the SDD workspace. Window chrome diverges from the Electron shell by
  explicit deferral: Electron's `hidden`/`hiddenInset` titlebars were not ported,
  so macOS and Windows ship fully decorated native chrome until a coordinated
  drag-region migration lands, and that divergence requires explicit user
  sign-off before any release (Task 13 ruling). The nightly channel has updater
  tooling but no schedule-triggered nightly producer workflow on this branch.
  The shell-side GitHub HTTPS transports (`ReleasesSource`, `EscalationFeeds`)
  remain unwired by design after the Task 17 TLS-surface ruling; the stopped
  transports degrade safely and parity holds without them, with a dedicated
  non-gating follow-up brief
  ([`.superpowers/sdd/2026-08-20-tauri-port/followup-github-transports-brief.md`](../.superpowers/sdd/2026-08-20-tauri-port/followup-github-transports-brief.md)).
- **Browser automation acceptance**: the runtime implementation is complete.
  Browser automation is owned by the daemon: one checksum-pinned `agent-browser`
  binary, per-session isolated Chromium profiles under the state root, a closed
  command policy, and teardown on session end — see
  [`architecture.md`](architecture.md), "Standalone Browser Runtime". Manual
  lifecycle acceptance across all three platforms remains native verification
  work.
- **In-flight tool portability**: drain can finish accepted work and interrupt
  can cancel it, but no common provider protocol serializes a currently executing
  tool call or detached background process for adoption by another controller.

- **Tracker lane**: GitHub tracker adapter exists, but there is no daemon
  observer loop or agent-lifecycle→issue mirroring yet, so the tracker does
  nothing at runtime ([#112](https://github.com/OmarAly92/operator/issues/112)).
- **Full raw PR/tracker fact surfacing**: the SCM observer writes facts and the
  desktop consumes concise PR summaries, but exposing the full raw `pr_*` /
  `tracker_*` CDC events to live consumers
  ([#110](https://github.com/OmarAly92/operator/issues/110)) and in
  `opr session get` ([#111](https://github.com/OmarAly92/operator/issues/111))
  is still open.

Tracking milestone:
[`rewrite`](https://github.com/OmarAly92/operator/milestone/1).
