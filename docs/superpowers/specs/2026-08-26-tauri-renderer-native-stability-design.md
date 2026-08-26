# Tauri renderer and native integration stability — design

**Date:** 2026-08-26
**Status:** proposed design
**Program:** `docs/superpowers/specs/2026-08-26-tauri-stabilization-program-design.md`
**Owns:** locale and shortcut hydration, notification activation, tray policy, preview acknowledgement, and Shift+Enter terminal semantics.

## Outcome

Cold launch uses authoritative persisted settings, native integrations follow their documented platform policies, preview opening is exactly-once with at-least-once acknowledgement, and agent-specific terminal input never leaks into plain shells.

These fixes share one design because each defect comes from treating an asynchronous native or daemon boundary as though it were immediate and infallible.

## Design principles

- Daemon-backed settings are unknown until the daemon is ready; a transient startup failure is not a persisted default.
- Native side effects and their acknowledgements are separate states.
- Platform policy is applied at the effect boundary, not only in a helper that callers can bypass.
- Events with user-visible meaning retain their stable identity across native and renderer layers.
- Unknown terminal capability selects standard terminal behavior.
- Renderer stores expose explicit loading, ready, retrying, and failed states rather than a single boolean that collapses them.

## Shared desktop bootstrap

### Readiness contract

Create one renderer-visible daemon readiness coordinator backed by the existing native daemon supervisor. It exposes:

```text
starting
ready { baseUrl, daemonRunId }
retrying { attempt, lastErrorCode }
recoverable_error { errorCode, action }
fatal_error { errorCode, action }
```

The base URL is accepted only from the native supervisor's authoritative status and must remain a trusted loopback URL. Stores do not poll or construct ports independently.

The coordinator resolves a shared readiness promise for the current daemon run. A daemon restart creates a new run identity and a new promise. Callers may await readiness with cancellation. They do not convert `starting` or a retryable 503 into defaults.

### Initial render sequence

```text
Tauri shell starts/attaches daemon
        │
        ▼
Renderer mounts minimal bootstrap surface
        │ await authoritative daemon readiness
        ▼
Load locale and keybindings in parallel
        │ both validated
        ▼
Apply locale + register native accelerators
        │
        ▼
Mount normal application routes
```

The bootstrap surface uses non-localized product identity and progress/error affordances. It does not render English product routes and later replace them with the persisted language. A bounded startup timeout changes the UI to a recoverable daemon-start failure without marking either store loaded.

Unrelated noncritical settings may continue loading after the route mounts if their existing behavior is safe. Locale and keybindings are critical because an incorrect fallback becomes user-visible or destructive.

## Locale hydration

### Store state

The locale store uses:

```text
uninitialized
waiting_for_daemon
loading
ready { locale, source }
retrying { attempt }
failed { errorCode }
```

Only a successful settings response, a validated response that contains no persisted locale, or an explicit user choice reaches `ready`. The default locale is applied only when the authoritative response says the setting is absent. Transport failure, synthetic 503, timeout, or daemon restart does not make English authoritative.

Concurrent `load` calls share one promise. A failed load remains retryable. Automatic retries use bounded exponential backoff with jitter and stop on cancellation or a non-retryable validation error. A daemon-run change cancels the old request and reloads against the new authoritative base.

### Locale writes

A user selection waits for the store to be ready, validates the locale against the supported set, writes it through the daemon settings API, and only then commits the durable UI state. An optimistic visual preview may be shown, but a failed write restores the authoritative locale and presents an actionable error.

The store never writes its fallback value merely because loading failed.

## Keybinding hydration and mutation

### Authoritative snapshot

The keybindings store uses the same readiness coordinator and explicit lifecycle states. Its ready state contains the complete validated override map and the daemon run identity from which it was loaded.

Native accelerator registration occurs only after that snapshot is ready. Until then, the application uses compiled defaults without persisting them. When authoritative overrides arrive, renderer and native registrations switch as one operation; a partial registration failure keeps the previous working set and reports the rejected bindings.

### Serialized writes

Every mutation enters one store-owned queue:

1. await the active hydration promise;
2. reject if hydration failed or the daemon run changed;
3. derive the next complete map from the authoritative snapshot;
4. validate conflicts and platform accelerator syntax;
5. persist through the daemon API;
6. install the native accelerator set;
7. publish the new renderer snapshot.

If persistence fails, neither renderer nor native registrations change. If native registration fails after persistence, the store restores the previous persisted map or returns a blocking reconciliation error; it never leaves renderer and native bindings silently different.

Reset-all and single-binding edits use the same queue. Two rapid edits cannot each merge against an empty or stale map.

## Notification activation

### Identity

`notification_show` keeps the provided Operator notification ID. The native layer maps it to the platform notification identifier and stores only the minimum in-memory/pending activation record needed to route a click. Title and body remain presentation data and are not used as identity.

Duplicate show requests for the same active ID update or replace the existing native notification according to platform capability; they do not create ambiguous click identities.

### Activation flow

```text
User clicks native notification
        │
        ▼
Platform activation handler receives stable ID
        │
        ├─ app stopped: launch Operator and queue activation
        └─ app running: continue
        ▼
Show/unminimize/focus main window
        │ renderer event system ready
        ▼
emit notifications:click { id }
        │
        ▼
renderer selects/navigates to matching target
```

macOS uses the application notification-center delegate. Windows uses the toast activation callback and the registered Operator application identity. Both adapters call a shared `NotificationActivationRouter`; the existing policy function is no longer an uncalled abstraction.

If activation arrives before the renderer event listener is ready, the native layer queues the ID. Renderer readiness drains the queue once. Repeated operating-system callbacks for the same activation token are deduplicated. A later deliberate click on a newly shown notification with the same product ID remains valid because it has a new native activation token.

Click routing focuses the main window before emitting. Failure to focus does not discard the event. Invalid or unknown IDs focus Operator but emit no navigation event and record a bounded diagnostic code.

Linux keeps its currently supported notification behavior in this scope; adding cross-desktop click activation is not required by the owning audit bug.

## Tray policy

Tray creation accepts an immutable `TrayContext` containing:

- platform;
- development versus packaged mode;
- parsed application version/channel;
- test override available only in explicit test builds.

The creation boundary calls the existing policy and returns `TrayOutcome::DisabledByPolicy` without constructing a tray when disallowed.

Binding behavior:

| Context | Tray |
|---|---|
| Non-macOS | Disabled |
| macOS development | Enabled |
| macOS packaged nightly | Enabled |
| macOS packaged stable | Disabled |
| macOS packaged feature/pr channel | Disabled unless existing reviewed policy explicitly classifies it as nightly |
| Invalid packaged version | Disabled with diagnostic |

Startup treats disabled-by-policy as success. Actual platform creation failure remains an error with existing recovery behavior. No caller can invoke a lower-level public tray constructor that bypasses the policy.

## External preview transaction

### Guarantees

- A preview revision is opened automatically at most once by one Operator installation record.
- A successfully opened revision is acknowledged to the daemon at least once until the daemon accepts the exact revision.
- Retrying an acknowledgement never opens another browser tab.
- Manual “reopen” is explicitly allowed to open another tab and does not alter automatic-open state.
- `clear` opens nothing and retires any matching pending work through daemon revision semantics.

### Native-owned journal

The Tauri shell owns `<state-root>/preview-open-state.json`, written atomically. It contains only the session identifier, revision, normalized target origin/path or a nonreversible target hash where sufficient, open state, acknowledgement state, and timestamps. Credentials embedded in a URL are rejected before opening and never stored.

The automatic flow is:

1. renderer receives a durable preview revision from the daemon;
2. it asks the native command to process the exact session, revision, and validated HTTP(S) target;
3. native checks the journal for an already-opened revision;
4. if absent, native opens the default browser;
5. after opener success, native atomically records `opened_pending_ack`;
6. native posts the acknowledgement to the authoritative loopback daemon;
7. on success, native records `acknowledged` and later prunes the entry;
8. on HTTP/transport failure, native preserves `opened_pending_ack` and retries only the POST.

If the daemon base is not ready, acknowledgement returns pending rather than success. Native listens for supervisor readiness and retries. A desktop restart reloads pending acknowledgements before processing new preview events, preventing a second open after a crash between steps 5 and 6.

The acknowledgement endpoint remains idempotent for the same session and revision. A newer revision is a separate transaction and may open once. An older event cannot replace a newer journal entry.

### Renderer state

The hook represents `opening`, `opened_pending_ack`, `acknowledged`, `open_failed`, and `ack_failed`. The retry button is operation-specific:

- `open_failed` retries open;
- `ack_failed` retries acknowledgement only;
- manual reopen always invokes the explicit reopen command.

## Terminal Shift+Enter semantics

Each terminal pane exposes a validated input capability:

```text
agent_tui_meta_return
standard_terminal
```

The capability comes from the pane/session kind already known by the product, not from terminal contents, process-title guessing, or user input. Agent TUI panes that explicitly support the existing `ESC CR` convention use `agent_tui_meta_return`. Login shells, command shells, unknown pane types, disconnected panes, and future integrations default to `standard_terminal`.

In `standard_terminal`, Shift+Enter follows xterm/browser terminal semantics and does not inject `ESC CR`. Other keyboard handling, paste, composition, Alt/Meta behavior, and Enter remain unchanged.

The capability is fixed for a mounted pane unless the authoritative pane kind changes. Reconnect retains it; terminal pooling cannot reuse a handler with the previous pane's capability.

## Error and observability contract

Stable diagnostic codes cover daemon readiness timeout, locale/keybinding hydration failure, accelerator reconciliation failure, notification activation routing failure, tray policy disablement/creation failure, preview open failure, preview acknowledgement pending/failure, and unsupported terminal capability.

Diagnostics record daemon run identity, setting type, platform, application channel, preview revision, or pane kind as applicable. They do not record locale-independent user content, notification body, terminal bytes, full preview URLs, or secrets.

## Tests

### Bootstrap and stores

- delayed daemon startup with persisted non-English locale produces no English application-route flash;
- transient 503 retries and loads the persisted locale;
- permanent daemon failure leaves locale unknown and shows recovery UI;
- concurrent locale loads share one request;
- shortcut load retries after startup 503;
- editing before hydration waits and preserves unrelated overrides;
- two rapid edits serialize against the latest snapshot;
- persistence/native-registration failures do not split authoritative state;
- full relaunch applies renderer and native shortcuts from persistence.

### Notifications

- macOS and Windows adapters preserve string ID mapping;
- running-app click focuses then emits the correct ID;
- cold-start click queues until renderer readiness and emits once;
- duplicate callback token is deduplicated;
- unknown ID focuses without invalid navigation;
- packaged click-through E2E covers real native notification activation on both platforms.

### Tray

- stable packaged macOS never invokes the platform tray constructor;
- nightly packaged and development macOS do invoke it;
- invalid version and non-macOS contexts are disabled;
- startup succeeds when policy disables the tray.

### Preview

- missing daemon base produces pending acknowledgement, not false success;
- opener success plus HTTP failure records pending state;
- retry performs one acknowledgement and zero opens;
- process restart resumes acknowledgement without reopening;
- opener failure may retry opening;
- newer revisions open independently and stale events cannot replace them;
- manual reopen opens but does not change acknowledgement state;
- invalid schemes and credential-bearing URLs are rejected.

### Terminal

- Shift+Enter in a compatible agent TUI sends the documented sequence;
- Shift+Enter in login and command shells does not send that sequence;
- unknown pane type is standard-terminal safe;
- reconnect and pooled-terminal reuse update the capability correctly;
- Enter, composition, paste, and other modifiers retain existing behavior.

## Expected file surface

Implementation is expected to touch:

- renderer bootstrap, daemon-status coordination, locale store, keybindings store, and root mounting;
- native and renderer shortcut reconciliation;
- `frontend/src-tauri/src/native.rs`, notification policy/adapter modules, and platform-specific activation registration;
- tray creation and startup wiring;
- preview bridge/hook plus a small native preview journal module;
- `XtermTerminal` and the pane metadata that supplies input capability;
- focused renderer, Rust, and packaged native tests.

No product behavior moves from the daemon into the renderer. Native preview journaling records effect delivery only; durable preview targets and revisions remain daemon-owned.

## Acceptance criteria

1. A cold native launch with a persisted non-English locale mounts product routes in that locale without a transient English fallback.
2. Shortcut edits cannot execute against an unhydrated map or erase unrelated persisted overrides.
3. Renderer and native accelerators match after a full relaunch.
4. Clicking a packaged macOS or Windows notification focuses Operator and delivers the exact ID once to the renderer.
5. Stable packaged macOS creates no tray; allowed nightly/development builds retain tray behavior.
6. An acknowledgement failure after browser open can be retried across renderer or app restart without opening another automatic tab.
7. Plain shells never receive the agent-specific Shift+Enter escape sequence.
8. All new state remains under the configured Operator root and all renderer/Rust/native tests pass.

## Out of scope

This design does not add the embedded Browser panel, redesign terminal/chat portability, broaden Linux notification activation, or redesign native titlebars.
