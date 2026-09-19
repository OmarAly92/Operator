# Settings › Mobile and the ngrok section — design

Date: 2026-09-19. Scope: `backend/` (tunnel package, mobile controller, OpenAPI)
and `frontend/` (renderer Settings dialog). The Flutter client is untouched.

## 1. Problem

Two bugs and one missing surface, all found from one incident on 2026-09-19.

**Incident.** The tunnel toggle failed with `tunnel: ngrok published no url within
1m0s`. Running ngrok by hand with the daemon's exact argv showed the real reason in
ngrok's own JSON log, repeated every second:

```
failed to send authentication request: failed to fetch CRL. errors encountered:
asn1: structure error: length too large
```

The agent fetches its CRL from `http://crl.ngrok-agent.com/ngrok.crl` over plain
HTTP. The user's ISP (Telecom Egypt) had a middlebox redirecting every plain-HTTP
request to a "100% of monthly quota consumed" page (`307`, `Via: 1.0 middlebox`,
`Location: http://megaplusredirection.tedata.net/VDSL-Redirection_100.html`).
ngrok parsed the HTML as DER and refused to authenticate. Meanwhile cloudflared,
which is HTTPS/QUIC only, published a URL in about five seconds when run by hand.

**Bug 1 — the real error is discarded.** `Manager.awaitURL`
([`manager.go:300-318`](../../../backend/internal/tunnel/manager.go)) returns the
generic timeout string. The 200 buffered log lines that carried the real error are
only consulted by `supervise` when the child process *exits*
(`manager.go:493`). ngrok never exited; it retried forever.

**Bug 2 — no fallback on a start timeout.** `runAwaitURL`
(`manager.go:284-297`) sets `StateFailed`, calls `retryableLocked()` and stops.
Fallback to the next provider lives only in `handleProviderRefusal`
(`manager.go:596`), reached from `supervise` after a process exit classified as
credential/refused. A provider that stays alive but never publishes never falls
through, so cloudflared was never tried.

**Missing surface.** Everything mobile lives in the Connect Mobile modal; ngrok is a
toggle, an authtoken dialog and one error line. There is no place to see what
ngrok is doing, which credential it uses, which binary runs, or why it failed, and
no way to log in, re-login or log out of ngrok except the token dialog that opens
on a credential rejection.

## 2. Goals

1. A **Mobile** tab in the Settings dialog sidebar that holds every mobile
   control. The Connect Mobile modal keeps working as a shortcut and renders the
   same components.
2. An **ngrok section** inside that tab: credential (log in / replace / remove),
   optional **API key** with the account view it unlocks (one-click login, stable
   domain, agent sessions, endpoints), session and agent facts, diagnostics and the
   live agent log.
3. Start-timeout failures carry the provider's own message and **fall back** to the
   next provider like any other refusal.
4. A CRL / HTTP-interception diagnosis that names the cause in plain words.

## 3. Non-goals

- Editing the user's system ngrok config
  (`~/Library/Application Support/ngrok/ngrok.yml`). Operator reads it to report
  "using your system ngrok login" and never writes it.
- An ngrok OAuth or browser login. The agent has none; the credential is the
  authtoken, and with an API key Operator can mint one.
- Account identity (email, plan). The ngrok API v2 has no such endpoint.
- A dedicated cloudflared section. It gets the fallback and error-surfacing fixes
  and appears in the Public access section as the active provider when used.
- Changes to the Flutter client or the pairing payload.

## 4. Tunnel manager fixes (`backend/internal/tunnel`)

### 4.1 Rule

A provider that **never published a URL** in the current attempt is treated as
refused: its log lines are classified, the message is surfaced, the provider is
marked sticky, and the manager moves to the next provider. A provider that **was
live** and then dropped keeps today's reconnect-in-place behaviour.

### 4.2 Changes

- `awaitURL` returns a typed error `errStartTimeout` (wrapping the existing
  message) instead of a bare `fmt.Errorf`.
- `runAwaitURL`, on `errStartTimeout`: stop the child (`stopChild`), read
  `logs.Lines()`, call `provider.ClassifyFailure`, and build the failure:
  - if the class is `FailureUnknown`, use `FailureRefused` with the message
    `"<provider> published no url within 1m0s"`;
  - otherwise keep the class and the provider's message.
  Then call `handleProviderRefusal(context.Background(), provider, failure, class)`
  (not `firstAwaitCtx`, which is cancelled the moment the attempt ends). This is the
  path `supervise` already uses, so stickiness, `NeedsAuthtoken`, the "both
  refused" terminal state and the `OnProvider` notification all stay in one place.
  `supervise` must not also run its post-exit classification for this case:
  `runAwaitURL` calls `cancel()` (the run context) and waits on `<-done` before
  classifying, exactly as the existing failed path does, so `supervise`'s
  first-attempt `select` takes its `ctx.Done()` case, stops the child and returns
  without classifying. No new channel is needed.
- `combineFailure` is untouched. `runAwaitURL` itself maps `FailureUnknown` and
  `FailureNetwork` to `FailureRefused` before calling `handleProviderRefusal`, so
  a never-published attempt always falls back. `FailureNetwork` still means
  "reconnect" for a provider that was live (the `supervise` path).
- `ngrokProvider.ClassifyFailure` recognises, in addition to `ERR_NGROK_4018`:
  - `failed to fetch CRL` → `FailureNetwork`, message
    `ngrok could not fetch its certificate revocation list (plain HTTP is being
    intercepted on this network)`;
  - `failed to send authentication request` (without the CRL text) →
    `FailureNetwork`, tidied verbatim message;
  - any other `"err"` → `FailureRefused` as today.
- `Status` gains `LastProvider string` and `FallbackReason string`, set by
  `handleProviderRefusal` (`LastProvider` = the skipped provider, `FallbackReason`
  = its message). `Error` keeps its current semantics untouched
  (`TestFallbackOnLimitAfterServingSwitchesAndKeepsTheMessage` asserts the skipped
  provider's message survives while cloudflared is live). The UI shows "Using
  cloudflared — ngrok: <fallbackReason>" when `state == live && lastProvider != ""
  && lastProvider != provider`. `Disable` and a fresh `Enable` clear both.

### 4.3 Tests (`manager_fallback_test.go`, `ngrok_test.go`)

- `TestStartTimeoutSurfacesTheProviderLogAndFallsBack`: fake ngrok stays alive,
  never publishes, logs a CRL error; after the (faked-clock) 60 s the manager
  stops it, `Status().FallbackReason` carries the CRL message, cloudflared is
  launched and goes live.
- `TestStartTimeoutWithoutAnyLogStillFallsBack`: empty log → message
  `ngrok published no url within 1m0s`, fallback still happens.
- `TestStartTimeoutOnTheLastProviderFailsTerminally`: cloudflared times out too →
  `StateFailed`, `Error` is cloudflared's message, `enabled` is false so Enable
  works again.
- `TestNgrokClassifyFailureCRLIsNetwork`, `TestNgrokClassifyFailureAuthRequestIsNetwork`.
- Existing fallback tests keep passing unchanged; `TestAFailedTunnelCanBeEnabledAgainWithoutADaemonRestart` covers the reset.

## 5. ngrok management in the daemon

### 5.1 Files

- `backend/internal/tunnel/ngrok_info.go` — agent facts and control-API reads.
- `backend/internal/tunnel/ngrok_apikey.go` — API-key storage and the ngrok API
  client (all calls go through the daemon; the renderer never holds the key).
- `backend/internal/tunnel/ngrok_diagnose.go` — diagnostics runner.
- `backend/internal/httpd/controllers/mobile_ngrok.go` — controller methods.
- `backend/internal/httpd/apispec/specgen/build.go` — operations + `schemaNames`.

### 5.2 Storage

- Authtoken: unchanged — `~/.operator/<dataDir>/mobile/ngrok.yml` written by
  `ngrok config add-authtoken`. New `Manager.RemoveAuthtoken()` rewrites that file
  without the `authtoken:` line (using `mergeNgrokWebAddr`'s parser: drop the key,
  keep `web_addr`).
- API key: `<dataDir>/mobile/ngrok-api-key`, mode `0600`, the key plus a trailing
  newline. `Manager.SetAPIKey(ctx, key)` verifies it with `GET /api_keys` before
  writing; `RemoveAPIKey()` deletes the file. Never logged; every error string that
  could echo it goes through `redact`.
- Stable domain: `<dataDir>/mobile/config.json` gains `ngrokDomain string`
  (`mobilebridge.Config`). When set, `ngrokProvider.Args` appends
  `--url=https://<domain>`. The `BridgeService` passes it to the provider through a
  new `Manager.SetNgrokDomain(domain string)`; the provider reads it under the
  manager lock at launch.

### 5.3 `GET /api/v1/mobile/tunnel/ngrok` → `MobileNgrokStatus`

Cheap, local-only; the section polls it every 2 s while visible.

```
credential: {
  present: bool,
  source: "operator" | "system" | "",   // which file carries authtoken:
  systemConfigPath: string,             // for the "system" hint
  suffix: string,                       // last 4 chars of the token, "" if absent
}
agent: {
  binaryPath: string,                   // resolved via Store.Ensure without downloading
  source: "path" | "managed" | "",      // Homebrew/PATH vs Operator download
  version: string,
  updateAvailable: bool,                // ngrok's "update available" log line seen
}
session: {                              // from the control API while a child runs
  status: "online" | "reconnecting" | "closing" | "",
  region: string, latency: string,      // /api/status session.legs[0]
  publicURL: string,
  connections: int, httpRequests: int,  // /api/tunnels metrics
}
domain: string                          // configured stable domain, "" if none
apiKey: { present: bool }
logs: [ { time: string, level: string, message: string } ]   // last 200, redacted
```

`Store` gains `Resolve(spec) (path, source string, ok bool)` — the lookup half of
`Ensure` with no download. Log lines are ngrok's JSON parsed into `t`, `lvl`,
`msg` + `err` (when non-nil), authtoken and API key redacted; non-JSON lines pass
through with `level: ""`. Lines are the manager's `lineRing` for the current or last
child; they survive a stop until the next Enable.

### 5.4 Authtoken routes

- `POST /api/v1/mobile/tunnel/authtoken` — unchanged (manual paste).
- `DELETE /api/v1/mobile/tunnel/authtoken` — removes Operator's token only. If the
  system config still has one, the response's `credential.source` becomes
  `"system"`; the UI says so.

### 5.5 API key and account: `/api/v1/mobile/tunnel/ngrok/…`

- `PUT api-key` `{key}` → verifies, stores, returns `MobileNgrokAccount`.
- `DELETE api-key` → deletes; the stable domain setting is kept (the agent needs
  only the authtoken to use it).
- `GET account` → `MobileNgrokAccount`, polled every 30 s while the section is
  visible **and** a key is present:

```
valid: bool, error: string               // 401/403 → valid:false with ngrok's message
credentials: [ { id, description, createdAt, isOperator: bool } ]
sessions:    [ { id, region, ip, agentVersion, os, startedAt, isThisMachine: bool } ]
endpoints:   [ { id, publicURL, proto, createdAt } ]
reservedDomains: [ { id, domain } ]
```

`isOperator` matches description `Operator on <hostname>`; `isThisMachine`
matches `ip` against the tunnel's own session or the hostname in `metadata`.

- `POST account/credential` → mints an authtoken via `POST /credentials`
  `{description: "Operator on <hostname>"}`, stores it exactly as
  `SetAuthtoken` does, revokes any *previous* Operator-minted credential for this
  hostname, returns `MobileNgrokStatus`. This is "Log in with API key".
- `DELETE account/credential/{id}` → `DELETE /credentials/{id}`; if it was the
  stored token, also `RemoveAuthtoken`.
- `PUT domain` `{domain}` → must be one of `reservedDomains` (or `""` to clear);
  writes `ngrokDomain`; if the tunnel is live on ngrok, restarts it.

ngrok API client: base `https://api.ngrok.com`, headers `Authorization: Bearer`,
`Ngrok-Version: 2`, 10 s timeout, pagination ignored beyond the first 100 (a
documented limit in the DTO description). Errors map to the daemon envelope with
codes `NGROK_API_UNAUTHORIZED`, `NGROK_API_ERROR`.

### 5.6 `POST /api/v1/mobile/tunnel/ngrok/diagnose` → `MobileNgrokDiagnosis`

Runs synchronously (≤ 30 s, context timeout) and returns:

```
checks: [ { name, ok: bool, detail: string } ]
summary: string          // one sentence for the UI banner
```

Checks, in order:

1. **Binary** — `Store.Resolve` + `ngrok version`.
2. **CRL over HTTP** — `GET http://crl.ngrok-agent.com/ngrok.crl` with redirects
   *disabled*. `ok` when 200 and the body parses with
   `x509.ParseRevocationList` (or `ParseCRL` fallback). A 3xx, a `Via` header
   containing `middlebox`, or a non-DER body reports
   `detail: "Plain HTTP is being intercepted on this network (redirected to
   <host>). ngrok cannot authenticate until this is lifted; cloudflared is
   unaffected."`
3. **Control plane** — TLS connect to `connect.ngrok-agent.com:443`.
4. **`ngrok diagnose`** — run the agent's own command with the same `--config`
   flags. Its output is `<Group>` header lines followed by two-space-indented
   `<Name>   [ OK ]` / `[ ERROR ]` rows, then an optional "Errors and warnings"
   block; each row becomes a check named `<Group>: <Name>`, and the first
   `- Err:` paragraph (joined, whitespace-collapsed) becomes the detail of the
   failing row. Captured 2026-09-19 on the incident network: `Ngrok Connectivity
   - Region: Auto (lowest latency)` / `TLS [ ERROR ]` with `ERR_NGROK_8003 …
   Possible Man-in-the Middle`.
5. **Credential** — present / source, and if an API key exists, whether the
   Operator credential still exists on the account.

`summary` is the first failing check's detail, or "ngrok can connect from this
machine." Nothing is persisted.

### 5.7 OpenAPI

Every new type is added to `schemaNames`; `openapi.yaml` and
`frontend/src/api/schema.ts` are regenerated and committed with the Go change
(`AGENTS.md` §API). `MobileTunnelStatus` gains `lastProvider` and
`fallbackReason`.

### 5.8 Tests

- `ngrok_info_test.go`: credential source resolution (operator / system / none),
  suffix, log parsing and redaction, control-API parsing with an `httptest`
  server.
- `ngrok_apikey_test.go`: verify-before-store, 0600, remove, account aggregation
  against a fake `api.ngrok.com` (`httptest` + base-URL injection), credential
  minting stores the token through the same path as `SetAuthtoken`, previous
  Operator credential revoked, domain validation.
- `ngrok_diagnose_test.go`: middlebox fake (`307` + `Via: 1.0 middlebox`) → CRL
  check fails with the interception detail; DER CRL → ok; PEM body → fails with a
  parse detail; `ngrok diagnose` output parsing from a fixture.
- `controllers/mobile_ngrok_test.go`: each route's envelope, 400 on empty key /
  unknown domain, 401 mapping.

## 6. Renderer: Settings › Mobile

### 6.1 Navigation

- `GlobalSettingsSection` gains `"mobile"`. `SettingsDialog.globalSections` inserts
  `{ id: "mobile", label: t("settings.mobile"), icon: Smartphone }` after
  *Claude accounts*.
- `useUiStore.openConnectMobile` keeps opening the modal. A new
  `openMobileSettings()` sets `settingsModal = { scope: "global", section: "mobile" }`;
  `SettingsModal` gains an optional `section`, and `SettingsDialog`'s reset effect
  honours it. `TunnelLiveRow` / `TunnelLiveRailButton` and the General section's
  *Connect mobile* row call `openMobileSettings`. The sidebar card that opens the
  modal is unchanged.

### 6.2 Components (`frontend/src/renderer/components/settings/mobile/`)

The body of `ConnectMobileModal` is split into section components that take the
status query and mutations from one hook, so the modal and the tab render the same
thing:

- `useMobileBridge.ts` — the `useQuery`/`useMutation` set now inside
  `ConnectMobileModal` (status, enable, disable, regenerate, tunnel enable/disable),
  unchanged behaviour, plus `ngrokStatus` (2 s), `ngrokAccount` (30 s, enabled only
  with a key and while mounted) and the new mutations.
- `MobileConnectionSection` — enable on my network, address, password + regenerate,
  QR / pairing, `ConnectMobileGetApp`, `ConnectMobileSetup`. Moved, not redesigned.
- `MobilePublicAccessSection` — the tunnel toggle row; state line; when
  `fallbackReason` is set: *"Using cloudflared — ngrok: <reason>"* in muted text with
  a *Details* link that scrolls to the ngrok section; when `failed`: the error in
  `text-error`.
- `NgrokSection` — `SettingsSection title="ngrok"` containing four grouped cards
  (`SettingsRow`s inside `SettingsSection grouped`):
  1. **Credential** — status row (*Not logged in* / *Logged in (…abcd) via Operator*
     / *Using your system ngrok login (~/Library/…/ngrok.yml)*), actions:
     *Log in* → `NgrokAuthtokenDialog` (or *Log in with API key* when a key is
     present, calling `POST account/credential`), *Replace token*, *Remove* (Operator
     token only, confirm dialog), *Open dashboard*.
  2. **API key** — masked presence row, *Add key* / *Replace* / *Remove* using a
     new `NgrokApiKeyDialog` (same shape as `NgrokAuthtokenDialog`, link to
     `https://dashboard.ngrok.com/api-keys`). Below it, when valid: **Stable
     domain** select over `reservedDomains` (+ *none*), **Authtokens** list with
     the Operator one marked and *Revoke*, **Agent sessions** list, **Endpoints**
     list. When invalid: the ngrok error in `text-error` with *Replace*.
  3. **Session & agent** — status dot + text (`online` / `reconnecting` / off),
     region · latency, public URL with copy, connections, live since, restarts;
     binary path with source badge (*Homebrew* / *Operator-managed*), version,
     *Update available* hint. *Restart tunnel* button (disable then enable).
  4. **Diagnostics** — *Run diagnostics* button; result list with ✓/✕ per check and
     the summary banner; **Agent log** panel: monospace, last 200 lines,
     `lvl: eror` rows in `text-error`, auto-scroll pinned to bottom unless the user
     scrolled up, *Copy* button.
- `ConnectMobileModal` becomes a thin shell rendering
  `MobileConnectionSection` + `MobilePublicAccessSection` (no ngrok section — that
  is the tab's job; a *Manage ngrok* link opens the tab).
- `GlobalSettingsForm` renders `<MobileSettingsSection>` =
  Connection + Public access + Ngrok for `section === "mobile"`.

### 6.3 Copy and design

- All copy through `t()` in `en.json` under `mobile.*` / `settings.mobile`; other
  locales fall back to English (`fallbackLng`). The literal-scan test
  (`renderer-coverage.test.ts`) gets allowlist entries only for `ngrok`,
  `cloudflared`, `Homebrew` and the config path.
- Look: shadcn primitives already used by the settings pages (`SettingsSection`,
  `SettingsRow`, `Button`, `Switch`, `Dialog`, `Select`); the agent-orchestrator
  clone rule in `DESIGN.md` applies. The log panel uses the terminal's mono font
  token, not the terminal renderer.

### 6.4 Tests (Vitest)

- `SettingsDialog.test.tsx`: Mobile appears in the sidebar; `openMobileSettings`
  lands on it.
- `MobileSettingsSection.test.tsx`: renders the three sections from a fake status.
- `NgrokSection.test.tsx`: states — no token; system token; Operator token; API
  key invalid; API key valid with domains/sessions; live session; fallback reason
  shown; diagnostics result rendering; log redaction never shows a token-shaped
  string; copy button writes the joined lines.
- `ConnectMobileModal.*.test.tsx`: existing tests keep passing against the shell.
- `TunnelLiveIndicator.test.tsx`: click opens the Mobile tab.

## 7. Real-app verification

Per `verify-operator-desktop-through-daemon-api-and-mux`: rebuild the daemon,
`curl` the new routes on port 3002, then run the renderer in the browser against
the isolated daemon (`verify-renderer-in-browser-against-isolated-daemon`) and
screenshot Settings › Mobile in both themes. For the CRL check, point the probe's
base URL at a local fake middlebox to reproduce the incident without the ISP.

## 8. Open risks

- ngrok's control API field names (`session.legs[].region/latency`,
  `metrics.conns.count`) are read from the running 3.39.x agent; the info code
  treats every field as optional so an older agent degrades to blanks.
- `ngrok diagnose` output is human text; the parser keys on the known check
  names and stores unrecognised lines under a single *Agent diagnose* check.
- The start-timeout fallback changes `supervise`'s first-attempt `select`; the
  reconnect test file (`manager_reconnect_test.go`) must stay green untouched.
