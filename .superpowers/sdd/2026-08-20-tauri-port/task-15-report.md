# Task 15 report — production standalone agent-browser adapter

Base: 9271ff7b0e364ad87879bbe0f64ca2adcf6c4fe3 (branch codex/tauri-port).
Contract: UNCOMMITTED working tree only; nothing staged, nothing committed.
Brief: task-15-brief.md (Step 4 git block overridden by controller instruction — implementer never stages or commits).

## Files created

- `backend/internal/adapters/agentbrowser/policy.go` (453 lines) — native command policy, action→native argument translation, JSON envelope parsing with `_boundary` trust semantics, minimal parent-env allowlist.
- `backend/internal/adapters/agentbrowser/install.go` (417) — serialized system-browser discovery (`doctor --json`) / managed engine install (`install --json`, 600s timeout), pinned-version + sha256 manifest verification under `<state-root>/browser-engine`, partial-install wipe before reinstall, `locateManagedExecutable` containment port.
- `backend/internal/adapters/agentbrowser/runtime.go` (~1030) — the `browser.Runtime` adapter: per-run/per-session isolated state under `<state-root>/browser-runtime/<run>/<session>`, owner.json marker + heartbeat, `/tmp` short socket alias (unix, 103-byte guard), stale-owner scavenge (runs + aliases), bounded process runner (1 MiB output cap, 60s command / 10s close timeouts, cancel kill, unix process-group SIGKILL), screenshot pipeline (5 MiB cap, PNG dimensions, base64), response-shape mapping per public action, safe teardown.
- `backend/internal/adapters/agentbrowser/process_alive_unix.go` / `process_alive_windows.go` — build-tagged liveness probe (`kill(pid,0)` / `OpenProcess`) and child kill helpers. Beyond the brief's three-file list; disclosed here. Precedent: Task 9's settings_wiring.go addition.
- `backend/internal/adapters/agentbrowser/policy_test.go` (276), `install_test.go` (416), `runtime_test.go` (879) — the TDD suite.
- `backend/internal/service/browser/runtime.go` (50) — adapter-neutral contract: `RuntimeStatus{Ready,ReadyAt}`, `RuntimeResult{RequestID,Value}`, `CommandError{Code,Message}`, `ErrUnavailable`, `Runtime` interface with exactly `Status(sessionID)` / `Execute(ctx,sessionID,action,args)` / `DestroySession(ctx,sessionID)`.

## Files modified

- `backend/internal/service/browser/service.go` — dropped the `browserruntime` import; service now speaks only neutral types over the exported `Runtime`.
- `backend/internal/service/browser/service_test.go` — fakes updated to neutral signatures (+ DestroySession); new test that `ErrUnavailable` surfaces unchanged through the service.
- `backend/internal/httpd/controllers/browser.go` — `BrowserService` interface on neutral types; transport constant now exactly `agent-browser-standalone`; error mapping moved to `browsersvc.CommandError`/`ErrUnavailable`; additive mappings AGENT_BROWSER_INSTALL_FAILED/TIMEOUT→503, AGENT_BROWSER_CANCELLED→408, OUTPUT_TOO_LARGE/INVALID_OUTPUT→422.
- `backend/internal/httpd/controllers/browser_test.go` — fakes updated; pins `"transport":"agent-browser-standalone"`, disconnected status path, NOT_INSTALLED and INSTALL_FAILED 503s.
- `backend/internal/daemon/daemon.go` — builds `agentbrowser.New(...)` (binary via `OPERATOR_AGENT_BROWSER_PATH` override → packaged layouts); wires it as the browser service runtime; session-manager `BrowserLifecycle` is now a small `browserTeardown` composite that destroys BOTH the standalone session state and (best-effort) the Electron broker target, so the desktop panel keeps its teardown path until Task 16 deletes it.

Constraint check: `grep -rn internal/browserruntime backend/internal/httpd/controllers backend/internal/service` returns nothing — no public controller or service type imports the broker package. The broker itself is untouched and still serving for Electron.

## RED evidence (Step 2)

Command: `cd backend && go test ./internal/adapters/agentbrowser ./internal/service/browser ./internal/httpd/controllers -run 'AgentBrowser|Browser'`

Result before implementation — all three packages failed to compile because the adapter and the neutral contract did not exist:

```
internal/adapters/agentbrowser/install_test.go:21:48: undefined: CommandRequest
internal/adapters/agentbrowser/runtime_test.go:38:13: undefined: EngineResolution
internal/service/browser/service_test.go:25:50: undefined: RuntimeStatus
internal/service/browser/service_test.go:34:4: undefined: RuntimeResult
internal/httpd/controllers/browser_test.go:21:20: undefined: browsersvc.RuntimeStatus
FAIL github.com/OmarAly92/operator/backend/internal/adapters/agentbrowser [build failed]
FAIL github.com/OmarAly92/operator/backend/internal/service/browser     [build failed]
FAIL github.com/OmarAly92/operator/backend/internal/httpd/controllers   [build failed]
```

## GREEN evidence

Final gate runs (all exit 0):

```
go build ./...                                  -> ok
go vet ./...                                    -> ok
gofmt -l (touched dirs)                         -> clean
go test -count=1 ./internal/adapters/agentbrowser   ok 2.955s
go test -count=1 ./internal/service/browser         ok 0.528s
go test -count=1 ./internal/httpd/controllers       ok 4.671s
go test -count=1 ./internal/cli                     ok 2.062s
go test -race -count=1  (same four packages)        all ok
go test -race -count=1 ./internal/daemon            ok 9.460s
go test ./internal/daemon/...                       ok
go test ./...  (FULL backend suite)                 exit 0, zero failures
```

Test counts: adapter package = 48 passing tests (list below); service+controller Browser-filtered run adds 30 passing tests (incl. subtests for each core action). Full backend `./...` re-ran clean afterwards.

Adapter tests (48): policy ports (validate allow/block/limits; translation snapshot/ref contract; waits/tabs/frames/dialogs; stable identifier codes URL_REQUIRED/REFERENCE_REQUIRED/TAB_ID_REQUIRED; tabs optional values; ParseJSON boundary preservation + page-shaped spoof rejection + failure envelopes), install (system-browser preferred; managed install with manifest version+sha256+executable containment; memoized reuse without respawning; concurrent resolves serialize to exactly one doctor+install; partial-install cleanup incl. `.download` leftovers; pinned-version-mismatch reinstall; checksum-tamper reinstall; install-failure fail-closed AGENT_BROWSER_INSTALL_FAILED; missing-executable AGENT_BROWSER_NOT_INSTALLED; containment refusal), runtime (isolated per-session state + env allowlist assertions incl. no AGENT_BROWSER_CDP / AUTO_CONNECT=0 / no AWS_SECRET_ACCESS_KEY / HTTP_PROXY; distinct roots+namespaces per session; concurrent first commands serialize to one session dir; --json append + untrustedExternalContent; console/errors normalization with trust markers; tabs/tab-new/get/open shapes; command-failure stable code; binary-missing fail closed; desktop-panel-only actions rejected without spawn; managed executable path injection; engine failure propagation; Status readiness; DestroySession close+dir removal+idle no-op; close-timeout survival; concurrent destroy dedupe to one close; screenshot base64/dimensions/cleanup; oversized screenshot rejection; invalid PNG rejection; scavenge dead-run roots only (live/malformed/unmarked/foreign preserved; fresh-dead within grace kept); owned-only socket alias scavenge; Execute triggers scavenge; owner heartbeat touch), process runner (real processes: capture+exit code; timeout kill; cancel kill; output cap AGENT_BROWSER_OUTPUT_TOO_LARGE; spawn failure AGENT_BROWSER_START_FAILED).

## Real-fixture verification (Phase 0 parity)

Harness: temporary env-gated Go test in the adapter package (`OPERATOR_AGENT_BROWSER_TEST_BINARY`), deleted after the run. It starts the phase0 fixture page (h1 "ready", button "swap" that sets title textContent="clicked", `console.log('fixture-loaded')`) on a loopback httptest server and drives the REAL packaged binary `frontend/agent-browser/agent-browser` (v0.33.1) through `adapter.Execute` exactly like production.

Command: `cd backend && OPERATOR_AGENT_BROWSER_TEST_BINARY=/Users/omaraly/development/AI/Operator-tauri/frontend/agent-browser/agent-browser go test ./internal/adapters/agentbrowser -run TestManualFixtureVerification -v -timeout 300s`

Outcome: **PASS** (70.8s wall, real Chromium launched by agent-browser's own system discovery: `"engine":"chrome","browserLaunched":true`). Observed transcript:

- `open <fixture>` → `{url:"http://127.0.0.1:<port>/", title:"Operator Phase 0 Fixture primary", _boundary:{nonce,origin}, lifecycle{...}, untrustedExternalContent:true}`
- `snapshot {}` → `text:"- heading \"ready\" [level=1, ref=e1]\n- button \"swap\" [ref=e2]"`, plus `refs:{e1,e2}` and root `_boundary` preserved verbatim.
- `click {ref:"@e2"}` → `{clicked:"@e2"}` (real click delivered).
- `console` → `{messages:[{level:"log", message:"<<<BEGIN UNTRUSTED EXTERNAL CONTENT>>>\nfixture-loaded\n<<<END ...>>>", timestamp}]}`
- `errors` → `{messages:[]}` (no page errors).
- `screenshot` → base64 PNG, width 1280 height 577 (headless Chromium default viewport), temp dir removed after read.
- `tab-new <fixture>?tab=second` → `{id:"t2", active:true, url:...}`; `tabs` → two entries `{id:t1|t2,url,title,active}`, `activeTabId:"t2"`; `tab-select t1` → `{id:"t1", title:"Operator Phase 0 Fixture primary", active:true}`; `tab-close` → `{closedTabId:"t1"}`.
- teardown: `DestroySession` ran native `close` then removed the session dir; the whole `<run>` root under `browser-runtime/` was gone (`ReadDir` returned empty) — "teardown clean".

A second raw-shape probe captured native stdout of open/tab new/tab list/get url/close to pin the mapping keys (native tab entries carry `tabId`, not `id`; that discovery fixed `shapeTabs`/`shapeSingleTab`/`shapeTabClose`). Harness files were then deleted from the tree.

## Design decisions and disclosed divergences

1. Transport string is exactly `agent-browser-standalone` (constant `browserTransport`, controller). The wire field name stays `"transport"` — response schema unchanged, so no OpenAPI regeneration was needed (apispec drift tests green).
2. Never set: `AGENT_BROWSER_CDP` (asserted absent in tests), auto-connect enforced via `AGENT_BROWSER_AUTO_CONNECT=0`, forbidden flags blocked at the policy layer (`--cdp --auto-connect --profile --session --namespace --restore --state --executable-path --extension --init-script --args --headers --proxy --plugin --allowed-domains`, exact and `=` forms), `connect`/`eval`/`get cdp-url`/non-snapshot `diff`/`stream` commands blocked, navigation restricted to explicit http(s).
3. Env isolation follows the phase0 probe shape: child gets PATH (+windows SYSTEMROOT/WINDIR/COMSPEC/PATHEXT) and locale vars from an allowlist, HOME/USERPROFILE=session dir, XDG_* under it, TMPDIR/TEMP/TMP=<session>/tmp, owned empty `config.json` via `AGENT_BROWSER_CONFIG` (kills user/project config pickup), plus Operator-scoped CONTENT_BOUNDARIES=1, MAX_OUTPUT=50000, IDLE_TIMEOUT_MS=300000.

4. Managed engine usage: when system discovery fails, the adapter passes the verified Chromium launcher to agent-browser via `AGENT_BROWSER_EXECUTABLE_PATH` (a documented native env var). This is how the shared read-only `<state-root>/browser-engine` tree is reused without ever pointing HOME at it during normal commands. Install-time processes DO run with HOME=engineRoot so downloads land inside it (phase0's `walkFiles(sessionRoot/.agent-browser/browsers)` shape), with an `.install-tmp` scratch dir for TMPDIR removed before manifesting.
5. Socket path length: agent-browser applies the 103-byte unix limit, and `~/.operator/browser-runtime/<run>/<session>` exceeds it, so the adapter ports the Electron runtime's `/tmp/opr-br-<pid>-<hex12>` symlink alias (real state stays under `~/.operator`; the alias is a symlink only). Alias scavenge verifies the target is `browser-runtime/<run>/s` under OUR state root before removing.
6. Deliberate non-port: TS's `stream disable` before every command was NOT ported. That defense existed because the Electron CDP bridge architecture could leave an input-capable stream enabled across native-daemon replacement. In standalone mode nothing ever calls `stream enable`, every session starts from an isolated fresh namespace/config, and the policy layer blocks `stream` commands outright (pinned by TestValidateAgentBrowserArgumentsBlocksOwnershipPersistenceAndUnsafeNavigation). Skipping avoids doubling process spawns per action. Flag for reviewer adjudication.
7. Desktop-panel-only actions keep their public names but fail honestly at the runtime with stable codes mapped by the existing controller switch: devtools-open/close → BROWSER_DEVTOOLS_UNAVAILABLE (503), network-start/status/list/stop/clear and unhighlight → BROWSER_AUTOMATION_UNAVAILABLE (503) — these were Electron CDP/WebContents features with no standalone equivalent until Task 16 removes them.
8. Response-shape fidelity: snapshot→`{text, refs, _boundary, untrustedExternalContent}`; console/errors→`{messages:[{level,message(markUntrusted+1MiB truncate),timestamp}]}` (Electron normalizeNativeMessages port); tabs/tab-new/tab-select/tab-close/get/open mapped per the raw-shape probe; screenshot→`{data,width,height}`. Electron-only fields that have no standalone meaning (viewId/canGoBack/canGoForward nav state, favicon, panel tab bookkeeping) are not synthesized — renderer consumers of those shapes are deleted in Task 16.
9. Session-manager teardown is a composite (standalone DestroySession + best-effort broker `__destroy-session`) so the mounted desktop panel still releases its targets during the Task 15→16 window; the standalone side always removes per-session state even when close fails or times out.

## Self-review findings (found and fixed during implementation)

1. Concurrent-init bug caught by TestConcurrentFirstCommandsSerializeSessionCreation: my first channel-based init dedupe handed the buffered outcome to one waiter and closed the channel, so additional waiters read a zero-value outcome → nil-pointer panic in sessionEnvironment. Replaced with a WaitGroup-based `sessionCall` shared by all waiters. -race clean after.
2. Exit-code handling gap: runForSession originally ignored `ExitCode != 0`, letting non-zero exits fall into JSON parsing (AGENT_BROWSER_INVALID_OUTPUT instead of AGENT_BROWSER_COMMAND_FAILED). Fixed + pinned by test.
3. assertHTTPURL ordering: `file:///tmp/secret` hit the host check first and returned INVALID_URL instead of BROWSER_URL_FORBIDDEN; scheme check now precedes host presence.
4. Native tab key mismatch discovered by the real fixture run (`tabId`, not `id`) — shape mappers fixed and re-verified live.
5. Engine memoization semantics: version/checksum revalidation tests initially assumed per-call validation against a mutated tree after a cached success. Correct production behavior is validate-once-per-run (full-tree sha256 each command would be prohibitive); tests rewritten to seed invalid state BEFORE first Resolve.
6. Process-group kill added after TestDestroySessionSurvivesCloseTimeout showed plain `Process.Kill` orphaned the shell's child holding the pipe (Wait blocked ~5s). Unix children now start with Setpgid and timeout/cancel SIGKILL the group.
7. Streaming-hash fix: manifest walker originally did os.ReadFile of whole files (200MB Chromium binary into RAM); now streams via io.Copy into sha256.
8. Install TMPDIR isolated to `.install-tmp` (deleted pre-manifest) so installer temp files can never pollute the checksum manifest.

## Concerns / disclosures for reviewer adjudication

1. ONE UNCAPTURED LOAD-SENSITIVE FAILURE: immediately after a rebuild cycle, one `go test ./internal/adapters/agentbrowser` run failed (7.58s total vs usual ~2s); the failing test name/output was not captured because the follow-up grep ran against a passing rerun. Protocol applied: 8 verbose runs under artificial CPU load + 3 plain + 6 `-race -v` runs, all green (exact outputs "ok ... 1.964–2.071s" plain; race runs ok at ~3.2s; final gate rerun all ok). Suspects are the two timing-bounded assertions (TestDestroySessionSurvivesCloseTimeout <3s, TestProcessRunnerKillsOnTimeout <5s — both prove return well before the 30s child sleep; normal margins are 10–30x). No code change made on speculation; flagging for the reviewer's judgment on whether to widen bounds.
2. Cross-run install serialization is in-process only (singleflight + mutex). Two concurrent daemon processes sharing a state root could both wipe/reinstall browser-engine; a running browser from the old tree could break. Same-machine dual daemons are already an unsupported state; noted rather than over-engineered (no flock precedent in this Go codebase).
3. Windows surface (named-pipe socket dir instead of alias, OpenProcess liveness, no process groups) is cfg-gated and line-reasoned but uncompiled locally — consistent with the repo's standing three-platform CI caveat.
4. Binary discovery defaults to packaged layouts + `OPERATOR_AGENT_BROWSER_PATH`; in dev checkouts without the override the adapter reports NOT_INSTALLED (status shows disconnected) rather than guessing. Task 18 owns packaging wiring.
5. First automation use may block up to 600s while the managed Chromium downloads (spec: "install ... on first automation use"); doctor+install happen lazily inside Execute, serialized.
6. golangci-lint remains unavailable locally (established external CI gate); go vet + gofmt clean here.

---

# Fix round 1 — Important #1: state root must not be derived from DataDir

Finding (adjudicated): `stateRoot()` = `filepath.Dir(dataDir)` escaped Operator-owned roots under an `OPERATOR_DATA_DIR`-style override (`OPERATOR_DATA_DIR=/tmp/op` put browser-engine/browser-runtime in `/tmp`). Fix: thread an explicit state root through `Options` instead of deriving it from DataDir's parent.

## Changes (surgical, only the finding)

1. RED first — new failing tests:
   - `TestResolveStateRootPrefersExplicitOverrideAndCanonicalFallback` (agentbrowser): explicit `Options.StateRoot` wins; empty resolves to canonical `<UserHomeDir>/.operator`. Failed with `undefined: resolveStateRoot` / `unknown field StateRoot`.
   - `TestExecutePlacesRuntimeUnderConfiguredStateRoot` (agentbrowser): `DataDir = <tmp>/override/operator-data` while `StateRoot = <other tmp>`; Execute must place session HOME under `<StateRoot>/browser-runtime/...` and never inside the override tree. Old derivation (`filepath.Dir(dataDir)` → `<tmp>/override`) fails both assertions by construction; pre-fix run also failed compilation because neither the field nor resolver existed.
   - `TestStateRootMatchesCanonicalOperatorHome` (config): pins new exported `config.StateRoot()` == `~/.operator`.
2. `backend/internal/adapters/agentbrowser/runtime.go`: added `Options.StateRoot`; adapter resolves once at `New` into a private field via `resolveStateRoot` (explicit → canonical `os.UserHomeDir()/.operator` → "" on failure); engine default wiring, `ensureRunRoot`, and scavenge (runtime runs + socket aliases) all use the resolved root; unresolvable root fails closed (engine resolver returns error; session creation refuses with a clear message) instead of writing anywhere else.
3. `backend/internal/config/config.go`: one exported wrapper `StateRoot() (string, error)` over the existing unexported `defaultStateDir()`, with doc comment explaining why shared desktop surfaces must hang off the canonical root.
4. `backend/internal/daemon/daemon.go`: passes `config.StateRoot()` into `agentbrowser.Options.StateRoot`; resolution failure logs a warning and leaves standalone browser disabled rather than blocking boot.
5. Test fixture fallout of the contract change: `newTestAdapter` now sets an explicit temp `StateRoot`, and its 4th return value / `runtimeRootFor` switched from dataDir-derived to state-root-derived, so existing lifecycle/scavenge/heartbeat tests keep asserting against the configured root instead of `filepath.Dir(dataDir)`.

## RED evidence (fix round)

```
cd backend && go test ./internal/adapters/agentbrowser ./internal/config \
  -run 'TestResolveStateRoot|TestExecutePlacesRuntimeUnderConfiguredStateRoot|TestStateRootMatchesCanonical'

internal/adapters/agentbrowser/runtime_test.go:882:14: undefined: resolveStateRoot
internal/adapters/agentbrowser/runtime_test.go:882:39: unknown field StateRoot in struct literal of type Options
internal/adapters/agentbrowser/runtime_test.go:901:11: options.StateRoot undefined (type *Options has no field or method StateRoot)
internal/config/config_test.go:286:20: undefined: StateRoot
FAIL github.com/OmarAly92/operator/backend/internal/adapters/agentbrowser [build failed]
FAIL github.com/OmarAly92/operator/backend/internal/config [build failed]
```

## GREEN evidence + covering gates (exact outputs)

```
cd backend
go build ./...                                   -> ok (no output)
go vet ./...                                     -> ok (no output)
go test -count=1 ./internal/adapters/agentbrowser \
    ./internal/service/browser ./internal/daemon ./internal/config
  ok  github.com/OmarAly92/operator/backend/internal/adapters/agentbrowser 2.287s
  ok  github.com/OmarAly92/operator/backend/internal/service/browser      0.422s
  ok  github.com/OmarAly92/operator/backend/internal/daemon               0.839s
  ok  github.com/OmarAly92/operator/backend/internal/config               (prior run 0.651s)
go test -race -count=1 ./internal/adapters/agentbrowser
  ok  github.com/OmarAly92/operator/backend/internal/adapters/agentbrowser 3.459s
gofmt -l internal/adapters/agentbrowser internal/config internal/daemon internal/service/browser
  -> no output (clean)
```

New-test GREEN run:

```
--- PASS: TestResolveStateRootPrefersExplicitOverrideAndCanonicalFallback (0.00s)
--- PASS: TestExecutePlacesRuntimeUnderConfiguredStateRoot (0.02s)
ok  github.com/OmarAly92/operator/backend/internal/adapters/agentbrowser 0.888s
--- PASS: TestStateRootMatchesCanonicalOperatorHome (0.00s)
ok  github.com/OmarAly92/operator/backend/internal/config 1.207s
```

Containment semantics now guaranteed: with `OPERATOR_DATA_DIR=/tmp/op`, `browser-engine` and `browser-runtime` stay at `<canonical ~/.operator>/…` (daemon passes `config.StateRoot()`), or wherever the deployment explicitly points `Options.StateRoot` — never at `filepath.Dir(override)`. The e2e harness's override (`internal/cli/e2e_test.go`) can therefore never relocate browser state outside an Operator-owned root; the adapter additionally refuses to operate (fail-closed, logged) if the canonical home cannot be resolved.

Scope note: only the state-root threading, its config export, daemon wiring, and the covering tests changed this round. Parked minors untouched; no reformatting; tree remains fully uncommitted (HEAD still 9271ff7b0, nothing staged).
