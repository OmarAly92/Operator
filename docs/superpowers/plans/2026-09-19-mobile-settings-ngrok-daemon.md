# Settings › Mobile / ngrok — daemon plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a tunnel provider that never publishes a URL fall back to the next provider with its real error surfaced, and give the daemon an ngrok management surface (credential, API key + account, session/agent facts, diagnostics, logs) under `/api/v1/mobile/tunnel/ngrok…`.

**Architecture:** All new logic lives in `backend/internal/tunnel` behind `*Manager` methods; `controllers.BridgeService` adapts them to wire DTOs; `httpd/router.go` mounts the routes on the loopback router; `apispec/specgen` describes them. The renderer never receives the API key or the authtoken — the daemon proxies every ngrok API call.

**Tech Stack:** Go 1.2x, chi, `net/http/httptest`, `crypto/x509`; OpenAPI via `go generate` + `openapi-typescript`.

**Spec:** `docs/superpowers/specs/2026-09-19-mobile-settings-ngrok-design.md` (sections 4 and 5).

## Global Constraints

- Work on `development`; never commit to `master`.
- No code comments (user rule). Existing comment density in touched files is left alone; new code adds none.
- Every `go test ./internal/tunnel/... ./internal/httpd/...` run must be green before a commit; run `go test -race ./internal/tunnel/...` before Task 3's commit.
- Secrets: the authtoken and the API key never appear in log lines, error strings or wire DTOs. Use the existing `redact` helper (`authtoken.go`).
- After any DTO or route change: `npm run api` from the repo root, then `cd backend && go test ./internal/httpd/...` (spec-drift + route parity), and commit `openapi.yaml` + `frontend/src/api/schema.ts` with the Go change.
- Routes are mounted only by `mountMobile` in `backend/internal/httpd/router.go` (loopback router) and must stay 1:1 with `mobileOperations()` in `specgen/build.go` — the parity test enforces it.
- Every new named DTO type gets a `schemaNames` entry (`"Controllers<Type>": "<Type>"`).
- Tests: Go table tests with `httptest` fakes; no network. Fake binaries are `#!/bin/sh` scripts (see `fake_provider_test.go`; they `t.Skip` on Windows).

---

## File map

| File | Responsibility |
|---|---|
| `backend/internal/tunnel/manager.go` | start-timeout → classify → fallback; `Status.LastProvider/FallbackReason`; `controlPort` tracking; `Logs()` |
| `backend/internal/tunnel/ngrok.go` | `ClassifyFailure` network cases; `--url` for the stable domain |
| `backend/internal/tunnel/ngrok_config.go` | `removeNgrokAuthtoken` |
| `backend/internal/tunnel/authtoken.go` | `RemoveAuthtoken`, `SetNgrokDomain`, `NgrokDomain` |
| `backend/internal/tunnel/binary.go` | `Store.Resolve` |
| `backend/internal/tunnel/ngrok_info.go` (new) | `NgrokInfo` snapshot: credential, agent, session, logs |
| `backend/internal/tunnel/ngrok_apikey.go` (new) | API-key file, `ngrokAPI` client, account aggregation, credential mint/revoke |
| `backend/internal/tunnel/ngrok_diagnose.go` (new) | diagnostics runner + `ngrok diagnose` parser + CRL probe |
| `backend/internal/httpd/controllers/dto.go` | new DTOs |
| `backend/internal/httpd/controllers/mobile.go` | `BridgeService` adapters, `TunnelController` interface growth |
| `backend/internal/httpd/controllers/mobile_ngrok.go` (new) | `MobileController` handlers |
| `backend/internal/httpd/router.go` | routes |
| `backend/internal/httpd/apispec/specgen/build.go` | operations + `schemaNames` |
| `backend/internal/mobilebridge/config.go` | `NgrokDomain` field |
| `backend/internal/daemon/daemon.go` | wire `NgrokDomain` from config into the manager at boot |

---

### Task 1: Start-timeout falls back and carries the provider's message

**Files:**
- Modify: `backend/internal/tunnel/manager.go` (`awaitURL` ~300-318, `runAwaitURL` ~284-297, `handleProviderRefusal` ~596, `Enable`, `Disable`, `Status` struct in `status.go`)
- Modify: `backend/internal/tunnel/status.go`
- Test: `backend/internal/tunnel/manager_fallback_test.go`

**Interfaces:**
- Produces: `Status.LastProvider string`, `Status.FallbackReason string`; unexported `startTimeoutError{provider string}`.

- [ ] **Step 1: Write the failing tests**

Append to `manager_fallback_test.go`:

```go
func newTimeoutFallbackManager(t *testing.T, first, second *fakeProvider, clock *fakeClock) (*Manager, *perProviderStore) {
	t.Helper()
	store := &perProviderStore{paths: map[string]string{
		first.name:  first.binary,
		second.name: second.binary,
	}, launches: map[string]int{}}
	m := New(Deps{
		Dir:       t.TempDir(),
		Providers: []Provider{first, second},
		Binaries:  store,
		Now:       clock.Now,
		Sleep: func(ctx context.Context, _ time.Duration) error {
			clock.advance(startTimeout / 4)
			return yieldSleep(ctx)
		},
		ReservePort: func() (int, error) { return 45998, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m, store
}

const crlLoggingScript = "#!/bin/sh\necho '{\"err\":\"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large\",\"lvl\":\"eror\",\"msg\":\"failed to reconnect session\"}'\nwhile true; do sleep 1; done\n"

func TestStartTimeoutSurfacesTheProviderLogAndFallsBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", crlLoggingScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{Class: FailureNetwork, Message: "ngrok could not fetch its certificate revocation list"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURL("https://fallback.trycloudflare.com")

	m, store := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Fatalf("provider = %q, want cloudflared after ngrok never published", status.Provider)
	}
	if status.LastProvider != "ngrok" {
		t.Errorf("LastProvider = %q, want ngrok", status.LastProvider)
	}
	if status.FallbackReason != "ngrok could not fetch its certificate revocation list" {
		t.Errorf("FallbackReason = %q, want the classified log message", status.FallbackReason)
	}
	if status.NeedsAuthtoken {
		t.Error("a network failure is not an authtoken problem")
	}
	if store.launchCount("ngrok") != 1 {
		t.Errorf("ngrok launched %d times, want exactly one attempt before fallback", store.launchCount("ngrok"))
	}
}

func TestStartTimeoutWithoutAnyLogStillFallsBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", sleepForeverScript)
	ngrok.setURLErr(ErrNoURLYet)
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m, _ := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Fatalf("provider = %q, want cloudflared", status.Provider)
	}
	want := "tunnel: ngrok published no url within 1m0s"
	if status.FallbackReason != want {
		t.Errorf("FallbackReason = %q, want %q", status.FallbackReason, want)
	}
}

func TestStartTimeoutOnTheLastProviderFailsTerminally(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", sleepForeverScript)
	ngrok.setURLErr(ErrNoURLYet)
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURLErr(ErrNoURLYet)

	m, _ := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateFailed)
	if status.Error != "tunnel: cloudflared published no url within 1m0s" {
		t.Errorf("Error = %q, want the last provider's timeout", status.Error)
	}
	cloudflared.setURLErr(nil)
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable after terminal failure: %v", err)
	}
	if got := waitForState(t, m, StateLive); got.LastProvider != "" || got.FallbackReason != "" {
		t.Errorf("a fresh Enable must clear LastProvider/FallbackReason, got %q / %q", got.LastProvider, got.FallbackReason)
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run 'TestStartTimeout' -v`
Expected: compile error `status.LastProvider undefined` (and the first test would otherwise hang on `failed`).

- [ ] **Step 3: Add the fields and the typed error**

`status.go`, inside `Status`:

```go
	LastProvider   string
	FallbackReason string
```

`manager.go`, near the constants:

```go
type startTimeoutError struct{ provider string }

func (e *startTimeoutError) Error() string {
	return fmt.Sprintf("tunnel: %s published no url within %s", e.provider, startTimeout)
}
```

Replace the last line of `awaitURL`:

```go
	return &startTimeoutError{provider: provider.Name()}
```

- [ ] **Step 4: Route the timeout through the refusal path**

Replace `runAwaitURL`:

```go
func (m *Manager) runAwaitURL(ctx context.Context, provider Provider, controlPort int, cancel context.CancelFunc, done, awaitDone, liveConfirmed chan struct{}) {
	defer close(awaitDone)
	err := m.awaitURL(ctx, provider, controlPort)
	if err == nil {
		close(liveConfirmed)
		return
	}
	if ctx.Err() != nil {
		return
	}
	var timeout *startTimeoutError
	if !errors.As(err, &timeout) {
		m.mu.Lock()
		m.status = Status{State: StateFailed, Error: err.Error(), NeedsAuthtoken: m.status.NeedsAuthtoken}
		m.retryableLocked()
		m.mu.Unlock()
		cancel()
		<-done
		return
	}
	cancel()
	<-done
	m.mu.Lock()
	logs := m.logs
	m.mu.Unlock()
	failure := provider.ClassifyFailure(logs.Lines())
	if failure.Message == "" {
		failure.Message = err.Error()
	}
	class := failure.Class
	if class == FailureUnknown || class == FailureNetwork {
		class = FailureRefused
	}
	m.handleProviderRefusal(context.Background(), provider, failure, class)
}
```

In `handleProviderRefusal`, after `m.lastFailureProvider = provider.Name()`:

```go
	m.status.LastProvider = provider.Name()
	m.status.FallbackReason = failure.Message
```

In `Enable`, the initial `m.status = Status{State: StateStarting}` already zeroes both fields. In `launch`, the `m.status = Status{...}` literal must carry them over — add `LastProvider: m.status.LastProvider, FallbackReason: m.status.FallbackReason,`. `Disable` already resets to `Status{State: StateOff}`.

In `failTerminally`, when `remaining == 0` the terminal `Error` must be the *last* provider's message: `handleProviderRefusal` already set `m.status.Error = failure.Message` before calling `failTerminally("")`, so nothing more is needed.

- [ ] **Step 5: Run the whole package**

Run: `cd backend && go test ./internal/tunnel/ -v -run 'Fallback|StartTimeout|Reconnect|Stale'` then `go test -race ./internal/tunnel/...`
Expected: all PASS, including `TestManagerStaleFirstAttemptURLTimeoutDoesNotKillARecoveredTunnel` (the stale-attempt guard is the `ctx.Err() != nil` early return, untouched).

- [ ] **Step 6: Commit**

```bash
git add backend/internal/tunnel/manager.go backend/internal/tunnel/status.go backend/internal/tunnel/manager_fallback_test.go
git commit -m "fix(tunnel): fall back when a provider never publishes and surface its log message"
```

---

### Task 2: ngrok classifies CRL / auth-request failures as network

**Files:**
- Modify: `backend/internal/tunnel/ngrok.go` (`ClassifyFailure`)
- Test: `backend/internal/tunnel/ngrok_test.go`

**Interfaces:**
- Produces: exported const `NgrokCRLMessage = "ngrok could not fetch its certificate revocation list (plain HTTP is being intercepted on this network)"`.

- [ ] **Step 1: Failing tests**

```go
func TestNgrokClassifyFailureCRLIsNetwork(t *testing.T) {
	lines := []string{
		`{"err":"<nil>","lvl":"info","msg":"open config file"}`,
		`{"err":"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large","lvl":"eror","msg":"failed to reconnect session"}`,
	}
	got := NgrokProvider(NgrokConfig{}).ClassifyFailure(lines)
	if got.Class != FailureNetwork {
		t.Fatalf("class = %v, want FailureNetwork", got.Class)
	}
	if got.Message != NgrokCRLMessage {
		t.Errorf("message = %q", got.Message)
	}
}

func TestNgrokClassifyFailureAuthRequestIsNetwork(t *testing.T) {
	lines := []string{`{"err":"failed to send authentication request: dial tcp: i/o timeout","lvl":"eror","msg":"failed to reconnect session"}`}
	got := NgrokProvider(NgrokConfig{}).ClassifyFailure(lines)
	if got.Class != FailureNetwork {
		t.Fatalf("class = %v, want FailureNetwork", got.Class)
	}
	if got.Message != "failed to send authentication request: dial tcp: i/o timeout" {
		t.Errorf("message = %q, want the tidied error verbatim", got.Message)
	}
}
```

- [ ] **Step 2: Run to verify failure** — `go test ./internal/tunnel/ -run TestNgrokClassifyFailure -v` → FAIL (`NgrokCRLMessage` undefined).

- [ ] **Step 3: Implement**

In `ngrok.go`:

```go
const NgrokCRLMessage = "ngrok could not fetch its certificate revocation list (plain HTTP is being intercepted on this network)"
```

Inside the loop of `ClassifyFailure`, after the `ERR_NGROK_4018` check:

```go
		if strings.Contains(rec.Err, "failed to fetch CRL") {
			return Failure{Class: FailureNetwork, Message: NgrokCRLMessage}
		}
		if strings.Contains(rec.Err, "failed to send authentication request") {
			return Failure{Class: FailureNetwork, Message: tidyProviderError(rec.Err)}
		}
```

- [ ] **Step 4: Run** — `go test ./internal/tunnel/ -run TestNgrok -v` → PASS (including the existing `Refused`/`Unknown` cases).

- [ ] **Step 5: Commit** — `git commit -am "feat(tunnel): classify ngrok CRL and auth-request failures as network"`

---

### Task 3: Manager exposes the control port and the log ring

**Files:**
- Modify: `backend/internal/tunnel/manager.go` (`Manager` struct, `launch`, `supervise` spawn path, `Disable`)
- Test: `backend/internal/tunnel/manager_test.go`

**Interfaces:**
- Produces: `func (m *Manager) ControlPort() int` (0 when no child), `func (m *Manager) Logs() []string` (empty slice when never launched).

- [ ] **Step 1: Failing test**

```go
func TestManagerExposesControlPortAndLogsWhileRunning(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\necho '{\"lvl\":\"info\",\"msg\":\"hello\"}'\nwhile true; do sleep 1; done\n")
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 46301, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()
	if m.ControlPort() != 0 || len(m.Logs()) != 0 {
		t.Fatal("no child yet: control port must be 0 and logs empty")
	}
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)
	if got := m.ControlPort(); got != 46301 {
		t.Errorf("ControlPort = %d, want 46301", got)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) && len(m.Logs()) == 0 {
		time.Sleep(5 * time.Millisecond)
	}
	if lines := m.Logs(); len(lines) != 1 || !strings.Contains(lines[0], "hello") {
		t.Errorf("Logs = %q, want the child's stdout line", lines)
	}
	_ = m.Disable(context.Background())
	if m.ControlPort() != 0 {
		t.Error("ControlPort must reset to 0 after Disable")
	}
	if len(m.Logs()) != 1 {
		t.Error("Logs must survive Disable until the next Enable")
	}
}
```

Add `"strings"` to the test file's imports.

- [ ] **Step 2: Run** → compile failure (`ControlPort` undefined).

- [ ] **Step 3: Implement**

Add `controlPort int` to the `Manager` struct. In `launch`, inside the locked block that sets `m.cmd, m.cancel, ...`, add `m.controlPort = controlPort`. In `supervise`, where `m.cmd = current; m.logs = currentLogs` is assigned after a respawn, add `m.controlPort = currentPort`. In `Disable`, in the first locked block, add `m.controlPort = 0`. Then:

```go
func (m *Manager) ControlPort() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.controlPort
}

func (m *Manager) Logs() []string {
	m.mu.Lock()
	logs := m.logs
	m.mu.Unlock()
	if logs == nil {
		return []string{}
	}
	return logs.Lines()
}
```

- [ ] **Step 4: Run** — `go test -race ./internal/tunnel/...` → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(tunnel): expose control port and log ring"`

---

### Task 4: Authtoken removal and the stable domain

**Files:**
- Modify: `backend/internal/tunnel/ngrok_config.go`, `backend/internal/tunnel/authtoken.go`, `backend/internal/tunnel/ngrok.go` (`Args`), `backend/internal/tunnel/manager.go` (`Manager` struct)
- Test: `backend/internal/tunnel/authtoken_test.go`, `backend/internal/tunnel/ngrok_test.go`

**Interfaces:**
- Produces: `func (m *Manager) RemoveAuthtoken() error`; `func (m *Manager) SetNgrokDomain(domain string)`; `func (m *Manager) NgrokDomain() string`; `NgrokConfig.Domain func() string` (provider reads the domain at `Args` time); `removeNgrokAuthtoken(existing string) string`.

- [ ] **Step 1: Failing tests**

`ngrok_test.go`:

```go
func TestRemoveNgrokAuthtokenKeepsWebAddrAndVersion(t *testing.T) {
	in := "version: \"3\"\nagent:\n    authtoken: abc123\n    web_addr: 127.0.0.1:4040\n"
	got := removeNgrokAuthtoken(in)
	want := "version: \"3\"\nagent:\n    web_addr: 127.0.0.1:4040\n"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestNgrokArgsAppendTheStableDomain(t *testing.T) {
	p := NgrokProvider(NgrokConfig{Domain: func() string { return "phone.example.ngrok.app" }})
	args := p.Args(3011, 4040)
	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "--url=https://phone.example.ngrok.app") {
		t.Fatalf("args = %v, want --url with the domain", args)
	}
}

func TestNgrokArgsOmitTheURLFlagWithoutADomain(t *testing.T) {
	args := NgrokProvider(NgrokConfig{}).Args(3011, 4040)
	if strings.Contains(strings.Join(args, " "), "--url") {
		t.Fatalf("args = %v, want no --url", args)
	}
}
```

`authtoken_test.go` (reuse that file's existing manager constructor helper; if it builds the manager inline, copy that `New(Deps{...})` block):

```go
func TestRemoveAuthtokenDropsOnlyOperatorsToken(t *testing.T) {
	dir := t.TempDir()
	own := filepath.Join(dir, "ngrok.yml")
	if err := os.WriteFile(own, []byte("version: \"3\"\nagent:\n    authtoken: secret\n    web_addr: 127.0.0.1:1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := New(Deps{Dir: dir, Providers: []Provider{NgrokProvider(NgrokConfig{OwnConfigPath: own})}, Binaries: fakeStore{}, Now: time.Now})
	if !m.HasAuthtoken() {
		t.Fatal("precondition: token present")
	}
	if err := m.RemoveAuthtoken(); err != nil {
		t.Fatalf("RemoveAuthtoken: %v", err)
	}
	if m.HasAuthtoken() {
		t.Error("token must be gone")
	}
	body, _ := os.ReadFile(own)
	if !strings.Contains(string(body), "web_addr: 127.0.0.1:1") {
		t.Errorf("web_addr must survive, got %q", body)
	}
}

func TestSetNgrokDomainIsReadBack(t *testing.T) {
	m := New(Deps{Dir: t.TempDir(), Binaries: fakeStore{}, Now: time.Now})
	m.SetNgrokDomain("a.ngrok.app")
	if m.NgrokDomain() != "a.ngrok.app" {
		t.Fatal("domain not stored")
	}
}
```

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement**

`ngrok_config.go`:

```go
func removeNgrokAuthtoken(existing string) string {
	var out []string
	for _, raw := range strings.Split(existing, "\n") {
		if strings.HasPrefix(strings.TrimSpace(raw), "authtoken:") {
			continue
		}
		out = append(out, raw)
	}
	return strings.Join(out, "\n")
}
```

`authtoken.go`:

```go
func (m *Manager) RemoveAuthtoken() error {
	path := ngrokConfigPath(m.dir)
	body, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(removeNgrokAuthtoken(string(body))), 0o600); err != nil {
		return err
	}
	m.mu.Lock()
	m.status.NeedsAuthtoken = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) SetNgrokDomain(domain string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ngrokDomain = strings.TrimSpace(domain)
}

func (m *Manager) NgrokDomain() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.ngrokDomain
}
```

Add `ngrokDomain string` to `Manager`. `ngrok.go`:

```go
type NgrokConfig struct {
	UserConfigPath string
	OwnConfigPath  string
	Domain         func() string
}
```

In `Args`, before the `--log=stdout` append:

```go
	if p.cfg.Domain != nil {
		if domain := p.cfg.Domain(); domain != "" {
			args = append(args, "--url=https://"+domain)
		}
	}
```

`daemon.go` (Task 10 wires the value; here only the closure): construct the manager in two steps so the provider can read back from it:

```go
	var tunnelMgr *tunnel.Manager
	tunnelMgr = tunnel.New(tunnel.Deps{
		...
		Providers: []tunnel.Provider{
			tunnel.NgrokProvider(tunnel.NgrokConfig{
				UserConfigPath: tunnel.DefaultNgrokConfigPath(),
				OwnConfigPath:  filepath.Join(cfg.DataDir, "mobile", "ngrok.yml"),
				Domain:         func() string { return tunnelMgr.NgrokDomain() },
			}),
```

- [ ] **Step 4: Run** — `go test ./internal/tunnel/... ./internal/daemon/...` → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(tunnel): remove Operator's ngrok authtoken; stable domain via --url"`

---

### Task 5: `Store.Resolve` and the `NgrokInfo` snapshot

**Files:**
- Modify: `backend/internal/tunnel/binary.go`
- Create: `backend/internal/tunnel/ngrok_info.go`
- Test: `backend/internal/tunnel/binary_test.go`, `backend/internal/tunnel/ngrok_info_test.go`

**Interfaces:**
- Produces:

```go
func (s *Store) Resolve(spec BinarySpec) (path string, source string, ok bool) // source: "path" | "managed"

type NgrokCredential struct{ Present bool; Source string; SystemConfigPath string; Suffix string }
type NgrokAgent struct{ BinaryPath, Source, Version string; UpdateAvailable bool }
type NgrokSession struct{ Status, Region, Latency, PublicURL string; Connections, HTTPRequests int }
type NgrokLogLine struct{ Time, Level, Message string }
type NgrokInfo struct {
	Credential NgrokCredential
	Agent      NgrokAgent
	Session    NgrokSession
	Domain     string
	APIKey     bool
	Logs       []NgrokLogLine
}
func (m *Manager) NgrokInfo(ctx context.Context) NgrokInfo
func parseNgrokLogLines(lines []string, secrets ...string) []NgrokLogLine
```

- [ ] **Step 1: Failing tests**

`binary_test.go` (reuse that file's `newStore`-style helper if present; otherwise construct `NewStore(StoreDeps{Dir: t.TempDir(), LookPath: ..., Version: ...})`):

```go
func TestResolvePrefersPathThenManagedCacheWithoutDownloading(t *testing.T) {
	dir := t.TempDir()
	spec := BinarySpec{Name: "ngrok", Version: "stable", MinVersion: "3.0.0"}
	s := NewStore(StoreDeps{
		Dir:      dir,
		LookPath: func(string) (string, error) { return "/opt/homebrew/bin/ngrok", nil },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})
	if path, source, ok := s.Resolve(spec); !ok || source != "path" || path != "/opt/homebrew/bin/ngrok" {
		t.Fatalf("Resolve = %q %q %v", path, source, ok)
	}
	s = NewStore(StoreDeps{Dir: dir, LookPath: func(string) (string, error) { return "", errors.New("nope") }})
	if _, _, ok := s.Resolve(spec); ok {
		t.Fatal("nothing cached: must report not resolved, never download")
	}
	cached := filepath.Join(dir, "ngrok-stable")
	if err := os.WriteFile(cached, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if path, source, ok := s.Resolve(spec); !ok || source != "managed" || path != cached {
		t.Fatalf("Resolve = %q %q %v", path, source, ok)
	}
}
```

`ngrok_info_test.go`:

```go
package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseNgrokLogLinesRedactsSecretsAndKeepsPlainLines(t *testing.T) {
	lines := []string{
		`{"t":"2026-09-19T20:05:59.864169+03:00","lvl":"eror","msg":"failed to reconnect session","err":"bad token sekret123"}`,
		`{"t":"2026-09-19T20:06:00.1+03:00","lvl":"info","msg":"open config file","err":"<nil>"}`,
		`plain text line`,
	}
	got := parseNgrokLogLines(lines, "sekret123")
	if len(got) != 3 {
		t.Fatalf("len = %d", len(got))
	}
	if got[0].Level != "eror" || got[0].Message != "failed to reconnect session: bad token [redacted]" {
		t.Errorf("line 0 = %+v", got[0])
	}
	if got[1].Message != "open config file" {
		t.Errorf("line 1 must drop a nil err, got %+v", got[1])
	}
	if got[2].Level != "" || got[2].Message != "plain text line" || got[2].Time != "" {
		t.Errorf("line 2 = %+v", got[2])
	}
}

func TestNgrokInfoReportsCredentialSourceAndSuffix(t *testing.T) {
	dir := t.TempDir()
	system := filepath.Join(dir, "system.yml")
	if err := os.WriteFile(system, []byte("version: \"3\"\nagent:\n    authtoken: systok_abcd\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := New(Deps{Dir: dir, Binaries: fakeStore{}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{UserConfigPath: system, OwnConfigPath: filepath.Join(dir, "ngrok.yml")}),
	}})
	info := m.NgrokInfo(context.Background())
	if !info.Credential.Present || info.Credential.Source != "system" || info.Credential.Suffix != "abcd" {
		t.Fatalf("credential = %+v", info.Credential)
	}
	if info.Credential.SystemConfigPath != system {
		t.Errorf("SystemConfigPath = %q", info.Credential.SystemConfigPath)
	}
	if err := os.WriteFile(filepath.Join(dir, "ngrok.yml"), []byte("version: \"3\"\nagent:\n    authtoken: optok_wxyz\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	info = m.NgrokInfo(context.Background())
	if info.Credential.Source != "operator" || info.Credential.Suffix != "wxyz" {
		t.Fatalf("operator token must win: %+v", info.Credential)
	}
}

func TestNgrokInfoReadsTheControlAPI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/status":
			_, _ = w.Write([]byte(`{"status":"online","agent_version":"3.39.6","session":{"legs":[{"region":"eu","latency":61600000}]}}`))
		case "/api/tunnels":
			_, _ = w.Write([]byte(`{"tunnels":[{"public_url":"https://x.ngrok.app","metrics":{"conns":{"count":4},"http":{"count":9}}}]}`))
		default:
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()
	port := controlPortOf(t, srv.URL)
	got := readNgrokSession(context.Background(), port)
	if got.Status != "online" || got.Region != "eu" || got.Latency != "62ms" || got.PublicURL != "https://x.ngrok.app" || got.Connections != 4 || got.HTTPRequests != 9 {
		t.Fatalf("session = %+v", got)
	}
}
```

`controlPortOf` parses the port out of `srv.URL` (`net.SplitHostPort` on the URL host, `strconv.Atoi`); add it to this test file. If `ngrok_test.go` already has an equivalent helper for `controlURL`, reuse that instead.

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement `Resolve`** in `binary.go`:

```go
func (s *Store) Resolve(spec BinarySpec) (string, string, bool) {
	if path, ok := s.fromPath(spec); ok {
		return path, "path", true
	}
	cached := s.cachedPath(spec)
	if _, err := os.Stat(cached); err == nil {
		return cached, "managed", true
	}
	return "", "", false
}
```

- [ ] **Step 4: Implement `ngrok_info.go`**

```go
package tunnel

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type NgrokCredential struct {
	Present          bool
	Source           string
	SystemConfigPath string
	Suffix           string
}

type NgrokAgent struct {
	BinaryPath      string
	Source          string
	Version         string
	UpdateAvailable bool
}

type NgrokSession struct {
	Status       string
	Region       string
	Latency      string
	PublicURL    string
	Connections  int
	HTTPRequests int
}

type NgrokLogLine struct {
	Time    string
	Level   string
	Message string
}

type NgrokInfo struct {
	Credential NgrokCredential
	Agent      NgrokAgent
	Session    NgrokSession
	Domain     string
	APIKey     bool
	Logs       []NgrokLogLine
}

type binaryResolver interface {
	Resolve(spec BinarySpec) (string, string, bool)
}

var authtokenLine = regexp.MustCompile(`(?m)^\s*authtoken:\s*(\S+)`)

func readAuthtoken(path string) string {
	if path == "" {
		return ""
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	match := authtokenLine.FindStringSubmatch(string(body))
	if match == nil {
		return ""
	}
	return strings.Trim(match[1], `"'`)
}

func tokenSuffix(token string) string {
	if len(token) <= 4 {
		return ""
	}
	return token[len(token)-4:]
}

func (m *Manager) ngrokConfig() (NgrokConfig, bool) {
	p, ok := m.providerNamed("ngrok").(ngrokProvider)
	if !ok {
		return NgrokConfig{}, false
	}
	return p.cfg, true
}

func (m *Manager) ngrokCredential() (NgrokCredential, string) {
	cfg, _ := m.ngrokConfig()
	cred := NgrokCredential{SystemConfigPath: cfg.UserConfigPath}
	if token := readAuthtoken(ngrokConfigPath(m.dir)); token != "" {
		cred.Present, cred.Source, cred.Suffix = true, "operator", tokenSuffix(token)
		return cred, token
	}
	if token := readAuthtoken(cfg.UserConfigPath); token != "" {
		cred.Present, cred.Source, cred.Suffix = true, "system", tokenSuffix(token)
		return cred, token
	}
	return cred, ""
}

func (m *Manager) ngrokAgent(lines []string) NgrokAgent {
	agent := NgrokAgent{}
	provider := m.providerNamed("ngrok")
	if provider == nil {
		return agent
	}
	if resolver, ok := m.binaries.(binaryResolver); ok {
		if path, source, ok := resolver.Resolve(provider.Binary()); ok {
			agent.BinaryPath, agent.Source = path, source
			out, err := exec.Command(path, "version").Output()
			if err == nil {
				agent.Version = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(string(out)), "ngrok version "))
			}
		}
	}
	for _, line := range lines {
		if strings.Contains(line, `"msg":"update available"`) {
			agent.UpdateAvailable = true
			break
		}
	}
	return agent
}

func readNgrokSession(ctx context.Context, controlPort int) NgrokSession {
	var session NgrokSession
	if controlPort == 0 {
		return session
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	var status struct {
		Status  string `json:"status"`
		Session struct {
			Legs []struct {
				Region  string      `json:"region"`
				Latency json.Number `json:"latency"`
			} `json:"legs"`
		} `json:"session"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/status"), &status); err != nil {
		return session
	}
	session.Status = status.Status
	if len(status.Session.Legs) > 0 {
		leg := status.Session.Legs[0]
		session.Region = leg.Region
		if ns, err := leg.Latency.Int64(); err == nil && ns > 0 {
			session.Latency = fmt.Sprintf("%dms", (ns+500000)/1000000)
		}
	}
	var tunnels struct {
		Tunnels []struct {
			PublicURL string `json:"public_url"`
			Metrics   struct {
				Conns struct{ Count int `json:"count"` } `json:"conns"`
				HTTP  struct{ Count int `json:"count"` } `json:"http"`
			} `json:"metrics"`
		} `json:"tunnels"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/tunnels"), &tunnels); err != nil {
		return session
	}
	for _, tun := range tunnels.Tunnels {
		if strings.HasPrefix(tun.PublicURL, "https://") {
			session.PublicURL = tun.PublicURL
			session.Connections = tun.Metrics.Conns.Count
			session.HTTPRequests = tun.Metrics.HTTP.Count
			break
		}
	}
	return session
}

func parseNgrokLogLines(lines []string, secrets ...string) []NgrokLogLine {
	out := make([]NgrokLogLine, 0, len(lines))
	for _, line := range lines {
		var rec struct {
			T   string `json:"t"`
			Lvl string `json:"lvl"`
			Msg string `json:"msg"`
			Err string `json:"err"`
		}
		entry := NgrokLogLine{Message: line}
		if json.Unmarshal([]byte(line), &rec) == nil && rec.Msg != "" {
			entry = NgrokLogLine{Time: rec.T, Level: rec.Lvl, Message: rec.Msg}
			if rec.Err != "" && rec.Err != "<nil>" {
				entry.Message += ": " + tidyProviderError(rec.Err)
			}
		}
		for _, secret := range secrets {
			if secret != "" {
				entry.Message = strings.ReplaceAll(entry.Message, secret, "[redacted]")
			}
		}
		out = append(out, entry)
	}
	return out
}

func (m *Manager) NgrokInfo(ctx context.Context) NgrokInfo {
	lines := m.Logs()
	cred, token := m.ngrokCredential()
	apiKey, _ := m.readAPIKey()
	return NgrokInfo{
		Credential: cred,
		Agent:      m.ngrokAgent(lines),
		Session:    readNgrokSession(ctx, m.ControlPort()),
		Domain:     m.NgrokDomain(),
		APIKey:     apiKey != "",
		Logs:       parseNgrokLogLines(lines, token, apiKey),
	}
}
```

`m.readAPIKey()` is defined in Task 6; for this task add a stub in `ngrok_apikey.go`:

```go
package tunnel

func (m *Manager) readAPIKey() (string, error) { return "", nil }
```

- [ ] **Step 5: Run** — `go test ./internal/tunnel/... -run 'Resolve|NgrokInfo|ParseNgrokLog' -v` → PASS.

- [ ] **Step 6: Commit** — `git add backend/internal/tunnel && git commit -m "feat(tunnel): ngrok info snapshot (credential source, agent, session, redacted logs)"`

---

### Task 6: API key storage and the ngrok API client

**Files:**
- Modify/Create: `backend/internal/tunnel/ngrok_apikey.go`
- Test: `backend/internal/tunnel/ngrok_apikey_test.go`

**Interfaces:**
- Produces:

```go
var ErrNgrokAPIUnauthorized = errors.New("tunnel: ngrok rejected the API key")

type NgrokAccountCredential struct{ ID, Description, CreatedAt string; IsOperator bool }
type NgrokAccountSession struct{ ID, Region, IP, AgentVersion, OS, StartedAt string; IsThisMachine bool }
type NgrokAccountEndpoint struct{ ID, PublicURL, Proto, CreatedAt string }
type NgrokReservedDomain struct{ ID, Domain string }
type NgrokAccount struct {
	Valid           bool
	Error           string
	Credentials     []NgrokAccountCredential
	Sessions        []NgrokAccountSession
	Endpoints       []NgrokAccountEndpoint
	ReservedDomains []NgrokReservedDomain
}

func (m *Manager) SetAPIKey(ctx context.Context, key string) error   // verifies, then stores 0600
func (m *Manager) RemoveAPIKey() error
func (m *Manager) NgrokAccount(ctx context.Context) NgrokAccount      // Valid:false + Error when no key/invalid
func (m *Manager) MintOperatorCredential(ctx context.Context) error   // POST /credentials, stores token, revokes previous Operator one
func (m *Manager) RevokeCredential(ctx context.Context, id string) error
func (m *Manager) SetStableDomain(ctx context.Context, domain string) error // "" clears; else must be reserved
func (m *Manager) readAPIKey() (string, error)
var ngrokAPIBase = "https://api.ngrok.com"   // tests override
func operatorCredentialDescription() string  // "Operator on <hostname>"
```

- [ ] **Step 1: Failing tests**

```go
package tunnel

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeNgrokAPI struct {
	t        *testing.T
	key      string
	created  []string
	deleted  []string
	server   *httptest.Server
}

func newFakeNgrokAPI(t *testing.T, key string) *fakeNgrokAPI {
	f := &fakeNgrokAPI{t: t, key: key}
	f.server = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.server.Close)
	prev := ngrokAPIBase
	ngrokAPIBase = f.server.URL
	t.Cleanup(func() { ngrokAPIBase = prev })
	return f
}

func (f *fakeNgrokAPI) handle(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Ngrok-Version") != "2" {
		w.WriteHeader(400)
		return
	}
	if r.Header.Get("Authorization") != "Bearer "+f.key {
		w.WriteHeader(401)
		_, _ = w.Write([]byte(`{"error_code":"ERR_NGROK_10005","msg":"Invalid API key"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	switch {
	case r.Method == "GET" && r.URL.Path == "/api_keys":
		_, _ = w.Write([]byte(`{"keys":[{"id":"ak_1","created_at":"2026-09-01T00:00:00Z"}]}`))
	case r.Method == "GET" && r.URL.Path == "/credentials":
		_, _ = w.Write([]byte(`{"credentials":[{"id":"cr_old","description":"` + operatorCredentialDescription() + `","created_at":"2026-08-01T00:00:00Z"},{"id":"cr_other","description":"laptop","created_at":"2026-07-01T00:00:00Z"}]}`))
	case r.Method == "POST" && r.URL.Path == "/credentials":
		var body struct{ Description string `json:"description"` }
		_ = json.NewDecoder(r.Body).Decode(&body)
		f.created = append(f.created, body.Description)
		_, _ = w.Write([]byte(`{"id":"cr_new","token":"2mintedtoken_zz99","description":"` + body.Description + `"}`))
	case r.Method == "DELETE" && strings.HasPrefix(r.URL.Path, "/credentials/"):
		f.deleted = append(f.deleted, strings.TrimPrefix(r.URL.Path, "/credentials/"))
		w.WriteHeader(204)
	case r.Method == "GET" && r.URL.Path == "/tunnel_sessions":
		_, _ = w.Write([]byte(`{"tunnel_sessions":[{"id":"ts_1","region":"eu","ip":"1.2.3.4","agent_version":"3.39.6","os":"darwin","started_at":"2026-09-19T17:00:00Z"}]}`))
	case r.Method == "GET" && r.URL.Path == "/endpoints":
		_, _ = w.Write([]byte(`{"endpoints":[{"id":"ep_1","public_url":"https://a.ngrok.app","proto":"https","created_at":"2026-09-19T17:00:01Z"}]}`))
	case r.Method == "GET" && r.URL.Path == "/reserved_domains":
		_, _ = w.Write([]byte(`{"reserved_domains":[{"id":"rd_1","domain":"phone.example.ngrok.app"}]}`))
	default:
		w.WriteHeader(404)
	}
}

func newAPIKeyManager(t *testing.T) (*Manager, string) {
	t.Helper()
	dir := t.TempDir()
	m := New(Deps{Dir: dir, Binaries: fakeStore{path: "/bin/sh"}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{OwnConfigPath: filepath.Join(dir, "ngrok.yml")}),
	}})
	return m, dir
}

func TestSetAPIKeyVerifiesBeforeStoring(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, dir := newAPIKeyManager(t)
	if err := m.SetAPIKey(context.Background(), "bad"); err == nil || !errors.Is(err, ErrNgrokAPIUnauthorized) {
		t.Fatalf("want ErrNgrokAPIUnauthorized, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "ngrok-api-key")); !os.IsNotExist(err) {
		t.Fatal("a rejected key must not be written")
	}
	if err := m.SetAPIKey(context.Background(), " good \n"); err != nil {
		t.Fatalf("SetAPIKey: %v", err)
	}
	info, err := os.Stat(filepath.Join(dir, "ngrok-api-key"))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("key file: %v mode %v", err, info.Mode())
	}
	if key, _ := m.readAPIKey(); key != "good" {
		t.Errorf("readAPIKey = %q", key)
	}
	if err := m.RemoveAPIKey(); err != nil {
		t.Fatal(err)
	}
	if key, _ := m.readAPIKey(); key != "" {
		t.Error("key must be gone")
	}
}

func TestNgrokAccountAggregatesTheFourLists(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, _ := newAPIKeyManager(t)
	if acc := m.NgrokAccount(context.Background()); acc.Valid || acc.Error == "" {
		t.Fatalf("without a key the account must be invalid with a reason: %+v", acc)
	}
	_ = m.SetAPIKey(context.Background(), "good")
	acc := m.NgrokAccount(context.Background())
	if !acc.Valid {
		t.Fatalf("account = %+v", acc)
	}
	if len(acc.Credentials) != 2 || !acc.Credentials[0].IsOperator || acc.Credentials[1].IsOperator {
		t.Errorf("credentials = %+v", acc.Credentials)
	}
	if len(acc.Sessions) != 1 || acc.Sessions[0].Region != "eu" {
		t.Errorf("sessions = %+v", acc.Sessions)
	}
	if len(acc.Endpoints) != 1 || acc.Endpoints[0].PublicURL != "https://a.ngrok.app" {
		t.Errorf("endpoints = %+v", acc.Endpoints)
	}
	if len(acc.ReservedDomains) != 1 || acc.ReservedDomains[0].Domain != "phone.example.ngrok.app" {
		t.Errorf("domains = %+v", acc.ReservedDomains)
	}
}

func TestMintOperatorCredentialStoresTheTokenAndRevokesThePreviousOne(t *testing.T) {
	api := newFakeNgrokAPI(t, "good")
	m, dir := newAPIKeyManager(t)
	_ = m.SetAPIKey(context.Background(), "good")
	if err := m.MintOperatorCredential(context.Background()); err != nil {
		t.Fatalf("Mint: %v", err)
	}
	if len(api.created) != 1 || api.created[0] != operatorCredentialDescription() {
		t.Errorf("created = %v", api.created)
	}
	if len(api.deleted) != 1 || api.deleted[0] != "cr_old" {
		t.Errorf("deleted = %v, want the previous Operator credential only", api.deleted)
	}
	body, _ := os.ReadFile(filepath.Join(dir, "ngrok.yml"))
	if !strings.Contains(string(body), "authtoken: 2mintedtoken_zz99") {
		t.Errorf("minted token must be stored, got %q", body)
	}
	if !m.HasAuthtoken() {
		t.Error("HasAuthtoken must be true after minting")
	}
}

func TestSetStableDomainRequiresAReservedDomain(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, _ := newAPIKeyManager(t)
	_ = m.SetAPIKey(context.Background(), "good")
	if err := m.SetStableDomain(context.Background(), "not-mine.ngrok.app"); err == nil {
		t.Fatal("an unreserved domain must be rejected")
	}
	if err := m.SetStableDomain(context.Background(), "phone.example.ngrok.app"); err != nil {
		t.Fatalf("SetStableDomain: %v", err)
	}
	if m.NgrokDomain() != "phone.example.ngrok.app" {
		t.Error("domain not applied")
	}
	if err := m.SetStableDomain(context.Background(), ""); err != nil || m.NgrokDomain() != "" {
		t.Errorf("clearing: err=%v domain=%q", err, m.NgrokDomain())
	}
}
```

Add `"errors"` to the imports. `MintOperatorCredential` must store the token **without** shelling out to a real ngrok binary: it writes the authtoken into `ngrokConfigPath(m.dir)` directly. Because `SetAuthtoken` shells out to `ngrok config add-authtoken`, extract the file write into a shared helper `writeNgrokAuthtoken(path, token string) error` that reads the existing file, drops any `authtoken:` line (`removeNgrokAuthtoken`), and merges `    authtoken: <token>` as the first line under `agent:` (use `mergeNgrokWebAddr`'s structure: parse `head`/`agentBody`, prepend the authtoken line to `agentBody`). `SetAuthtoken` keeps calling the ngrok binary (it validates the token format) — do not change it.

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement `ngrok_apikey.go`** (replace the Task 5 stub):

```go
package tunnel

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var ErrNgrokAPIUnauthorized = errors.New("tunnel: ngrok rejected the API key")

var ngrokAPIBase = "https://api.ngrok.com"

const ngrokAPITimeout = 10 * time.Second

type NgrokAccountCredential struct {
	ID          string
	Description string
	CreatedAt   string
	IsOperator  bool
}

type NgrokAccountSession struct {
	ID            string
	Region        string
	IP            string
	AgentVersion  string
	OS            string
	StartedAt     string
	IsThisMachine bool
}

type NgrokAccountEndpoint struct {
	ID        string
	PublicURL string
	Proto     string
	CreatedAt string
}

type NgrokReservedDomain struct {
	ID     string
	Domain string
}

type NgrokAccount struct {
	Valid           bool
	Error           string
	Credentials     []NgrokAccountCredential
	Sessions        []NgrokAccountSession
	Endpoints       []NgrokAccountEndpoint
	ReservedDomains []NgrokReservedDomain
}

func ngrokAPIKeyPath(dir string) string { return filepath.Join(dir, "ngrok-api-key") }

func (m *Manager) readAPIKey() (string, error) {
	body, err := os.ReadFile(ngrokAPIKeyPath(m.dir))
	if os.IsNotExist(err) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(body)), nil
}

func operatorCredentialDescription() string {
	host, err := os.Hostname()
	if err != nil || host == "" {
		host = "this machine"
	}
	return "Operator on " + host
}

type ngrokAPI struct {
	key    string
	client *http.Client
}

func (a ngrokAPI) do(ctx context.Context, method, path string, body any, out any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}
	req, err := http.NewRequestWithContext(ctx, method, ngrokAPIBase+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+a.key)
	req.Header.Set("Ngrok-Version", "2")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := a.client.Do(req)
	if err != nil {
		return fmt.Errorf("tunnel: ngrok api: %w", err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode == http.StatusUnauthorized || res.StatusCode == http.StatusForbidden {
		return ErrNgrokAPIUnauthorized
	}
	if res.StatusCode < 200 || res.StatusCode > 299 {
		var apiErr struct {
			Msg string `json:"msg"`
		}
		_ = json.Unmarshal(raw, &apiErr)
		if apiErr.Msg == "" {
			apiErr.Msg = fmt.Sprintf("status %d", res.StatusCode)
		}
		return fmt.Errorf("tunnel: ngrok api %s %s: %s", method, path, redact(apiErr.Msg, a.key))
	}
	if out != nil && len(raw) > 0 {
		return json.Unmarshal(raw, out)
	}
	return nil
}

func (m *Manager) api() (ngrokAPI, error) {
	key, err := m.readAPIKey()
	if err != nil {
		return ngrokAPI{}, err
	}
	if key == "" {
		return ngrokAPI{}, errors.New("tunnel: no ngrok API key is stored")
	}
	return ngrokAPI{key: key, client: &http.Client{Timeout: ngrokAPITimeout}}, nil
}

func (m *Manager) SetAPIKey(ctx context.Context, key string) error {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" {
		return errors.New("tunnel: API key must not be empty")
	}
	probe := ngrokAPI{key: trimmed, client: &http.Client{Timeout: ngrokAPITimeout}}
	if err := probe.do(ctx, http.MethodGet, "/api_keys", nil, nil); err != nil {
		return err
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	return os.WriteFile(ngrokAPIKeyPath(m.dir), []byte(trimmed+"\n"), 0o600)
}

func (m *Manager) RemoveAPIKey() error {
	err := os.Remove(ngrokAPIKeyPath(m.dir))
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func (m *Manager) NgrokAccount(ctx context.Context) NgrokAccount {
	api, err := m.api()
	if err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	ctx, cancel := context.WithTimeout(ctx, 2*ngrokAPITimeout)
	defer cancel()

	var creds struct {
		Credentials []struct {
			ID          string `json:"id"`
			Description string `json:"description"`
			CreatedAt   string `json:"created_at"`
		} `json:"credentials"`
	}
	if err := api.do(ctx, http.MethodGet, "/credentials", nil, &creds); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var sessions struct {
		Sessions []struct {
			ID           string `json:"id"`
			Region       string `json:"region"`
			IP           string `json:"ip"`
			AgentVersion string `json:"agent_version"`
			OS           string `json:"os"`
			StartedAt    string `json:"started_at"`
		} `json:"tunnel_sessions"`
	}
	if err := api.do(ctx, http.MethodGet, "/tunnel_sessions", nil, &sessions); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var endpoints struct {
		Endpoints []struct {
			ID        string `json:"id"`
			PublicURL string `json:"public_url"`
			Proto     string `json:"proto"`
			CreatedAt string `json:"created_at"`
		} `json:"endpoints"`
	}
	if err := api.do(ctx, http.MethodGet, "/endpoints", nil, &endpoints); err != nil {
		return NgrokAccount{Error: err.Error()}
	}
	var domains struct {
		Domains []struct {
			ID     string `json:"id"`
			Domain string `json:"domain"`
		} `json:"reserved_domains"`
	}
	if err := api.do(ctx, http.MethodGet, "/reserved_domains", nil, &domains); err != nil {
		return NgrokAccount{Error: err.Error()}
	}

	ownURL := m.Status().URL
	operator := operatorCredentialDescription()
	acc := NgrokAccount{Valid: true}
	for _, c := range creds.Credentials {
		acc.Credentials = append(acc.Credentials, NgrokAccountCredential{ID: c.ID, Description: c.Description, CreatedAt: c.CreatedAt, IsOperator: c.Description == operator})
	}
	for _, s := range sessions.Sessions {
		acc.Sessions = append(acc.Sessions, NgrokAccountSession{ID: s.ID, Region: s.Region, IP: s.IP, AgentVersion: s.AgentVersion, OS: s.OS, StartedAt: s.StartedAt})
	}
	for _, e := range endpoints.Endpoints {
		acc.Endpoints = append(acc.Endpoints, NgrokAccountEndpoint{ID: e.ID, PublicURL: e.PublicURL, Proto: e.Proto, CreatedAt: e.CreatedAt})
	}
	for _, d := range domains.Domains {
		acc.ReservedDomains = append(acc.ReservedDomains, NgrokReservedDomain{ID: d.ID, Domain: d.Domain})
	}
	if ownURL != "" && len(acc.Sessions) == 1 {
		acc.Sessions[0].IsThisMachine = true
	}
	return acc
}

func (m *Manager) MintOperatorCredential(ctx context.Context) error {
	api, err := m.api()
	if err != nil {
		return err
	}
	description := operatorCredentialDescription()
	var existing struct {
		Credentials []struct {
			ID          string `json:"id"`
			Description string `json:"description"`
		} `json:"credentials"`
	}
	if err := api.do(ctx, http.MethodGet, "/credentials", nil, &existing); err != nil {
		return err
	}
	var minted struct {
		ID    string `json:"id"`
		Token string `json:"token"`
	}
	if err := api.do(ctx, http.MethodPost, "/credentials", map[string]string{"description": description}, &minted); err != nil {
		return err
	}
	if minted.Token == "" {
		return errors.New("tunnel: ngrok returned a credential without a token")
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	if err := writeNgrokAuthtoken(ngrokConfigPath(m.dir), minted.Token); err != nil {
		return err
	}
	for _, c := range existing.Credentials {
		if c.Description == description && c.ID != minted.ID {
			_ = api.do(ctx, http.MethodDelete, "/credentials/"+c.ID, nil, nil)
		}
	}
	m.mu.Lock()
	delete(m.stickyFrom, "ngrok")
	m.status.NeedsAuthtoken = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) RevokeCredential(ctx context.Context, id string) error {
	api, err := m.api()
	if err != nil {
		return err
	}
	if strings.TrimSpace(id) == "" {
		return errors.New("tunnel: credential id must not be empty")
	}
	return api.do(ctx, http.MethodDelete, "/credentials/"+id, nil, nil)
}

func (m *Manager) SetStableDomain(ctx context.Context, domain string) error {
	trimmed := strings.TrimSpace(domain)
	if trimmed == "" {
		m.SetNgrokDomain("")
		return nil
	}
	acc := m.NgrokAccount(ctx)
	if !acc.Valid {
		return errors.New("tunnel: " + acc.Error)
	}
	for _, d := range acc.ReservedDomains {
		if d.Domain == trimmed {
			m.SetNgrokDomain(trimmed)
			return nil
		}
	}
	return fmt.Errorf("tunnel: %s is not a reserved domain on this ngrok account", trimmed)
}
```

`ngrok_config.go` gains:

```go
func writeNgrokAuthtoken(path, token string) error {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	body := removeNgrokAuthtoken(string(existing))
	if !strings.Contains(body, "\nagent:") && !strings.HasPrefix(body, "agent:") {
		body = mergeNgrokWebAddr(body, 0)
		body = strings.Replace(body, ngrokConfigIndent+"web_addr: 127.0.0.1:0\n", "", 1)
	}
	body = strings.Replace(body, "agent:\n", "agent:\n"+ngrokConfigIndent+"authtoken: "+token+"\n", 1)
	return os.WriteFile(path, []byte(body), 0o600)
}
```

Add a test in `ngrok_test.go` for `writeNgrokAuthtoken` on (a) an empty file → `version: "3"\nagent:\n    authtoken: T\n`; (b) an existing file with `web_addr` → the authtoken line is inserted directly under `agent:` and `web_addr` is kept; (c) an existing authtoken → replaced, not duplicated.

- [ ] **Step 4: Run** — `go test ./internal/tunnel/... -run 'APIKey|NgrokAccount|Mint|StableDomain|WriteNgrokAuthtoken' -v` → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(tunnel): ngrok API key storage, account view, one-click credential, stable domain"`

---

### Task 7: Diagnostics runner

**Files:**
- Create: `backend/internal/tunnel/ngrok_diagnose.go`
- Test: `backend/internal/tunnel/ngrok_diagnose_test.go`, fixture `backend/internal/tunnel/testdata/ngrok-diagnose-crl.txt`

**Interfaces:**
- Produces:

```go
type NgrokCheck struct{ Name string; OK bool; Detail string }
type NgrokDiagnosis struct{ Checks []NgrokCheck; Summary string }
func (m *Manager) NgrokDiagnose(ctx context.Context) NgrokDiagnosis
var ngrokCRLURL = "http://crl.ngrok-agent.com/ngrok.crl"      // tests override
var ngrokConnectAddr = "connect.ngrok-agent.com:443"          // tests override
func probeCRL(ctx context.Context, url string) NgrokCheck
func parseNgrokDiagnose(output string) []NgrokCheck
```

- [ ] **Step 1: Save the fixture** — `testdata/ngrok-diagnose-crl.txt` with exactly the output captured on 2026-09-19:

```
Testing ngrok connectivity...

Internet Connectivity
  Name Resolution                           [ OK ]
  TCP                                       [ OK ]
  TLS                                       [ OK ]
Localhost Connectivity
  Name Resolution                           [ OK ]
Ngrok Connectivity - Region: Auto (lowest latency)
  Name Resolution                           [ OK ]
  TCP                                       [ OK ]
  TLS                                    [ ERROR ]

Errors and warnings encountered during diagnostics:

* Diagnostics
  * Connectivity
    - Err: No tunnel servers could establish a TLS connection.
           (ERR_NGROK_8008)
    * connect.ngrok-agent.com (3.122.29.226:443)
      - Warn: Failed to establish TLS connection to connect.ngrok-agent.com
              with error: failed to fetch CRL. errors encountered: asn1:
              structure error: length too large. Possible Man-in-the Middle.
              (ERR_NGROK_8003)
      - Err: Failed to establish TLS connection to 3.122.29.226 with error:
             failed to fetch CRL. errors encountered: asn1: structure error:
             length too large. Possible Man-in-the Middle.
             (ERR_NGROK_8003)
```

- [ ] **Step 2: Failing tests**

```go
package tunnel

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestParseNgrokDiagnoseNamesGroupsAndAttachesTheFirstError(t *testing.T) {
	raw, err := os.ReadFile("testdata/ngrok-diagnose-crl.txt")
	if err != nil {
		t.Fatal(err)
	}
	checks := parseNgrokDiagnose(string(raw))
	if len(checks) != 7 {
		t.Fatalf("got %d checks: %+v", len(checks), checks)
	}
	if checks[0].Name != "Internet Connectivity: Name Resolution" || !checks[0].OK {
		t.Errorf("check 0 = %+v", checks[0])
	}
	last := checks[6]
	if last.Name != "Ngrok Connectivity: TLS" || last.OK {
		t.Errorf("check 6 = %+v", last)
	}
	if !strings.Contains(last.Detail, "No tunnel servers could establish a TLS connection. (ERR_NGROK_8008)") {
		t.Errorf("detail = %q", last.Detail)
	}
}

func derCRL(t *testing.T) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "t"}, NotBefore: time.Now(), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageCRLSign, IsCA: true, BasicConstraintsValid: true}
	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(certDER)
	crl, err := x509.CreateRevocationList(rand.Reader, &x509.RevocationList{Number: big.NewInt(1), ThisUpdate: time.Now(), NextUpdate: time.Now().Add(time.Hour)}, cert, key)
	if err != nil {
		t.Fatal(err)
	}
	return crl
}

func TestProbeCRL(t *testing.T) {
	cases := []struct {
		name    string
		handler http.HandlerFunc
		wantOK  bool
		wantIn  string
	}{
		{"der", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write(derCRL(t)) }, true, ""},
		{"middlebox", func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Via", "1.0 middlebox")
			w.Header().Set("Location", "http://megaplusredirection.tedata.net/VDSL-Redirection_100.html")
			w.WriteHeader(307)
		}, false, "intercepted on this network (redirected to megaplusredirection.tedata.net)"},
		{"pem", func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("-----BEGIN X509 CRL-----\nMIIB\n")) }, false, "not a DER certificate revocation list"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(tc.handler)
			defer srv.Close()
			got := probeCRL(context.Background(), srv.URL+"/ngrok.crl")
			if got.OK != tc.wantOK || !strings.Contains(got.Detail, tc.wantIn) {
				t.Fatalf("got %+v, want ok=%v detail containing %q", got, tc.wantOK, tc.wantIn)
			}
		})
	}
}

func TestNgrokDiagnoseSummaryIsTheFirstFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Via", "1.0 middlebox")
		w.WriteHeader(307)
	}))
	defer srv.Close()
	prevURL, prevAddr := ngrokCRLURL, ngrokConnectAddr
	ngrokCRLURL, ngrokConnectAddr = srv.URL+"/ngrok.crl", "127.0.0.1:1"
	defer func() { ngrokCRLURL, ngrokConnectAddr = prevURL, prevAddr }()

	fake := newFakeProvider(t, "ngrok", "#!/bin/sh\ncat \"$(dirname \"$0\")/../diagnose.txt\" 2>/dev/null || cat testdata/ngrok-diagnose-crl.txt\n")
	m := New(Deps{Dir: t.TempDir(), Binaries: fakeStore{path: fake.binary}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{OwnConfigPath: "/nonexistent/ngrok.yml"}),
	}})
	d := m.NgrokDiagnose(context.Background())
	if len(d.Checks) < 3 {
		t.Fatalf("checks = %+v", d.Checks)
	}
	if d.Checks[0].Name != "Binary" {
		t.Errorf("first check = %+v", d.Checks[0])
	}
	if !strings.Contains(d.Summary, "intercepted") {
		t.Errorf("summary = %q, want the CRL interception to lead", d.Summary)
	}
}
```

The fake binary in the last test ignores its args and prints the fixture (`ngrok version` output will be the fixture too — the Binary check only asserts the binary resolved and ran, so `OK` is true and the detail is the first output line).

- [ ] **Step 3: Run** → compile failures.

- [ ] **Step 4: Implement**

```go
package tunnel

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type NgrokCheck struct {
	Name   string
	OK     bool
	Detail string
}

type NgrokDiagnosis struct {
	Checks  []NgrokCheck
	Summary string
}

var (
	ngrokCRLURL      = "http://crl.ngrok-agent.com/ngrok.crl"
	ngrokConnectAddr = "connect.ngrok-agent.com:443"
)

const ngrokDiagnoseTimeout = 30 * time.Second

func probeCRL(ctx context.Context, target string) NgrokCheck {
	check := NgrokCheck{Name: "CRL over HTTP"}
	client := &http.Client{
		Timeout:       8 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, http.NoBody)
	if err != nil {
		check.Detail = err.Error()
		return check
	}
	res, err := client.Do(req)
	if err != nil {
		check.Detail = "could not reach " + target + ": " + err.Error()
		return check
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode >= 300 && res.StatusCode < 400 || strings.Contains(strings.ToLower(res.Header.Get("Via")), "middlebox") {
		host := "an unknown host"
		if loc, err := url.Parse(res.Header.Get("Location")); err == nil && loc.Host != "" {
			host = loc.Host
		}
		check.Detail = fmt.Sprintf("Plain HTTP is being intercepted on this network (redirected to %s). ngrok cannot authenticate until this is lifted; cloudflared is unaffected.", host)
		return check
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		check.Detail = err.Error()
		return check
	}
	if _, err := x509.ParseRevocationList(body); err != nil {
		check.Detail = fmt.Sprintf("%s returned %d bytes that are not a DER certificate revocation list (%v)", target, len(body), err)
		return check
	}
	check.OK = true
	check.Detail = fmt.Sprintf("fetched %d bytes from %s", len(body), target)
	return check
}

func probeControlPlane(ctx context.Context, addr string) NgrokCheck {
	check := NgrokCheck{Name: "Control plane TLS"}
	dialer := &tls.Dialer{NetDialer: &net.Dialer{Timeout: 8 * time.Second}}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		check.Detail = "TLS to " + addr + " failed: " + err.Error()
		return check
	}
	_ = conn.Close()
	check.OK = true
	check.Detail = "TLS handshake with " + addr + " succeeded"
	return check
}

var diagnoseRow = regexp.MustCompile(`^\s{2}(\S.*?)\s+\[\s*(OK|ERROR|WARN)\s*\]\s*$`)

func parseNgrokDiagnose(output string) []NgrokCheck {
	var checks []NgrokCheck
	group := ""
	firstErr := ""
	inErrors := false
	var errBuf []string
	flushErr := func() {
		if firstErr == "" && len(errBuf) > 0 {
			firstErr = strings.Join(strings.Fields(strings.Join(errBuf, " ")), " ")
		}
		errBuf = nil
	}
	for _, raw := range strings.Split(output, "\n") {
		line := strings.TrimRight(raw, "\r")
		if strings.HasPrefix(line, "Errors and warnings") {
			inErrors = true
			continue
		}
		if inErrors {
			trimmed := strings.TrimSpace(line)
			switch {
			case strings.HasPrefix(trimmed, "- Err:"):
				flushErr()
				errBuf = append(errBuf, strings.TrimPrefix(trimmed, "- Err:"))
			case len(errBuf) > 0 && !strings.HasPrefix(trimmed, "-") && !strings.HasPrefix(trimmed, "*") && trimmed != "":
				errBuf = append(errBuf, trimmed)
			default:
				flushErr()
			}
			continue
		}
		if m := diagnoseRow.FindStringSubmatch(line); m != nil {
			name := strings.TrimSpace(m[1])
			if group != "" {
				name = group + ": " + name
			}
			checks = append(checks, NgrokCheck{Name: name, OK: m[2] == "OK"})
			continue
		}
		if line != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "Testing") {
			group = line
			if i := strings.Index(group, " - "); i > 0 {
				group = group[:i]
			}
		}
	}
	flushErr()
	if firstErr != "" {
		for i := range checks {
			if !checks[i].OK {
				checks[i].Detail = firstErr
				break
			}
		}
	}
	return checks
}

func (m *Manager) NgrokDiagnose(ctx context.Context) NgrokDiagnosis {
	ctx, cancel := context.WithTimeout(ctx, ngrokDiagnoseTimeout)
	defer cancel()
	var checks []NgrokCheck

	binary := NgrokCheck{Name: "Binary"}
	var path string
	if provider := m.providerNamed("ngrok"); provider != nil {
		if resolver, ok := m.binaries.(binaryResolver); ok {
			if p, source, ok := resolver.Resolve(provider.Binary()); ok {
				path = p
				out, err := exec.CommandContext(ctx, p, "version").Output()
				if err == nil {
					binary.OK = true
					binary.Detail = fmt.Sprintf("%s (%s): %s", p, source, strings.TrimSpace(strings.SplitN(string(out), "\n", 2)[0]))
				} else {
					binary.Detail = fmt.Sprintf("%s failed to run: %v", p, err)
				}
			} else {
				binary.Detail = "ngrok is not installed and has not been downloaded yet; enabling the tunnel downloads it"
			}
		}
	}
	checks = append(checks, binary)
	checks = append(checks, probeCRL(ctx, ngrokCRLURL))
	checks = append(checks, probeControlPlane(ctx, ngrokConnectAddr))

	if path != "" {
		args := []string{"diagnose"}
		if p, ok := m.providerNamed("ngrok").(ngrokProvider); ok {
			for _, cfg := range p.configPaths() {
				args = append(args, "--config", cfg)
			}
		}
		out, _ := exec.CommandContext(ctx, path, args...).CombinedOutput()
		parsed := parseNgrokDiagnose(string(out))
		if len(parsed) == 0 {
			checks = append(checks, NgrokCheck{Name: "ngrok diagnose", Detail: strings.TrimSpace(string(out))})
		}
		checks = append(checks, parsed...)
	}

	cred, _ := m.ngrokCredential()
	credential := NgrokCheck{Name: "Credential", OK: cred.Present}
	switch cred.Source {
	case "operator":
		credential.Detail = "authtoken stored by Operator"
	case "system":
		credential.Detail = "using the system ngrok login at " + cred.SystemConfigPath
	default:
		credential.Detail = "no authtoken; ngrok will fall back to cloudflared"
	}
	checks = append(checks, credential)

	summary := "ngrok can connect from this machine."
	for _, c := range checks {
		if !c.OK {
			summary = c.Detail
			break
		}
	}
	return NgrokDiagnosis{Checks: checks, Summary: summary}
}
```

Remove unused imports (`errors`) if the compiler complains.

- [ ] **Step 5: Run** — `go test ./internal/tunnel/... -run 'Diagnose|ProbeCRL' -v` → PASS. Then the full package with `-race`.

- [ ] **Step 6: Commit** — `git add backend/internal/tunnel && git commit -m "feat(tunnel): ngrok diagnostics (CRL interception probe, control-plane TLS, ngrok diagnose parser)"`

---

### Task 8: Wire DTOs, `BridgeService` adapters and the `TunnelController` interface

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go` (after `MobileAuthtokenRequest`), `backend/internal/httpd/controllers/mobile.go`
- Test: `backend/internal/httpd/controllers/mobile_test.go` (extend `fakeBridge`; the `fakeTunnel` used by the BridgeService tests must implement the grown interface)

**Interfaces:**
- Produces (DTOs; every field tagged `json` + `description`):

```go
type MobileNgrokCredential struct{ Present bool; Source string; SystemConfigPath string; Suffix string }
type MobileNgrokAgent struct{ BinaryPath, Source, Version string; UpdateAvailable bool }
type MobileNgrokSession struct{ Status, Region, Latency, PublicURL string; Connections, HTTPRequests int }
type MobileNgrokLogLine struct{ Time, Level, Message string }
type MobileNgrokStatus struct{ Credential MobileNgrokCredential; Agent MobileNgrokAgent; Session MobileNgrokSession; Domain string; APIKey MobileNgrokAPIKey; Logs []MobileNgrokLogLine }
type MobileNgrokAPIKey struct{ Present bool }
type MobileNgrokAPIKeyRequest struct{ Key string }
type MobileNgrokAccountCredential / Session / Endpoint / ReservedDomain  (mirror tunnel.*)
type MobileNgrokAccount struct{ Valid bool; Error string; Credentials []…; Sessions []…; Endpoints []…; ReservedDomains []… }
type MobileNgrokDomainRequest struct{ Domain string }
type MobileNgrokCredentialIDParam struct{ ID string `path:"id"` }
type MobileNgrokCheck struct{ Name string; OK bool; Detail string }
type MobileNgrokDiagnosis struct{ Checks []MobileNgrokCheck; Summary string }
```

`MobileTunnelStatus` gains `LastProvider string `json:"lastProvider"`` and `FallbackReason string `json:"fallbackReason"``.

- `TunnelController` gains: `RemoveAuthtoken() error`, `NgrokInfo(ctx) tunnel.NgrokInfo`, `SetAPIKey(ctx, key) error`, `RemoveAPIKey() error`, `NgrokAccount(ctx) tunnel.NgrokAccount`, `MintOperatorCredential(ctx) error`, `RevokeCredential(ctx, id) error`, `SetStableDomain(ctx, domain) error`, `NgrokDiagnose(ctx) tunnel.NgrokDiagnosis`.
- `mobileBridge` gains: `RemoveAuthtoken() (MobileStatusResponse, error)`, `NgrokStatus(ctx) MobileNgrokStatus`, `SetAPIKey(ctx, key) (MobileNgrokAccount, error)`, `RemoveAPIKey() (MobileNgrokStatus, error)`, `NgrokAccount(ctx) MobileNgrokAccount`, `MintCredential(ctx) (MobileNgrokStatus, error)`, `RevokeCredential(ctx, id) (MobileNgrokAccount, error)`, `SetDomain(ctx, domain) (MobileNgrokStatus, error)`, `Diagnose(ctx) MobileNgrokDiagnosis`.

- [ ] **Step 1: Failing test** — in `mobile_test.go`, a BridgeService-level test using the file's existing fake tunnel (grow the fake with recording no-op implementations of the new methods returning canned `tunnel.NgrokInfo{Credential: tunnel.NgrokCredential{Present: true, Source: "operator", Suffix: "abcd"}}` etc.):

```go
func TestBridgeNgrokStatusMapsTheSnapshotAndTunnelStatusCarriesFallback(t *testing.T) {
	ft := &fakeTunnel{status: tunnel.Status{State: tunnel.StateLive, Provider: "cloudflared", URL: "https://x.trycloudflare.com", LastProvider: "ngrok", FallbackReason: tunnel.NgrokCRLMessage}}
	b := &BridgeService{LAN: &fakeLAN{}, ConfigPath: filepath.Join(t.TempDir(), "config.json"), DefaultPort: 3011, Tunnel: ft}
	st := b.Status()
	if st.Tunnel.LastProvider != "ngrok" || st.Tunnel.FallbackReason != tunnel.NgrokCRLMessage {
		t.Fatalf("tunnel = %+v", st.Tunnel)
	}
	ng := b.NgrokStatus(context.Background())
	if !ng.Credential.Present || ng.Credential.Source != "operator" || ng.Credential.Suffix != "abcd" {
		t.Fatalf("ngrok status = %+v", ng)
	}
	if ng.Logs == nil {
		t.Fatal("logs must serialise as [] not null")
	}
}

func TestBridgeSetDomainRestartsALiveNgrokTunnel(t *testing.T) {
	ft := &fakeTunnel{status: tunnel.Status{State: tunnel.StateLive, Provider: "ngrok", URL: "https://a.ngrok.app"}}
	b := &BridgeService{LAN: &fakeLAN{running: true}, ConfigPath: filepath.Join(t.TempDir(), "config.json"), DefaultPort: 3011, Tunnel: ft}
	if _, err := b.SetDomain(context.Background(), "phone.example.ngrok.app"); err != nil {
		t.Fatal(err)
	}
	if ft.disableCalls != 1 || ft.enableCalls != 1 {
		t.Fatalf("disable=%d enable=%d, want one restart", ft.disableCalls, ft.enableCalls)
	}
	cfg, _ := mobilebridge.Load(b.ConfigPath)
	if cfg.NgrokDomain != "phone.example.ngrok.app" {
		t.Errorf("domain not persisted: %+v", cfg)
	}
}
```

`fakeTunnel` is declared at `mobile_test.go:72`; add the counters `enableCalls`/`disableCalls` if it lacks them, and a `status tunnel.Status` field returned by `Status()`.

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement**

`mobilebridge/config.go`: add `NgrokDomain string `json:"ngrokDomain,omitempty"`` to the `State` struct (line ~28).

`dto.go`: the types above, e.g.

```go
type MobileNgrokStatus struct {
	Credential MobileNgrokCredential `json:"credential"`
	Agent      MobileNgrokAgent      `json:"agent"`
	Session    MobileNgrokSession    `json:"session"`
	Domain     string                `json:"domain" description:"Reserved domain the agent is told to use; empty for a random URL."`
	APIKey     MobileNgrokAPIKey     `json:"apiKey"`
	Logs       []MobileNgrokLogLine  `json:"logs" description:"Last 200 agent log lines, secrets redacted."`
}
```

(Write all of them with the same care; descriptions are what the OpenAPI shows.)

`mobile.go`:

```go
func ngrokStatusFrom(info tunnel.NgrokInfo) MobileNgrokStatus {
	logs := make([]MobileNgrokLogLine, 0, len(info.Logs))
	for _, l := range info.Logs {
		logs = append(logs, MobileNgrokLogLine{Time: l.Time, Level: l.Level, Message: l.Message})
	}
	return MobileNgrokStatus{
		Credential: MobileNgrokCredential{Present: info.Credential.Present, Source: info.Credential.Source, SystemConfigPath: info.Credential.SystemConfigPath, Suffix: info.Credential.Suffix},
		Agent:      MobileNgrokAgent{BinaryPath: info.Agent.BinaryPath, Source: info.Agent.Source, Version: info.Agent.Version, UpdateAvailable: info.Agent.UpdateAvailable},
		Session:    MobileNgrokSession{Status: info.Session.Status, Region: info.Session.Region, Latency: info.Session.Latency, PublicURL: info.Session.PublicURL, Connections: info.Session.Connections, HTTPRequests: info.Session.HTTPRequests},
		Domain:     info.Domain,
		APIKey:     MobileNgrokAPIKey{Present: info.APIKey},
		Logs:       logs,
	}
}

func ngrokAccountFrom(acc tunnel.NgrokAccount) MobileNgrokAccount { /* same shape, slices initialised to empty */ }
func ngrokDiagnosisFrom(d tunnel.NgrokDiagnosis) MobileNgrokDiagnosis { /* same */ }

func (b *BridgeService) NgrokStatus(ctx context.Context) MobileNgrokStatus {
	if b.Tunnel == nil {
		return ngrokStatusFrom(tunnel.NgrokInfo{})
	}
	return ngrokStatusFrom(b.Tunnel.NgrokInfo(ctx))
}

func (b *BridgeService) RemoveAuthtoken() (MobileStatusResponse, error) {
	if err := b.Tunnel.RemoveAuthtoken(); err != nil {
		return MobileStatusResponse{}, err
	}
	return b.Status(), nil
}

func (b *BridgeService) SetAPIKey(ctx context.Context, key string) (MobileNgrokAccount, error) {
	if err := b.Tunnel.SetAPIKey(ctx, key); err != nil {
		return MobileNgrokAccount{}, err
	}
	return ngrokAccountFrom(b.Tunnel.NgrokAccount(ctx)), nil
}

func (b *BridgeService) RemoveAPIKey() (MobileNgrokStatus, error) {
	if err := b.Tunnel.RemoveAPIKey(); err != nil {
		return MobileNgrokStatus{}, err
	}
	return b.NgrokStatus(context.Background()), nil
}

func (b *BridgeService) NgrokAccount(ctx context.Context) MobileNgrokAccount {
	return ngrokAccountFrom(b.Tunnel.NgrokAccount(ctx))
}

func (b *BridgeService) MintCredential(ctx context.Context) (MobileNgrokStatus, error) {
	if err := b.Tunnel.MintOperatorCredential(ctx); err != nil {
		return MobileNgrokStatus{}, err
	}
	return b.NgrokStatus(ctx), nil
}

func (b *BridgeService) RevokeCredential(ctx context.Context, id string) (MobileNgrokAccount, error) {
	if err := b.Tunnel.RevokeCredential(ctx, id); err != nil {
		return MobileNgrokAccount{}, err
	}
	return b.NgrokAccount(ctx), nil
}

func (b *BridgeService) SetDomain(ctx context.Context, domain string) (MobileNgrokStatus, error) {
	if err := b.Tunnel.SetStableDomain(ctx, domain); err != nil {
		return MobileNgrokStatus{}, err
	}
	st, err := mobilebridge.Load(b.ConfigPath)
	if err != nil {
		return MobileNgrokStatus{}, err
	}
	st.NgrokDomain = strings.TrimSpace(domain)
	if err := mobilebridge.Save(b.ConfigPath, st); err != nil {
		return MobileNgrokStatus{}, err
	}
	if live := b.Tunnel.Status(); live.State == tunnel.StateLive && live.Provider == "ngrok" {
		if err := b.Tunnel.Disable(ctx); err != nil {
			return MobileNgrokStatus{}, err
		}
		if err := b.Tunnel.Enable(ctx); err != nil {
			return MobileNgrokStatus{}, err
		}
	}
	return b.NgrokStatus(ctx), nil
}

func (b *BridgeService) Diagnose(ctx context.Context) MobileNgrokDiagnosis {
	return ngrokDiagnosisFrom(b.Tunnel.NgrokDiagnose(ctx))
}
```

`mobilebridge.Save(path, State)` and `mobilebridge.Load(path) (State, error)` are the existing persistence functions (`config.go:41,59`); the struct is `State`, not `Config`. `tunnelStatus()` copies `LastProvider`/`FallbackReason` from `tunnel.Status`.

- [ ] **Step 4: Run** — `go test ./internal/httpd/controllers/... ./internal/mobilebridge/...` → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(mobile): ngrok wire DTOs and bridge adapters"`

---

### Task 9: Controller handlers, routes and OpenAPI

**Files:**
- Create: `backend/internal/httpd/controllers/mobile_ngrok.go`
- Modify: `backend/internal/httpd/router.go` (`mountMobile`), `backend/internal/httpd/apispec/specgen/build.go` (`mobileOperations`, `schemaNames`), `backend/internal/httpd/mobile_routes_test.go` (`fakeMobileBridge` grows)
- Test: `backend/internal/httpd/controllers/mobile_ngrok_test.go`
- Generated: `backend/internal/httpd/apispec/openapi.yaml`, `frontend/src/api/schema.ts`

**Interfaces:**
- Routes (all loopback-only via `mountMobile`):
  - `GET    /api/v1/mobile/tunnel/ngrok` → `MobileNgrokStatus` (`getMobileNgrok`)
  - `DELETE /api/v1/mobile/tunnel/authtoken` → `MobileStatusResponse` (`removeMobileTunnelAuthtoken`)
  - `PUT    /api/v1/mobile/tunnel/ngrok/api-key` body `MobileNgrokAPIKeyRequest` → `MobileNgrokAccount` (`setMobileNgrokAPIKey`)
  - `DELETE /api/v1/mobile/tunnel/ngrok/api-key` → `MobileNgrokStatus` (`removeMobileNgrokAPIKey`)
  - `GET    /api/v1/mobile/tunnel/ngrok/account` → `MobileNgrokAccount` (`getMobileNgrokAccount`)
  - `POST   /api/v1/mobile/tunnel/ngrok/account/credential` → `MobileNgrokStatus` (`mintMobileNgrokCredential`)
  - `DELETE /api/v1/mobile/tunnel/ngrok/account/credential/{id}` → `MobileNgrokAccount` (`revokeMobileNgrokCredential`, `pathParams: MobileNgrokCredentialIDParam`)
  - `PUT    /api/v1/mobile/tunnel/ngrok/domain` body `MobileNgrokDomainRequest` → `MobileNgrokStatus` (`setMobileNgrokDomain`)
  - `POST   /api/v1/mobile/tunnel/ngrok/diagnose` → `MobileNgrokDiagnosis` (`diagnoseMobileNgrok`)
- Error codes: `MOBILE_AUTHTOKEN_REMOVE` (500), `MOBILE_NGROK_APIKEY_BODY` (400), `NGROK_API_UNAUTHORIZED` (401, when `errors.Is(err, tunnel.ErrNgrokAPIUnauthorized)`), `NGROK_API_ERROR` (502 otherwise), `MOBILE_NGROK_DOMAIN_BODY` (400), `MOBILE_NGROK_DOMAIN` (400).

- [ ] **Step 1: Failing tests** — `mobile_ngrok_test.go`, following `mobile_test.go`'s handler-test style (build a `MobileController{Bridge: &fakeBridge{}}`, `httptest.NewRecorder`, decode the envelope):

```go
func TestNgrokStatusRoute(t *testing.T) {
	c := &MobileController{Bridge: &fakeBridge{}}
	rec := httptest.NewRecorder()
	c.NgrokStatus(rec, httptest.NewRequest(http.MethodGet, "/api/v1/mobile/tunnel/ngrok", nil))
	if rec.Code != 200 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var body MobileNgrokStatus
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Logs == nil {
		t.Error("logs must be [] on the wire")
	}
}

func TestSetAPIKeyRouteMapsErrors(t *testing.T) {
	cases := []struct {
		body     string
		err      error
		wantCode int
		wantErr  string
	}{
		{`{"key":""}`, nil, 400, "MOBILE_NGROK_APIKEY_BODY"},
		{`not json`, nil, 400, "MOBILE_NGROK_APIKEY_BODY"},
		{`{"key":"k"}`, tunnel.ErrNgrokAPIUnauthorized, 401, "NGROK_API_UNAUTHORIZED"},
		{`{"key":"k"}`, errors.New("boom"), 502, "NGROK_API_ERROR"},
		{`{"key":"k"}`, nil, 200, ""},
	}
	for _, tc := range cases {
		b := &fakeBridge{apiKeyErr: tc.err}
		c := &MobileController{Bridge: b}
		rec := httptest.NewRecorder()
		c.SetNgrokAPIKey(rec, httptest.NewRequest(http.MethodPut, "/api/v1/mobile/tunnel/ngrok/api-key", strings.NewReader(tc.body)))
		if rec.Code != tc.wantCode {
			t.Errorf("%s: code %d want %d (%s)", tc.body, rec.Code, tc.wantCode, rec.Body)
		}
		if tc.wantErr != "" && !strings.Contains(rec.Body.String(), tc.wantErr) {
			t.Errorf("%s: body %s lacks %s", tc.body, rec.Body, tc.wantErr)
		}
	}
}

func TestRevokeCredentialRouteReadsThePathParam(t *testing.T) {
	b := &fakeBridge{}
	r := chi.NewRouter()
	r.Delete("/api/v1/mobile/tunnel/ngrok/account/credential/{id}", (&MobileController{Bridge: b}).RevokeNgrokCredential)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodDelete, "/api/v1/mobile/tunnel/ngrok/account/credential/cr_1", nil))
	if rec.Code != 200 || b.revoked != "cr_1" {
		t.Fatalf("code %d revoked %q", rec.Code, b.revoked)
	}
}
```

Grow `fakeBridge` in `mobile_test.go` with `apiKeyErr error`, `revoked string` and no-op implementations of every new `mobileBridge` method (returning zero values with initialised slices).

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement `mobile_ngrok.go`**

```go
package controllers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/OmarAly92/operator/backend/internal/httpd/envelope"
	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

func writeNgrokError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, tunnel.ErrNgrokAPIUnauthorized) {
		envelope.WriteAPIError(w, r, http.StatusUnauthorized, "unauthorized", "NGROK_API_UNAUTHORIZED", err.Error(), nil)
		return
	}
	envelope.WriteAPIError(w, r, http.StatusBadGateway, "upstream", "NGROK_API_ERROR", err.Error(), nil)
}

func (c *MobileController) NgrokStatus(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.NgrokStatus(r.Context()))
}

func (c *MobileController) RemoveAuthtoken(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RemoveAuthtoken()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_AUTHTOKEN_REMOVE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) SetNgrokAPIKey(w http.ResponseWriter, r *http.Request) {
	var body MobileNgrokAPIKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || strings.TrimSpace(body.Key) == "" {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_APIKEY_BODY", "an ngrok API key is required", nil)
		return
	}
	res, err := c.Bridge.SetAPIKey(r.Context(), body.Key)
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) RemoveNgrokAPIKey(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RemoveAPIKey()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_NGROK_APIKEY_REMOVE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) NgrokAccount(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.NgrokAccount(r.Context()))
}

func (c *MobileController) MintNgrokCredential(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.MintCredential(r.Context())
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) RevokeNgrokCredential(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.RevokeCredential(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		writeNgrokError(w, r, err)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) SetNgrokDomain(w http.ResponseWriter, r *http.Request) {
	var body MobileNgrokDomainRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_DOMAIN_BODY", "malformed request body", nil)
		return
	}
	res, err := c.Bridge.SetDomain(r.Context(), body.Domain)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_NGROK_DOMAIN", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, res)
}

func (c *MobileController) DiagnoseNgrok(w http.ResponseWriter, r *http.Request) {
	envelope.WriteJSON(w, http.StatusOK, c.Bridge.Diagnose(r.Context()))
}
```

`envelope.WriteAPIError(w, r, status, kind, code, message, details)` takes any kind string; `"unauthorized"` is already used by the auth middleware (`httpd/auth.go:233`), `"upstream"` is new and fine.

`router.go` `mountMobile` gains, after the authtoken route:

```go
	r.Delete("/api/v1/mobile/tunnel/authtoken", c.RemoveAuthtoken)
	r.Get("/api/v1/mobile/tunnel/ngrok", c.NgrokStatus)
	r.Put("/api/v1/mobile/tunnel/ngrok/api-key", c.SetNgrokAPIKey)
	r.Delete("/api/v1/mobile/tunnel/ngrok/api-key", c.RemoveNgrokAPIKey)
	r.Get("/api/v1/mobile/tunnel/ngrok/account", c.NgrokAccount)
	r.Post("/api/v1/mobile/tunnel/ngrok/account/credential", c.MintNgrokCredential)
	r.Delete("/api/v1/mobile/tunnel/ngrok/account/credential/{id}", c.RevokeNgrokCredential)
	r.Put("/api/v1/mobile/tunnel/ngrok/domain", c.SetNgrokDomain)
	r.Post("/api/v1/mobile/tunnel/ngrok/diagnose", c.DiagnoseNgrok)
```

`specgen/build.go`: nine new `operation` entries in `mobileOperations()` in the shape of `setMobileTunnelAuthtoken` (ids and DTOs listed under Interfaces; the revoke one carries `pathParams: []any{controllers.MobileNgrokCredentialIDParam{}}`; 401/502 responses use `envelope.APIError{}`). Update the comment count in `mobileOperations`' doc comment only if the parity test reads it (it does not; leave it). Add every new DTO to `schemaNames`:

```go
	"ControllersMobileNgrokStatus":            "MobileNgrokStatus",
	"ControllersMobileNgrokCredential":        "MobileNgrokCredential",
	"ControllersMobileNgrokAgent":             "MobileNgrokAgent",
	"ControllersMobileNgrokSession":           "MobileNgrokSession",
	"ControllersMobileNgrokLogLine":           "MobileNgrokLogLine",
	"ControllersMobileNgrokAPIKey":            "MobileNgrokAPIKey",
	"ControllersMobileNgrokAPIKeyRequest":     "MobileNgrokAPIKeyRequest",
	"ControllersMobileNgrokAccount":           "MobileNgrokAccount",
	"ControllersMobileNgrokAccountCredential": "MobileNgrokAccountCredential",
	"ControllersMobileNgrokAccountSession":    "MobileNgrokAccountSession",
	"ControllersMobileNgrokAccountEndpoint":   "MobileNgrokAccountEndpoint",
	"ControllersMobileNgrokReservedDomain":    "MobileNgrokReservedDomain",
	"ControllersMobileNgrokDomainRequest":     "MobileNgrokDomainRequest",
	"ControllersMobileNgrokCredentialIDParam": "MobileNgrokCredentialIDParam",
	"ControllersMobileNgrokCheck":             "MobileNgrokCheck",
	"ControllersMobileNgrokDiagnosis":         "MobileNgrokDiagnosis",
```

- [ ] **Step 4: Regenerate and verify**

```bash
npm run api
cd backend && go test ./internal/httpd/... ./internal/tunnel/...
```

Expected: PASS, including the spec-drift and route-parity tests. `git status` shows `openapi.yaml` and `frontend/src/api/schema.ts` modified.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/httpd backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(mobile): ngrok management routes (status, authtoken removal, API key, account, domain, diagnose)"
```

---

### Task 10: Boot wiring and real-daemon verification

**Files:**
- Modify: `backend/internal/daemon/daemon.go` (~262-275, and where `restoreMobileOnBoot` runs ~463)
- Test: `backend/internal/daemon/*_test.go` only if an existing test constructs the tunnel manager (grep `tunnel.New` in tests; if none, no new unit test — the verification below is the check).

- [ ] **Step 1: Wire the domain closure** (from Task 4) and, right before `restoreMobileOnBoot`, load the mobile config and push the saved domain into the manager:

```go
	if st, err := mobilebridge.Load(mobilebridge.Path(cfg.DataDir)); err == nil && st.NgrokDomain != "" {
		tunnelMgr.SetNgrokDomain(st.NgrokDomain)
	}
```

- [ ] **Step 2: Build and run against an isolated daemon** (memory: *Verify Operator desktop via daemon API and /mux*; the daemon dev data dir is `~/.operator/dev`, port 3002):

```bash
cd backend && go build ./... && cd .. && npm run lint
```

Then start the dev daemon the way `RUN_APP_COMMANDS.md` prescribes and exercise:

```bash
curl -s http://127.0.0.1:3002/api/v1/mobile/tunnel/ngrok | jq '.credential, .agent, .apiKey'
curl -s -X POST http://127.0.0.1:3002/api/v1/mobile/tunnel/ngrok/diagnose | jq '.summary, [.checks[] | {name, ok}]'
curl -s -X POST http://127.0.0.1:3002/api/v1/mobile/tunnel/enable | jq .tunnel
sleep 65
curl -s http://127.0.0.1:3002/api/v1/mobile/status | jq .tunnel
```

Expected on the incident network: the diagnose summary names the interception; after ~60 s the status shows `provider: "cloudflared"`, `lastProvider: "ngrok"`, `fallbackReason` = `NgrokCRLMessage`, `state: "live"` with a `trycloudflare.com` URL. On a healthy network: ngrok goes live directly and `fallbackReason` is empty. Paste the actual JSON into the commit message body or the PR.

- [ ] **Step 3: Commit** — `git commit -am "feat(daemon): restore the ngrok stable domain at boot"`

---

## Self-review

- Spec §4.1–4.3 → Tasks 1–2. §4.2's `LastProvider/FallbackReason` → Task 1 Step 4. §5.2 storage → Tasks 4, 6. §5.3 → Tasks 3, 5, 8, 9. §5.4 → Tasks 4, 9. §5.5 → Tasks 6, 8, 9. §5.6 → Task 7, 9. §5.7 → Task 9 Step 4. §5.8 tests → each task's Step 1. Boot wiring (spec §5.2 "passes it to the provider") → Task 10.
- Names used across tasks: `NgrokCRLMessage` (T2→T8 test), `ControlPort/Logs` (T3→T5), `removeNgrokAuthtoken`/`writeNgrokAuthtoken` (T4/T6), `binaryResolver` (T5→T7), `readAPIKey` stub (T5) replaced in T6, `ErrNgrokAPIUnauthorized` (T6→T9), `operatorCredentialDescription` (T6 test + impl), `ngrokCRLURL`/`ngrokConnectAddr` (T7), controller method names (T9 handlers ↔ router ↔ tests).
- No placeholders remain; the "same shape" mapping helpers in Task 8 are one-to-one field copies of the DTOs listed in that task's Interfaces block.
