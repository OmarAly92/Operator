# Telemetry

Operator uses anonymous telemetry to understand reliability and product usage. The
Electron renderer sends sanitized PostHog events directly, and the Go daemon can
persist allowlisted events locally and fan them out to PostHog when remote
telemetry is enabled.

For cost-control runbooks, including the v2 PostHog event namespace and legacy
ingestion drop rules, see [posthog-cost-controls.md](posthog-cost-controls.md).

## What is collected

- App activation events: `opr.app.active` / `opr.v2.app.active` from the
  renderer and meaningful user-context CLI commands, each capped to one event
  per six-hour UTC slot, or four per day per install/channel
- Renderer load and daily route-surface usage, grouped by coarse surface names
- Project/task/session UI actions, with project identifiers SHA-256 hashed
- Renderer exceptions, reduced to error name and coarse context
- Daemon operational events: CLI invocation, session spawn/failure, waiting-input
  transitions, HTTP 5xx, and daemon panics
- Code review outcomes: `opr.review.triggered`, `opr.review.submitted`,
  `opr.review.cancelled`, and `opr.review.trigger_failed`. These carry the reviewer
  `harness`, the `verdict` (`approved` / `changes_requested`), how long the pass
  took, whether the review reached the provider, and a coarse `error_kind` on
  failure. The review body is never sent: it is reviewer prose about a user's
  source code. The PR URL and target SHA are also withheld, because both identify
  the repository. `opr.review.submitted` fires only on the real running-to-complete
  transition, so a reviewer retrying a submit cannot double-count a verdict
- Desktop update outcomes: `opr.renderer.update_failed`,
  `opr.renderer.update_downloaded`, and `opr.renderer.update_unsupported`. These
  carry a coarse `error_category`, the `phase` (`check` or `download`), whether
  the operation was `automatic` or `manual`, and the target version. The
  updater's raw error message is never sent, because it can contain feed URLs
  and local staging paths; it is bucketed into a category first. Progress is not
  reported, since it fires per percent tick and the UI already shows it.

  These are decided in the **main process**, at the updater's operation
  boundary, and pushed to the renderer on a channel separate from
  `updates:status`. That separation matters: `auto-updater.ts` deliberately
  suppresses the UI status when an *automatic* check fails, and automatic checks
  run hourly. A renderer observer watching statuses would therefore miss the
  silent-failure case these exist to diagnose. Owning it in main also makes
  `phase` and `to_version` authoritative, since only main knows which operation
  was running and what it was fetching
- Agent inventory: `opr.renderer.agents_available`, reported once per app launch
  with `installed_count`, `authorized_count`, `supported_count`, and a sorted list
  of authorized agent ids. Agent ids are a fixed vocabulary from Operator's own
  registry, never user input. This exists because `opr.session.spawned` only shows
  which harness *ran*, so an install with six authorized agents that always picks
  one was indistinguishable from an install that only had that one
- Operator version context (`app_version` / `ao_version`), platform, and build mode
- Mobile app product events (`client = "mobile"` / `"mobile-web"`), all under the
  `opr.v2.*` namespace and carrying `telemetry_schema_version = 2`:
  `opr.v2.app.active` (once per UTC day), `opr.v2.mobile_app.paired`
  (`method`, `from_onboarding`), `opr.v2.mobile_app.connected` (`trigger`,
  emitted only on the not-open-to-open transition, never per poll tick),
  `opr.v2.mobile_app.onboarding_started` / `_completed` / `_skipped`,
  `opr.v2.mobile_app.notification_opened` (`target`, `cold_start`), and
  `opr.v2.mobile_app.feature_used` (`feature`, `outcome`). Every event carries
  `$process_person_profile: false` (anonymous rate), and the client is built with
  `personProfiles: "never"`, `enableSessionReplay: false`, and
  `captureAppLifecycleEvents: false`. There is no screen recording, no touch or
  screen autocapture, and no free-text property: the allowlist in
  `packages/mobile/lib/telemetry/events.ts` drops any unregistered key, so session
  titles, project names, terminal output, and the connection password cannot
  leave the device. Identity is posthog-react-native's persisted anonymous
  install id, device-based and never IP. Errors are out of scope here and go to
  Sentry, not PostHog. A dev client (`npm start`) constructs no client and sends
  nothing.

PostHog session recording is disabled in the client via
`disable_session_recording`, so the project-side replay toggle cannot turn it on.
Replay is billed per recording rather than per event, which puts it outside every
rate limit described below, and Operator does not watch replays. If a time-boxed
investigation ever needs it, network request names are masked before recording.

Feature flags and surveys are also disabled in the client
(`advanced_disable_flags`, `disable_surveys`). Operator reads no flags and ships no
surveys, and `/flags` requests are billed, so those requests were pure cost.

## Privacy

Before any renderer event or recording is transmitted:

- Absolute file paths (`/home/...`, `/Users/...`, `C:\...`) are replaced with
  `[redacted-local-path]`
- Local URLs (`file://`, `app://renderer`, `localhost`, `127.0.0.1`, `[::1]`)
  are replaced with `[redacted-local-url]`
- Project IDs are one-way hashed and never sent in plain text

Daemon events use a remote payload allowlist before PostHog export. Project and
session IDs are hashed, and raw location/IP fields are not accepted from Operator
payloads. Geographic reporting should use PostHog's GeoIP enrichment only.

Three burst-prone daemon events — `opr.http.5xx`, `opr.daemon.panic`,
`opr.cli.usage_errors` — are aggregated before export: every occurrence in a
rolling one-minute window is folded into a single rollup event carrying
`count`, `window_start`, and `window_end`, instead of exporting one PostHog
event per occurrence. A storm of 10,000 errors and one of 6 both cost the same
one event, and the true magnitude is still visible via `count` rather than
being silently capped away. Only the most recent occurrence's other
properties (path, fingerprint, etc.) are kept on the rollup — if a burst hits
several different endpoints or fingerprints in the same window, the ones
overwritten by later occurrences aren't visible on that rollup. Local SQLite
storage is unaffected: it receives every raw occurrence, unaggregated, for
full-fidelity debugging regardless of what PostHog sees.

Everything reaching PostHog remotely is still bounded per event name: a
5-per-minute burst cap plus a 200-per-day hard ceiling for ordinary events,
or a 1,500-per-day ceiling for the three aggregated names above (since their
per-occurrence cost is already collapsed by aggregation, the daily cap there
is a structural backstop rather than the primary limit). The renderer applies
the same 5-per-minute / 200-per-day shape to its own event and exception
capture path, without the aggregation step.

All events are sent as PostHog anonymous events (`$process_person_profile:
false`; the renderer never calls `identify()`). The renderer keeps PostHog SDK
persistence in memory, disables person profiles, and explicitly bootstraps the
Operator install ID as anonymous. This prevents legacy PostHog state from restoring
an identified user or replacing the stable Operator device ID after an upgrade. The
install ID still deduplicates unique-user counts, but no person profiles are
created — person properties and person-property cohorts are intentionally
unavailable. Operator's heartbeat and route reservations continue to use their own
sanitized `localStorage` keys independently of PostHog SDK persistence.

`opr.cli.invoked` is capped at once per actor type and command path per UTC day
per install. Routine successful internal/read-only commands (`opr status`,
`opr session ls`, `opr session get`, `opr project ls`, `opr project get`,
`opr orchestrator ls`, `opr hooks`, and `opr pty-host`) are excluded outright.
Commands that never reflect product activity — the supervisor-driven
`opr daemon`/`opr start`, the self-documenting `opr completion`/`opr help`, and
the internal `opr agent-process` runtime process — are also excluded outright.

CLI invocations are classified by actor:

- `actor_type=user`: a user-context CLI command. These can refresh CLI-channel
  `opr.app.active`.
- `actor_type=agent`: commands run inside an Operator-managed agent session
  (`OPERATOR_SESSION_ID` is set). These are useful command-adoption signal but do not
  refresh `opr.app.active`, because agents can keep running after the human has
  stopped actively using Operator. Routine internal paths such as `opr hooks` are
  dropped on success.
- `actor_type=system`: supervisor/runtime background processes. These are not
  sent as CLI usage.

The per-command daily cap keeps invocation frequency off PostHog, and the CLI
reservation state is persisted under the Operator data dir so a daemon restart does
not re-emit every polling command for the same day.

Routine successful internal/read-only commands are not reliability signal by
themselves and should not be reintroduced as success telemetry. For commands
such as `opr status`, `opr session ls`, `opr session get`, `opr project ls`,
`opr project get`, `opr orchestrator ls`, `opr hooks`, and `opr pty-host`, track
only meaningful user-impacting failures through a separate, rate-limited event
such as `opr.v2.cli.failed`. That event should carry safe enum-like fields such
as `command_path`, `actor_type`, `error_category`, and stable `error_code`; it
must not include raw error messages, stack traces, local paths, project names,
repository URLs, prompts, terminal output, tokens, or request payloads.

`opr.renderer.route_viewed` is capped at once per coarse surface per UTC day per
renderer install. This preserves surface adoption and retention signal while
dropping repeated navigation churn inside the same surface.

## Product Metrics Model

Operator currently has a stable install ID, not a signed-in account user ID. That
means today's DAU/MAU can accurately represent active installs, but not unique
people across multiple machines. True user-level new/churn/journey metrics
require an explicit stable user identity from a login, license, or workspace
account system. That identity should be sent as a first-party Operator user ID (or a
one-way hash of it) only when the user has authenticated or explicitly enabled
account-level telemetry; it should not be inferred from machine fingerprints,
paths, git remotes, emails in repo config, or other local data.

The minimum signals for accurate usage analytics are:

- `opr.app.active` / `opr.v2.app.active`: up to one event per six-hour UTC slot
  per install/account when a human uses the desktop app or runs a meaningful
  user-context CLI command. This powers DAU, WAU, MAU, retention, and churn
  while keeping arbitrary rolling windows from undercounting long-running
  usage. Renderer active events are sent immediately; a slot is released for
  retry when the SDK rejects or throws while capturing the event.
- `opr.projects.created` and `opr.onboarding.first_project_added`: activation
  funnel from install to first project.
- `opr.session.spawned`, `opr.session.spawn_failed`, and
  `opr.onboarding.first_session_spawned`: activation funnel from project to
  first running agent, plus spawn reliability.
- `opr.cli.invoked` / `opr.v2.cli.invoked` with `actor_type=user|agent`:
  command adoption by actor for meaningful non-internal commands, capped by
  command/install/day. Agent-context command usage is product signal, but
  should be analyzed separately from active-user counts.
- `opr.session.waiting_input_entered/exited`: whether agents are making progress
  or waiting on the human, with dwell time.
- Renderer and daemon error/crash events: reliability and support signal.

Signals that should not drive active-user metrics:

- Internal runtime hosts such as `opr pty-host`.
- Supervisor startup/control commands such as `opr daemon` and `opr start`.
- Agent hook callbacks and other CLI commands run with `OPERATOR_SESSION_ID`, except
  as separate agent-activity or command-adoption metrics.
- Raw polling frequency for read-only state commands.

## Install ID

On first run, a random install identifier is generated and stored at
`~/.operator/data/telemetry_install_id` (or `$OPERATOR_DATA_DIR/telemetry_install_id`). The
renderer and daemon both use this ID as the PostHog distinct ID so activity is
deduplicated across app launches and CLI invocations. It is not linked to any
personal account. In the renderer it is also the PostHog device ID, and the SDK
is explicitly kept in anonymous mode.

## Configuration

Renderer PostHog key and host are baked in at build time. To point a build at
another PostHog project, set these environment variables before building:

```bash
VITE_OPERATOR_POSTHOG_KEY=phc_yourkey
VITE_OPERATOR_POSTHOG_HOST=https://your-posthog-host.com
```

Daemon event capture is off by default when the daemon is launched directly. The
Electron supervisor starts the daemon with these defaults unless the environment
already provides explicit values:

```bash
OPERATOR_TELEMETRY_EVENTS=on
OPERATOR_TELEMETRY_REMOTE=posthog
OPERATOR_TELEMETRY_POSTHOG_KEY=phc_yourkey
OPERATOR_TELEMETRY_POSTHOG_HOST=https://us.i.posthog.com
```

The supervisor also passes `OPERATOR_TELEMETRY_APP_VERSION` (the Electron app version)
so daemon events carry `app_version`/`ao_version`. The daemon binary has no
version of its own that release tooling sets, so without this every daemon event
arrives unattributable to a release and a failure rate cannot be traced to the
build that caused it.

Local daemon telemetry is retained in SQLite for 30 days.

### Kill switch

`OPERATOR_TELEMETRY_DISABLED_EVENTS` is a comma-separated list of event streams that
must never reach PostHog:

```bash
OPERATOR_TELEMETRY_DISABLED_EVENTS="opr.v2.app.active, opr.renderer.*"
```

An entry ending in `*` matches by prefix. Matching is case-insensitive and
accepts either the internal name (`opr.app.active`) or the exported PostHog alias
(`opr.v2.app.active`), so the name visible in PostHog works without translation.

The list is enforced in two places, because Operator has two producers: the daemon's
billed sink, and the renderer, which talks to PostHog directly. The supervisor
passes the list to the daemon as an environment variable and to the renderer on
the telemetry bootstrap, so denying `opr.v2.app.active` silences both rather than
leaving the renderer sending under the same exported name.

Renderer export is additionally off by default on unpackaged builds, so a
developer's ordinary session does not appear in the production project as a real
install. `OPERATOR_TELEMETRY_RENDERER=on` opts a dev build back in for deliberate
testing; `off` opts a packaged build out.

This exists because every other control in this document is compiled into the
build. Silencing a stream previously meant shipping a release and waiting for
users to install it, which took weeks the one time a stream turned out to be
expensive. The denylist is applied by the daemon at startup, so it takes effect
on installs that already exist.

The switch is applied outermost on the remote chain: a silenced stream consumes
no aggregation window, no rate-limit slot, and no export. Local SQLite storage is
deliberately unaffected, so a stream silenced in production stays debuggable
locally. Unrecognized entries are inert rather than fatal, because the switch has
to be usable in a hurry.
