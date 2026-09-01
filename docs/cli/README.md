# Operator CLI

The `opr` CLI is a thin Go/Cobra client for the local Operator daemon.
It starts, discovers, inspects, and stops the daemon through the loopback HTTP
surface and the `running.json` handshake. It must not open SQLite directly or
call runtime, workspace, tracker, or agent adapters in-process.

When using the CLI directly from a shell, make sure the daemon is running first
with `opr start` or by opening the desktop app. Product commands such as
`opr agent ls` and `opr spawn` call the loopback daemon and will fail with a
"daemon is not running" error if no `running.json` points at a live process. From
a source checkout, build and run the local binary explicitly, for example:

```bash
cd backend
go build -o ./bin/opr ./cmd/opr
./bin/opr agent ls
```

## Current commands

Every product command resolves to a daemon HTTP route. Run `opr <command>
--help` for the authoritative flag shape.

### Daemon control

| Command                       | Purpose                                                                                                                           |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `opr start`                    | Start the daemon in the background and wait for `/readyz`.                                                                        |
| `opr stop`                     | Gracefully stop the daemon via loopback `POST /shutdown` after verifying daemon identity.                                         |
| `opr status` / `--json`        | Report daemon state from `running.json`, process liveness, `/healthz`, and `/readyz`.                                             |
| `opr doctor` / `--json`        | Check config, data directory, DB-file presence, daemon state, `git`, and the built-in pty-host runtime. |
| `opr completion <shell>`       | Generate completions for `bash`, `zsh`, `fish`, or `powershell`.                                                                  |
| `opr version` / `opr --version` | Print build metadata.                                                                                                             |
| `opr daemon`                   | Hidden internal daemon entrypoint used by `opr start`.                                                                             |

### Product commands

| Command                             | Daemon route                                   |
| ----------------------------------- | ---------------------------------------------- |
| `opr project add`                    | `POST /api/v1/projects`                        |
| `opr project ls`                     | `GET /api/v1/projects`                         |
| `opr project get <id>`               | `GET /api/v1/projects/{id}`                    |
| `opr project set-config <id>`        | `PUT /api/v1/projects/{id}/config`             |
| `opr project rm <id>`                | `DELETE /api/v1/projects/{id}`                 |
| `opr agent ls`                       | `GET /api/v1/agents`                           |
| `opr agent ls --refresh`             | `POST /api/v1/agents/refresh`                  |
| `opr spawn`                          | `POST /api/v1/sessions`                        |
| `opr session ls`                     | `GET /api/v1/sessions`                         |
| `opr session get <id>`               | `GET /api/v1/sessions/{id}`                    |
| `opr session kill <id>`              | `POST /api/v1/sessions/{id}/kill`              |
| `opr session restore <id>`           | `POST /api/v1/sessions/{id}/restore`           |
| `opr session switch-agent <id> <target-harness>` | `POST /api/v1/sessions/{id}/switch-agent` |
| `opr session agent-switch ls <session-id>` | `GET /api/v1/sessions/{id}/agent-switches` |
| `opr session handoff submit`         | `POST /api/v1/sessions/{id}/agent-switches/{switchId}/handoff` |
| `opr session rename <id> <name>`     | `PATCH /api/v1/sessions/{id}`                  |
| `opr session cleanup`                | `POST /api/v1/sessions/cleanup`                |
| `opr session claim-pr <id> <pr-ref>` | `POST /api/v1/sessions/{id}/pr/claim`          |
| `opr orchestrator ls`                | `GET /api/v1/orchestrators`                    |
| `opr send`                           | `POST /api/v1/sessions/{id}/send`              |
| `opr preview [url]`                  | `POST /api/v1/sessions/{id}/preview`           |
| `opr preview start/status/stop`      | `POST/GET/DELETE /api/v1/sessions/{id}/preview/server` |
| `opr browser ...`                    | `GET /api/v1/browser/status`, `POST /api/v1/browser/commands` |
| `opr hooks <agent> <event>`          | `POST /api/v1/sessions/{id}/activity` (hidden) |

`opr agent ls` prints the daemon-supported agent catalog with local install/auth
readiness. Use `--refresh` to rerun the bounded local probes and `--json` to
print the raw inventory response.

`opr spawn` resolves project context in this order: explicit `--project`,
`OPERATOR_PROJECT_ID`, `OPERATOR_SESSION_ID` (by fetching the current session from the
daemon), then the current working directory matched against registered project
paths. If `OPERATOR_SESSION_ID` is set but the session cannot be fetched, pass
`--project` explicitly.

Agent switching is initially available only for worker sessions whose source
and target harnesses are Claude Code or Codex. The main command
accepts optional handoff guidance and an idempotency key:

```bash
opr session switch-agent opr-7 codex \
  --note "Continue the failing integration test" \
  --idempotency-key switch-opr-7-to-codex

opr session agent-switch ls opr-7 --json
```

`switch-agent` and `agent-switch ls` both support `--json`.
The `agent-switch` command also has the `agent-switches` alias, and `ls` has the
`list` alias.

`opr session handoff submit` is the internal source-agent path for optional
semantic enrichment, not a required human step in a normal switch. It requires
the switch ID, exact source launch generation, and a regular file containing
one JSON object no larger than 64 KiB. `--session` defaults to
`OPERATOR_SESSION_ID`:

```bash
OPERATOR_SESSION_ID=opr-7 opr session handoff submit \
  --switch switch-123 \
  --source-generation generation-456 \
  --file /tmp/opr-handoff.json \
  --json
```

Switching preserves the Operator worker session and worktree. It does not translate,
clip, or rewrite provider transcript files; providers continue to own their
native history and compaction.

If `--agent` / `--harness` is omitted, `opr spawn` uses the resolved project's
`worker.agent` config. Before spawning, the CLI refreshes the advisory agent
catalog and fails early when the selected agent is unsupported, not installed,
or unauthorized. It warns-but-continues when auth remains unknown because daemon
spawn remains the authoritative runtime validation point. Use
`--skip-agent-check` to bypass only this CLI-side preflight.

`opr preview` resolves its session from the `OPERATOR_SESSION_ID` environment variable
(it is meant to run inside a session), not a flag. With no argument it
autodetects an `index.html` in the session workspace; with a URL argument it
opens that URL verbatim (`file://`, `http`, `https`).

`opr preview start [configuration]` loads `.operator/launch.json` from the session
workspace, starts that exact command under a session-owned supervisor, selects
or records its loopback port, waits for readiness, and publishes application
targets as external previews that open once in the user's default browser.
`status` reports bounded recent logs and `stop`
terminates the managed process tree. Multiple configurations must be selected
by name; Operator does not assign confidence scores to arbitrary localhost servers.
This is an optional, reusable project configuration, not a prerequisite for
preview. Agents must not create it automatically. Static HTML and Markdown use
the direct file preview and must not cause package-manager scaffolding,
dependency installation, or a development server to be introduced.
`opr preview clear` removes the current session's preview target without opening
anything.

When a browser-displayable file is the requested artifact, agents should call
`opr preview <workspace-path>` immediately after creating or materially updating
the primary output. Markdown, HTML, PDF, SVG, and common images can be served
directly. Supporting assets must not replace an active application preview.

`opr browser` also resolves its target from `OPERATOR_SESSION_ID`, but drives the
daemon-owned standalone browser runtime: one checksum-pinned `agent-browser`
binary with a per-session isolated Chromium profile under the operator state
root (`backend/internal/adapters/agentbrowser/`). The allowlisted command set
includes `status`, `open`, `snapshot`, `click`, `dblclick`, `focus`, `fill`,
`type`, `press`, `hover`, `scroll`, `scrollintoview`, `drag`, `select`,
`check`, `uncheck`, `get`, `highlight`, `tabs`, `tab new/select/close`,
`frame`, `dialog`, `wait`, `screenshot`, `console`, and `errors`. Logical tab
IDs remain stable for the session; references from a snapshot are invalidated
after navigation or DOM replacement and when changing tabs — take another
snapshot when a command reports `STALE_REFERENCE`. Browser waits cover load
completion, text or selector appearance and disappearance, URL matching, fixed
delays, and a configurable DOM-stability window. Ending the session discards
the isolated profile, so cookies and web storage never leak between workers.

Panel-only capabilities were dropped with the removed desktop Browser panel:
`devtools open/close` fails with `BROWSER_DEVTOOLS_UNAVAILABLE`, and network
capture plus `unhighlight` fail with `BROWSER_AUTOMATION_UNAVAILABLE` — the
standalone runtime has no implementation for them and refuses instead of
approximating. The daemon runs the engine headlessly, so no desktop app window
needs to be open.

`go run .` in `backend/` remains a compatibility wrapper around the daemon.

PR actions are available through `opr pr merge` and
`opr pr resolve-comments`. Review actions are available through `opr review ls`,
`opr review trigger` (also `execute` and `restart`), `opr review cancel` (also
`stop`), and `opr review submit`.

## Configuration

The CLI and daemon share the same environment-driven config:

| Var                   | Default              | Purpose                                                                                        |
| --------------------- | -------------------- | ---------------------------------------------------------------------------------------------- |
| `OPERATOR_PORT`             | `3001`               | Loopback daemon port.                                                                          |
| `OPERATOR_RUN_FILE`         | `~/.operator/running.json` | PID/port handshake.                                                                            |
| `OPERATOR_DATA_DIR`         | `~/.operator/data`         | SQLite data directory.                                                                         |
| `OPERATOR_REQUEST_TIMEOUT`  | `60s`                | REST request timeout.                                                                          |
| `OPERATOR_SHUTDOWN_TIMEOUT` | `10s`                | Graceful shutdown cap.                                                                         |
| `OPERATOR_KEEP_DAEMON`      | unset (off)          | Keep the desktop app's daemon running after the window closes; stop only via `opr stop`. (fork) |

The daemon always binds `127.0.0.1`.

## Manual smoke test

```bash
cd backend
go build -o /tmp/opr ./cmd/opr

tmp=$(mktemp -d)
export OPERATOR_RUN_FILE="$tmp/running.json"
export OPERATOR_DATA_DIR="$tmp/data"
export OPERATOR_PORT=3037

/tmp/opr status --json
/tmp/opr doctor
/tmp/opr start
/tmp/opr status --json
/tmp/opr stop
/tmp/opr status --json
rm -rf "$tmp"
```

## Adding new commands

Add a product command only when a daemon HTTP route owns the corresponding
mutation/read; the CLI must call that route rather than reimplementing daemon
behavior. Commands not yet exposed but with backend routes in place include
`opr events ...` (over the CDC/SSE endpoint) and CLI parity for PR/review
actions.

Do not port old in-process TypeScript CLI behavior that mixed command handling
with storage and runtime implementation details.
