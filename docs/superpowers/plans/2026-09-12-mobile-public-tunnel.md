# Connect Mobile Public Tunnel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one switch to the Connect Mobile dialog that makes the mobile bridge reachable from outside the LAN, so pairing stays "flip, scan, connected" when the phone is on cellular.

**Architecture:** A new `backend/internal/tunnel` package supervises a vendor CLI child process (ngrok preferred, cloudflared as the zero-setup fallback) pointed at the existing Connect Mobile LAN port, modeled on `previewserver.Manager`. Two new loopback-only routes drive it; `/api/v1/mobile/status` grows a `tunnel` object the renderer already polls. The QR payload gains a `v:2` shape carrying a full `https://` URL, which the Flutter app learns to parse.

**Tech Stack:** Go 1.x (chi router, `log/slog`, stdlib `net/http`, `os/exec`), React 19 + TypeScript + TanStack Query + radix-ui + Tailwind v4 (renderer), Flutter 3.44.5 + Dio + Cubit (mobile), OpenAPI generated via `npm run api`.

**Spec:** [`docs/superpowers/specs/2026-09-12-mobile-public-tunnel-design.md`](../specs/2026-09-12-mobile-public-tunnel-design.md) — read it before Task 1. Measurements it cites live in [`docs/superpowers/evidence/mobile-public-tunnel-probes.md`](../evidence/mobile-public-tunnel-probes.md); when a step says "as measured", that file is the source.

## Global Constraints

- **No code comments.** The user's `~/.claude/CLAUDE.md` says "don't make comments". This overrides the surrounding files' dense comment style — do not add explanatory comments to new code, and do not "fix" the resulting mismatch. Prose that would have been a comment belongs in the spec or a commit message. (Doc comments are not lint-required: `backend/.golangci.yml` enables no `exported` revive rule.)
- **Conventional commits** (`feat:`, `fix:`, `test:`, `docs:`, `chore:`), per `AGENTS.md`.
- **Go gate:** `cd backend && go test ./...` and `npm run lint` (runs `go test ./...` + golangci-lint v2.12.2) must pass.
- **Renderer gate:** `npm run typecheck`, `npm run frontend:lint`, and the renderer vitest suite.
- **Mobile gate:** from `packages/mobile`, `flutter analyze` must print "No issues found!" and `flutter test` must pass. CI pins Flutter **3.44.5**.
- **API contract changes** (`AGENTS.md:118`–`:141`): after touching any DTO or route, run `npm run api` and commit `backend/internal/httpd/apispec/openapi.yaml` + `frontend/src/api/schema.ts` alongside the Go change. Add a `schemaNames` entry in `backend/internal/httpd/apispec/specgen/build.go:144` for every new named type.
- **Every new `en.json` key must be translated into all 7 other locales** with non-empty values and identical `{{interpolation}}` variables — enforced by `frontend/src/renderer/i18n/instance.test.ts:149` and `:162`. Locales: `de, es, fr, ja, ko, pt-BR, zh-CN`.
- **No network access in tests.** Every test in this plan uses `httptest`, a fake binary script, or an injected clock. No test may start a real tunnel.
- **The ngrok authtoken is a credential.** Never log it, never return it from any endpoint, never put it in telemetry, never let it reach the stdout line buffer.
- **Never modify the user's `~/Library/Application Support/ngrok/ngrok.yml`.** Operator writes only `<dataDir>/mobile/ngrok.yml`.
- **Mobile:** Cubit only (never Bloc-with-events), no `freezed`/`json_serializable` in first-party code, no `flutter_screenutil` in feature code, inline English copy (no `LocaleKeys` for product copy).

---

## File Structure

**New — `backend/internal/tunnel/`** (no httpd/daemon imports, mirroring `mobilebridge`'s framing):

| File | Responsibility |
| --- | --- |
| `status.go` | `State`, `Status`, `Failure`, `FailureClass` value types |
| `provider.go` | `Provider` interface, `BinarySpec`, `ArchiveKind`, shared loopback JSON helpers |
| `ngrok.go` | ngrok provider: argv, `/api/tunnels`, `/api/status`, `ERR_NGROK_4018` classification |
| `cloudflared.go` | cloudflared provider: argv, `/quicktunnel`, `/ready` (503-tolerant) |
| `binary.go` | `BinaryStore`: PATH lookup, download, archive extract, checksum (cloudflared) or version-floor check (ngrok) |
| `manager.go` | `Manager`: enable/disable/status, supervision, health polling, backoff, provider fallback |
| `registry.go` | PID registry persistence + orphan reaping across daemon restarts |
| `process_unix.go`, `process_windows.go` | Start-time process identity + terminate/force-kill, per-GOOS |

**Modified — backend:**

| File | Change |
| --- | --- |
| `backend/internal/mobilebridge/config.go` | `State.TunnelEnabled`; `GeneratePasswordN` |
| `backend/internal/httpd/auth.go` | `sourceKey` honors a trusted forwarded header when loopback + tunnel live |
| `backend/internal/httpd/lan_listener.go` | `SetTrustedForwardHeader` on `LANManager` |
| `backend/internal/httpd/controllers/dto.go:1356` | `MobileStatusResponse.Tunnel`, `MobileTunnelStatus`, `MobileAuthtokenRequest` |
| `backend/internal/httpd/controllers/mobile.go` | `mobileBridge` grows tunnel methods; `BridgeService.Tunnel`; conditional warning |
| `backend/internal/httpd/router.go:139` | three new routes under `/api/v1/mobile/tunnel` |
| `backend/internal/httpd/apispec/specgen/build.go` | operations + `schemaNames` |
| `backend/internal/daemon/daemon.go:251`, `:402` | construct + wire the tunnel manager; stop it on shutdown |
| `backend/internal/daemon/mobile_restore.go` | auto-start the tunnel on boot when persisted enabled |

**Modified — renderer:**

| File | Change |
| --- | --- |
| `frontend/src/renderer/components/ConnectMobileModal.tsx` | tunnel toggle, state rendering, QR/address swap, polling |
| `frontend/src/renderer/components/settings/TunnelConfirmDialog.tsx` *(new)* | one-time "make it global" confirmation |
| `frontend/src/renderer/components/settings/NgrokAuthtokenDialog.tsx` *(new)* | token paste + validate |
| `frontend/src/renderer/i18n/*.json` | new `mobile.tunnel.*` keys in all 8 locales |

**Modified — mobile:**

| File | Change |
| --- | --- |
| `packages/mobile/lib/feature/pairing/logic/pairing_payload.dart` | parse `v:2` (`url`) alongside `v:1`; expose payload version |
| `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart:39` | take `secure` from the payload; surface unsupported-version |
| `packages/mobile/lib/core/error_handling/connection_error.dart` | `ConnectionFailure.unsupportedPayload` + copy |
| `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart:38` | default `ngrok-skip-browser-warning` header |
| `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart:51` | same header on WebView requests |

**Modified — docs:** `frontend/src/landing/content/docs/configuration/remote-access.mdx`.

---

## Phase 1 — The tunnel package (no HTTP surface, no UI)

### Task 1: Provider contracts and response parsers

**Files:**
- Create: `backend/internal/tunnel/status.go`, `backend/internal/tunnel/provider.go`, `backend/internal/tunnel/ngrok.go`, `backend/internal/tunnel/cloudflared.go`
- Test: `backend/internal/tunnel/ngrok_test.go`, `backend/internal/tunnel/cloudflared_test.go`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `State` constants (`StateOff`/`StateDownloading`/`StateStarting`/`StateLive`/`StateReconnecting`/`StateFailed`), `Status{State,Provider,URL,Error,Since,Restarts,NeedsAuthtoken}`, `Failure{Class,Message}`, `FailureClass` constants (`FailureUnknown`/`FailureCredential`/`FailureRefused`/`FailureNetwork`), `BinarySpec`, `ArchiveKind` (`ArchiveZip`/`ArchiveTarGz`), `Provider` interface, `NgrokProvider(configPaths []string) Provider`, `CloudflaredProvider() Provider`, and `ErrNoURLYet`.

- [ ] **Step 1: Write the failing parser tests**

Create `backend/internal/tunnel/ngrok_test.go` — the JSON bodies are copied verbatim from evidence §2 and §9:

```go
package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
)

func controlPortOf(t *testing.T, srv *httptest.Server) int {
	t.Helper()
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parse test server url: %v", err)
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		t.Fatalf("parse test server port: %v", err)
	}
	return port
}

func TestNgrokPublicURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/tunnels" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"tunnels":[{"name":"command_line","public_url":"https://imagines-livestock-widely.ngrok-free.dev","proto":"https"}]}`))
	}))
	defer srv.Close()

	got, err := NgrokProvider(nil).PublicURL(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("PublicURL: %v", err)
	}
	if want := "https://imagines-livestock-widely.ngrok-free.dev"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestNgrokPublicURLEmptyTunnelsIsNotReadyYet(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"tunnels":[]}`))
	}))
	defer srv.Close()

	if _, err := NgrokProvider(nil).PublicURL(context.Background(), controlPortOf(t, srv)); err != ErrNoURLYet {
		t.Fatalf("got %v, want ErrNoURLYet", err)
	}
}

func TestNgrokHealthyReadsSessionStatus(t *testing.T) {
	body := `{"status":"online","agent_version":"3.39.6","session":{"legs":[{"region":"eu","latency":"0ms"}]}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/status" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(body))
	}))
	defer srv.Close()

	ok, err := NgrokProvider(nil).Healthy(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Healthy: %v", err)
	}
	if !ok {
		t.Error("want healthy for status online")
	}
}

func TestNgrokHealthyFalseWhenNotOnline(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"reconnecting"}`))
	}))
	defer srv.Close()

	ok, err := NgrokProvider(nil).Healthy(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Healthy: %v", err)
	}
	if ok {
		t.Error("want not healthy for status reconnecting")
	}
}

func TestNgrokClassifyFailureCredential(t *testing.T) {
	lines := []string{
		`{"lvl":"info","msg":"starting web service","obj":"web"}`,
		`{"err":"authentication failed: This ngrok session is not authenticated. ngrok requires an account and a valid credential to start a session.\n\nERR_NGROK_4018\r\n","lvl":"eror","msg":"failed to reconnect session"}`,
	}
	got := NgrokProvider(nil).ClassifyFailure(lines)
	if got.Class != FailureCredential {
		t.Errorf("class = %v, want FailureCredential", got.Class)
	}
	if got.Message == "" {
		t.Error("want the provider's own error text carried through")
	}
}

func TestNgrokClassifyFailureRefusedCarriesUnknownErrorVerbatim(t *testing.T) {
	lines := []string{`{"err":"account limit exceeded: ERR_NGROK_9999","lvl":"eror","msg":"session closing"}`}
	got := NgrokProvider(nil).ClassifyFailure(lines)
	if got.Class != FailureRefused {
		t.Errorf("class = %v, want FailureRefused", got.Class)
	}
	if got.Message != "account limit exceeded: ERR_NGROK_9999" {
		t.Errorf("message = %q, want the err field verbatim", got.Message)
	}
}

func TestNgrokClassifyFailureUnknownWithoutAnyError(t *testing.T) {
	lines := []string{`{"lvl":"info","msg":"tunnel session started"}`}
	if got := NgrokProvider(nil).ClassifyFailure(lines); got.Class != FailureUnknown {
		t.Errorf("class = %v, want FailureUnknown", got.Class)
	}
}

func TestNgrokArgsPointAtLocalPortAndOurConfigs(t *testing.T) {
	args := NgrokProvider([]string{"/u/ngrok.yml", "/o/ngrok.yml"}).Args(3011, 50893)
	joined := " " + stringsJoin(args, " ") + " "
	for _, want := range []string{" http ", " 3011 ", " --config /u/ngrok.yml ", " --config /o/ngrok.yml ", " --log=stdout ", " --log-format=json ", " --inspect=false "} {
		if !containsString(joined, want) {
			t.Errorf("args %v missing %q", args, want)
		}
	}
}
```

Add these two helpers at the bottom of the same file so the assertions above read plainly:

```go
func stringsJoin(parts []string, sep string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += sep
		}
		out += p
	}
	return out
}

func containsString(haystack, needle string) bool {
	return len(needle) <= len(haystack) && indexOf(haystack, needle) >= 0
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}
```

Create `backend/internal/tunnel/cloudflared_test.go` — note the 503 case, which is the real pre-ready response observed in evidence §9:

```go
package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCloudflaredPublicURLFromQuickTunnel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/quicktunnel" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"hostname":"cradle-compatibility-biology-saskatchewan.trycloudflare.com"}`))
	}))
	defer srv.Close()

	got, err := CloudflaredProvider().PublicURL(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("PublicURL: %v", err)
	}
	if want := "https://cradle-compatibility-biology-saskatchewan.trycloudflare.com"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestCloudflaredReadyCountsConnections(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":200,"readyConnections":1,"connectorId":"c687b758"}`))
	}))
	defer srv.Close()

	ok, err := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Ready: %v", err)
	}
	if !ok {
		t.Error("want ready with readyConnections 1")
	}
}

func TestCloudflaredReadyTolerates503WhileConnecting(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	ok, err := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("503 while connecting must not be an error, got %v", err)
	}
	if ok {
		t.Error("want not ready")
	}
}

func TestCloudflaredReadyFalseWithZeroConnections(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":200,"readyConnections":0}`))
	}))
	defer srv.Close()

	ok, _ := CloudflaredProvider().Ready(context.Background(), controlPortOf(t, srv))
	if ok {
		t.Error("want not ready with zero connections")
	}
}

func TestCloudflaredArgsRequestAQuickTunnel(t *testing.T) {
	args := CloudflaredProvider().Args(3011, 50893)
	joined := " " + stringsJoin(args, " ") + " "
	for _, want := range []string{" tunnel ", " --no-autoupdate ", " --url http://127.0.0.1:3011 ", " --metrics 127.0.0.1:50893 "} {
		if !containsString(joined, want) {
			t.Errorf("args %v missing %q", args, want)
		}
	}
}

func TestCloudflaredClientIPHeaderPrefersCfConnectingIP(t *testing.T) {
	if got := CloudflaredProvider().ClientIPHeader(); got != "Cf-Connecting-Ip" {
		t.Errorf("got %q, want Cf-Connecting-Ip", got)
	}
	if got := NgrokProvider(nil).ClientIPHeader(); got != "X-Forwarded-For" {
		t.Errorf("got %q, want X-Forwarded-For", got)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run 'Ngrok|Cloudflared' -v`
Expected: FAIL — the package does not compile (`undefined: NgrokProvider`, `undefined: ErrNoURLYet`, …).

- [ ] **Step 3: Write `status.go`**

```go
package tunnel

import "time"

type State string

const (
	StateOff          State = "off"
	StateDownloading  State = "downloading"
	StateStarting     State = "starting"
	StateLive         State = "live"
	StateReconnecting State = "reconnecting"
	StateFailed       State = "failed"
)

type Status struct {
	State          State
	Provider       string
	URL            string
	Error          string
	Since          time.Time
	Restarts       int
	NeedsAuthtoken bool
}

type FailureClass int

const (
	FailureUnknown FailureClass = iota
	FailureCredential
	FailureRefused
	FailureNetwork
)

type Failure struct {
	Class   FailureClass
	Message string
}
```

- [ ] **Step 4: Write `provider.go`**

```go
package tunnel

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"time"
)

var ErrNoURLYet = errors.New("tunnel: public url not published yet")

type ArchiveKind int

const (
	ArchiveZip ArchiveKind = iota
	ArchiveTarGz
)

type BinarySpec struct {
	Name       string
	Version    string
	Archive    ArchiveKind
	EntryName  string
	URL        func(goos, goarch string) (string, error)
	SHA256     map[string]string
	MinVersion string
}

type Provider interface {
	Name() string
	Binary() BinarySpec
	Args(localPort, controlPort int) []string
	PublicURL(ctx context.Context, controlPort int) (string, error)
	Ready(ctx context.Context, controlPort int) (bool, error)
	Healthy(ctx context.Context, controlPort int) (bool, error)
	ClientIPHeader() string
	ClassifyFailure(logLines []string) Failure
}

var controlClient = &http.Client{Timeout: 3 * time.Second}

func controlURL(controlPort int, path string) string {
	return "http://" + net.JoinHostPort("127.0.0.1", strconv.Itoa(controlPort)) + path
}

func getJSON(ctx context.Context, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	res, err := controlClient.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("tunnel: %s returned %d", url, res.StatusCode)
	}
	return json.NewDecoder(res.Body).Decode(out)
}

func getJSONStatus(ctx context.Context, url string, out any) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}
	res, err := controlClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return res.StatusCode, nil
	}
	return res.StatusCode, json.NewDecoder(res.Body).Decode(out)
}
```

- [ ] **Step 5: Write `ngrok.go`**

The `ngrok-v3-stable-<os>-<arch>.zip` URL is a rolling channel and its version component is ignored by the server (evidence §13), so `SHA256` is deliberately nil and `MinVersion` carries the check instead.

```go
package tunnel

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

type ngrokProvider struct{ configPaths []string }

func NgrokProvider(configPaths []string) Provider {
	return ngrokProvider{configPaths: configPaths}
}

func (ngrokProvider) Name() string { return "ngrok" }

func (ngrokProvider) Binary() BinarySpec {
	return BinarySpec{
		Name:      "ngrok",
		Version:   "stable",
		Archive:   ArchiveZip,
		EntryName: "ngrok",
		URL: func(goos, goarch string) (string, error) {
			target, err := ngrokTarget(goos, goarch)
			if err != nil {
				return "", err
			}
			return "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-" + target + ".zip", nil
		},
		MinVersion: "3.0.0",
	}
}

func ngrokTarget(goos, goarch string) (string, error) {
	arch, ok := map[string]string{"amd64": "amd64", "arm64": "arm64"}[goarch]
	if !ok {
		return "", fmt.Errorf("tunnel: ngrok has no build for %s/%s", goos, goarch)
	}
	switch goos {
	case "darwin", "linux", "windows":
		return goos + "-" + arch, nil
	default:
		return "", fmt.Errorf("tunnel: ngrok has no build for %s/%s", goos, goarch)
	}
}

func (p ngrokProvider) Args(localPort, controlPort int) []string {
	args := []string{"http", fmt.Sprint(localPort)}
	for _, path := range p.configPaths {
		args = append(args, "--config", path)
	}
	return append(args, "--log=stdout", "--log-format=json", "--inspect=false")
}

func (ngrokProvider) PublicURL(ctx context.Context, controlPort int) (string, error) {
	var body struct {
		Tunnels []struct {
			PublicURL string `json:"public_url"`
		} `json:"tunnels"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/tunnels"), &body); err != nil {
		return "", err
	}
	for _, tun := range body.Tunnels {
		if strings.HasPrefix(tun.PublicURL, "https://") {
			return tun.PublicURL, nil
		}
	}
	return "", ErrNoURLYet
}

func (p ngrokProvider) Ready(ctx context.Context, controlPort int) (bool, error) {
	_, err := p.PublicURL(ctx, controlPort)
	if err == nil {
		return true, nil
	}
	return false, nil
}

func (ngrokProvider) Healthy(ctx context.Context, controlPort int) (bool, error) {
	var body struct {
		Status string `json:"status"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/api/status"), &body); err != nil {
		return false, err
	}
	return body.Status == "online", nil
}

func (ngrokProvider) ClientIPHeader() string { return "X-Forwarded-For" }

func (ngrokProvider) ClassifyFailure(logLines []string) Failure {
	var first string
	for _, line := range logLines {
		var rec struct {
			Err string `json:"err"`
		}
		if json.Unmarshal([]byte(line), &rec) != nil {
			continue
		}
		if rec.Err == "" || rec.Err == "<nil>" {
			continue
		}
		if strings.Contains(rec.Err, "ERR_NGROK_4018") {
			return Failure{Class: FailureCredential, Message: tidyProviderError(rec.Err)}
		}
		if first == "" {
			first = tidyProviderError(rec.Err)
		}
	}
	if first != "" {
		return Failure{Class: FailureRefused, Message: first}
	}
	return Failure{Class: FailureUnknown}
}

func tidyProviderError(raw string) string {
	cleaned := strings.ReplaceAll(raw, "\r", " ")
	cleaned = strings.ReplaceAll(cleaned, "\n", " ")
	return strings.Join(strings.Fields(cleaned), " ")
}
```

- [ ] **Step 6: Write `cloudflared.go`**

```go
package tunnel

import (
	"context"
	"fmt"
	"net/http"
	"strings"
)

type cloudflaredProvider struct{}

func CloudflaredProvider() Provider { return cloudflaredProvider{} }

func (cloudflaredProvider) Name() string { return "cloudflared" }

const cloudflaredVersion = "2026.3.0"

func (cloudflaredProvider) Binary() BinarySpec {
	return BinarySpec{
		Name:      "cloudflared",
		Version:   cloudflaredVersion,
		Archive:   ArchiveTarGz,
		EntryName: "cloudflared",
		URL: func(goos, goarch string) (string, error) {
			if goarch != "amd64" && goarch != "arm64" {
				return "", fmt.Errorf("tunnel: cloudflared has no build for %s/%s", goos, goarch)
			}
			return "https://github.com/cloudflare/cloudflared/releases/download/" +
				cloudflaredVersion + "/cloudflared-" + goos + "-" + goarch + ".tgz", nil
		},
		SHA256: cloudflaredChecksums,
	}
}

func (cloudflaredProvider) Args(localPort, controlPort int) []string {
	return []string{
		"tunnel", "--no-autoupdate",
		"--metrics", fmt.Sprintf("127.0.0.1:%d", controlPort),
		"--url", fmt.Sprintf("http://127.0.0.1:%d", localPort),
	}
}

func (cloudflaredProvider) PublicURL(ctx context.Context, controlPort int) (string, error) {
	var body struct {
		Hostname string `json:"hostname"`
	}
	if err := getJSON(ctx, controlURL(controlPort, "/quicktunnel"), &body); err != nil {
		return "", err
	}
	if body.Hostname == "" {
		return "", ErrNoURLYet
	}
	return "https://" + body.Hostname, nil
}

func (cloudflaredProvider) Ready(ctx context.Context, controlPort int) (bool, error) {
	var body struct {
		ReadyConnections int `json:"readyConnections"`
	}
	code, err := getJSONStatus(ctx, controlURL(controlPort, "/ready"), &body)
	if err != nil {
		return false, err
	}
	if code == http.StatusServiceUnavailable {
		return false, nil
	}
	if code != http.StatusOK {
		return false, fmt.Errorf("tunnel: cloudflared /ready returned %d", code)
	}
	return body.ReadyConnections >= 1, nil
}

func (p cloudflaredProvider) Healthy(ctx context.Context, controlPort int) (bool, error) {
	return p.Ready(ctx, controlPort)
}

func (cloudflaredProvider) ClientIPHeader() string { return "Cf-Connecting-Ip" }

func (cloudflaredProvider) ClassifyFailure(logLines []string) Failure {
	for _, line := range logLines {
		if strings.Contains(line, "ERR ") || strings.Contains(line, "error=") {
			return Failure{Class: FailureRefused, Message: tidyProviderError(line)}
		}
	}
	return Failure{Class: FailureUnknown}
}
```

Add the checksum table as its own file so refreshing it is a one-file change. Create `backend/internal/tunnel/cloudflared_checksums.go` with an empty map for now — Task 2 Step 7 fills it with real values:

```go
package tunnel

var cloudflaredChecksums = map[string]string{}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run 'Ngrok|Cloudflared' -v`
Expected: PASS — all 13 tests.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): add provider contracts and ngrok/cloudflared parsers"
```

---

### Task 2: Binary store — PATH first, download second

**Files:**
- Create: `backend/internal/tunnel/binary.go`, `backend/internal/tunnel/cloudflared_checksums.go` (rewritten)
- Test: `backend/internal/tunnel/binary_test.go`

**Interfaces:**
- Consumes: `BinarySpec`, `ArchiveKind`, `ArchiveZip`, `ArchiveTarGz` (Task 1).
- Produces: `BinaryStore` interface with `Ensure(ctx context.Context, spec BinarySpec) (string, error)`; `NewStore(deps StoreDeps) *Store`; `StoreDeps{Dir string, HTTPClient *http.Client, LookPath func(string) (string, error), Version func(path string) (string, error), Log *slog.Logger}`.

The download is attempted **second**, not first: the spec's §6 `PATH` fallback is inverted into a preference here for one measured reason — a Homebrew-managed ngrok has better provenance than the rolling artifact we can fetch (evidence §13), and it costs nothing when absent.

- [ ] **Step 1: Write the failing tests**

```go
package tunnel

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func zipped(t *testing.T, name string, content []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create(name)
	if err != nil {
		t.Fatalf("zip create: %v", err)
	}
	if _, err := w.Write(content); err != nil {
		t.Fatalf("zip write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip close: %v", err)
	}
	return buf.Bytes()
}

func tarred(t *testing.T, name string, content []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o755, Size: int64(len(content))}); err != nil {
		t.Fatalf("tar header: %v", err)
	}
	if _, err := tw.Write(content); err != nil {
		t.Fatalf("tar write: %v", err)
	}
	if err := tw.Close(); err != nil {
		t.Fatalf("tar close: %v", err)
	}
	if err := gz.Close(); err != nil {
		t.Fatalf("gzip close: %v", err)
	}
	return buf.Bytes()
}

func TestStorePrefersBinaryOnPath(t *testing.T) {
	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "/opt/homebrew/bin/ngrok", nil },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	got, err := store.Ensure(context.Background(), NgrokProvider(nil).Binary())
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if got != "/opt/homebrew/bin/ngrok" {
		t.Errorf("got %q, want the PATH binary", got)
	}
}

func TestStoreRejectsPathBinaryBelowMinVersion(t *testing.T) {
	payload := []byte("fake-ngrok")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	spec := NgrokProvider(nil).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "/usr/local/bin/ngrok", nil },
		Version: func(path string) (string, error) {
			if path == "/usr/local/bin/ngrok" {
				return "2.3.40", nil
			}
			return "3.39.6", nil
		},
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if got == "/usr/local/bin/ngrok" {
		t.Fatal("a PATH binary below MinVersion must not be used")
	}
	if body, readErr := os.ReadFile(got); readErr != nil || !bytes.Equal(body, payload) {
		t.Fatalf("downloaded binary content = %q, %v", body, readErr)
	}
}

func TestStoreDownloadsAndExtractsZip(t *testing.T) {
	payload := []byte("fake-ngrok-binary")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	dir := t.TempDir()
	spec := NgrokProvider(nil).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      dir,
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if filepath.Dir(got) != dir {
		t.Errorf("binary landed in %q, want under %q", got, dir)
	}
	info, err := os.Stat(got)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o755 {
		t.Errorf("mode = %v, want 0755", info.Mode().Perm())
	}
}

func TestStoreDownloadsAndExtractsTarGzVerifyingChecksum(t *testing.T) {
	payload := []byte("fake-cloudflared-binary")
	archive := tarred(t, "cloudflared", payload)
	sum := sha256.Sum256(archive)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	spec := CloudflaredProvider().Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }
	spec.SHA256 = map[string]string{runtime.GOOS + "/" + runtime.GOARCH: hex.EncodeToString(sum[:])}

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
	})

	got, err := store.Ensure(context.Background(), spec)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if body, readErr := os.ReadFile(got); readErr != nil || !bytes.Equal(body, payload) {
		t.Fatalf("extracted content = %q, %v", body, readErr)
	}
}

func TestStoreRejectsChecksumMismatch(t *testing.T) {
	archive := tarred(t, "cloudflared", []byte("tampered"))
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(archive)
	}))
	defer srv.Close()

	spec := CloudflaredProvider().Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }
	spec.SHA256 = map[string]string{
		runtime.GOOS + "/" + runtime.GOARCH: "0000000000000000000000000000000000000000000000000000000000000000",
	}

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
	})

	if _, err := store.Ensure(context.Background(), spec); err == nil {
		t.Fatal("want an error on checksum mismatch")
	}
}

func TestStoreReusesCachedBinaryWithoutDownloading(t *testing.T) {
	payload := []byte("fake-ngrok")
	var hits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits++
		_, _ = w.Write(zipped(t, "ngrok", payload))
	}))
	defer srv.Close()

	spec := NgrokProvider(nil).Binary()
	spec.URL = func(string, string) (string, error) { return srv.URL, nil }

	store := NewStore(StoreDeps{
		Dir:      t.TempDir(),
		LookPath: func(string) (string, error) { return "", errors.New("not found") },
		Version:  func(string) (string, error) { return "3.39.6", nil },
	})

	for i := 0; i < 2; i++ {
		if _, err := store.Ensure(context.Background(), spec); err != nil {
			t.Fatalf("Ensure %d: %v", i, err)
		}
	}
	if hits != 1 {
		t.Errorf("downloaded %d times, want 1", hits)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run Store -v`
Expected: FAIL — `undefined: NewStore`, `undefined: StoreDeps`.

- [ ] **Step 3: Write `binary.go`**

```go
package tunnel

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type BinaryStore interface {
	Ensure(ctx context.Context, spec BinarySpec) (string, error)
}

type StoreDeps struct {
	Dir        string
	HTTPClient *http.Client
	LookPath   func(string) (string, error)
	Version    func(path string) (string, error)
	Log        *slog.Logger
}

type Store struct {
	dir      string
	client   *http.Client
	lookPath func(string) (string, error)
	version  func(string) (string, error)
	log      *slog.Logger
}

func NewStore(deps StoreDeps) *Store {
	client := deps.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Minute}
	}
	lookPath := deps.LookPath
	if lookPath == nil {
		lookPath = exec.LookPath
	}
	version := deps.Version
	if version == nil {
		version = binaryVersion
	}
	log := deps.Log
	if log == nil {
		log = slog.Default()
	}
	return &Store{dir: deps.Dir, client: client, lookPath: lookPath, version: version, log: log}
}

func (s *Store) Ensure(ctx context.Context, spec BinarySpec) (string, error) {
	if path, ok := s.fromPath(spec); ok {
		return path, nil
	}
	cached := s.cachedPath(spec)
	if _, err := os.Stat(cached); err == nil {
		return cached, nil
	}
	return s.download(ctx, spec, cached)
}

func (s *Store) fromPath(spec BinarySpec) (string, bool) {
	path, err := s.lookPath(spec.Name)
	if err != nil || path == "" {
		return "", false
	}
	if spec.MinVersion == "" {
		return path, true
	}
	found, err := s.version(path)
	if err != nil {
		return "", false
	}
	if compareVersions(found, spec.MinVersion) < 0 {
		return "", false
	}
	return path, true
}

func (s *Store) cachedPath(spec BinarySpec) string {
	name := spec.Name + "-" + spec.Version
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	return filepath.Join(s.dir, name)
}

func (s *Store) download(ctx context.Context, spec BinarySpec, dest string) (string, error) {
	url, err := spec.URL(runtime.GOOS, runtime.GOARCH)
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	res, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", spec.Name, err)
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download %s: %s returned %d", spec.Name, url, res.StatusCode)
	}
	archive, err := io.ReadAll(res.Body)
	if err != nil {
		return "", fmt.Errorf("download %s: %w", spec.Name, err)
	}
	if want := spec.SHA256[runtime.GOOS+"/"+runtime.GOARCH]; want != "" {
		sum := sha256.Sum256(archive)
		if got := hex.EncodeToString(sum[:]); got != want {
			return "", fmt.Errorf("download %s: checksum mismatch (got %s)", spec.Name, got)
		}
	}
	binary, err := extract(spec, archive)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(s.dir, "."+spec.Name+"-*.tmp")
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	defer func() { _ = os.Remove(tmpName) }()
	if _, err := tmp.Write(binary); err != nil {
		_ = tmp.Close()
		return "", err
	}
	if err := tmp.Chmod(0o755); err != nil {
		_ = tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Rename(tmpName, dest); err != nil {
		return "", err
	}
	if spec.MinVersion != "" {
		found, err := s.version(dest)
		if err != nil {
			return "", fmt.Errorf("verify %s: %w", spec.Name, err)
		}
		if compareVersions(found, spec.MinVersion) < 0 {
			return "", fmt.Errorf("verify %s: reported version %s is below %s", spec.Name, found, spec.MinVersion)
		}
	}
	return dest, nil
}

func extract(spec BinarySpec, archive []byte) ([]byte, error) {
	switch spec.Archive {
	case ArchiveZip:
		return extractZip(spec.EntryName, archive)
	case ArchiveTarGz:
		return extractTarGz(spec.EntryName, archive)
	default:
		return nil, fmt.Errorf("tunnel: unknown archive kind for %s", spec.Name)
	}
}

func extractZip(entry string, archive []byte) ([]byte, error) {
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return nil, err
	}
	for _, file := range reader.File {
		if filepath.Base(file.Name) != entry && filepath.Base(file.Name) != entry+".exe" {
			continue
		}
		rc, err := file.Open()
		if err != nil {
			return nil, err
		}
		defer func() { _ = rc.Close() }()
		return io.ReadAll(io.LimitReader(rc, 200<<20))
	}
	return nil, fmt.Errorf("tunnel: %s not found in archive", entry)
}

func extractTarGz(entry string, archive []byte) ([]byte, error) {
	gz, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return nil, err
	}
	defer func() { _ = gz.Close() }()
	reader := tar.NewReader(gz)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("tunnel: %s not found in archive", entry)
		}
		if err != nil {
			return nil, err
		}
		if header.Typeflag != tar.TypeReg {
			continue
		}
		if filepath.Base(header.Name) != entry && filepath.Base(header.Name) != entry+".exe" {
			continue
		}
		return io.ReadAll(io.LimitReader(reader, 200<<20))
	}
}

func binaryVersion(path string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, path, "--version").CombinedOutput()
	if err != nil {
		return "", err
	}
	return firstVersionToken(string(out)), nil
}

func firstVersionToken(text string) string {
	for _, field := range strings.Fields(text) {
		trimmed := strings.TrimPrefix(field, "v")
		if len(trimmed) == 0 || trimmed[0] < '0' || trimmed[0] > '9' {
			continue
		}
		if strings.Contains(trimmed, ".") {
			return strings.TrimSuffix(trimmed, ",")
		}
	}
	return ""
}

func compareVersions(a, b string) int {
	aParts, bParts := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(aParts) || i < len(bParts); i++ {
		var x, y int
		if i < len(aParts) {
			x, _ = strconv.Atoi(numericPrefix(aParts[i]))
		}
		if i < len(bParts) {
			y, _ = strconv.Atoi(numericPrefix(bParts[i]))
		}
		if x != y {
			if x < y {
				return -1
			}
			return 1
		}
	}
	return 0
}

func numericPrefix(part string) string {
	end := 0
	for end < len(part) && part[end] >= '0' && part[end] <= '9' {
		end++
	}
	return part[:end]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run Store -v`
Expected: PASS — all 6 `Store` tests.

- [ ] **Step 5: Run the whole package plus the linter**

Run: `cd backend && go test ./internal/tunnel/ && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./internal/tunnel/...`
Expected: PASS, no lint findings.

- [ ] **Step 6: Record the real cloudflared checksums**

These cannot be invented — compute them from the pinned release. Run exactly:

```bash
for target in darwin-amd64 darwin-arm64 linux-amd64 linux-arm64; do
  printf '%s ' "$target"
  curl -sL "https://github.com/cloudflare/cloudflared/releases/download/2026.3.0/cloudflared-${target}.tgz" | shasum -a 256 | cut -d' ' -f1
done
```

- [ ] **Step 7: Write the checksums into `cloudflared_checksums.go`**

Replace the placeholder map with the command's output, one entry per target, keyed `GOOS/GOARCH`:

```go
package tunnel

var cloudflaredChecksums = map[string]string{
	"darwin/amd64": "<paste darwin-amd64 sum>",
	"darwin/arm64": "<paste darwin-arm64 sum>",
	"linux/amd64":  "<paste linux-amd64 sum>",
	"linux/arm64":  "<paste linux-arm64 sum>",
}
```

Windows is deliberately absent: cloudflared ships `.exe`/`.msi` rather than a `.tgz` for that platform, so `BinarySpec.URL` returning a `.tgz` would be wrong there. On Windows the store finds a `PATH` binary or the tunnel reports `failed` — acceptable, because Task 5's fallback keeps ngrok working and the desktop app's Windows support for this feature can be completed separately.

- [ ] **Step 8: Verify the checksums are well-formed**

Run: `cd backend && gofmt -l internal/tunnel && go test ./internal/tunnel/`
Expected: `gofmt -l` prints nothing; tests PASS. Each pasted value must be 64 hex characters — a short or `<paste …>` value is a plan failure, not an acceptable placeholder.

- [ ] **Step 9: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): add binary store with PATH preference and pinned cloudflared checksums"
```

---

### Task 3: Manager — start, publish URL, stop

**Files:**
- Create: `backend/internal/tunnel/manager.go`, `backend/internal/tunnel/process_unix.go`, `backend/internal/tunnel/process_windows.go`
- Test: `backend/internal/tunnel/manager_test.go`, `backend/internal/tunnel/fake_provider_test.go`

**Interfaces:**
- Consumes: `Provider`, `BinaryStore`, `Status`, `State`, `Failure` (Tasks 1–2).
- Produces: `Manager` with `Enable(ctx) error`, `Disable(ctx) error`, `Status() Status`, `Close()`, `SetLocalPort(port int)`; `Deps{Log, Dir, Providers []Provider, Binaries BinaryStore, Now func() time.Time, Sleep func(context.Context, time.Duration) error, ReservePort func() (int, error), OnProvider func(header string)}`; `New(Deps) *Manager`.
- `OnProvider` is called with the live provider's `ClientIPHeader()` on every transition into `StateLive`, and with `""` on stop — Task 8 wires it to the auth layer.

- [ ] **Step 1: Write the test scaffolding for a fake provider and fake binary**

Create `backend/internal/tunnel/fake_provider_test.go`:

```go
package tunnel

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

type fakeProvider struct {
	name     string
	header   string
	binary   string
	mu       sync.Mutex
	url      string
	urlErr   error
	ready    bool
	healthy  bool
	failure  Failure
	urlCalls int
}

func newFakeProvider(t *testing.T, name string, script string) *fakeProvider {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, name)
	if runtime.GOOS == "windows" {
		t.Skip("fake shell-script binaries are not portable to Windows")
	}
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake binary: %v", err)
	}
	return &fakeProvider{
		name:    name,
		header:  "X-Forwarded-For",
		binary:  path,
		url:     "https://fake-" + name + ".example",
		ready:   true,
		healthy: true,
	}
}

func (f *fakeProvider) setURL(url string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.url = url
}

func (f *fakeProvider) setHealthy(ok bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.healthy = ok
}

func (f *fakeProvider) setFailure(failure Failure) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.failure = failure
}

func (f *fakeProvider) setURLErr(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.urlErr = err
}

func (f *fakeProvider) Name() string { return f.name }

func (f *fakeProvider) Binary() BinarySpec {
	return BinarySpec{Name: f.name, Version: "test", EntryName: f.name}
}

func (f *fakeProvider) Args(localPort, controlPort int) []string { return []string{"run"} }

func (f *fakeProvider) PublicURL(_ context.Context, _ int) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.urlCalls++
	if f.urlErr != nil {
		return "", f.urlErr
	}
	return f.url, nil
}

func (f *fakeProvider) Ready(context.Context, int) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.ready, nil
}

func (f *fakeProvider) Healthy(context.Context, int) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.healthy, nil
}

func (f *fakeProvider) ClientIPHeader() string { return f.header }

func (f *fakeProvider) ClassifyFailure([]string) Failure {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.failure
}

type fakeStore struct{ path string }

func (s fakeStore) Ensure(context.Context, BinarySpec) (string, error) { return s.path, nil }

const sleepForeverScript = "#!/bin/sh\nwhile true; do sleep 1; done\n"

const exitImmediatelyScript = "#!/bin/sh\necho 'boom' >&2\nexit 1\n"
```

- [ ] **Step 2: Write the failing lifecycle tests**

Create `backend/internal/tunnel/manager_test.go`:

```go
package tunnel

import (
	"context"
	"errors"
	"testing"
	"time"
)

func waitForState(t *testing.T, m *Manager, want State) Status {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	var last Status
	for time.Now().Before(deadline) {
		last = m.Status()
		if last.State == want {
			return last
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("state = %q (err %q), want %q", last.State, last.Error, want)
	return last
}

func newTestManager(t *testing.T, providers ...Provider) *Manager {
	t.Helper()
	first, ok := providers[0].(*fakeProvider)
	if !ok {
		t.Fatal("first provider must be a *fakeProvider")
	}
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   providers,
		Binaries:    fakeStore{path: first.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m
}

func TestManagerStartsAndPublishesURL(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	m := newTestManager(t, provider)

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}

	status := waitForState(t, m, StateLive)
	if status.URL != "https://fake-ngrok.example" {
		t.Errorf("URL = %q", status.URL)
	}
	if status.Provider != "ngrok" {
		t.Errorf("Provider = %q", status.Provider)
	}
	if status.Since.IsZero() {
		t.Error("Since must be set when live")
	}
}

func TestManagerStatusIsOffBeforeEnable(t *testing.T) {
	m := newTestManager(t, newFakeProvider(t, "ngrok", sleepForeverScript))
	if got := m.Status().State; got != StateOff {
		t.Errorf("state = %q, want off", got)
	}
}

func TestManagerDisableStopsTheChild(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	m := newTestManager(t, provider)
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)

	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}
	status := m.Status()
	if status.State != StateOff {
		t.Errorf("state = %q, want off", status.State)
	}
	if status.URL != "" {
		t.Errorf("URL = %q, want cleared on stop", status.URL)
	}
}

func TestManagerReportsTrustedHeaderOnLiveAndClearsOnStop(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	headers := make(chan string, 8)
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
		OnProvider:  func(header string) { headers <- header },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)
	if got := <-headers; got != "X-Forwarded-For" {
		t.Errorf("header = %q on live", got)
	}

	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}
	if got := <-headers; got != "" {
		t.Errorf("header = %q on stop, want empty", got)
	}
}

func TestManagerEnableIsIdempotent(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	m := newTestManager(t, provider)

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("first Enable: %v", err)
	}
	waitForState(t, m, StateLive)
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("second Enable: %v", err)
	}
	if got := m.Status().Restarts; got != 0 {
		t.Errorf("restarts = %d, want 0 — a redundant Enable must not restart", got)
	}
}

func TestManagerWaitsForURLBeforeGoingLive(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	provider.setURLErr(ErrNoURLYet)
	m := newTestManager(t, provider)

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateStarting)

	provider.setURLErr(nil)
	status := waitForState(t, m, StateLive)
	if status.URL == "" {
		t.Error("want a URL once the provider publishes one")
	}
}

func TestManagerSurfacesBinaryStoreFailureAsFailed(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    failingStore{},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err == nil {
		t.Fatal("want an error when no provider can produce a binary")
	}
	status := m.Status()
	if status.State != StateFailed {
		t.Errorf("state = %q, want failed", status.State)
	}
	if status.Error == "" {
		t.Error("want the store's error surfaced")
	}
}

type failingStore struct{}

func (failingStore) Ensure(context.Context, BinarySpec) (string, error) {
	return "", errors.New("no binary available")
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run Manager -v`
Expected: FAIL — `undefined: New`, `undefined: Deps`, `undefined: Manager`.

- [ ] **Step 4: Write `process_unix.go` and `process_windows.go`**

`process_unix.go`:

```go
//go:build !windows

package tunnel

import (
	"os/exec"
	"strings"
	"syscall"
)

func newTunnelCommand(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return cmd
}

func processStartTime(pid int) string {
	if pid <= 0 {
		return ""
	}
	out, err := exec.Command("ps", "-o", "lstart=", "-p", itoa(pid)).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func terminateProcess(cmd *exec.Cmd) error {
	if cmd == nil || cmd.Process == nil {
		return nil
	}
	return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
}

func forceKillProcess(cmd *exec.Cmd) error {
	if cmd == nil || cmd.Process == nil {
		return nil
	}
	return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
}

func forceKillPID(pid int, recordedStart string) error {
	if pid <= 0 {
		return nil
	}
	if recordedStart == "" || processStartTime(pid) != recordedStart {
		return nil
	}
	return syscall.Kill(-pid, syscall.SIGKILL)
}
```

`process_windows.go`:

```go
//go:build windows

package tunnel

import "os/exec"

func newTunnelCommand(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}

func processStartTime(int) string { return "" }

func terminateProcess(cmd *exec.Cmd) error {
	if cmd == nil || cmd.Process == nil {
		return nil
	}
	return cmd.Process.Kill()
}

func forceKillProcess(cmd *exec.Cmd) error { return terminateProcess(cmd) }

func forceKillPID(int, string) error { return nil }
```

The PID-identity guard in `forceKillPID` mirrors `previewserver`'s
`forceKillPreviewPID` (`backend/internal/previewserver/process_unix.go:113`), which
exists because a recycled PID once killed an unrelated process tree. Do not
drop the `recordedStart` comparison.

Add `itoa` to `manager.go` in the next step (`strconv.Itoa`, aliased so
`process_unix.go` needs no extra import).

- [ ] **Step 5: Write `manager.go`**

```go
package tunnel

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os/exec"
	"strconv"
	"sync"
	"time"
)

const (
	urlPollInterval  = 250 * time.Millisecond
	startTimeout     = 60 * time.Second
	healthInterval   = 15 * time.Second
	backoffFloor     = time.Second
	backoffCeiling   = 60 * time.Second
	healthResetAfter = 60 * time.Second
	stopGrace        = 5 * time.Second
	logRetention     = 200
)

func itoa(value int) string { return strconv.Itoa(value) }

type Deps struct {
	Log         *slog.Logger
	Dir         string
	Providers   []Provider
	Binaries    BinaryStore
	Now         func() time.Time
	Sleep       func(context.Context, time.Duration) error
	ReservePort func() (int, error)
	OnProvider  func(clientIPHeader string)
}

type Manager struct {
	log         *slog.Logger
	dir         string
	providers   []Provider
	binaries    BinaryStore
	now         func() time.Time
	sleep       func(context.Context, time.Duration) error
	reservePort func() (int, error)
	onProvider  func(string)

	mu         sync.Mutex
	status     Status
	localPort  int
	enabled    bool
	stickyFrom map[string]bool
	cmd        *exec.Cmd
	cancel     context.CancelFunc
	done       chan struct{}
	logs       *lineRing
}

func New(deps Deps) *Manager {
	log := deps.Log
	if log == nil {
		log = slog.Default()
	}
	now := deps.Now
	if now == nil {
		now = time.Now
	}
	sleep := deps.Sleep
	if sleep == nil {
		sleep = sleepContext
	}
	reserve := deps.ReservePort
	if reserve == nil {
		reserve = reserveLoopbackPort
	}
	onProvider := deps.OnProvider
	if onProvider == nil {
		onProvider = func(string) {}
	}
	return &Manager{
		log:         log,
		dir:         deps.Dir,
		providers:   deps.Providers,
		binaries:    deps.Binaries,
		now:         now,
		sleep:       sleep,
		reservePort: reserve,
		onProvider:  onProvider,
		status:      Status{State: StateOff},
		stickyFrom:  map[string]bool{},
	}
}

func (m *Manager) SetLocalPort(port int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.localPort = port
}

func (m *Manager) Status() Status {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.status
}

func (m *Manager) Enable(ctx context.Context) error {
	m.mu.Lock()
	if m.enabled {
		m.mu.Unlock()
		return nil
	}
	m.enabled = true
	m.status = Status{State: StateStarting}
	m.mu.Unlock()

	if err := m.startFirstWorkingProvider(ctx); err != nil {
		m.mu.Lock()
		m.enabled = false
		m.status = Status{State: StateFailed, Error: err.Error(), NeedsAuthtoken: m.status.NeedsAuthtoken}
		m.mu.Unlock()
		return err
	}
	return nil
}

func (m *Manager) Disable(ctx context.Context) error {
	m.mu.Lock()
	m.enabled = false
	cancel, done := m.cancel, m.done
	m.cancel, m.done = nil, nil
	m.stickyFrom = map[string]bool{}
	m.mu.Unlock()

	if cancel != nil {
		cancel()
	}
	if done != nil {
		select {
		case <-done:
		case <-time.After(stopGrace + time.Second):
		}
	}

	m.mu.Lock()
	m.status = Status{State: StateOff}
	m.mu.Unlock()
	m.onProvider("")
	return nil
}

func (m *Manager) Close() {
	stopCtx, cancel := context.WithTimeout(context.Background(), stopGrace)
	defer cancel()
	_ = m.Disable(stopCtx)
}

func (m *Manager) startFirstWorkingProvider(ctx context.Context) error {
	var lastErr error
	for _, provider := range m.providers {
		m.mu.Lock()
		skip := m.stickyFrom[provider.Name()]
		m.mu.Unlock()
		if skip {
			continue
		}
		if err := m.launch(ctx, provider); err != nil {
			lastErr = err
			m.log.Warn("tunnel provider unavailable", "provider", provider.Name(), "err", err)
			continue
		}
		return nil
	}
	if lastErr == nil {
		lastErr = errors.New("no tunnel provider available")
	}
	return lastErr
}

func (m *Manager) launch(ctx context.Context, provider Provider) error {
	m.setState(StateDownloading, provider.Name())
	binary, err := m.binaries.Ensure(ctx, provider.Binary())
	if err != nil {
		return err
	}
	controlPort, err := m.reservePort()
	if err != nil {
		return err
	}

	m.mu.Lock()
	localPort := m.localPort
	m.mu.Unlock()

	runCtx, cancel := context.WithCancel(context.Background())
	cmd := newTunnelCommand(binary, provider.Args(localPort, controlPort)...)
	logs := newLineRing(logRetention)
	cmd.Stdout = logs
	cmd.Stderr = logs
	if err := cmd.Start(); err != nil {
		cancel()
		return err
	}

	done := make(chan struct{})
	m.mu.Lock()
	m.cmd, m.cancel, m.done, m.logs = cmd, cancel, done, logs
	m.status = Status{State: StateStarting, Provider: provider.Name()}
	m.mu.Unlock()

	m.recordPID(provider.Name(), cmd)
	m.setState(StateStarting, provider.Name())

	go m.supervise(runCtx, provider, cmd, controlPort, logs, done)

	if err := m.awaitURL(runCtx, provider, controlPort); err != nil {
		cancel()
		<-done
		return err
	}
	return nil
}

func (m *Manager) awaitURL(ctx context.Context, provider Provider, controlPort int) error {
	deadline := m.now().Add(startTimeout)
	for m.now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		url, err := provider.PublicURL(ctx, controlPort)
		if err == nil && url != "" {
			m.publishURL(provider, url)
			return nil
		}
		if err := m.sleep(ctx, urlPollInterval); err != nil {
			return err
		}
	}
	return fmt.Errorf("tunnel: %s published no url within %s", provider.Name(), startTimeout)
}

func (m *Manager) publishURL(provider Provider, url string) {
	m.mu.Lock()
	m.status.State = StateLive
	m.status.Provider = provider.Name()
	m.status.URL = url
	m.status.Error = ""
	if m.status.Since.IsZero() {
		m.status.Since = m.now()
	}
	m.mu.Unlock()
	m.onProvider(provider.ClientIPHeader())
}

func (m *Manager) setState(state State, providerName string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.status.State = state
	m.status.Provider = providerName
}

func sleepContext(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func reserveLoopbackPort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer func() { _ = listener.Close() }()
	addr, ok := listener.Addr().(*net.TCPAddr)
	if !ok {
		return 0, errors.New("tunnel: reserved listener returned no TCP address")
	}
	return addr.Port, nil
}
```

Add the bounded log ring in the same file — a trimmed copy of
`previewserver`'s `lineBuffer` (`backend/internal/previewserver/manager.go:928`),
kept local because the original is unexported there:

```go
type lineRing struct {
	mu      sync.Mutex
	max     int
	lines   []string
	partial string
}

func newLineRing(capacity int) *lineRing { return &lineRing{max: capacity} }

func (r *lineRing) Write(data []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	text := r.partial + string(data)
	for {
		index := indexByte(text, '\n')
		if index < 0 {
			break
		}
		r.appendLocked(trimCR(text[:index]))
		text = text[index+1:]
	}
	r.partial = text
	if len(r.partial) > 8192 {
		r.partial = r.partial[len(r.partial)-8192:]
	}
	return len(data), nil
}

func (r *lineRing) Lines() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := append([]string{}, r.lines...)
	if r.partial != "" {
		out = append(out, r.partial)
	}
	return out
}

func (r *lineRing) appendLocked(line string) {
	r.lines = append(r.lines, line)
	if len(r.lines) > r.max {
		r.lines = append([]string{}, r.lines[len(r.lines)-r.max:]...)
	}
}

func indexByte(text string, target byte) int {
	for i := 0; i < len(text); i++ {
		if text[i] == target {
			return i
		}
	}
	return -1
}

func trimCR(line string) string {
	if len(line) > 0 && line[len(line)-1] == '\r' {
		return line[:len(line)-1]
	}
	return line
}
```

`supervise` and `recordPID` are added in Tasks 4–6. To keep this task
compiling and its tests meaningful, add these minimal versions now:

```go
func (m *Manager) supervise(ctx context.Context, provider Provider, cmd *exec.Cmd, controlPort int, logs *lineRing, done chan struct{}) {
	defer close(done)
	exited := make(chan error, 1)
	go func() { exited <- cmd.Wait() }()

	select {
	case <-ctx.Done():
		_ = terminateProcess(cmd)
		select {
		case <-exited:
		case <-time.After(stopGrace):
			_ = forceKillProcess(cmd)
			<-exited
		}
	case <-exited:
	}
}

func (m *Manager) recordPID(string, *exec.Cmd) {}
```

- [ ] **Step 6: Run to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run Manager -v`
Expected: PASS — all 7 `Manager` tests.

- [ ] **Step 7: Verify no goroutine or child leaks**

Run: `cd backend && go test -race ./internal/tunnel/`
Expected: PASS with no race reports.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): supervise the provider child and publish its public url"
```

---

### Task 4: Health polling, reconnection, and restart counting

**Files:**
- Modify: `backend/internal/tunnel/manager.go` (replace the minimal `supervise`)
- Test: `backend/internal/tunnel/manager_reconnect_test.go`

**Interfaces:**
- Consumes: `Manager`, `Deps.Sleep`, `Provider.Healthy` (Tasks 1, 3).
- Produces: no new exported names. `Status.Restarts` now increments, and `StateReconnecting` becomes reachable. `Deps.Sleep` is the only time source used for backoff, so tests drive it.

- [ ] **Step 1: Write the failing tests**

```go
package tunnel

import (
	"context"
	"sync"
	"testing"
	"time"
)

type recordingSleeper struct {
	mu     sync.Mutex
	waits  []time.Duration
	resume chan struct{}
}

func newRecordingSleeper() *recordingSleeper {
	return &recordingSleeper{resume: make(chan struct{}, 128)}
}

func (s *recordingSleeper) sleep(ctx context.Context, d time.Duration) error {
	s.mu.Lock()
	s.waits = append(s.waits, d)
	s.mu.Unlock()
	if d < backoffFloor {
		return nil
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-s.resume:
		return nil
	}
}

func (s *recordingSleeper) backoffWaits() []time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []time.Duration
	for _, w := range s.waits {
		if w >= backoffFloor {
			out = append(out, w)
		}
	}
	return out
}

func (s *recordingSleeper) release(n int) {
	for i := 0; i < n; i++ {
		s.resume <- struct{}{}
	}
}

func TestManagerRestartsAfterUnexpectedExit(t *testing.T) {
	restartOnce := "#!/bin/sh\nif [ -f \"$TUNNEL_TEST_MARKER\" ]; then while true; do sleep 1; done; fi\ntouch \"$TUNNEL_TEST_MARKER\"\nexit 1\n"
	provider := newFakeProvider(t, "ngrok", restartOnce)
	t.Setenv("TUNNEL_TEST_MARKER", t.TempDir()+"/marker")

	sleeper := newRecordingSleeper()
	sleeper.release(8)
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	status := waitForState(t, m, StateLive)
	if status.Restarts < 1 {
		t.Errorf("restarts = %d, want at least 1", status.Restarts)
	}
}

func TestManagerBackoffScheduleIsExponentialAndCapped(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})

	sleeper := newRecordingSleeper()
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	go func() { _ = m.Enable(context.Background()) }()
	waitForState(t, m, StateReconnecting)

	for i := 0; i < 8; i++ {
		sleeper.release(1)
		time.Sleep(20 * time.Millisecond)
	}

	waits := sleeper.backoffWaits()
	if len(waits) < 4 {
		t.Fatalf("only %d backoff waits recorded", len(waits))
	}
	want := []time.Duration{backoffFloor, 2 * backoffFloor, 4 * backoffFloor, 8 * backoffFloor}
	for i, expected := range want {
		if waits[i] != expected {
			t.Errorf("wait[%d] = %v, want %v", i, waits[i], expected)
		}
	}
	for _, wait := range waits {
		if wait > backoffCeiling {
			t.Errorf("wait %v exceeds ceiling %v", wait, backoffCeiling)
		}
	}
}

func TestManagerNeverGivesUpOnNetworkFailures(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})

	sleeper := newRecordingSleeper()
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	go func() { _ = m.Enable(context.Background()) }()
	waitForState(t, m, StateReconnecting)

	for i := 0; i < 12; i++ {
		sleeper.release(1)
		time.Sleep(10 * time.Millisecond)
	}
	if got := m.Status().State; got == StateFailed {
		t.Error("a network-shaped failure must stay reconnecting, never failed")
	}
}

func TestManagerRestartsWhenHealthProbeReportsNotOnline(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	sleeper := newRecordingSleeper()
	sleeper.release(32)

	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)

	provider.setHealthy(false)
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.Status().Restarts >= 1 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("two consecutive unhealthy probes must trigger a restart")
}

func TestManagerRepublishesAChangedURLAcrossRestart(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	sleeper := newRecordingSleeper()
	sleeper.release(32)

	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)

	provider.setURL("https://second-url.example")
	provider.setHealthy(false)
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.Status().URL == "https://second-url.example" {
			return
		}
		provider.setHealthy(true)
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("URL = %q, want the republished one", m.Status().URL)
}

func TestManagerDisableDuringBackoffStopsPromptly(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})

	sleeper := newRecordingSleeper()
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       sleeper.sleep,
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)

	go func() { _ = m.Enable(context.Background()) }()
	waitForState(t, m, StateReconnecting)

	start := time.Now()
	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Errorf("Disable took %v during backoff, want prompt", elapsed)
	}
	if got := m.Status().State; got != StateOff {
		t.Errorf("state = %q, want off", got)
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run 'Restart|Backoff|GivesUp|Health|Republishes|DuringBackoff' -v`
Expected: FAIL — restarts stay 0, `StateReconnecting` is never reached.

- [ ] **Step 3: Replace `supervise` in `manager.go`**

```go
func (m *Manager) supervise(ctx context.Context, provider Provider, cmd *exec.Cmd, controlPort int, logs *lineRing, done chan struct{}) {
	defer close(done)

	current := cmd
	currentPort := controlPort
	currentLogs := logs
	backoff := backoffFloor

	for {
		exited := make(chan error, 1)
		go func(c *exec.Cmd) { exited <- c.Wait() }(current)

		healthy := m.watchHealth(ctx, provider, currentPort)

		var stopped bool
		select {
		case <-ctx.Done():
			m.stopChild(current, exited)
			stopped = true
		case <-healthy:
			m.stopChild(current, exited)
		case <-exited:
		}
		if stopped {
			return
		}

		published := m.Status().URL != ""
		failure := provider.ClassifyFailure(currentLogs.Lines())
		class := combineFailure(published, failure)

		if class == FailureCredential || class == FailureRefused {
			m.handleProviderRefusal(ctx, provider, failure, class)
			return
		}

		m.mu.Lock()
		if !m.enabled {
			m.mu.Unlock()
			return
		}
		m.status.State = StateReconnecting
		m.status.URL = ""
		if failure.Message != "" {
			m.status.Error = failure.Message
		}
		m.status.Restarts++
		m.mu.Unlock()
		m.onProvider("")

		if err := m.sleep(ctx, backoff); err != nil {
			return
		}
		backoff *= 2
		if backoff > backoffCeiling {
			backoff = backoffCeiling
		}

		next, nextPort, nextLogs, err := m.spawn(provider)
		if err != nil {
			m.mu.Lock()
			m.status.Error = err.Error()
			m.mu.Unlock()
			continue
		}
		current, currentPort, currentLogs = next, nextPort, nextLogs

		m.mu.Lock()
		m.cmd = current
		m.logs = currentLogs
		m.mu.Unlock()
		m.recordPID(provider.Name(), current)

		if err := m.awaitURL(ctx, provider, currentPort); err != nil {
			if ctx.Err() != nil {
				m.stopChild(current, nil)
				return
			}
			continue
		}
		backoff = backoffFloor
	}
}

func (m *Manager) watchHealth(ctx context.Context, provider Provider, controlPort int) <-chan struct{} {
	unhealthy := make(chan struct{})
	go func() {
		strikes := 0
		lastGood := m.now()
		for {
			if err := m.sleep(ctx, healthInterval); err != nil {
				return
			}
			if m.Status().State != StateLive {
				continue
			}
			ok, err := provider.Healthy(ctx, controlPort)
			if err == nil && ok {
				strikes = 0
				lastGood = m.now()
				continue
			}
			strikes++
			if strikes >= 2 {
				if m.now().Sub(lastGood) >= healthResetAfter {
					strikes = 0
				}
				close(unhealthy)
				return
			}
		}
	}()
	return unhealthy
}

func (m *Manager) stopChild(cmd *exec.Cmd, exited chan error) {
	_ = terminateProcess(cmd)
	if exited == nil {
		return
	}
	select {
	case <-exited:
	case <-time.After(stopGrace):
		_ = forceKillProcess(cmd)
		<-exited
	}
}

func (m *Manager) spawn(provider Provider) (*exec.Cmd, int, *lineRing, error) {
	binary, err := m.binaries.Ensure(context.Background(), provider.Binary())
	if err != nil {
		return nil, 0, nil, err
	}
	controlPort, err := m.reservePort()
	if err != nil {
		return nil, 0, nil, err
	}
	m.mu.Lock()
	localPort := m.localPort
	m.mu.Unlock()

	logs := newLineRing(logRetention)
	cmd := newTunnelCommand(binary, provider.Args(localPort, controlPort)...)
	cmd.Stdout = logs
	cmd.Stderr = logs
	if err := cmd.Start(); err != nil {
		return nil, 0, nil, err
	}
	return cmd, controlPort, logs, nil
}

func combineFailure(published bool, failure Failure) FailureClass {
	switch failure.Class {
	case FailureCredential, FailureRefused, FailureNetwork:
		return failure.Class
	}
	if published {
		return FailureNetwork
	}
	return FailureRefused
}
```

`handleProviderRefusal` is written in Task 5. Add this stub now so the
package compiles and every test in this task exercises the reconnect path:

```go
func (m *Manager) handleProviderRefusal(context.Context, Provider, Failure, FailureClass) {}
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run 'Restart|Backoff|GivesUp|Health|Republishes|DuringBackoff' -v`
Expected: PASS — all 6 tests.

- [ ] **Step 5: Run the full package under the race detector**

Run: `cd backend && go test -race ./internal/tunnel/`
Expected: PASS. The status mutex is taken on every read/write of `m.status`; a race report here means a missed lock, not a flaky test.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): observe liveness and reconnect with capped backoff"
```

---

### Task 5: Provider fallback — classified by failure shape

**Files:**
- Modify: `backend/internal/tunnel/manager.go` (replace the `handleProviderRefusal` stub)
- Test: `backend/internal/tunnel/manager_fallback_test.go`

**Interfaces:**
- Consumes: `Manager`, `combineFailure`, `FailureClass` (Tasks 1, 4).
- Produces: no new exported names. `Status.NeedsAuthtoken` becomes reachable, and a refused provider is recorded in `Manager.stickyFrom` so it is skipped until `Disable`.

Spec §7 is the authority: only `ERR_NGROK_4018` is matched by code, everything
else is classified by shape, and the provider's own message is carried verbatim.

- [ ] **Step 1: Write the failing tests**

```go
package tunnel

import (
	"context"
	"testing"
	"time"
)

func newFallbackManager(t *testing.T, first, second *fakeProvider) *Manager {
	t.Helper()
	m := New(Deps{
		Dir:       t.TempDir(),
		Providers: []Provider{first, second},
		Binaries: perProviderStore{paths: map[string]string{
			first.name:  first.binary,
			second.name: second.binary,
		}},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m
}

type perProviderStore struct{ paths map[string]string }

func (s perProviderStore) Ensure(_ context.Context, spec BinarySpec) (string, error) {
	return s.paths[spec.Name], nil
}

func TestFallbackOnMissingAuthtokenSwitchesAndFlagsTheDialog(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{
		Class:   FailureCredential,
		Message: "authentication failed: ERR_NGROK_4018",
	})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURL("https://fallback.trycloudflare.com")

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Errorf("provider = %q, want cloudflared", status.Provider)
	}
	if status.URL != "https://fallback.trycloudflare.com" {
		t.Errorf("URL = %q", status.URL)
	}
	if !status.NeedsAuthtoken {
		t.Error("ERR_NGROK_4018 must flag that the authtoken dialog is wanted")
	}
	if status.Error == "" {
		t.Error("want ngrok's own message carried through")
	}
}

func TestFallbackOnLimitAfterServingSwitchesAndKeepsTheMessage(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Errorf("provider = %q, want cloudflared", status.Provider)
	}
	if status.Error != "account limit exceeded" {
		t.Errorf("error = %q, want the provider's message verbatim", status.Error)
	}
	if status.NeedsAuthtoken {
		t.Error("a quota refusal is not an authtoken problem")
	}
}

func TestFallbackIsStickyAndDoesNotFlapBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)

	before := ngrok.urlCalls
	cloudflared.setHealthy(false)
	time.Sleep(100 * time.Millisecond)
	cloudflared.setHealthy(true)

	if ngrok.urlCalls > before {
		t.Error("a refused provider must not be retried until Disable")
	}
	if got := m.Status().Provider; got != "cloudflared" {
		t.Errorf("provider = %q, want the sticky fallback", got)
	}
}

func TestDisableClearsTheStickyFallback(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}

	before := ngrok.urlCalls
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if ngrok.urlCalls == before {
		t.Error("after Disable, ngrok must be attempted again")
	}
}

func TestNoFallbackWhenBothProvidersAreRefused(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "ngrok refused"})
	cloudflared := newFakeProvider(t, "cloudflared", exitImmediatelyScript)
	cloudflared.setFailure(Failure{Class: FailureRefused, Message: "cloudflared refused"})

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.Status().State == StateFailed {
			if m.Status().Error == "" {
				t.Error("want an error message when every provider is refused")
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("state = %q, want failed", m.Status().State)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run 'Fallback|Sticky|NoFallback' -v`
Expected: FAIL — the stub does nothing, so the manager never switches provider.

- [ ] **Step 3: Replace the `handleProviderRefusal` stub**

```go
func (m *Manager) handleProviderRefusal(ctx context.Context, provider Provider, failure Failure, class FailureClass) {
	m.mu.Lock()
	if !m.enabled {
		m.mu.Unlock()
		return
	}
	m.stickyFrom[provider.Name()] = true
	m.status.URL = ""
	m.status.Error = failure.Message
	if class == FailureCredential {
		m.status.NeedsAuthtoken = true
	}
	m.status.State = StateStarting
	remaining := 0
	for _, candidate := range m.providers {
		if !m.stickyFrom[candidate.Name()] {
			remaining++
		}
	}
	m.mu.Unlock()
	m.onProvider("")

	m.log.Warn("tunnel provider refused; falling back",
		"provider", provider.Name(), "class", class, "err", failure.Message)

	if remaining == 0 {
		m.mu.Lock()
		m.status.State = StateFailed
		if m.status.Error == "" {
			m.status.Error = "no tunnel provider available"
		}
		m.mu.Unlock()
		return
	}

	if err := m.startFirstWorkingProvider(ctx); err != nil {
		m.mu.Lock()
		m.status.State = StateFailed
		m.status.Error = err.Error()
		m.mu.Unlock()
	}
}
```

`handleProviderRefusal` runs on the supervise goroutine, which is returning
immediately after this call — so `startFirstWorkingProvider` installs a fresh
`cmd`/`cancel`/`done` for the new provider without racing the old supervisor.
Preserve the `return` after the call in `supervise`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run 'Fallback|Sticky|NoFallback' -v`
Expected: PASS — all 5 tests.

- [ ] **Step 5: Run the full package**

Run: `cd backend && go test -race ./internal/tunnel/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): fall back between providers by failure shape"
```

---

### Task 6: PID registry and orphan reaping

**Files:**
- Create: `backend/internal/tunnel/registry.go`
- Modify: `backend/internal/tunnel/manager.go` (`recordPID`, plus a `Reap` call site)
- Test: `backend/internal/tunnel/registry_test.go`

**Interfaces:**
- Consumes: `Manager`, `forceKillPID`, `processStartTime` (Tasks 3–4).
- Produces: `(*Manager).Reap()`, called by the daemon before any `Enable`; `registryPath(dir string) string`; `persistedTunnel{Provider string, PID int, StartTime string, StartedAt time.Time}`.

An unreaped tunnel child is a public URL that outlived the app that created it
(spec §4), so this is not optional.

- [ ] **Step 1: Write the failing tests**

```go
package tunnel

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestReapRemovesTheRegistryFile(t *testing.T) {
	dir := t.TempDir()
	path := registryPath(dir)
	body, err := json.Marshal([]persistedTunnel{{Provider: "ngrok", PID: 999999, StartTime: "Fri Sep 12 18:00:00 2026"}})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := os.WriteFile(path, body, 0o600); err != nil {
		t.Fatalf("seed registry: %v", err)
	}

	New(Deps{Dir: dir}).Reap()

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("registry still present: %v", err)
	}
}

func TestReapSkipsEntriesWithoutARecordedStartTime(t *testing.T) {
	dir := t.TempDir()
	body, err := json.Marshal([]persistedTunnel{{Provider: "ngrok", PID: os.Getpid()}})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if err := os.WriteFile(registryPath(dir), body, 0o600); err != nil {
		t.Fatalf("seed registry: %v", err)
	}

	New(Deps{Dir: dir}).Reap()

	if _, err := os.Stat(registryPath(dir)); !os.IsNotExist(err) {
		t.Error("registry should be cleared even when entries are skipped")
	}
}

func TestReapToleratesAMissingRegistry(t *testing.T) {
	New(Deps{Dir: t.TempDir()}).Reap()
}

func TestReapToleratesACorruptRegistry(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(registryPath(dir), []byte("{not json"), 0o600); err != nil {
		t.Fatalf("seed registry: %v", err)
	}
	New(Deps{Dir: dir}).Reap()
}

func TestRecordPIDWritesTheRegistry(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	dir := t.TempDir()
	m := New(Deps{
		Dir:         dir,
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)

	body, err := os.ReadFile(filepath.Join(dir, "tunnel-processes.json"))
	if err != nil {
		t.Fatalf("read registry: %v", err)
	}
	var entries []persistedTunnel
	if err := json.Unmarshal(body, &entries); err != nil {
		t.Fatalf("decode registry: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("entries = %d, want 1", len(entries))
	}
	if entries[0].PID <= 0 || entries[0].Provider != "ngrok" {
		t.Errorf("entry = %+v", entries[0])
	}
	if entries[0].StartTime == "" {
		t.Error("StartTime must be recorded, or reaping cannot verify PID identity")
	}
}
```

Add `"context"` to the import block alongside the others.

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run 'Reap|RecordPID' -v`
Expected: FAIL — `undefined: registryPath`, `undefined: persistedTunnel`, `Reap` undefined.

- [ ] **Step 3: Write `registry.go`**

```go
package tunnel

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type persistedTunnel struct {
	Provider  string    `json:"provider"`
	PID       int       `json:"pid"`
	StartTime string    `json:"startTime,omitempty"`
	StartedAt time.Time `json:"startedAt"`
}

func registryPath(dir string) string { return filepath.Join(dir, "tunnel-processes.json") }

func (m *Manager) Reap() {
	path := registryPath(m.dir)
	body, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	if err != nil {
		m.log.Warn("read tunnel process registry", "err", err)
		return
	}
	var entries []persistedTunnel
	if err := json.Unmarshal(body, &entries); err != nil {
		m.log.Warn("decode tunnel process registry", "err", err)
		if removeErr := os.Remove(path); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
			m.log.Warn("remove tunnel process registry", "err", removeErr)
		}
		return
	}
	for _, entry := range entries {
		if entry.PID <= 0 {
			continue
		}
		if entry.StartTime == "" {
			m.log.Warn("skip reaping tunnel process without a recorded start time",
				"provider", entry.Provider, "pid", entry.PID)
			continue
		}
		if err := forceKillPID(entry.PID, entry.StartTime); err != nil {
			m.log.Warn("reap orphaned tunnel process",
				"provider", entry.Provider, "pid", entry.PID, "err", err)
		}
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		m.log.Warn("remove stale tunnel process registry", "err", err)
	}
}

func (m *Manager) writeRegistry(entries []persistedTunnel) {
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		m.log.Warn("create tunnel state dir", "err", err)
		return
	}
	body, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		m.log.Warn("encode tunnel process registry", "err", err)
		return
	}
	if err := os.WriteFile(registryPath(m.dir), body, 0o600); err != nil {
		m.log.Warn("write tunnel process registry", "err", err)
	}
}

func (m *Manager) clearRegistry() {
	if err := os.Remove(registryPath(m.dir)); err != nil && !errors.Is(err, os.ErrNotExist) {
		m.log.Warn("clear tunnel process registry", "err", err)
	}
}

func pidEntry(provider string, cmd *exec.Cmd, now time.Time) (persistedTunnel, bool) {
	if cmd == nil || cmd.Process == nil {
		return persistedTunnel{}, false
	}
	pid := cmd.Process.Pid
	return persistedTunnel{
		Provider:  provider,
		PID:       pid,
		StartTime: processStartTime(pid),
		StartedAt: now,
	}, true
}
```

- [ ] **Step 4: Replace the `recordPID` stub in `manager.go`**

```go
func (m *Manager) recordPID(providerName string, cmd *exec.Cmd) {
	entry, ok := pidEntry(providerName, cmd, m.now())
	if !ok {
		return
	}
	m.writeRegistry([]persistedTunnel{entry})
}
```

And clear the registry when the tunnel stops — add `m.clearRegistry()` to `Disable`, immediately after the status is set to `StateOff`:

```go
	m.mu.Lock()
	m.status = Status{State: StateOff}
	m.mu.Unlock()
	m.clearRegistry()
	m.onProvider("")
	return nil
```

- [ ] **Step 5: Run to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run 'Reap|RecordPID' -v`
Expected: PASS — all 5 tests.

- [ ] **Step 6: Run the whole package and the linter**

Run: `cd backend && go test -race ./internal/tunnel/ && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs ./internal/tunnel/...`
Expected: PASS, no findings.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/tunnel
git commit -m "feat(tunnel): persist child pids and reap orphans across restarts"
```

---

## Phase 2 — Backend wiring and the HTTP surface

### Task 7: Persisted tunnel intent and the long password

**Files:**
- Modify: `backend/internal/mobilebridge/config.go:27` (State), `:91` (`GeneratePassword`)
- Test: `backend/internal/mobilebridge/config_test.go`

**Interfaces:**
- Consumes: nothing from Phase 1.
- Produces: `State.TunnelEnabled bool` (JSON `tunnelEnabled`); `GeneratePasswordN(n int) (string, error)`; `TunnelPasswordLength = 22`; `GeneratePassword()` unchanged in behavior (8 chars).

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/mobilebridge/config_test.go`:

```go
func TestGeneratePasswordNLength(t *testing.T) {
	got, err := GeneratePasswordN(TunnelPasswordLength)
	if err != nil {
		t.Fatalf("GeneratePasswordN: %v", err)
	}
	if len(got) != TunnelPasswordLength {
		t.Errorf("len = %d, want %d", len(got), TunnelPasswordLength)
	}
	for _, r := range got {
		if !strings.ContainsRune(pwAlphabet, r) {
			t.Errorf("password contains %q, outside the alphabet", r)
		}
	}
}

func TestGeneratePasswordStillReturnsEightChars(t *testing.T) {
	got, err := GeneratePassword()
	if err != nil {
		t.Fatalf("GeneratePassword: %v", err)
	}
	if len(got) != 8 {
		t.Errorf("len = %d, want 8 — the LAN default must not change", len(got))
	}
}

func TestTunnelPasswordIsLongEnoughToFacePublicInternet(t *testing.T) {
	if TunnelPasswordLength < 20 {
		t.Fatalf("TunnelPasswordLength = %d; a public URL needs materially more than the 8-char LAN password", TunnelPasswordLength)
	}
}

func TestSaveAndLoadRoundTripTunnelEnabled(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := Save(path, State{Enabled: true, Password: "pw", LastPort: 3011, TunnelEnabled: true}); err != nil {
		t.Fatalf("Save: %v", err)
	}
	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !got.TunnelEnabled {
		t.Error("TunnelEnabled must survive a save/load round trip")
	}
}

func TestLoadDefaultsTunnelEnabledToFalseForOldConfigs(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"enabled":true,"password":"pw","lastPort":3011}`), 0o600); err != nil {
		t.Fatalf("seed config: %v", err)
	}
	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got.TunnelEnabled {
		t.Error("a config written before this feature must not imply a public tunnel")
	}
}
```

Ensure the test file imports `os`, `path/filepath`, and `strings`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/mobilebridge/ -run 'Password|TunnelEnabled' -v`
Expected: FAIL — `undefined: GeneratePasswordN`, `unknown field TunnelEnabled`.

- [ ] **Step 3: Add the field and the generator**

In `backend/internal/mobilebridge/config.go`, extend `State`:

```go
type State struct {
	Enabled       bool   `json:"enabled"`
	Password      string `json:"password"`
	LastPort      int    `json:"lastPort"`
	TunnelEnabled bool   `json:"tunnelEnabled"`
}
```

Replace `GeneratePassword` with the parameterized pair:

```go
const TunnelPasswordLength = 22

func GeneratePassword() (string, error) { return GeneratePasswordN(8) }

func GeneratePasswordN(n int) (string, error) {
	if n <= 0 {
		return "", fmt.Errorf("mobilebridge: password length must be positive, got %d", n)
	}
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	for i, b := range buf {
		buf[i] = pwAlphabet[int(b)%len(pwAlphabet)]
	}
	return string(buf), nil
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && go test ./internal/mobilebridge/ -v`
Expected: PASS, including the pre-existing tests.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/mobilebridge
git commit -m "feat(mobilebridge): persist tunnel intent and add a long tunnel password"
```

---

### Task 8: Proxy-aware lockout

**Files:**
- Modify: `backend/internal/httpd/auth.go:77` (`sourceKey`), `:168` (`authMiddleware`), `backend/internal/httpd/lan_listener.go:34` (`NewLANManager`), `:108` (LANManager methods)
- Test: `backend/internal/httpd/auth_test.go`

**Interfaces:**
- Consumes: `Manager.Deps.OnProvider` (Task 3) — the daemon wires it to `LANManager.SetTrustedForwardHeader` in Task 10.
- Produces: `forwardedTrust` with `Set(header string)` and `header() string`; `sourceKey(r *http.Request, trust *forwardedTrust) string`; `(*LANManager).SetTrustedForwardHeader(name string)`, which satisfies a new method on `controllers.LANController`.

Without this, every tunneled request arrives from `127.0.0.1` and collapses the
5-fails-per-minute lockout into one shared bucket — a stranger who finds the URL
could lock the owner's phone out (spec §9).

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/httpd/auth_test.go`:

```go
func TestSourceKeyUsesRemoteAddrByDefault(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "192.168.1.44:52133"
	if got := sourceKey(req, &forwardedTrust{}); got != "192.168.1.44" {
		t.Errorf("got %q, want 192.168.1.44", got)
	}
}

func TestSourceKeyHonorsForwardedHeaderFromLoopback(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("Cf-Connecting-Ip")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	if got := sourceKey(req, trust); got != "203.0.113.9" {
		t.Errorf("got %q, want the forwarded client ip", got)
	}
}

func TestSourceKeyIgnoresForwardedHeaderFromNonLoopback(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "192.168.1.44:52133"
	req.Header.Set("X-Forwarded-For", "203.0.113.9")

	if got := sourceKey(req, trust); got != "192.168.1.44" {
		t.Errorf("got %q — a LAN client must not be able to forge its lockout bucket", got)
	}
}

func TestSourceKeyIgnoresForwardedHeaderWhenNoTunnelIsLive(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("X-Forwarded-For", "203.0.113.9")

	if got := sourceKey(req, &forwardedTrust{}); got != "127.0.0.1" {
		t.Errorf("got %q, want 127.0.0.1 when no tunnel is running", got)
	}
}

func TestSourceKeyTakesFirstEntryOfMultiValuedForwardedFor(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("X-Forwarded-For", "203.0.113.9, 70.41.3.18, 150.172.238.178")

	if got := sourceKey(req, trust); got != "203.0.113.9" {
		t.Errorf("got %q, want the left-most (client) entry", got)
	}
}

func TestSourceKeyFallsBackWhenForwardedHeaderIsEmptyOrJunk(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("X-Forwarded-For")

	for name, value := range map[string]string{"empty": "", "commas": " , ,"} {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
		req.RemoteAddr = "127.0.0.1:41111"
		req.Header.Set("X-Forwarded-For", value)
		if got := sourceKey(req, trust); got != "127.0.0.1" {
			t.Errorf("%s: got %q, want the remote addr fallback", name, got)
		}
	}
}

func TestSourceKeySeparatesTwoTunneledClientsIntoDifferentBuckets(t *testing.T) {
	trust := &forwardedTrust{}
	trust.Set("Cf-Connecting-Ip")

	first := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	first.RemoteAddr = "127.0.0.1:41111"
	first.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	second := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	second.RemoteAddr = "127.0.0.1:41112"
	second.Header.Set("Cf-Connecting-Ip", "198.51.100.7")

	if sourceKey(first, trust) == sourceKey(second, trust) {
		t.Error("two tunneled clients must not share one lockout bucket")
	}
}

func TestLANManagerSetTrustedForwardHeaderReachesAuth(t *testing.T) {
	manager := NewMobileLAN(http.NotFoundHandler(), 0, nil, nil)
	manager.SetTrustedForwardHeader("Cf-Connecting-Ip")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/sessions", nil)
	req.RemoteAddr = "127.0.0.1:41111"
	req.Header.Set("Cf-Connecting-Ip", "203.0.113.9")

	if got := sourceKey(req, manager.forwarded); got != "203.0.113.9" {
		t.Errorf("got %q, want the header set through the manager", got)
	}

	manager.SetTrustedForwardHeader("")
	if got := sourceKey(req, manager.forwarded); got != "127.0.0.1" {
		t.Errorf("got %q, want trust cleared when the tunnel stops", got)
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/httpd/ -run 'SourceKey|TrustedForward' -v`
Expected: FAIL — `undefined: forwardedTrust`, and `sourceKey` takes one argument.

- [ ] **Step 3: Add `forwardedTrust` and rewrite `sourceKey` in `auth.go`**

```go
type forwardedTrust struct {
	name atomic.Pointer[string]
}

func (f *forwardedTrust) Set(header string) { f.name.Store(&header) }

func (f *forwardedTrust) header() string {
	if p := f.name.Load(); p != nil {
		return *p
	}
	return ""
}

func sourceKey(r *http.Request, trust *forwardedTrust) string {
	remote := r.RemoteAddr
	if host, _, err := net.SplitHostPort(remote); err == nil {
		remote = host
	}
	header := ""
	if trust != nil {
		header = trust.header()
	}
	if header == "" || !isLoopbackAddress(remote) {
		return remote
	}
	for _, part := range strings.Split(r.Header.Get(header), ",") {
		if candidate := strings.TrimSpace(part); candidate != "" {
			return candidate
		}
	}
	return remote
}

func isLoopbackAddress(host string) bool {
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
```

- [ ] **Step 4: Thread the trust through `authMiddleware`**

Change the signature and the one `sourceKey` call inside it:

```go
func authMiddleware(state *authState, lock *lockout, connected *mobileConnectReporter, trust *forwardedTrust) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			src := sourceKey(r, trust)
```

The rest of the body is unchanged.

- [ ] **Step 5: Own the trust on `LANManager`**

In `lan_listener.go`, add the field, construct it, and expose the setter:

```go
type LANManager struct {
	handler     http.Handler
	defaultPort int
	log         *slog.Logger
	state       *authState
	forwarded   *forwardedTrust

	mu    sync.Mutex
	srv   *http.Server
	ln    net.Listener
	bound int
}

func NewLANManager(handler http.Handler, state *authState, defaultPort int, log *slog.Logger, sink ports.EventSink) *LANManager {
	lock := newLockout(5, time.Minute, time.Now)
	trust := &forwardedTrust{}
	return &LANManager{
		handler:     lanControlBlock(authMiddleware(state, lock, newMobileConnectReporter(sink, time.Now), trust)(handler)),
		defaultPort: defaultPort,
		log:         loggerOrDefault(log),
		state:       state,
		forwarded:   trust,
	}
}

func (m *LANManager) SetTrustedForwardHeader(name string) {
	m.forwarded.Set(name)
}
```

- [ ] **Step 6: Fix every other `authMiddleware` / `sourceKey` caller**

Run: `cd backend && grep -rn "authMiddleware(\|sourceKey(" internal/ | grep -v "_test.go"`
Update each hit to pass the new argument. Then run the same grep including tests and update those call sites too.

- [ ] **Step 7: Run to verify they pass**

Run: `cd backend && go test ./internal/httpd/ -v -run 'SourceKey|TrustedForward|Lockout|Auth'`
Expected: PASS, with the existing auth and lockout tests still green.

- [ ] **Step 8: Run the whole backend**

Run: `cd backend && go test ./...`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend/internal/httpd
git commit -m "feat(httpd): key the lockout on the real client ip when tunneled"
```

---

### Task 9: Tunnel endpoints and the status field

**Files:**
- Modify: `backend/internal/httpd/controllers/dto.go:1356`, `backend/internal/httpd/controllers/mobile.go`, `backend/internal/httpd/router.go:139`, `backend/internal/httpd/apispec/specgen/build.go:144` and `:735`
- Test: `backend/internal/httpd/controllers/mobile_test.go`, `backend/internal/httpd/mobile_routes_test.go`

**Interfaces:**
- Consumes: `tunnel.Status`, `tunnel.State*` (Task 1); `mobilebridge.State.TunnelEnabled`, `GeneratePasswordN`, `TunnelPasswordLength` (Task 7).
- Produces: `MobileTunnelStatus{State,Provider,URL,Error,Since,Restarts,NeedsAuthtoken,HasAuthtoken}`; `MobileStatusResponse.Tunnel *MobileTunnelStatus`; `MobileAuthtokenRequest{Token string}`; `TunnelController` interface; `BridgeService.Tunnel`; controller methods `TunnelEnable`, `TunnelDisable`, `SetAuthtoken`; routes `POST /api/v1/mobile/tunnel/{enable,disable,authtoken}`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/httpd/controllers/mobile_test.go`:

```go
type fakeTunnel struct {
	status         tunnel.Status
	enableErr      error
	enabled        bool
	disabled       bool
	savedToken     string
	saveTokenErr   error
	hasAuthtokenOn bool
}

func (f *fakeTunnel) Enable(context.Context) error {
	if f.enableErr != nil {
		return f.enableErr
	}
	f.enabled = true
	f.status = tunnel.Status{State: tunnel.StateLive, Provider: "ngrok", URL: "https://x.ngrok-free.dev"}
	return nil
}

func (f *fakeTunnel) Disable(context.Context) error {
	f.disabled = true
	f.status = tunnel.Status{State: tunnel.StateOff}
	return nil
}

func (f *fakeTunnel) Status() tunnel.Status { return f.status }

func (f *fakeTunnel) SetAuthtoken(_ context.Context, token string) error {
	if f.saveTokenErr != nil {
		return f.saveTokenErr
	}
	f.savedToken = token
	f.hasAuthtokenOn = true
	return nil
}

func (f *fakeTunnel) HasAuthtoken() bool { return f.hasAuthtokenOn }

func TestStatusCarriesTunnelStateAndNeverThePassword(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{status: tunnel.Status{
		State: tunnel.StateLive, Provider: "cloudflared",
		URL: "https://a.trycloudflare.com", Restarts: 2, NeedsAuthtoken: true,
	}}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	got := bridge.Status()
	if got.Tunnel == nil {
		t.Fatal("Tunnel must be present in the status")
	}
	if got.Tunnel.State != "live" || got.Tunnel.Provider != "cloudflared" {
		t.Errorf("tunnel = %+v", got.Tunnel)
	}
	if got.Tunnel.URL != "https://a.trycloudflare.com" {
		t.Errorf("URL = %q", got.Tunnel.URL)
	}
	if got.Tunnel.Restarts != 2 || !got.Tunnel.NeedsAuthtoken {
		t.Errorf("tunnel = %+v", got.Tunnel)
	}
}

func TestTunnelEnableRotatesToTheLongPasswordAndPersistsIntent(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "short12", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	got, err := bridge.TunnelEnable()
	if err != nil {
		t.Fatalf("TunnelEnable: %v", err)
	}
	if len(got.Password) != mobilebridge.TunnelPasswordLength {
		t.Errorf("password length = %d, want %d", len(got.Password), mobilebridge.TunnelPasswordLength)
	}
	if !tun.enabled {
		t.Error("the tunnel manager was not started")
	}
	state, err := mobilebridge.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !state.TunnelEnabled {
		t.Error("tunnel intent must be persisted so it survives a restart")
	}
	if len(state.Password) != mobilebridge.TunnelPasswordLength {
		t.Error("the rotated password must be persisted")
	}
}

func TestTunnelEnableRefusesWhileTheBridgeIsOff(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	bridge := &BridgeService{LAN: &fakeLAN{running: false}, ConfigPath: path, DefaultPort: 3011, Tunnel: &fakeTunnel{}}

	if _, err := bridge.TunnelEnable(); err == nil {
		t.Fatal("want an error: a tunnel to a listener that is not running is meaningless")
	}
}

func TestTunnelDisableClearsIntentButKeepsTheBridge(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011, TunnelEnabled: true}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	if _, err := bridge.TunnelDisable(); err != nil {
		t.Fatalf("TunnelDisable: %v", err)
	}
	if !tun.disabled {
		t.Error("the tunnel manager was not stopped")
	}
	state, err := mobilebridge.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if state.TunnelEnabled {
		t.Error("tunnel intent must be cleared")
	}
	if !state.Enabled {
		t.Error("disabling the tunnel must not disable the LAN bridge")
	}
}

func TestWarningNamesPublicExposureWhileTunneled(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	live := &BridgeService{
		LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011,
		Tunnel: &fakeTunnel{status: tunnel.Status{State: tunnel.StateLive, Provider: "ngrok"}},
	}
	lanOnly := &BridgeService{
		LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011,
		Tunnel: &fakeTunnel{status: tunnel.Status{State: tunnel.StateOff}},
	}

	if live.Status().Warning == lanOnly.Status().Warning {
		t.Error("the tunneled warning must differ from the plaintext-LAN warning")
	}
	if strings.Contains(live.Status().Warning, "not encrypted") {
		t.Error("a tunneled connection is HTTPS; the plaintext warning is wrong there")
	}
}

func TestSetAuthtokenRejectsBlankAndNeverEchoesTheToken(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	if _, err := bridge.SetAuthtoken("   "); err == nil {
		t.Fatal("want an error for a blank token")
	}

	got, err := bridge.SetAuthtoken("2abc_secretTokenValue")
	if err != nil {
		t.Fatalf("SetAuthtoken: %v", err)
	}
	if tun.savedToken != "2abc_secretTokenValue" {
		t.Errorf("saved token = %q", tun.savedToken)
	}
	encoded, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if strings.Contains(string(encoded), "2abc_secretTokenValue") {
		t.Fatal("the authtoken must never appear in an API response")
	}
	if got.Tunnel == nil || !got.Tunnel.HasAuthtoken {
		t.Error("status should report that a token is now present")
	}
}
```

If `fakeLAN` does not already exist in this test file, add it mirroring the
`LANController` interface (`backend/internal/httpd/controllers/mobile.go:70`),
including the new `SetTrustedForwardHeader(string)` no-op method. Add imports:
`context`, `encoding/json`, `path/filepath`, `strings`, and the `mobilebridge`
and `tunnel` packages.

Append to `backend/internal/httpd/mobile_routes_test.go`, following the shape of
the existing route tests there:

```go
func TestTunnelRoutesAre404OnTheLANListener(t *testing.T) {
	for _, path := range []string{
		"/api/v1/mobile/tunnel/enable",
		"/api/v1/mobile/tunnel/disable",
		"/api/v1/mobile/tunnel/authtoken",
	} {
		if !isLANControlBlockedPath(path) {
			t.Errorf("%s must be blocked on the LAN listener", path)
		}
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/httpd/... -run 'Tunnel|Authtoken|Warning' -v`
Expected: FAIL — `unknown field Tunnel`, `undefined: MobileTunnelStatus`.

- [ ] **Step 3: Add the DTOs**

In `backend/internal/httpd/controllers/dto.go`, replace `MobileStatusResponse` and add the two new types:

```go
type MobileStatusResponse struct {
	Enabled  bool                `json:"enabled"`
	Host     string              `json:"host"`
	Port     int                 `json:"port"`
	Password string              `json:"password"`
	Warning  string              `json:"warning"`
	Tunnel   *MobileTunnelStatus `json:"tunnel,omitempty"`
}

type MobileTunnelStatus struct {
	State          string `json:"state" description:"off, downloading, starting, live, reconnecting or failed."`
	Provider       string `json:"provider" description:"ngrok or cloudflared; empty while off."`
	URL            string `json:"url" description:"Public HTTPS origin; empty unless live."`
	Error          string `json:"error" description:"The provider's own message when something went wrong."`
	Since          string `json:"since,omitempty" description:"RFC3339 timestamp of the current live tunnel."`
	Restarts       int    `json:"restarts" description:"Reconnect count for the current enable."`
	NeedsAuthtoken bool   `json:"needsAuthtoken" description:"True when ngrok rejected the credential and the dialog should open."`
	HasAuthtoken   bool   `json:"hasAuthtoken" description:"Whether an ngrok authtoken is stored. Never carries the token itself."`
}

type MobileAuthtokenRequest struct {
	Token string `json:"token" description:"ngrok authtoken. Stored via ngrok's own config tooling; never echoed back."`
}
```

- [ ] **Step 4: Extend the controller**

In `backend/internal/httpd/controllers/mobile.go`, add the warning constant, widen the interfaces, and add the methods:

```go
const mobileTunnelWarning = "This desktop is reachable from the internet. Anyone with the address and password can start agents and run terminal commands here."

type mobileBridge interface {
	Status() MobileStatusResponse
	Enable() (MobileStatusResponse, error)
	Disable() error
	Regenerate() (MobileStatusResponse, error)
	TunnelEnable() (MobileStatusResponse, error)
	TunnelDisable() (MobileStatusResponse, error)
	SetAuthtoken(token string) (MobileStatusResponse, error)
}

type TunnelController interface {
	Enable(ctx context.Context) error
	Disable(ctx context.Context) error
	Status() tunnel.Status
	SetAuthtoken(ctx context.Context, token string) error
	HasAuthtoken() bool
}
```

Add `SetTrustedForwardHeader(name string)` to the `LANController` interface, and
`Tunnel TunnelController` to `BridgeService`.

`withWarning` becomes tunnel-aware, so replace it:

```go
func withWarning(res MobileStatusResponse) MobileStatusResponse {
	if res.Tunnel != nil && res.Tunnel.State == string(tunnel.StateLive) {
		res.Warning = mobileTunnelWarning
		return res
	}
	res.Warning = mobileUnencryptedWarning
	return res
}
```

Add the three handlers next to the existing four:

```go
func (c *MobileController) TunnelEnable(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.TunnelEnable()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_TUNNEL_ENABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) TunnelDisable(w http.ResponseWriter, r *http.Request) {
	res, err := c.Bridge.TunnelDisable()
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusInternalServerError, "internal", "MOBILE_TUNNEL_DISABLE", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}

func (c *MobileController) SetAuthtoken(w http.ResponseWriter, r *http.Request) {
	var body MobileAuthtokenRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_AUTHTOKEN_BODY", "malformed request body", nil)
		return
	}
	res, err := c.Bridge.SetAuthtoken(body.Token)
	if err != nil {
		envelope.WriteAPIError(w, r, http.StatusBadRequest, "invalid_request", "MOBILE_AUTHTOKEN", err.Error(), nil)
		return
	}
	envelope.WriteJSON(w, http.StatusOK, withWarning(res))
}
```

Add the `BridgeService` implementations:

```go
func (b *BridgeService) tunnelStatus() *MobileTunnelStatus {
	if b.Tunnel == nil {
		return nil
	}
	st := b.Tunnel.Status()
	out := &MobileTunnelStatus{
		State:          string(st.State),
		Provider:       st.Provider,
		URL:            st.URL,
		Error:          st.Error,
		Restarts:       st.Restarts,
		NeedsAuthtoken: st.NeedsAuthtoken,
		HasAuthtoken:   b.Tunnel.HasAuthtoken(),
	}
	if !st.Since.IsZero() {
		out.Since = st.Since.UTC().Format(time.RFC3339)
	}
	return out
}

func (b *BridgeService) TunnelEnable() (MobileStatusResponse, error) {
	if !b.LAN.Running() {
		return MobileStatusResponse{}, errors.New("enable mobile access before making it reachable from the internet")
	}
	pw, err := mobilebridge.GeneratePasswordN(mobilebridge.TunnelPasswordLength)
	if err != nil {
		return MobileStatusResponse{}, err
	}
	if _, err := b.enableWithPassword(pw); err != nil {
		return MobileStatusResponse{}, err
	}
	if err := b.setTunnelIntent(true); err != nil {
		return MobileStatusResponse{}, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := b.Tunnel.Enable(ctx); err != nil {
		return b.Status(), nil
	}
	return b.Status(), nil
}

func (b *BridgeService) TunnelDisable() (MobileStatusResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := b.Tunnel.Disable(ctx); err != nil {
		return MobileStatusResponse{}, err
	}
	if err := b.setTunnelIntent(false); err != nil {
		return MobileStatusResponse{}, err
	}
	return b.Status(), nil
}

func (b *BridgeService) SetAuthtoken(token string) (MobileStatusResponse, error) {
	trimmed := strings.TrimSpace(token)
	if trimmed == "" {
		return MobileStatusResponse{}, errors.New("authtoken must not be empty")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	if err := b.Tunnel.SetAuthtoken(ctx, trimmed); err != nil {
		return MobileStatusResponse{}, err
	}
	return b.Status(), nil
}

func (b *BridgeService) setTunnelIntent(on bool) error {
	st, err := mobilebridge.Load(b.ConfigPath)
	if err != nil {
		return err
	}
	st.TunnelEnabled = on
	return mobilebridge.Save(b.ConfigPath, st)
}
```

Finally, add `res.Tunnel = b.tunnelStatus()` inside `BridgeService.Status()` before it returns.

`TunnelEnable` deliberately returns `b.Status(), nil` when `Tunnel.Enable`
errors: the manager has already recorded `StateFailed` with the provider's own
message, and that is more useful to the dialog than a 500 that discards it.

- [ ] **Step 5: Mount the routes**

In `backend/internal/httpd/router.go`, inside `mountMobile`:

```go
	r.Post("/api/v1/mobile/tunnel/enable", c.TunnelEnable)
	r.Post("/api/v1/mobile/tunnel/disable", c.TunnelDisable)
	r.Post("/api/v1/mobile/tunnel/authtoken", c.SetAuthtoken)
```

No change to `lanControlBlockedPrefixes` is needed — `/api/v1/mobile` already
covers the new paths, which the route test above asserts.

- [ ] **Step 6: Register the operations and schema names**

In `backend/internal/httpd/apispec/specgen/build.go`, add to `schemaNames`:

```go
	"ControllersMobileTunnelStatus":   "MobileTunnelStatus",
	"ControllersMobileAuthtokenRequest": "MobileAuthtokenRequest",
```

And add three operations after the existing mobile block:

```go
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/enable", id: "enableMobileTunnel", tag: "mobile",
			summary: "Make the Connect Mobile bridge reachable from the internet",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/disable", id: "disableMobileTunnel", tag: "mobile",
			summary: "Stop the public tunnel, leaving the LAN bridge running",
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusForbidden, envelope.APIError{}},
				{http.StatusInternalServerError, envelope.APIError{}},
			},
		},
		{
			method: http.MethodPost, path: "/api/v1/mobile/tunnel/authtoken", id: "setMobileTunnelAuthtoken", tag: "mobile",
			summary: "Store an ngrok authtoken for a stable tunnel address",
			req:     controllers.MobileAuthtokenRequest{},
			resps: []respUnit{
				{http.StatusOK, controllers.MobileStatusResponse{}},
				{http.StatusBadRequest, envelope.APIError{}},
				{http.StatusForbidden, envelope.APIError{}},
			},
		},
```

Check the neighbouring entries for the exact field name used for a request body
(`req` above) and match it; if the registry spells it differently, use that spelling.

- [ ] **Step 7: Regenerate the API artifacts**

Run: `npm run api`
Expected: `backend/internal/httpd/apispec/openapi.yaml` and `frontend/src/api/schema.ts` both change. If `api:spec` fails, the `schemaNames` entry is missing or misspelled.

- [ ] **Step 8: Run to verify they pass**

Run: `cd backend && go test ./internal/httpd/...`
Expected: PASS, including the spec-drift and route/spec parity tests.

- [ ] **Step 9: Commit**

```bash
git add backend/internal/httpd backend/internal/httpd/apispec/openapi.yaml frontend/src/api/schema.ts
git commit -m "feat(httpd): add tunnel enable/disable/authtoken routes and status"
```

---

### Task 10: Daemon wiring, auto-start on boot, shutdown

**Files:**
- Modify: `backend/internal/daemon/daemon.go:251` and `:402`, `backend/internal/daemon/mobile_restore.go`
- Test: `backend/internal/daemon/mobile_restore_test.go`

**Interfaces:**
- Consumes: `tunnel.New`, `tunnel.NewStore`, `tunnel.NgrokProvider`, `tunnel.CloudflaredProvider`, `(*Manager).Reap`, `(*Manager).SetLocalPort` (Tasks 1–6); `controllers.BridgeService.Tunnel`, `LANController.SetTrustedForwardHeader` (Tasks 8–9).
- Produces: `restoreMobileOnBoot(path string, lan controllers.LANController, tun tunnelStarter) error` — one extra parameter; `tunnelStarter` interface local to the daemon package with `Enable(context.Context) error`.

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/daemon/mobile_restore_test.go`:

```go
type fakeTunnelStarter struct {
	enabled int
	err     error
}

func (f *fakeTunnelStarter) Enable(context.Context) error {
	f.enabled++
	return f.err
}

func TestRestoreStartsTheTunnelWhenPersistedEnabled(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{
		Enabled: true, Password: "pw", LastPort: 3011, TunnelEnabled: true,
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	lan := &fakeLAN{}
	starter := &fakeTunnelStarter{}

	if err := restoreMobileOnBoot(path, lan, starter); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if starter.enabled != 1 {
		t.Errorf("tunnel enabled %d times, want 1 — the user must not have to be at the desk", starter.enabled)
	}
}

func TestRestoreLeavesTheTunnelOffWhenNotPersisted(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	starter := &fakeTunnelStarter{}

	if err := restoreMobileOnBoot(path, &fakeLAN{}, starter); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if starter.enabled != 0 {
		t.Error("a tunnel must never start unless it was explicitly enabled before")
	}
}

func TestRestoreDoesNotStartTheTunnelWhenTheBridgeIsOff(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: false, TunnelEnabled: true}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	starter := &fakeTunnelStarter{}

	if err := restoreMobileOnBoot(path, &fakeLAN{}, starter); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if starter.enabled != 0 {
		t.Error("no bridge means nothing to tunnel to")
	}
}

func TestRestoreSurfacesButSurvivesATunnelStartFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{
		Enabled: true, Password: "pw", LastPort: 3011, TunnelEnabled: true,
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	starter := &fakeTunnelStarter{err: errors.New("no binary")}

	err := restoreMobileOnBoot(path, &fakeLAN{}, starter)
	if err == nil {
		t.Fatal("want the failure reported so the caller can log it")
	}
	if !strings.Contains(err.Error(), "no binary") {
		t.Errorf("err = %v, want the cause preserved", err)
	}
}
```

Reuse the `fakeLAN` already in this package's tests; add
`SetTrustedForwardHeader(string)` to it as a no-op. Add imports: `context`,
`errors`, `strings`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/daemon/ -run Restore -v`
Expected: FAIL — `restoreMobileOnBoot` takes two arguments.

- [ ] **Step 3: Extend `mobile_restore.go`**

```go
package daemon

import (
	"context"
	"fmt"

	"github.com/OmarAly92/operator/backend/internal/httpd/controllers"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

type tunnelStarter interface {
	Enable(ctx context.Context) error
}

func restoreMobileOnBoot(path string, lan controllers.LANController, tun tunnelStarter) error {
	state, err := mobilebridge.Load(path)
	if err != nil {
		return fmt.Errorf("load mobile bridge state: %w", err)
	}
	if !state.Enabled {
		return nil
	}
	lan.SetPasswordHash(mobilebridge.HashPassword(state.Password))
	if _, err := lan.Start(state.LastPort); err != nil {
		return fmt.Errorf("restart mobile LAN listener: %w", err)
	}
	if !state.TunnelEnabled || tun == nil {
		return nil
	}
	if err := tun.Enable(context.Background()); err != nil {
		return fmt.Errorf("restart mobile tunnel: %w", err)
	}
	return nil
}
```

- [ ] **Step 4: Construct and wire the manager in `daemon.go`**

Beside the existing `bs := &controllers.BridgeService{...}` at `:251`, build the manager. It must exist before `bs` so it can be assigned, but its `OnProvider` needs `lan`, which only exists at `:402` — so use the same late-binding shape already used for `bs.LAN`:

```go
	tunnelMgr := tunnel.New(tunnel.Deps{
		Log: log,
		Dir: filepath.Join(cfg.DataDir, "mobile"),
		Providers: []tunnel.Provider{
			tunnel.NgrokProvider([]string{filepath.Join(cfg.DataDir, "mobile", "ngrok.yml")}),
			tunnel.CloudflaredProvider(),
		},
		Binaries: tunnel.NewStore(tunnel.StoreDeps{
			Dir: filepath.Join(cfg.DataDir, "bin"),
			Log: log,
		}),
	})
	tunnelMgr.Reap()
	bs := &controllers.BridgeService{
		ConfigPath:  mobilebridge.Path(cfg.DataDir),
		DefaultPort: mobilebridge.DefaultPort,
		Tunnel:      tunnelMgr,
	}
```

`Reap()` runs before anything can start a tunnel, which is the point: it kills a
child left behind by a previous daemon generation before a new one is launched.

Then at `:402`, after `bs.LAN = lan`:

```go
	bs.LAN = lan
	tunnelMgr.SetLocalPort(mobilebridge.DefaultPort)
	tunnelMgr.SetOnProvider(lan.SetTrustedForwardHeader)
```

Add `SetOnProvider(fn func(string))` to `tunnel.Manager` — the callback cannot be
passed in `Deps` because `lan` does not exist yet at construction time:

```go
func (m *Manager) SetOnProvider(fn func(string)) {
	if fn == nil {
		fn = func(string) {}
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onProvider = fn
}
```

Guard every `m.onProvider(...)` call site so it reads the field under the lock
rather than calling while holding it:

```go
func (m *Manager) notifyProvider(header string) {
	m.mu.Lock()
	fn := m.onProvider
	m.mu.Unlock()
	fn(header)
}
```

Replace each `m.onProvider(x)` with `m.notifyProvider(x)`.

- [ ] **Step 5: Update the restore call and add shutdown**

At the `restoreMobileOnBoot` call site (`daemon.go:408`):

```go
	if err := restoreMobileOnBoot(mobilebridge.Path(cfg.DataDir), lan, tunnelMgr); err != nil {
		log.Warn("restore mobile bridge on boot failed", "err", err)
	}
```

Find where the daemon tears down its other long-lived services on shutdown (the
same place `lcStack.Stop()` and `cdcPipe.Stop()` are called) and add
`tunnelMgr.Close()`. A daemon that exits without stopping the tunnel leaves a
public URL alive, which is the failure mode `Reap` exists to clean up — do not
rely on reaping instead of closing.

- [ ] **Step 6: Run to verify they pass**

Run: `cd backend && go test ./internal/daemon/ -run Restore -v`
Expected: PASS — all 4 tests.

- [ ] **Step 7: Run the whole backend with the race detector and the linter**

Run: `cd backend && go test -race ./... && go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.12.2 run --path-mode=abs`
Expected: PASS, no findings.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/daemon backend/internal/tunnel
git commit -m "feat(daemon): supervise the mobile tunnel and restore it on boot"
```

---

### Task 11: Authtoken storage through ngrok's own tooling

**Files:**
- Modify: `backend/internal/tunnel/manager.go` (add `SetAuthtoken`, `HasAuthtoken`)
- Create: `backend/internal/tunnel/authtoken.go`
- Test: `backend/internal/tunnel/authtoken_test.go`

**Interfaces:**
- Consumes: `Manager`, `Deps.Dir`, `BinaryStore` (Tasks 2–3).
- Produces: `(*Manager).SetAuthtoken(ctx context.Context, token string) error`, `(*Manager).HasAuthtoken() bool`, `ngrokConfigPath(dir string) string`. Satisfies `controllers.TunnelController` (Task 9).

Written with `ngrok config add-authtoken TOKEN --config <ours>`, verified to
exist and to accept `--config` (evidence §12), so ngrok owns the credential's
serialization and the user's personal config is never touched (spec §10).

- [ ] **Step 1: Write the failing tests**

```go
package tunnel

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSetAuthtokenInvokesNgrokConfigAddAuthtokenWithOurConfigPath(t *testing.T) {
	dir := t.TempDir()
	recorder := filepath.Join(dir, "argv.txt")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + recorder + "\"\n"
	provider := newFakeProvider(t, "ngrok", script)

	m := New(Deps{
		Dir:       dir,
		Providers: []Provider{provider},
		Binaries:  fakeStore{path: provider.binary},
		Now:       time.Now,
	})

	if err := m.SetAuthtoken(context.Background(), "2abc_secret"); err != nil {
		t.Fatalf("SetAuthtoken: %v", err)
	}

	body, err := os.ReadFile(recorder)
	if err != nil {
		t.Fatalf("read argv: %v", err)
	}
	args := strings.Split(strings.TrimSpace(string(body)), "\n")
	want := []string{"config", "add-authtoken", "2abc_secret", "--config", ngrokConfigPath(dir)}
	if len(args) != len(want) {
		t.Fatalf("argv = %v, want %v", args, want)
	}
	for i := range want {
		if args[i] != want[i] {
			t.Errorf("argv[%d] = %q, want %q", i, args[i], want[i])
		}
	}
}

func TestSetAuthtokenRejectsBlank(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\nexit 0\n")
	m := New(Deps{Dir: t.TempDir(), Providers: []Provider{provider}, Binaries: fakeStore{path: provider.binary}})

	if err := m.SetAuthtoken(context.Background(), "  "); err == nil {
		t.Fatal("want an error for a blank token")
	}
}

func TestSetAuthtokenSurfacesNgrokRejection(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\necho 'ERROR: invalid authtoken' >&2\nexit 1\n")
	m := New(Deps{Dir: t.TempDir(), Providers: []Provider{provider}, Binaries: fakeStore{path: provider.binary}})

	err := m.SetAuthtoken(context.Background(), "bogus")
	if err == nil {
		t.Fatal("want an error when ngrok rejects the token")
	}
	if !strings.Contains(err.Error(), "invalid authtoken") {
		t.Errorf("err = %v, want ngrok's own message carried through", err)
	}
}

func TestSetAuthtokenNeverPutsTheTokenInAnError(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\necho 'ERROR: nope' >&2\nexit 1\n")
	m := New(Deps{Dir: t.TempDir(), Providers: []Provider{provider}, Binaries: fakeStore{path: provider.binary}})

	err := m.SetAuthtoken(context.Background(), "2abc_supersecret")
	if err == nil {
		t.Fatal("want an error")
	}
	if strings.Contains(err.Error(), "2abc_supersecret") {
		t.Fatal("the token must never appear in an error message")
	}
}

func TestHasAuthtokenReflectsOurConfigFile(t *testing.T) {
	dir := t.TempDir()
	m := New(Deps{Dir: dir})

	if m.HasAuthtoken() {
		t.Error("no config file means no token")
	}
	if err := os.MkdirAll(filepath.Dir(ngrokConfigPath(dir)), 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(ngrokConfigPath(dir), []byte("version: \"3\"\nagent:\n    authtoken: x\n"), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if !m.HasAuthtoken() {
		t.Error("a config carrying an authtoken must report true")
	}
}

func TestSetAuthtokenClearsTheStickyNgrokFallback(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\nexit 0\n")
	m := New(Deps{Dir: t.TempDir(), Providers: []Provider{provider}, Binaries: fakeStore{path: provider.binary}})
	m.mu.Lock()
	m.stickyFrom["ngrok"] = true
	m.status.NeedsAuthtoken = true
	m.mu.Unlock()

	if err := m.SetAuthtoken(context.Background(), "2abc_secret"); err != nil {
		t.Fatalf("SetAuthtoken: %v", err)
	}
	m.mu.Lock()
	sticky := m.stickyFrom["ngrok"]
	needs := m.status.NeedsAuthtoken
	m.mu.Unlock()

	if sticky {
		t.Error("a new token must make ngrok eligible again")
	}
	if needs {
		t.Error("NeedsAuthtoken must clear once a token is stored")
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/tunnel/ -run Authtoken -v`
Expected: FAIL — `undefined: ngrokConfigPath`, `SetAuthtoken` undefined.

- [ ] **Step 3: Write `authtoken.go`**

```go
package tunnel

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func ngrokConfigPath(dir string) string { return filepath.Join(dir, "ngrok.yml") }

func (m *Manager) HasAuthtoken() bool {
	body, err := os.ReadFile(ngrokConfigPath(m.dir))
	if err != nil {
		return false
	}
	return strings.Contains(string(body), "authtoken:")
}

func (m *Manager) SetAuthtoken(ctx context.Context, token string) error {
	trimmed := strings.TrimSpace(token)
	if trimmed == "" {
		return errors.New("tunnel: authtoken must not be empty")
	}
	provider := m.providerNamed("ngrok")
	if provider == nil {
		return errors.New("tunnel: ngrok provider is not configured")
	}
	binary, err := m.binaries.Ensure(ctx, provider.Binary())
	if err != nil {
		return err
	}
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		return err
	}
	cmd := newTunnelCommand(binary, "config", "add-authtoken", trimmed, "--config", ngrokConfigPath(m.dir))
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tunnel: ngrok rejected the authtoken: %s", redact(string(out), trimmed))
	}
	if err := os.Chmod(ngrokConfigPath(m.dir), 0o600); err != nil {
		return err
	}

	m.mu.Lock()
	delete(m.stickyFrom, "ngrok")
	m.status.NeedsAuthtoken = false
	m.mu.Unlock()
	return nil
}

func (m *Manager) providerNamed(name string) Provider {
	for _, candidate := range m.providers {
		if candidate.Name() == name {
			return candidate
		}
	}
	return nil
}

func redact(text, secret string) string {
	cleaned := strings.ReplaceAll(text, secret, "[redacted]")
	return strings.Join(strings.Fields(cleaned), " ")
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd backend && go test ./internal/tunnel/ -run Authtoken -v`
Expected: PASS — all 6 tests.

- [ ] **Step 5: Confirm `Manager` satisfies the controller interface**

Add a compile-time assertion to `backend/internal/httpd/controllers/mobile.go`:

```go
var _ TunnelController = (*tunnel.Manager)(nil)
```

Run: `cd backend && go build ./... && go test ./...`
Expected: PASS. A mismatch here is a signature drift between Tasks 9 and 11 — fix the method, not the assertion.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/tunnel backend/internal/httpd/controllers
git commit -m "feat(tunnel): store the ngrok authtoken via ngrok's own config tooling"
```

---

## Phase 3 — Renderer

### Task 12: Copy in all eight locales

**Files:**
- Modify: `frontend/src/renderer/i18n/en.json`, `de.json`, `es.json`, `fr.json`, `ja.json`, `ko.json`, `pt-BR.json`, `zh-CN.json`
- Test: `frontend/src/renderer/i18n/instance.test.ts` (existing — it is the gate, not a new test)

**Interfaces:**
- Consumes: nothing.
- Produces: 17 `mobile.tunnel.*` keys available to Tasks 13–15. Exact key names below — Tasks 13–15 reference them verbatim.

Doing this first means Tasks 13–15 never sit red on a missing-translation failure.
`instance.test.ts:149` requires every English key to exist non-empty in all
seven other catalogs, and `:162` requires identical `{{variables}}`.

- [ ] **Step 1: Add the English keys**

Add to `frontend/src/renderer/i18n/en.json`, keeping the file's existing
alphabetical-ish grouping near the other `mobile.*` keys:

```json
"mobile.tunnel.enable": "Reachable outside my network",
"mobile.tunnel.enableHint": "Open a secure public address so your phone can connect from anywhere.",
"mobile.tunnel.downloading": "Preparing the tunnel…",
"mobile.tunnel.starting": "Opening a public address…",
"mobile.tunnel.live": "Reachable from anywhere via {{provider}}",
"mobile.tunnel.reconnecting": "Reconnecting…",
"mobile.tunnel.failed": "Could not open a public address",
"mobile.tunnel.rescan": "The address changed — scan the new code with your phone.",
"mobile.tunnel.confirmTitle": "Make this desktop reachable from the internet?",
"mobile.tunnel.confirmBody": "Anyone with the address and password can start agents and run terminal commands on this computer. The password is inside the QR code. You can turn this off at any time.",
"mobile.tunnel.confirmAccept": "Make it global",
"mobile.tunnel.tokenTitle": "Pair once with ngrok",
"mobile.tunnel.tokenBody": "An ngrok authtoken gives this desktop a stable address, so your phone pairs once instead of scanning again after every restart.",
"mobile.tunnel.tokenGet": "Get my authtoken",
"mobile.tunnel.tokenLabel": "ngrok authtoken",
"mobile.tunnel.tokenSave": "Save and test",
"mobile.tunnel.tokenDismiss": "Not now",
```

`mobile.tunnel.live` is the only key with an interpolation variable
(`{{provider}}`); every locale must keep that exact spelling or
`instance.test.ts:162` fails.

- [ ] **Step 2: Add the same 17 keys to the seven other locales**

`de.json`:

```json
"mobile.tunnel.enable": "Außerhalb meines Netzwerks erreichbar",
"mobile.tunnel.enableHint": "Eine sichere öffentliche Adresse öffnen, damit sich dein Telefon von überall verbinden kann.",
"mobile.tunnel.downloading": "Tunnel wird vorbereitet…",
"mobile.tunnel.starting": "Öffentliche Adresse wird geöffnet…",
"mobile.tunnel.live": "Von überall erreichbar über {{provider}}",
"mobile.tunnel.reconnecting": "Neu verbinden…",
"mobile.tunnel.failed": "Öffentliche Adresse konnte nicht geöffnet werden",
"mobile.tunnel.rescan": "Die Adresse hat sich geändert – scanne den neuen Code mit deinem Telefon.",
"mobile.tunnel.confirmTitle": "Diesen Desktop aus dem Internet erreichbar machen?",
"mobile.tunnel.confirmBody": "Wer Adresse und Passwort hat, kann auf diesem Computer Agents starten und Terminal-Befehle ausführen. Das Passwort steckt im QR-Code. Du kannst dies jederzeit ausschalten.",
"mobile.tunnel.confirmAccept": "Global schalten",
"mobile.tunnel.tokenTitle": "Einmal mit ngrok koppeln",
"mobile.tunnel.tokenBody": "Ein ngrok-Authtoken gibt diesem Desktop eine feste Adresse, sodass dein Telefon einmal gekoppelt wird und nicht nach jedem Neustart erneut scannen muss.",
"mobile.tunnel.tokenGet": "Authtoken holen",
"mobile.tunnel.tokenLabel": "ngrok-Authtoken",
"mobile.tunnel.tokenSave": "Speichern und testen",
"mobile.tunnel.tokenDismiss": "Jetzt nicht",
```

`es.json`:

```json
"mobile.tunnel.enable": "Accesible fuera de mi red",
"mobile.tunnel.enableHint": "Abre una dirección pública segura para que tu teléfono pueda conectarse desde cualquier lugar.",
"mobile.tunnel.downloading": "Preparando el túnel…",
"mobile.tunnel.starting": "Abriendo una dirección pública…",
"mobile.tunnel.live": "Accesible desde cualquier lugar mediante {{provider}}",
"mobile.tunnel.reconnecting": "Reconectando…",
"mobile.tunnel.failed": "No se pudo abrir una dirección pública",
"mobile.tunnel.rescan": "La dirección cambió: escanea el nuevo código con tu teléfono.",
"mobile.tunnel.confirmTitle": "¿Hacer que este equipo sea accesible desde internet?",
"mobile.tunnel.confirmBody": "Cualquier persona con la dirección y la contraseña puede iniciar agentes y ejecutar comandos de terminal en este equipo. La contraseña está dentro del código QR. Puedes desactivarlo cuando quieras.",
"mobile.tunnel.confirmAccept": "Hacerlo global",
"mobile.tunnel.tokenTitle": "Vincula una sola vez con ngrok",
"mobile.tunnel.tokenBody": "Un authtoken de ngrok le da a este equipo una dirección estable, así tu teléfono se vincula una vez en lugar de escanear después de cada reinicio.",
"mobile.tunnel.tokenGet": "Obtener mi authtoken",
"mobile.tunnel.tokenLabel": "Authtoken de ngrok",
"mobile.tunnel.tokenSave": "Guardar y probar",
"mobile.tunnel.tokenDismiss": "Ahora no",
```

`fr.json`:

```json
"mobile.tunnel.enable": "Accessible hors de mon réseau",
"mobile.tunnel.enableHint": "Ouvrir une adresse publique sécurisée pour que votre téléphone puisse se connecter de partout.",
"mobile.tunnel.downloading": "Préparation du tunnel…",
"mobile.tunnel.starting": "Ouverture d'une adresse publique…",
"mobile.tunnel.live": "Accessible de partout via {{provider}}",
"mobile.tunnel.reconnecting": "Reconnexion…",
"mobile.tunnel.failed": "Impossible d'ouvrir une adresse publique",
"mobile.tunnel.rescan": "L'adresse a changé — scannez le nouveau code avec votre téléphone.",
"mobile.tunnel.confirmTitle": "Rendre ce poste accessible depuis internet ?",
"mobile.tunnel.confirmBody": "Toute personne disposant de l'adresse et du mot de passe peut lancer des agents et exécuter des commandes de terminal sur cet ordinateur. Le mot de passe se trouve dans le QR code. Vous pouvez désactiver cela à tout moment.",
"mobile.tunnel.confirmAccept": "Rendre global",
"mobile.tunnel.tokenTitle": "Appairer une seule fois avec ngrok",
"mobile.tunnel.tokenBody": "Un authtoken ngrok donne à ce poste une adresse stable : votre téléphone s'appaire une fois au lieu de rescanner après chaque redémarrage.",
"mobile.tunnel.tokenGet": "Obtenir mon authtoken",
"mobile.tunnel.tokenLabel": "Authtoken ngrok",
"mobile.tunnel.tokenSave": "Enregistrer et tester",
"mobile.tunnel.tokenDismiss": "Pas maintenant",
```

`ja.json`:

```json
"mobile.tunnel.enable": "ネットワーク外からも接続可能にする",
"mobile.tunnel.enableHint": "安全な公開アドレスを開いて、どこからでもスマートフォンが接続できるようにします。",
"mobile.tunnel.downloading": "トンネルを準備中…",
"mobile.tunnel.starting": "公開アドレスを開いています…",
"mobile.tunnel.live": "{{provider}} 経由でどこからでも接続可能",
"mobile.tunnel.reconnecting": "再接続中…",
"mobile.tunnel.failed": "公開アドレスを開けませんでした",
"mobile.tunnel.rescan": "アドレスが変わりました。スマートフォンで新しいコードをスキャンしてください。",
"mobile.tunnel.confirmTitle": "このデスクトップをインターネットから接続できるようにしますか？",
"mobile.tunnel.confirmBody": "アドレスとパスワードを知っている人は、このコンピューターでエージェントを起動し、ターミナルコマンドを実行できます。パスワードは QR コードに含まれています。いつでもオフにできます。",
"mobile.tunnel.confirmAccept": "公開する",
"mobile.tunnel.tokenTitle": "ngrok で一度だけペアリング",
"mobile.tunnel.tokenBody": "ngrok の authtoken を設定するとアドレスが固定され、再起動ごとにスキャンし直す必要がなくなります。",
"mobile.tunnel.tokenGet": "authtoken を取得",
"mobile.tunnel.tokenLabel": "ngrok authtoken",
"mobile.tunnel.tokenSave": "保存してテスト",
"mobile.tunnel.tokenDismiss": "後で",
```

`ko.json`:

```json
"mobile.tunnel.enable": "네트워크 외부에서 접속 허용",
"mobile.tunnel.enableHint": "안전한 공개 주소를 열어 어디서든 휴대폰이 연결할 수 있게 합니다.",
"mobile.tunnel.downloading": "터널 준비 중…",
"mobile.tunnel.starting": "공개 주소를 여는 중…",
"mobile.tunnel.live": "{{provider}}을 통해 어디서든 접속 가능",
"mobile.tunnel.reconnecting": "다시 연결 중…",
"mobile.tunnel.failed": "공개 주소를 열 수 없습니다",
"mobile.tunnel.rescan": "주소가 변경되었습니다. 휴대폰으로 새 코드를 스캔하세요.",
"mobile.tunnel.confirmTitle": "이 데스크톱을 인터넷에서 접속할 수 있게 할까요?",
"mobile.tunnel.confirmBody": "주소와 비밀번호를 아는 사람은 이 컴퓨터에서 에이전트를 실행하고 터미널 명령을 실행할 수 있습니다. 비밀번호는 QR 코드에 담겨 있습니다. 언제든지 끌 수 있습니다.",
"mobile.tunnel.confirmAccept": "공개로 전환",
"mobile.tunnel.tokenTitle": "ngrok으로 한 번만 페어링",
"mobile.tunnel.tokenBody": "ngrok authtoken을 등록하면 주소가 고정되어 재시작할 때마다 다시 스캔할 필요가 없습니다.",
"mobile.tunnel.tokenGet": "authtoken 가져오기",
"mobile.tunnel.tokenLabel": "ngrok authtoken",
"mobile.tunnel.tokenSave": "저장 후 테스트",
"mobile.tunnel.tokenDismiss": "나중에",
```

`pt-BR.json`:

```json
"mobile.tunnel.enable": "Acessível fora da minha rede",
"mobile.tunnel.enableHint": "Abre um endereço público seguro para que seu telefone possa conectar de qualquer lugar.",
"mobile.tunnel.downloading": "Preparando o túnel…",
"mobile.tunnel.starting": "Abrindo um endereço público…",
"mobile.tunnel.live": "Acessível de qualquer lugar via {{provider}}",
"mobile.tunnel.reconnecting": "Reconectando…",
"mobile.tunnel.failed": "Não foi possível abrir um endereço público",
"mobile.tunnel.rescan": "O endereço mudou — escaneie o novo código com seu telefone.",
"mobile.tunnel.confirmTitle": "Tornar este computador acessível pela internet?",
"mobile.tunnel.confirmBody": "Qualquer pessoa com o endereço e a senha pode iniciar agentes e executar comandos de terminal neste computador. A senha está dentro do QR code. Você pode desativar isso quando quiser.",
"mobile.tunnel.confirmAccept": "Tornar global",
"mobile.tunnel.tokenTitle": "Pareie uma única vez com o ngrok",
"mobile.tunnel.tokenBody": "Um authtoken do ngrok dá a este computador um endereço estável, então seu telefone pareia uma vez em vez de escanear depois de cada reinício.",
"mobile.tunnel.tokenGet": "Obter meu authtoken",
"mobile.tunnel.tokenLabel": "Authtoken do ngrok",
"mobile.tunnel.tokenSave": "Salvar e testar",
"mobile.tunnel.tokenDismiss": "Agora não",
```

`zh-CN.json`:

```json
"mobile.tunnel.enable": "可从网络外部访问",
"mobile.tunnel.enableHint": "开启一个安全的公网地址，让手机可以从任何地方连接。",
"mobile.tunnel.downloading": "正在准备隧道…",
"mobile.tunnel.starting": "正在开启公网地址…",
"mobile.tunnel.live": "已可通过 {{provider}} 从任何地方访问",
"mobile.tunnel.reconnecting": "正在重新连接…",
"mobile.tunnel.failed": "无法开启公网地址",
"mobile.tunnel.rescan": "地址已变更——请用手机扫描新的二维码。",
"mobile.tunnel.confirmTitle": "让这台电脑可从互联网访问？",
"mobile.tunnel.confirmBody": "任何拿到地址和密码的人都可以在这台电脑上启动代理并执行终端命令。密码就在二维码里。你可以随时关闭。",
"mobile.tunnel.confirmAccept": "开启公网访问",
"mobile.tunnel.tokenTitle": "与 ngrok 一次配对",
"mobile.tunnel.tokenBody": "配置 ngrok authtoken 可为这台电脑提供固定地址，手机只需配对一次，不必每次重启后重新扫码。",
"mobile.tunnel.tokenGet": "获取我的 authtoken",
"mobile.tunnel.tokenLabel": "ngrok authtoken",
"mobile.tunnel.tokenSave": "保存并测试",
"mobile.tunnel.tokenDismiss": "暂不",
```

- [ ] **Step 3: Run the i18n gate**

Run: `cd frontend && npx vitest run src/renderer/i18n/`
Expected: PASS. A failure names the exact missing `locale.key` or placeholder mismatch.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/renderer/i18n
git commit -m "feat(i18n): add public tunnel copy in all eight locales"
```

---

### Task 13: Tunnel toggle, states, and QR swap

**Files:**
- Modify: `frontend/src/renderer/components/ConnectMobileModal.tsx`
- Test: `frontend/src/renderer/components/ConnectMobileModal.tunnel.test.tsx`

**Interfaces:**
- Consumes: the `tunnel` object on `/api/v1/mobile/status` (Task 9); `mobile.tunnel.*` keys (Task 12).
- Produces: `pairingPayloadV2(url: string, password: string): string` exported from `ConnectMobileModal.tsx`, used by the tests and by nothing else yet; `MobileTunnelStatus` local type.

- [ ] **Step 1: Write the failing tests**

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { mobileStatus, post } = vi.hoisted(() => ({
	mobileStatus: {
		enabled: true,
		host: "192.168.1.20",
		port: 3011,
		password: "hunter2secret",
		warning: "",
		tunnel: {
			state: "off",
			provider: "",
			url: "",
			error: "",
			restarts: 0,
			needsAuthtoken: false,
			hasAuthtoken: false,
		},
	},
	post: vi.fn(),
}));

vi.mock("../lib/telemetry", () => ({ captureRendererEvent: vi.fn() }));
vi.mock("../lib/api-client", () => ({
	apiClient: {
		GET: async () => ({ data: mobileStatus, error: undefined }),
		POST: post,
	},
	apiErrorMessage: () => "failed",
}));

import { ConnectMobileModal, pairingPayloadV2 } from "./ConnectMobileModal";

function renderModal() {
	const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
	return render(
		<QueryClientProvider client={client}>
			<ConnectMobileModal open onOpenChange={vi.fn()} />
		</QueryClientProvider>,
	);
}

describe("Connect Mobile tunnel toggle", () => {
	beforeEach(() => {
		post.mockReset();
		post.mockResolvedValue({ data: mobileStatus, error: undefined });
		mobileStatus.enabled = true;
		mobileStatus.tunnel = {
			state: "off",
			provider: "",
			url: "",
			error: "",
			restarts: 0,
			needsAuthtoken: false,
			hasAuthtoken: false,
		};
	});

	test("shows the tunnel switch while the bridge is on", async () => {
		renderModal();
		await waitFor(() => expect(screen.getByRole("switch", { name: "Reachable outside my network" })).toBeTruthy());
	});

	test("disables the tunnel switch while the bridge is off", async () => {
		mobileStatus.enabled = false;
		renderModal();
		await waitFor(() => {
			const toggle = screen.getByRole("switch", { name: "Reachable outside my network" });
			expect(toggle.getAttribute("disabled")).not.toBeNull();
		});
	});

	test("QR stays on the LAN address until the tunnel is live", async () => {
		mobileStatus.tunnel.state = "starting";
		renderModal();
		await waitFor(() => expect(screen.getByText("Opening a public address…")).toBeTruthy());
		expect(screen.getByText("192.168.1.20:3011")).toBeTruthy();
	});

	test("QR and address swap to the tunnel URL once live", async () => {
		mobileStatus.tunnel.state = "live";
		mobileStatus.tunnel.provider = "ngrok";
		mobileStatus.tunnel.url = "https://imagines-livestock-widely.ngrok-free.dev";
		renderModal();

		await waitFor(() => expect(screen.getByText("https://imagines-livestock-widely.ngrok-free.dev")).toBeTruthy());
		expect(screen.getByText("Reachable from anywhere via ngrok")).toBeTruthy();
		expect(screen.queryByText("192.168.1.20:3011")).toBeNull();
	});

	test("renders reconnecting without an error treatment", async () => {
		mobileStatus.tunnel.state = "reconnecting";
		mobileStatus.tunnel.restarts = 3;
		renderModal();
		await waitFor(() => expect(screen.getByText("Reconnecting…")).toBeTruthy());
	});

	test("renders the provider's own message on failure", async () => {
		mobileStatus.tunnel.state = "failed";
		mobileStatus.tunnel.error = "account limit exceeded";
		renderModal();
		await waitFor(() => expect(screen.getByText("account limit exceeded")).toBeTruthy());
	});

	test("v2 payload carries the url and password, and no host or port", () => {
		const payload = JSON.parse(pairingPayloadV2("https://x.ngrok-free.dev", "pw"));
		expect(payload).toEqual({ v: 2, url: "https://x.ngrok-free.dev", password: "pw" });
	});

	test("turning the switch off calls the disable route", async () => {
		mobileStatus.tunnel.state = "live";
		mobileStatus.tunnel.url = "https://x.ngrok-free.dev";
		mobileStatus.tunnel.provider = "ngrok";
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/disable"));
	});
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd frontend && npx vitest run src/renderer/components/ConnectMobileModal.tunnel.test.tsx`
Expected: FAIL — `pairingPayloadV2` is not exported and no tunnel switch is rendered.

- [ ] **Step 3: Extend `ConnectMobileModal.tsx`**

Add the type to the `MobileStatus` interface and the v2 payload builder:

```tsx
interface MobileTunnelStatus {
	state: "off" | "downloading" | "starting" | "live" | "reconnecting" | "failed";
	provider: string;
	url: string;
	error: string;
	since?: string;
	restarts: number;
	needsAuthtoken: boolean;
	hasAuthtoken: boolean;
}

interface MobileStatus {
	enabled: boolean;
	host: string;
	port: number;
	password: string;
	warning: string;
	tunnel?: MobileTunnelStatus;
}

export function pairingPayloadV2(url: string, password: string): string {
	return JSON.stringify({ v: 2, url, password });
}
```

Add the mutations next to `enable`/`disable`/`regenerate`:

```tsx
	const tunnelEnable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/enable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});

	const tunnelDisable = useMutation({
		mutationFn: async () => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/disable");
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: invalidate,
	});
```

Derive the tunnel view state and poll while it is in flight — add
`refetchInterval` to the existing `useQuery`:

```tsx
	const query = useQuery({
		queryKey: mobileStatusQueryKey,
		queryFn: fetchMobileStatus,
		enabled: open,
		refetchInterval: (q) => {
			const state = q.state.data?.tunnel?.state;
			return state === "downloading" || state === "starting" || state === "reconnecting" ? 1000 : false;
		},
	});
```

Then, after the existing enable-toggle row and before the pairing details:

```tsx
	const tunnel = status?.tunnel;
	const tunnelLive = tunnel?.state === "live" && tunnel.url !== "";
	const tunnelBusy = tunnelEnable.isPending || tunnelDisable.isPending;
	const tunnelOn = tunnelLive || tunnel?.state === "starting" || tunnel?.state === "downloading" || tunnel?.state === "reconnecting";

	const tunnelMessage = (() => {
		if (!tunnel) return null;
		switch (tunnel.state) {
			case "downloading":
				return t("mobile.tunnel.downloading");
			case "starting":
				return t("mobile.tunnel.starting");
			case "reconnecting":
				return t("mobile.tunnel.reconnecting");
			case "live":
				return t("mobile.tunnel.live", { provider: tunnel.provider });
			case "failed":
				return tunnel.error || t("mobile.tunnel.failed");
			default:
				return null;
		}
	})();
```

Render the row:

```tsx
							<div className="relative flex items-start justify-between gap-3 px-3 py-3">
								<div className="flex min-w-0 flex-col gap-1 pr-2">
									<span className="text-subtitle leading-(--leading-settings-mobile-title) text-settings-label">
										{t("mobile.tunnel.enable")}
									</span>
									<span className="text-caption leading-(--leading-settings-mobile-hint) text-settings-muted">
										{t("mobile.tunnel.enableHint")}
									</span>
									{tunnelMessage && (
										<span
											className={cn(
												"text-caption leading-(--leading-settings-mobile-hint)",
												tunnel?.state === "failed" ? "text-error" : "text-settings-muted",
											)}
										>
											{tunnelMessage}
										</span>
									)}
								</div>
								<div className="flex shrink-0 items-center gap-2 pt-0.5">
									{tunnelBusy && <Loader2 className="size-4 animate-spin text-settings-muted" aria-hidden="true" />}
									<Switch
										checked={Boolean(tunnelOn)}
										onCheckedChange={onTunnelToggle}
										disabled={!enabled || tunnelBusy}
										aria-label={t("mobile.tunnel.enable")}
									/>
								</div>
							</div>
```

And the handler — the confirmation gate arrives in Task 14, so for now it calls straight through:

```tsx
	const onTunnelToggle = (next: boolean) => {
		if (tunnelBusy) return;
		clearActionErrors();
		if (next) {
			tunnelEnable.mutate();
			return;
		}
		tunnelDisable.mutate();
	};
```

Swap the QR and address row when live:

```tsx
												<QRCodeSVG
													value={
														tunnelLive && tunnel
															? pairingPayloadV2(tunnel.url, status.password)
															: pairingPayload(status.host, status.port, status.password)
													}
													size={QR_CODE_SIZE}
													className="block size-(--size-settings-mobile-qr-code)"
												/>
```

```tsx
												<span className="tracking-settings-mono break-all text-settings-label">
													{tunnelLive && tunnel ? tunnel.url : `${status.host}:${status.port}`}
												</span>
```

Add `tunnelEnable.error` / `tunnelDisable.error` to the `actionError` chain and
`tunnelEnable.reset()` / `tunnelDisable.reset()` to `clearActionErrors`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd frontend && npx vitest run src/renderer/components/ConnectMobileModal.tunnel.test.tsx`
Expected: PASS — all 8 tests.

- [ ] **Step 5: Confirm the existing modal tests still pass, plus typecheck and lint**

Run: `cd frontend && npx vitest run src/renderer/components/ConnectMobileModal.telemetry.test.tsx && cd .. && npm run typecheck && npm run frontend:lint`
Expected: PASS. The pre-existing telemetry test must not need editing; if it breaks, the toggle row was inserted into the wrong branch.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/components
git commit -m "feat(renderer): add the public tunnel toggle and swap the QR when live"
```

---

### Task 14: One-time confirmation dialog

**Files:**
- Create: `frontend/src/renderer/components/settings/TunnelConfirmDialog.tsx`
- Modify: `frontend/src/renderer/components/ConnectMobileModal.tsx`
- Test: `frontend/src/renderer/components/settings/TunnelConfirmDialog.test.tsx`

**Interfaces:**
- Consumes: `mobile.tunnel.confirm*` keys (Task 12); `Dialog` primitives from `../ui/dialog`; `Button` from `../ui/button`.
- Produces: `TunnelConfirmDialog({ open, onOpenChange, onConfirm })`; `TUNNEL_CONFIRM_STORAGE_KEY = "opr.mobile.tunnelConfirmed"`.

Acknowledgement is remembered in `localStorage`: it is a per-machine UI
preference, not daemon state, and the daemon already records the real thing
(`TunnelEnabled`).

- [ ] **Step 1: Write the failing tests**

```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

import { TunnelConfirmDialog, TUNNEL_CONFIRM_STORAGE_KEY } from "./TunnelConfirmDialog";

describe("TunnelConfirmDialog", () => {
	beforeEach(() => {
		window.localStorage.clear();
	});

	test("states plainly what becomes reachable", () => {
		render(<TunnelConfirmDialog open onOpenChange={vi.fn()} onConfirm={vi.fn()} />);
		expect(screen.getByText("Make this desktop reachable from the internet?")).toBeTruthy();
		expect(screen.getByText(/start agents and run terminal commands/)).toBeTruthy();
	});

	test("confirming calls onConfirm and remembers the acknowledgement", async () => {
		const onConfirm = vi.fn();
		render(<TunnelConfirmDialog open onOpenChange={vi.fn()} onConfirm={onConfirm} />);

		await userEvent.click(screen.getByRole("button", { name: "Make it global" }));

		expect(onConfirm).toHaveBeenCalledTimes(1);
		expect(window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY)).toBe("1");
	});

	test("cancelling neither confirms nor remembers", async () => {
		const onConfirm = vi.fn();
		const onOpenChange = vi.fn();
		render(<TunnelConfirmDialog open onOpenChange={onOpenChange} onConfirm={onConfirm} />);

		await userEvent.click(screen.getByRole("button", { name: "Cancel" }));

		expect(onConfirm).not.toHaveBeenCalled();
		expect(window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY)).toBeNull();
		expect(onOpenChange).toHaveBeenCalledWith(false);
	});
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd frontend && npx vitest run src/renderer/components/settings/TunnelConfirmDialog.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

```tsx
import { useTranslation } from "react-i18next";

import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../ui/dialog";
import { Button } from "../ui/button";

export const TUNNEL_CONFIRM_STORAGE_KEY = "opr.mobile.tunnelConfirmed";

export function tunnelAlreadyConfirmed(): boolean {
	try {
		return window.localStorage.getItem(TUNNEL_CONFIRM_STORAGE_KEY) === "1";
	} catch {
		return false;
	}
}

interface TunnelConfirmDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onConfirm: () => void;
}

export function TunnelConfirmDialog({ open, onOpenChange, onConfirm }: TunnelConfirmDialogProps) {
	const { t } = useTranslation();

	const confirm = () => {
		try {
			window.localStorage.setItem(TUNNEL_CONFIRM_STORAGE_KEY, "1");
		} catch {
			// A blocked storage write must not block the action itself.
		}
		onConfirm();
		onOpenChange(false);
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{t("mobile.tunnel.confirmTitle")}</DialogTitle>
					<DialogDescription>{t("mobile.tunnel.confirmBody")}</DialogDescription>
				</DialogHeader>
				<DialogFooter>
					<Button type="button" variant="footer" onClick={() => onOpenChange(false)}>
						{t("blocks.cancel")}
					</Button>
					<Button type="button" onClick={confirm}>
						{t("mobile.tunnel.confirmAccept")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
```

The one `catch` comment above is load-bearing for a silent branch — if the
no-comments rule is applied strictly, delete it; the behavior is unchanged.
`blocks.cancel` is reused rather than adding an 18th key in eight languages.

Check `../ui/dialog` actually exports `DialogFooter`; if not, use the footer
markup that `ConnectMobileModal` already uses for its button row.

- [ ] **Step 4: Gate the toggle on it in `ConnectMobileModal.tsx`**

```tsx
	const [confirmOpen, setConfirmOpen] = useState(false);

	const onTunnelToggle = (next: boolean) => {
		if (tunnelBusy) return;
		clearActionErrors();
		if (!next) {
			tunnelDisable.mutate();
			return;
		}
		if (!tunnelAlreadyConfirmed()) {
			setConfirmOpen(true);
			return;
		}
		tunnelEnable.mutate();
	};
```

Render it inside the dialog body:

```tsx
					<TunnelConfirmDialog
						open={confirmOpen}
						onOpenChange={setConfirmOpen}
						onConfirm={() => tunnelEnable.mutate()}
					/>
```

- [ ] **Step 5: Add the gate test to the modal suite**

Append to `ConnectMobileModal.tunnel.test.tsx`:

```tsx
	test("the first enable asks for confirmation before calling the route", async () => {
		window.localStorage.clear();
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		expect(screen.getByText("Make this desktop reachable from the internet?")).toBeTruthy();
		expect(post).not.toHaveBeenCalled();

		await userEvent.click(screen.getByRole("button", { name: "Make it global" }));
		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
	});

	test("a remembered acknowledgement skips straight to the route", async () => {
		window.localStorage.setItem("opr.mobile.tunnelConfirmed", "1");
		renderModal();

		const toggle = await waitFor(() => screen.getByRole("switch", { name: "Reachable outside my network" }));
		await userEvent.click(toggle);

		await waitFor(() => expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/enable"));
		expect(screen.queryByText("Make this desktop reachable from the internet?")).toBeNull();
	});
```

- [ ] **Step 6: Run to verify everything passes**

Run: `cd frontend && npx vitest run src/renderer/components/ && cd .. && npm run typecheck && npm run frontend:lint`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/components
git commit -m "feat(renderer): gate the first tunnel enable behind a confirmation"
```

---

### Task 15: ngrok authtoken dialog

**Files:**
- Create: `frontend/src/renderer/components/settings/NgrokAuthtokenDialog.tsx`
- Modify: `frontend/src/renderer/components/ConnectMobileModal.tsx`
- Test: `frontend/src/renderer/components/settings/NgrokAuthtokenDialog.test.tsx`

**Interfaces:**
- Consumes: `mobile.tunnel.token*` keys (Task 12); `POST /api/v1/mobile/tunnel/authtoken` (Task 9); `tunnel.needsAuthtoken` from status.
- Produces: `NgrokAuthtokenDialog({ open, onOpenChange, onSaved })`; `NGROK_AUTHTOKEN_URL = "https://dashboard.ngrok.com/get-started/your-authtoken"`.

Never a wall: the tunnel is already live on cloudflared behind it, and
dismissing changes nothing (spec §10).

- [ ] **Step 1: Write the failing tests**

```tsx
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { post } = vi.hoisted(() => ({ post: vi.fn() }));

vi.mock("../../lib/api-client", () => ({
	apiClient: { POST: post },
	apiErrorMessage: (error: unknown) => String((error as { message?: string })?.message ?? "failed"),
}));

import { NgrokAuthtokenDialog } from "./NgrokAuthtokenDialog";

describe("NgrokAuthtokenDialog", () => {
	beforeEach(() => {
		post.mockReset();
		post.mockResolvedValue({ data: {}, error: undefined });
	});

	test("explains the benefit and offers the token page", () => {
		render(<NgrokAuthtokenDialog open onOpenChange={vi.fn()} onSaved={vi.fn()} />);
		expect(screen.getByText("Pair once with ngrok")).toBeTruthy();
		expect(screen.getByRole("button", { name: "Get my authtoken" })).toBeTruthy();
	});

	test("masks the field by default", () => {
		render(<NgrokAuthtokenDialog open onOpenChange={vi.fn()} onSaved={vi.fn()} />);
		const field = screen.getByLabelText("ngrok authtoken");
		expect(field.getAttribute("type")).toBe("password");
	});

	test("saving posts the token and reports success", async () => {
		const onSaved = vi.fn();
		render(<NgrokAuthtokenDialog open onOpenChange={vi.fn()} onSaved={onSaved} />);

		await userEvent.type(screen.getByLabelText("ngrok authtoken"), "2abc_secret");
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));

		await waitFor(() =>
			expect(post).toHaveBeenCalledWith("/api/v1/mobile/tunnel/authtoken", {
				body: { token: "2abc_secret" },
			}),
		);
		await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1));
	});

	test("a rejected token shows the provider's message and stays open", async () => {
		post.mockResolvedValue({ data: undefined, error: { message: "ngrok rejected the authtoken: invalid" } });
		const onSaved = vi.fn();
		render(<NgrokAuthtokenDialog open onOpenChange={vi.fn()} onSaved={onSaved} />);

		await userEvent.type(screen.getByLabelText("ngrok authtoken"), "bogus");
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));

		await waitFor(() => expect(screen.getByText(/invalid/)).toBeTruthy());
		expect(onSaved).not.toHaveBeenCalled();
	});

	test("an empty field cannot be submitted", async () => {
		render(<NgrokAuthtokenDialog open onOpenChange={vi.fn()} onSaved={vi.fn()} />);
		await userEvent.click(screen.getByRole("button", { name: "Save and test" }));
		expect(post).not.toHaveBeenCalled();
	});

	test("dismissing changes nothing", async () => {
		const onOpenChange = vi.fn();
		render(<NgrokAuthtokenDialog open onOpenChange={onOpenChange} onSaved={vi.fn()} />);

		await userEvent.click(screen.getByRole("button", { name: "Not now" }));

		expect(post).not.toHaveBeenCalled();
		expect(onOpenChange).toHaveBeenCalledWith(false);
	});
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd frontend && npx vitest run src/renderer/components/settings/NgrokAuthtokenDialog.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the component**

```tsx
import { useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Eye, EyeOff, Loader2 } from "lucide-react";

import { apiClient, apiErrorMessage } from "../../lib/api-client";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "../ui/dialog";
import { Button } from "../ui/button";

export const NGROK_AUTHTOKEN_URL = "https://dashboard.ngrok.com/get-started/your-authtoken";

interface NgrokAuthtokenDialogProps {
	open: boolean;
	onOpenChange: (open: boolean) => void;
	onSaved: () => void;
}

export function NgrokAuthtokenDialog({ open, onOpenChange, onSaved }: NgrokAuthtokenDialogProps) {
	const { t } = useTranslation();
	const [token, setToken] = useState("");
	const [revealed, setRevealed] = useState(false);

	const save = useMutation({
		mutationFn: async (value: string) => {
			const { data, error } = await apiClient.POST("/api/v1/mobile/tunnel/authtoken", {
				body: { token: value },
			});
			if (error) throw new Error(apiErrorMessage(error));
			return data;
		},
		onSuccess: () => {
			setToken("");
			onSaved();
			onOpenChange(false);
		},
	});

	const submit = () => {
		const trimmed = token.trim();
		if (trimmed === "" || save.isPending) return;
		save.mutate(trimmed);
	};

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{t("mobile.tunnel.tokenTitle")}</DialogTitle>
					<DialogDescription>{t("mobile.tunnel.tokenBody")}</DialogDescription>
				</DialogHeader>

				<Button type="button" variant="footer" onClick={() => window.open(NGROK_AUTHTOKEN_URL, "_blank")}>
					{t("mobile.tunnel.tokenGet")}
				</Button>

				<label className="mt-4 flex flex-col gap-1 text-caption text-settings-muted" htmlFor="ngrok-authtoken">
					{t("mobile.tunnel.tokenLabel")}
					<div className="flex items-center gap-2">
						<input
							id="ngrok-authtoken"
							type={revealed ? "text" : "password"}
							value={token}
							onChange={(event) => setToken(event.target.value)}
							className="min-w-0 flex-1 rounded-md border border-(--color-border-settings-input) bg-transparent px-2 py-1 text-settings-label"
						/>
						<button
							type="button"
							aria-label={revealed ? t("mobile.tunnel.tokenLabel") : t("mobile.tunnel.tokenLabel")}
							onClick={() => setRevealed((value) => !value)}
							className="inline-flex size-6 items-center justify-center text-settings-muted hover:text-settings-label"
						>
							{revealed ? <EyeOff className="size-4" aria-hidden="true" /> : <Eye className="size-4" aria-hidden="true" />}
						</button>
					</div>
				</label>

				{save.error instanceof Error && <p className="mt-2 text-xs text-error">{save.error.message}</p>}

				<DialogFooter>
					<Button type="button" variant="footer" onClick={() => onOpenChange(false)}>
						{t("mobile.tunnel.tokenDismiss")}
					</Button>
					<Button type="button" onClick={submit} disabled={save.isPending}>
						{save.isPending && <Loader2 className="mr-2 size-4 animate-spin" aria-hidden="true" />}
						{t("mobile.tunnel.tokenSave")}
					</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
```

- [ ] **Step 4: Open it from the modal when the daemon asks**

In `ConnectMobileModal.tsx`:

```tsx
	const [tokenOpen, setTokenOpen] = useState(false);
	const needsAuthtoken = tunnel?.needsAuthtoken ?? false;

	useEffect(() => {
		if (needsAuthtoken) setTokenOpen(true);
	}, [needsAuthtoken]);
```

Render it beside the confirm dialog, and add a persistent affordance so a user
on the fallback can reach it without waiting for a failure:

```tsx
					<NgrokAuthtokenDialog open={tokenOpen} onOpenChange={setTokenOpen} onSaved={invalidate} />
```

```tsx
									{tunnelLive && tunnel?.provider === "cloudflared" && !tunnel.hasAuthtoken && (
										<button
											type="button"
											onClick={() => setTokenOpen(true)}
											className="text-caption text-settings-muted underline hover:text-settings-label"
										>
											{t("mobile.tunnel.tokenTitle")}
										</button>
									)}
```

- [ ] **Step 5: Add the rescan notice**

When the live provider is the fallback, the URL rotates on every restart, so the
user must be told (spec §5 rule 3). Render under the QR:

```tsx
										{tunnelLive && tunnel?.provider === "cloudflared" && (
											<p className="mt-2 text-caption text-settings-muted">{t("mobile.tunnel.rescan")}</p>
										)}
```

- [ ] **Step 6: Run the full renderer gate**

Run: `cd frontend && npx vitest run src/renderer/ && cd .. && npm run typecheck && npm run frontend:lint`
Expected: PASS, including `renderer-coverage.test.ts` — every new string goes through `t()`, so no new entry in its `approvedLiterals` allowlist should be needed. If it flags one, replace the literal with a key rather than extending the allowlist.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/renderer/components
git commit -m "feat(renderer): add the ngrok authtoken dialog and fallback rescan notice"
```

---

## Phase 4 — Mobile client

Nothing in Phase 1–3 reaches a phone until this phase ships a build. Run every
command in this phase from `packages/mobile`.

### Task 16: Pairing payload v2

**Files:**
- Modify: `packages/mobile/lib/feature/pairing/logic/pairing_payload.dart`
- Test: `packages/mobile/test/feature/pairing/logic/pairing_payload_test.dart`

**Interfaces:**
- Consumes: the `{v:2,url,password}` QR produced by `pairingPayloadV2` (Task 13).
- Produces: `PairingPayload` gains `final bool secure`; `parsePairingPayload(String raw)` accepts v1 and v2; `pairingPayloadVersion(String raw) -> int?` so the caller can tell "unknown version" from "not our QR".

- [ ] **Step 1: Update the existing test that asserts v2 is rejected**

`pairing_payload_test.dart` currently asserts `{"v":2,…}` → null. That is the
behavior this task deliberately changes, so edit it rather than leaving a
contradiction. Replace the `rejects a wrong or missing version` test with:

```dart
    test('rejects a missing version', () {
      expect(parsePairingPayload('{"host":"10.0.0.5","port":"3011"}'), isNull);
    });

    test('rejects a version newer than we understand', () {
      expect(parsePairingPayload('{"v":99,"url":"https://x.ngrok-free.dev"}'), isNull);
      expect(pairingPayloadVersion('{"v":99,"url":"https://x.ngrok-free.dev"}'), 99);
    });
```

- [ ] **Step 2: Write the failing v2 tests**

Add inside the same `group`:

```dart
    test('v1 stays insecure with its host and port', () {
      final payload = parsePairingPayload('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}');
      expect(payload, const PairingPayload(host: '10.0.0.5', port: '3011', password: 'secret12', secure: false));
    });

    test('parses a v2 tunnel payload as a secure host on 443', () {
      final payload = parsePairingPayload(
        '{"v":2,"url":"https://imagines-livestock-widely.ngrok-free.dev","password":"averylongtunnelpassword"}',
      );
      expect(payload?.host, 'imagines-livestock-widely.ngrok-free.dev');
      expect(payload?.port, '443');
      expect(payload?.secure, isTrue);
      expect(payload?.password, 'averylongtunnelpassword');
    });

    test('honours an explicit port in a v2 url', () {
      final payload = parsePairingPayload('{"v":2,"url":"https://example.com:8443","password":"pw"}');
      expect(payload?.host, 'example.com');
      expect(payload?.port, '8443');
      expect(payload?.secure, isTrue);
    });

    test('rejects a v2 payload without a url', () {
      expect(parsePairingPayload('{"v":2,"password":"pw"}'), isNull);
    });

    test('rejects a v2 url that is not https', () {
      expect(parsePairingPayload('{"v":2,"url":"http://plain.example","password":"pw"}'), isNull);
      expect(parsePairingPayload('{"v":2,"url":"ftp://nope.example","password":"pw"}'), isNull);
    });

    test('rejects a malformed v2 url', () {
      expect(parsePairingPayload('{"v":2,"url":"https://","password":"pw"}'), isNull);
      expect(parsePairingPayload('{"v":2,"url":"not a url","password":"pw"}'), isNull);
    });

    test('reports the version for recognised payloads too', () {
      expect(pairingPayloadVersion('{"v":1,"host":"10.0.0.5","port":"3011"}'), 1);
      expect(pairingPayloadVersion('{"v":2,"url":"https://x.example"}'), 2);
      expect(pairingPayloadVersion('not json'), isNull);
      expect(pairingPayloadVersion('{"host":"10.0.0.5"}'), isNull);
    });
```

- [ ] **Step 3: Run to verify they fail**

Run: `flutter test test/feature/pairing/logic/pairing_payload_test.dart`
Expected: FAIL — `PairingPayload` has no `secure`, `pairingPayloadVersion` undefined.

- [ ] **Step 4: Rewrite `pairing_payload.dart`**

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

class PairingPayload extends Equatable {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.password,
    required this.secure,
  });

  final String host;
  final String port;
  final String password;
  final bool secure;

  @override
  List<Object?> get props => [host, port, password, secure];
}

int? pairingPayloadVersion(String raw) {
  final map = _decodeObject(raw);
  if (map == null) return null;
  final version = map['v'];
  return version is int ? version : null;
}

PairingPayload? parsePairingPayload(String raw) {
  final map = _decodeObject(raw);
  if (map == null) return null;

  final password = map['password'];
  final asString = password is String ? password : '';

  switch (map['v']) {
    case 1:
      return _parseV1(map, asString);
    case 2:
      return _parseV2(map, asString);
    default:
      return null;
  }
}

Map<String, dynamic>? _decodeObject(String raw) {
  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  return parsed is Map<String, dynamic> ? parsed : null;
}

PairingPayload? _parseV1(Map<String, dynamic> map, String password) {
  final host = map['host'];
  if (host is! String || host.isEmpty) return null;

  final port = map['port'];
  if (port is! String && port is! num) return null;

  return PairingPayload(host: host, port: port.toString(), password: password, secure: false);
}

PairingPayload? _parseV2(Map<String, dynamic> map, String password) {
  final url = map['url'];
  if (url is! String || url.isEmpty) return null;

  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;

  return PairingPayload(
    host: uri.host,
    port: (uri.hasPort ? uri.port : 443).toString(),
    password: password,
    secure: true,
  );
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/feature/pairing/logic/pairing_payload_test.dart`
Expected: PASS — all tests in the group.

- [ ] **Step 6: Fix every other construction site**

`PairingPayload` gained a required field, so existing constructions fail to
compile. Find and fix them:

Run: `grep -rn "PairingPayload(" lib test | grep -v "class PairingPayload"`
Add `secure: false` to each v1-shaped literal.

- [ ] **Step 7: Run the mobile gate**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" and a green suite.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): parse the v2 tunnel pairing payload"
```

---

### Task 17: Honour `secure`, and explain a stale address

**Files:**
- Modify: `packages/mobile/lib/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart:28`–`:41`, `packages/mobile/lib/core/error_handling/connection_error.dart:3` and `:41`
- Test: `packages/mobile/test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`, `packages/mobile/test/core/error_handling/connection_error_test.dart`

**Interfaces:**
- Consumes: `PairingPayload.secure`, `pairingPayloadVersion` (Task 16).
- Produces: `ConnectionFailure.unsupportedPayload` and its `describeConnectionFailure` case. `PairingScanCubit` builds `ServerConfig` with `secure: parsed.secure`.

This fixes a live bug on the way past: `secure: current?.secure ?? false` means
a scan can never turn TLS on today, whatever the QR says.

- [ ] **Step 1: Write the failing tests**

Append to the cubit test (matching the file's existing `bloc_test`/mocktail setup):

```dart
  blocTest<PairingScanCubit, PairingScanState>(
    'a v2 payload connects over https',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => const Result.success(null));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan(
      '{"v":2,"url":"https://x.ngrok-free.dev","password":"averylongtunnelpassword"}',
      TargetPlatform.iOS,
    ),
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured.single as ServerConfig;
      expect(captured.secure, isTrue);
      expect(captured.host, 'x.ngrok-free.dev');
      expect(captured.httpPort, '443');
      expect(captured.httpBase, 'https://x.ngrok-free.dev:443');
    },
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'a v1 payload stays on plain http',
    build: () {
      when(() => repository.verifyAndConnect(any())).thenAnswer((_) async => const Result.success(null));
      return PairingScanCubit(repository, store, fromOnboarding: false);
    },
    act: (cubit) => cubit.onScan('{"v":1,"host":"10.0.0.5","port":"3011","password":"secret12"}', TargetPlatform.iOS),
    verify: (_) {
      final captured = verify(() => repository.verifyAndConnect(captureAny())).captured.single as ServerConfig;
      expect(captured.secure, isFalse);
      expect(captured.httpBase, 'http://10.0.0.5:3011');
    },
  );

  blocTest<PairingScanCubit, PairingScanState>(
    'an unknown payload version asks the user to update the app',
    build: () => PairingScanCubit(repository, store, fromOnboarding: false),
    act: (cubit) => cubit.onScan('{"v":99,"url":"https://x.example"}', TargetPlatform.iOS),
    expect: () => [
      isA<VerifyFailureState>().having(
        (state) => state.copy.title,
        'title',
        'Update Operator on this phone',
      ),
    ],
    verify: (_) => verifyNever(() => repository.verifyAndConnect(any())),
  );
```

Create `packages/mobile/test/core/error_handling/connection_error_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';

void main() {
  group('describeConnectionFailure', () {
    test('unsupportedPayload tells the user to update the app', () {
      final copy = describeConnectionFailure(
        ConnectionFailure.unsupportedPayload,
        host: '',
        port: '',
        platform: TargetPlatform.iOS,
      );
      expect(copy.title, 'Update Operator on this phone');
      expect(copy.message, contains('newer'));
      expect(copy.showLocalNetworkHint, isFalse);
    });

    test('a tunnelled host never gets the local-network hint', () {
      final copy = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: 'x.ngrok-free.dev',
        port: '443',
        platform: TargetPlatform.iOS,
      );
      expect(copy.showLocalNetworkHint, isFalse);
    });

    test('a LAN host on iOS still gets the local-network hint', () {
      final copy = describeConnectionFailure(
        ConnectionFailure.unreachable,
        host: '192.168.1.20',
        port: '3011',
        platform: TargetPlatform.iOS,
      );
      expect(copy.showLocalNetworkHint, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/core/error_handling/connection_error_test.dart test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`
Expected: FAIL — `unsupportedPayload` is not a `ConnectionFailure` member.

- [ ] **Step 3: Add the failure case**

In `connection_error.dart`, extend the enum and add the case to the switch:

```dart
enum ConnectionFailure { notOprQr, unsupportedPayload, unreachable, auth, rateLimited, serverError }
```

```dart
    case ConnectionFailure.unsupportedPayload:
      return const ConnectionErrorCopy(
        title: 'Update Operator on this phone',
        message: 'That pairing code was made by a newer version of Operator. '
            'Update the app from TestFlight, then scan again.',
        showLocalNetworkHint: false,
      );
```

`isLocalNetworkHost` already returns false for a hostname like
`x.ngrok-free.dev` (it only matches `localhost`, `.local`, and private IPv4
ranges), so the tunnelled-host assertion passes with no change there.

- [ ] **Step 4: Use the payload's `secure` and branch on the version**

In `pairing_scan_cubit.dart`, replace the parse-and-build block:

```dart
    final parsed = parsePairingPayload(raw);
    if (parsed == null) {
      final version = pairingPayloadVersion(raw);
      final reason = version != null && version > 2
          ? ConnectionFailure.unsupportedPayload
          : ConnectionFailure.notOprQr;
      emit(VerifyFailureState(describeConnectionFailure(reason, host: '', port: '', platform: platform)));
      return;
    }

    _scanned = true;
    final current = _serverConfigStore.current;
    final target = ServerConfig(
      host: parsed.host,
      httpPort: parsed.port,
      secure: parsed.secure,
      password: parsed.password.isNotEmpty ? parsed.password : (current?.password ?? ''),
    );
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/core/error_handling/connection_error_test.dart test/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit_test.dart`
Expected: PASS.

- [ ] **Step 6: Check for other `ConnectionFailure` switches**

An exhaustive `switch` elsewhere over the enum will now fail to compile. Run:
`grep -rn "ConnectionFailure\." lib test | grep -v connection_error.dart`
Handle `unsupportedPayload` in each exhaustive switch found.

- [ ] **Step 7: Run the mobile gate**

Run: `flutter analyze && flutter test`
Expected: "No issues found!" and a green suite.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "fix(mobile): honour the pairing payload's secure flag"
```

---

### Task 18: Always send `ngrok-skip-browser-warning`

**Files:**
- Modify: `packages/mobile/lib/core/api/api_request_helpers/dio_consumer.dart:38`, `packages/mobile/lib/feature/preview/presentation/preview_screen/ui/widgets/preview_browser.dart:47`
- Test: `packages/mobile/test/core/api/dio_consumer_headers_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: no new API. `DioConsumer.setDefaultDioOptions` adds the header; the WebView sends it too.

Measured: ngrok's interstitial is gated on User-Agent — Dio's UA passes but a
browser UA gets an HTML warning page that never reaches the daemon (evidence
§6). The WebView sends a browser UA, so without this the preview breaks on the
ngrok path. Inert on LAN and on cloudflared.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/api/api_request_helpers/dio_consumer.dart';
import 'package:operator_mobile/core/api/interceptors/server_config_interceptor.dart';
import 'package:operator_mobile/core/api/server_config.dart';

class _StaticConfig implements ServerConfigSource {
  @override
  ServerConfig? get current => const ServerConfig(host: 'h', httpPort: '3011', secure: false, password: 'pw');
}

void main() {
  test('every request carries the ngrok interstitial bypass header', () {
    final consumer = DioConsumer(_StaticConfig());
    expect(consumer.client.options.headers['ngrok-skip-browser-warning'], '1');
  });

  test('the standard json headers are still present', () {
    final consumer = DioConsumer(_StaticConfig());
    expect(consumer.client.options.headers['accept'], 'application/json');
    expect(consumer.client.options.headers['Content-Type'], 'application/json');
  });
}
```

Check `ServerConfigSource`'s exact member list and implement it fully in
`_StaticConfig`; if it declares more than `current`, add the missing members.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/api/dio_consumer_headers_test.dart`
Expected: FAIL — the header is null.

- [ ] **Step 3: Add the header in `dio_consumer.dart`**

```dart
  @override
  void setDefaultDioOptions() {
    client.options
      ..headers = {
        'accept': 'application/json',
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': '1',
      }
      ..connectTimeout = const Duration(seconds: 12)
      ..receiveTimeout = const Duration(seconds: 12);
  }
```

Do not touch the two 12-second timeouts — they are load-bearing and documented
in `CLAUDE.md`.

- [ ] **Step 4: Add the header to the WebView**

In `preview_browser.dart`, `_load()`:

```dart
  void _load() {
    final password = sl<ServerConfigStore>().current?.password ?? '';
    final headers = <String, String>{'ngrok-skip-browser-warning': '1'};
    if (widget.preview.authenticated && password.isNotEmpty) {
      headers['Authorization'] = 'Bearer $password';
    }
    _controller.loadRequest(Uri.parse(widget.preview.url), headers: headers);
  }
```

The existing doc comment above `_load()` documents the `Authorization` rule and
stays accurate — leave it in place.

- [ ] **Step 5: Run to verify it passes, then the whole gate**

Run: `flutter test test/core/api/dio_consumer_headers_test.dart && flutter analyze && flutter test`
Expected: PASS, "No issues found!", green suite.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib packages/mobile/test
git commit -m "feat(mobile): always bypass the ngrok browser interstitial"
```

---

### Task 19: Guard the cloudflared SSE assumption

**Files:**
- Create: `packages/mobile/test/core/no_sse_consumer_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: a test that fails if the app ever starts consuming SSE.

cloudflared quick tunnels buffer SSE (evidence §4). That is harmless **only**
because the app consumes none — everything live rides the mux WebSocket. If an
SSE consumer ever appears, live updates would silently arrive in batches on the
fallback path with no error anywhere. Spec §3 requires this guard.

- [ ] **Step 1: Write the test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app consumes no SSE, which the cloudflared fallback depends on', () {
    final offenders = <String>[];
    final pattern = RegExp(r"text/event-stream|EventSource|ResponseType\.stream");

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (pattern.hasMatch(source)) offenders.add(entity.path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'cloudflared quick tunnels buffer SSE, so an SSE consumer would make live '
          'updates arrive in batches with no error on that path. Either keep live data '
          'on the mux WebSocket, or drop the cloudflared fallback. Offenders: $offenders',
    );
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/core/no_sse_consumer_test.dart`
Expected: PASS. A failure here is a genuine design conflict, not a broken test — read the reason string before changing anything.

- [ ] **Step 3: Run the gate and commit**

Run: `flutter analyze && flutter test`

```bash
git add packages/mobile/test
git commit -m "test(mobile): fail if an SSE consumer appears, which would break the fallback"
```

---

## Phase 5 — Documentation

### Task 20: Rewrite the remote-access docs

**Files:**
- Modify: `frontend/src/landing/content/docs/configuration/remote-access.mdx`

**Interfaces:**
- Consumes: the finished behavior of Tasks 1–19.
- Produces: no code.

The page currently instructs the reader **not** to expose the bridge to the
public internet and describes the security model as plaintext-HTTP-on-a-trusted-
network. Both predate this feature. Leaving that text beside a button that does
the opposite is worse than either alone (spec §14).

- [ ] **Step 1: Replace the contradictory sentences**

In the intro paragraph, the sentence forbidding exposure applies to the
**primary loopback daemon**, which is still true — keep it, but make its subject
explicit so it cannot be read as forbidding the mobile tunnel:

> Operator's primary daemon listener is always bound to `127.0.0.1`… Do not expose **that listener** with `HOST=0.0.0.0`, a public reverse proxy, or port forwarding.

In the **Security model** list, replace the final bullet
("…do not expose its port to the public internet") with:

```mdx
- On a LAN the mobile listener uses plaintext HTTP and is intended for a trusted network. Do not port-forward it or place it behind your own reverse proxy.
- To reach it from outside your network, use **Connect Mobile → Reachable outside my network**, which terminates TLS at the tunnel provider. Do not hand-roll an equivalent.
```

- [ ] **Step 2: Add a section after "Tailscale"**

```mdx
## Reachable outside your network

Enable Connect Mobile, then turn on **Reachable outside my network**. Operator
opens an HTTPS tunnel to the mobile listener and rewrites the pairing QR to that
address, so one scan pairs a phone on cellular.

The first time you turn it on, Operator asks you to confirm: while the tunnel is
live, anyone with the address **and** the connection password can start agents
and run terminal commands on that machine. Turning the tunnel on rotates the
connection password to a much longer one, which the QR carries for you.

Two providers sit behind the switch:

- **Cloudflare quick tunnel** — the default when you have not configured ngrok.
  It needs no account at all, but its address changes every time Operator
  restarts, so your phone has to scan the new code each time. Cloudflare gives
  account-less tunnels no uptime guarantee.
- **ngrok** — used whenever an authtoken is saved. Your address stays the same
  across restarts, so a phone pairs once and keeps working. ngrok requires a
  free account; Operator's dialog links to the token page and stores the token
  under `~/.operator/mobile/ngrok.yml`, leaving any ngrok config of your own
  untouched.

If ngrok cannot serve — no token, a revoked token, an exhausted free allowance —
Operator falls back to a Cloudflare quick tunnel rather than failing, and tells
you which provider is live. The address changes when that happens, so the phone
needs one more scan.

The tunnel stays on across restarts once enabled, and starts again with the
bridge, so you can still reach the machine after it reboots while you are away.
Turn the switch off, or regenerate the connection password, to revoke access.
```

- [ ] **Step 2 (continued): Refresh the stale "What mobile supports" paragraph**

That section still describes "The Expo/React Native app", which was deleted at
milestone M6 (see `CLAUDE.md`). Change the opening sentence to name the Flutter
client:

> The Operator mobile app is a native control surface over the same daemon resources as desktop.

- [ ] **Step 3: Verify the docs build**

Run: `cd frontend && npm run typecheck`
Expected: PASS. If the landing site has its own build (check `frontend/package.json` scripts for a `landing:*` entry), run that too.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/landing/content/docs/configuration/remote-access.mdx
git commit -m "docs: describe reaching Connect Mobile from outside the network"
```

---

## Final verification

- [ ] **Run every gate in one pass**

```bash
npm run lint
npm run typecheck
npm run frontend:lint
npm run api
git status --short
```

`npm run api` must leave the tree **clean** — a diff means the committed
`openapi.yaml` or `schema.ts` is stale, which fails the api-drift CI job.

```bash
cd frontend && npx vitest run src/renderer/
cd ../packages/mobile && flutter analyze && flutter test
```

- [ ] **Manual end-to-end check, in this order**

1. `cd frontend && npm run tauri:dev` (see `RUN_APP_COMMANDS.md`).
2. Open **Connect Mobile**, enable mobile access, flip **Reachable outside my network**, accept the confirmation.
3. Expect `live` within ~10s. With no ngrok authtoken the provider reads `cloudflared`; with one it reads `ngrok`.
4. `curl -sS -o /dev/null -w '%{http_code}\n' <the URL shown>` → `401` (the bridge is up and demanding the password — a `200` here would mean auth is not being enforced, which is a bug to stop and fix).
5. Scan the QR with a **new** mobile build on cellular with Wi-Fi off. The session list should load.
6. Restart the daemon. The tunnel must come back on its own. On ngrok the URL is unchanged and the phone reconnects with no action; on cloudflared it changes and the phone needs a re-scan.
7. Turn the switch off and confirm `curl` to the old URL now fails.
8. `pgrep -fl "ngrok|cloudflared"` → empty. A surviving process is an orphan-reaping bug.

---

## Self-Review

**Spec coverage** — each spec section mapped to the task that implements it:

| Spec section | Task(s) |
| --- | --- |
| §2 Easy / Reliable / Practical framing | 12–15 (easy), 4 (reliable), 7 + 10 (practical) |
| §3 Provider choice, SSE finding, interstitial | 1 (both providers), 19 (SSE guard), 18 (interstitial) |
| §4 `tunnel` package, `Provider` seam, `agent.web_addr` | 1, 3; the `web_addr` config file is written by Task 11 and passed as `--config` by Task 1's `Args` |
| §5 Pair once, never cache the URL, authtoken trivial to add, paths not equivalent | 4 (re-read URL on every start), 15 (dialog + rescan notice) |
| §6 Binary acquisition, per-provider verification, PATH fallback | 2 |
| §7 Health, backoff, retry forever, fallback by shape, sticky, known limitation | 4, 5 |
| §8 API surface, `since`, `restarts`, async enable + polling | 9, 13 |
| §9 Persistence, long password, proxy-aware lockout, conditional warning | 7, 8, 9, 10 |
| §10 Renderer toggle, indicator, one-time confirm, authtoken dialog, storage | 13, 14, 15 |
| §11 Payload v2, `secure`, stale URL, skip-browser-warning, TestFlight | 16, 17, 18 |
| §12 Deliberately not built | nothing built — no task adds custom domains, expiry, the ngrok SDK, or IP pinning |
| §13 Testing | tests in every task; §11's SSE guard is Task 19 |
| §14 Docs | 20 |
| §15 Risks | mitigations land in 2 (checksum), 4 (flapping), 5 (quota fallback), 9 (leak revocation) |

**One spec item deliberately deferred, flagged rather than silently dropped:**
spec §10 asks for a tunnel-live indicator discoverable *outside* the Connect
Mobile dialog. Task 13 states the requirement but leaves placement to the
implementer, because the surrounding chrome (`Sidebar.tsx`, `WindowTitlebar.tsx`)
was not surveyed while writing the spec and guessing a location would be worse
than naming the gap. Decide it during Task 13 review, or split it into its own
task then.

**Placeholder scan:** the only intentional fill-in is Task 2 Step 7's checksum
table, which Step 6 generates with an exact command and Step 8 verifies is 64
hex characters — values that cannot be known without fetching the release.
Windows cloudflared is explicitly scoped out in that same step with the reason
given. No "TBD", no "add error handling", no "similar to Task N".

**Type consistency checks performed:**
- `Status` fields (`State`, `Provider`, `URL`, `Error`, `Since`, `Restarts`, `NeedsAuthtoken`) are identical in Task 1's definition, Task 4's mutations, Task 5's assertions, and Task 9's DTO mapping.
- `Provider` has exactly eight methods in Task 1 and the fake in Task 3 implements all eight.
- `controllers.TunnelController` (Task 9) matches `*tunnel.Manager`'s real methods: `Enable`, `Disable`, `Status`, `SetAuthtoken` (Tasks 3, 11) plus `HasAuthtoken` (Task 11) — Task 11 Step 5 asserts this at compile time.
- `sourceKey` is two-argument everywhere after Task 8, with Step 6 sweeping callers.
- `restoreMobileOnBoot` is three-argument in both Task 10's tests and its implementation.
- `PairingPayload` gains `secure` in Task 16 and Task 17 consumes exactly that name; Task 16 Step 6 sweeps constructions.
- `pairingPayloadV2` (Task 13) and `_parseV2` (Task 16) agree on the wire shape `{v:2,url,password}`.
- i18n keys used in Tasks 13–15 are exactly the 17 defined in Task 12, plus the pre-existing `blocks.cancel`.

**Ordering constraint:** Task 12 must precede 13–15, or those tasks fail on the
locale-parity gate rather than on their own assertions. Tasks 16–19 can run in
parallel with Phase 3; Task 20 must be last.
