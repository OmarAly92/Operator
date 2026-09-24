# operator status

Operator ships a working single-user local loop: the Go daemon and the Tauri +
React desktop shell drive a live daemon over HTTP/SSE/WebSocket. The core GitHub
flow works end-to-end: add project → spawn session → attach terminal
→ observe PR → merge.

`master` is what users have (desktop releases are cut from it, latest v0.14.3 on
2026-09-17); `development` carries everything below that is not yet released.
This file tracks progress. For what the product _is_ and how to run it, see the
top-level [`README.md`](../README.md); for the backend mental model see
[`architecture.md`](architecture.md); for shipping a release see
[`RUN_APP_COMMANDS.md`](../RUN_APP_COMMANDS.md).

_Last reviewed 2026-09-17._

## Build & test

The local gate is the backend Go build and race-enabled test suite:

```bash
cd backend && go build ./... && go test -race ./...
```

`npm run lint` (from the repo root) runs `go test ./...` plus golangci-lint v2.12.2.
Frontend checks live under `frontend/` (`npm run typecheck`, `npm run tauri:build`,
Playwright renderer E2E, WebdriverIO native-shell E2E).
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
  rollback, cleanup, send, activity, PR claim/list.
- One session kind: the delegator/worker split was removed on 2026-09-20;
  every session is a worker, spawned from the New Task dialog, a ticket/plan,
  auto-review, or tracker intake. Every session runs the agent's own terminal UI in the
  pty-host runtime; there is no chat controller to choose and no interface
  handoff. The ACP/chat subsystem was removed in Phase 4 of
  `docs/superpowers/specs/2026-09-04-single-session-interface-design.md`
  (see `docs/superpowers/plans/2026-09-06-phase-4-report.md`).
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
- Durable dashboard notifications for `needs_input`, `turn_finished`,
  `agent_exited`, `ready_to_merge`, `pr_merged`, and `pr_closed_unmerged`:
  backend enrichment/persistence, cursor-paginated read/unread history, live
  notification stream, and read acknowledgement API.
- SCM observer (`internal/observe/scm`) wired into the daemon: GitHub provider,
  lazy/non-blocking auth, per-PR polling with ETag guards and semantic diffing,
  feeding PR facts into lifecycle, which sends agent nudges for CI failures,
  review feedback, and merge conflicts.
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
  integrations, and pins every webview/state path under `~/.operator`.
  WebdriverIO E2E drives the real binary through Tauri's
  embedded WebDriver (`npm run test:e2e:tauri`) on macOS and Linux in CI
  (`tauri-webdriver.yml`); no Windows leg exists yet.
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
- Updates, end to end: installed apps check the published `latest.json` at
  launch and hourly, download and minisign-verify the archive into
  `<state-root>/updater/staged`, and install it on quit or via "Restart &
  install"; latest/feature channels, downgrade support, interrupted-download
  recovery, staged-artifact adoption across launches, and a first-run opt-in
  that keeps updates disabled until accepted. Proven on macOS on 2026-09-17
  (0.13.9 → 0.14.0 on quit; 0.14.2 → 0.14.3 fully hands-off). Releases are
  built and signed by `frontend-release.yml` on four runners and triggered by a
  version bump on `master` (`release-on-bump.yml`).
- Real daemon wiring via the generated `openapi-fetch` typed client
  (`src/api/schema.ts`); mock data only in `VITE_RENDERER_PREVIEW` web-preview mode.
- Shell: sidebar (projects + sessions, add/remove project), sessions board,
  session view + inspector, project settings, pull-requests page,
  New Task spawn flow.
- SessionView always renders the agent's live terminal. There is no other
  session interface to pick or switch to — the desktop has no blocks view.
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
  restart. Startup parse weight dropped ~34.5% via route-level code splitting.
- Shell-terminal history replays decoded raw bytes before its live mux attachment opens,
  preserving chronological block order across page reloads and daemon restarts.
- In-app notification center with click access, Unread/All filters, paginated
  REST catch-up, live notification stream updates, separate PR/session target
  actions, persistent read history, mark-read controls, and native app toasts
  while the app is running. On macOS, toasts go through UNUserNotificationCenter
  in packaged builds (the Tauri notification plugin remains for dev), and
  clicking a toast focuses the window and opens that session. Windows/WinRT
  click activation is not yet implemented.

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
- Phone alerts ride ntfy (ntfy.sh) with a per-pairing topic claimed through
  `/api/v1/phone-alerts`, gated on Connect Mobile plus a claimed, unquiet,
  foreground-absent, coalesced session; the app itself raises local
  notifications from the live mux `notifications` channel while open. The
  earlier Expo push path and `/api/v1/push/devices` are removed.

## In flight / not yet a runtime feature

- **Operator MCP server (`docs/plans/kanban-mcp.md`)**: every worker session
  gets `opr mcp`: read tools (`board_get`, `session_get`, `ticket_get`),
  `session_report` (agent-driven Needs you / ready for review, with the reason on
  the desktop and mobile cards and in the alert) and self-scoped actions. Wired
  for Claude Code, Codex, OpenCode, Qwen, Amp, Copilot, Auggie, Crush and Kilo;
  the remaining harnesses are handed off in
  `docs/plans/kanban-mcp-remaining-harnesses.md`.
- **macOS signing and notarization**: there is no Apple Developer account, so
  macOS builds are ad-hoc signed and not notarized. Auto-update works, but a
  fresh DMG download must be allowed through Gatekeeper by hand. Adding the
  `APPLE_*` secrets switches `frontend-release.yml` to signed, notarized builds
  with no other change.
- **Unverified on Windows and Linux**: every release builds and signs all four
  targets, and the updater engine is unit-tested, but install-on-quit has only
  been exercised on macOS. Windows relies on the plugin's NSIS hand-off (the
  daemon is shut down from `on_before_exit` first) and Linux on the AppImage
  replace; neither has been run on real hardware. Windows has no WebdriverIO
  leg. Warm-start, idle-memory, download-size and installed-footprint numbers
  are unmeasured.
- **OS toast-click activation**: delivered on macOS via UNUserNotificationCenter
  in packaged builds. Windows/WinRT activation is not yet implemented; Windows
  and Linux keep the Tauri notification plugin.
- **Feature (`pr<N>`) builds have no in-app picker**: the shell-side GitHub
  releases transport (`ReleasesSource`) is deliberately unwired, so a feature
  pin can only be set through the settings API; the stopped transport degrades
  safely, and escalation is only the 48-hour rule for a staged stable update
  (`evaluate_escalation(staged_at_ms, now_ms)`).
- **Terminal package size rule**: `packages/terminal`'s `check:boundaries`
  caps source files at 600 lines and four files have exceeded it since
  2026-09-10 (`crates/vt-wasm/src/lib.rs`, `ts/react/src/TerminalSurface.tsx`,
  `ts/renderer-dom/src/dom-block-renderer.ts` and its test), so `terminal.yml`
  and the `frontend.yml` boundary step are red until they are split.
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
  nothing at runtime.
- **Full raw PR/tracker fact surfacing**: the SCM observer writes facts and the
  desktop consumes concise PR summaries, but the full raw `pr_*` /
  `tracker_*` CDC events are not exposed to live consumers or `opr session get`.
- **Deferred designs** live in [`docs/todo/`](todo/): the embedded browser panel
  (`browser-panel-webview.md`), direct-spawn coordination
  (`operator-approach-3-direct-spawn-spec.md`) and worktree isolation state
  (`worktree-isolation-state.md`).
