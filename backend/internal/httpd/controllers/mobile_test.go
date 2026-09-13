package controllers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
	"github.com/OmarAly92/operator/backend/internal/tunnel"
)

type fakeBridge struct{ enabled bool }

func (f *fakeBridge) Status() MobileStatusResponse {
	return MobileStatusResponse{Enabled: f.enabled, Host: "192.168.1.42", Port: 3011}
}
func (f *fakeBridge) Enable() (MobileStatusResponse, error) {
	f.enabled = true
	r := f.Status()
	r.Password = "abcd1234"
	return r, nil
}
func (f *fakeBridge) Disable() error { f.enabled = false; return nil }
func (f *fakeBridge) Regenerate() (MobileStatusResponse, error) {
	r := f.Status()
	r.Password = "wxyz5678"
	return r, nil
}
func (f *fakeBridge) TunnelEnable() (MobileStatusResponse, error)  { return f.Status(), nil }
func (f *fakeBridge) TunnelDisable() (MobileStatusResponse, error) { return f.Status(), nil }
func (f *fakeBridge) SetAuthtoken(token string) (MobileStatusResponse, error) {
	return f.Status(), nil
}

// fakeLAN is a minimal LANController for exercising BridgeService directly.
type fakeLAN struct {
	running    bool
	port       int
	hash       string
	strong     bool
	stopCalls  int
	forcedPort int
}

func (f *fakeLAN) Start(port int) (int, error) {
	f.running = true
	f.port = port
	if f.forcedPort != 0 {
		f.port = f.forcedPort
	}
	return f.port, nil
}
func (f *fakeLAN) Stop(ctx context.Context) error {
	f.stopCalls++
	f.running = false
	return nil
}
func (f *fakeLAN) Running() bool                  { return f.running }
func (f *fakeLAN) BoundPort() int                 { return f.port }
func (f *fakeLAN) SetPasswordHash(h string)       { f.hash = h }
func (f *fakeLAN) PasswordHash() string           { return f.hash }
func (f *fakeLAN) SetPasswordStrong(strong bool)  { f.strong = strong }
func (f *fakeLAN) PasswordStrong() bool           { return f.strong }
func (f *fakeLAN) SetTrustedForwardHeader(string) {}

type fakeTunnel struct {
	status         tunnel.Status
	enableErr      error
	enabled        bool
	enableCalls    int
	localPort      int
	disabled       bool
	savedToken     string
	saveTokenErr   error
	hasAuthtokenOn bool
}

func (f *fakeTunnel) SetLocalPort(port int) { f.localPort = port }

func (f *fakeTunnel) Enable(context.Context) error {
	f.enableCalls++
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

// When Save fails during a fresh enable, the listener that Start already opened
// must be torn back down and the armed hash rolled back — otherwise a LAN
// listener stays live on 0.0.0.0 while persisted state/UI say enable failed.
func TestMobileEnableRollsBackListenerWhenSaveFails(t *testing.T) {
	// A ConfigPath whose parent is a regular file makes mobilebridge.Save's
	// MkdirAll (and thus Save) fail deterministically.
	blocker := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	lan := &fakeLAN{}
	b := &BridgeService{LAN: lan, ConfigPath: filepath.Join(blocker, "mobile", "config.json"), DefaultPort: 3011}

	if _, err := b.Enable(); err == nil {
		t.Fatal("expected enable to fail on Save error")
	}
	if lan.Running() {
		t.Fatal("listener still running after failed enable; must be stopped")
	}
	if lan.stopCalls == 0 {
		t.Fatal("expected Stop to be called on rollback")
	}
	if lan.hash != "" {
		t.Fatalf("expected hash rolled back to empty, got %q", lan.hash)
	}
}

func TestMobileEnableReturnsPassword(t *testing.T) {
	c := &MobileController{Bridge: &fakeBridge{}}
	w := httptest.NewRecorder()
	c.Enable(w, httptest.NewRequest(http.MethodPost, "/api/v1/mobile/enable", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("got %d", w.Code)
	}
	var got MobileStatusResponse
	json.NewDecoder(w.Body).Decode(&got)
	if !got.Enabled || got.Password != "abcd1234" || got.Warning == "" {
		t.Fatalf("bad response: %+v", got)
	}
}

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

func TestSetAuthtokenReportsARejectionWithoutEchoingTheToken(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{saveTokenErr: errors.New("ngrok rejected the authtoken for 2abc_leakedFakeToken: unauthorized")}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	_, err := bridge.SetAuthtoken("2abc_leakedFakeToken")
	if err == nil {
		t.Fatal("a rejected authtoken must be reported, not swallowed as success")
	}
	if strings.Contains(err.Error(), "2abc_leakedFakeToken") {
		t.Fatalf("the token must never appear in the surfaced error: %q", err)
	}
	if !strings.Contains(err.Error(), "unauthorized") {
		t.Errorf("error = %q, want the provider's own message carried through", err)
	}

	c := &MobileController{Bridge: bridge}
	w := httptest.NewRecorder()
	body := strings.NewReader(`{"token":"2abc_leakedFakeToken"}`)
	c.SetAuthtoken(w, httptest.NewRequest(http.MethodPost, "/api/v1/mobile/tunnel/authtoken", body))
	if w.Code == http.StatusOK {
		t.Errorf("status = %d, want a failure for a rejected token", w.Code)
	}
	if strings.Contains(w.Body.String(), "2abc_leakedFakeToken") {
		t.Fatalf("HTTP response body must never contain the token: %s", w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "unauthorized") {
		t.Errorf("HTTP response body must carry the provider's message: %s", w.Body.String())
	}
}

func TestTunnelEnableDoesNotRotateThePasswordOnARetry(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tun := &fakeTunnel{}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	first, err := bridge.TunnelEnable()
	if err != nil {
		t.Fatalf("first TunnelEnable: %v", err)
	}
	if len(first.Password) != mobilebridge.TunnelPasswordLength {
		t.Fatalf("password length = %d, want the tunnel-length rotation on the off->on transition", len(first.Password))
	}

	tun.status = tunnel.Status{State: tunnel.StateFailed, Error: "every provider refused"}
	second, err := bridge.TunnelEnable()
	if err != nil {
		t.Fatalf("retry TunnelEnable: %v", err)
	}
	if second.Password != first.Password {
		t.Errorf("password rotated on a retry (%q -> %q); that drops the paired phone for nothing",
			first.Password, second.Password)
	}
	if tun.enableCalls != 2 {
		t.Errorf("Enable calls = %d, want the retry to still reach the tunnel manager", tun.enableCalls)
	}
}

func TestTunnelEnableRotatesAgainAfterTunnelDisable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "pw", LastPort: 3011}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	bridge := &BridgeService{LAN: &fakeLAN{running: true, port: 3011}, ConfigPath: path, DefaultPort: 3011, Tunnel: &fakeTunnel{}}

	first, err := bridge.TunnelEnable()
	if err != nil {
		t.Fatalf("first TunnelEnable: %v", err)
	}
	if _, err := bridge.TunnelDisable(); err != nil {
		t.Fatalf("TunnelDisable: %v", err)
	}
	second, err := bridge.TunnelEnable()
	if err != nil {
		t.Fatalf("second TunnelEnable: %v", err)
	}
	if second.Password == first.Password {
		t.Error("a genuine off->on transition must rotate the connection password")
	}
}

func TestEnableTargetsTheTunnelAtThePortActuallyBound(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	tun := &fakeTunnel{}
	lan := &fakeLAN{forcedPort: 49876}
	bridge := &BridgeService{LAN: lan, ConfigPath: path, DefaultPort: 3011, Tunnel: tun}

	if _, err := bridge.Enable(); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	if tun.localPort != 49876 {
		t.Fatalf("tunnel local port = %d, want the port the listener actually bound (49876), not the requested 3011", tun.localPort)
	}
}

func TestPasswordStrengthFollowsThePasswordThatIsArmed(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	lan := &fakeLAN{}
	bridge := &BridgeService{LAN: lan, ConfigPath: path, DefaultPort: 3011, Tunnel: &fakeTunnel{}}

	if _, err := bridge.Enable(); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	if lan.strong {
		t.Fatal("the 8-char LAN password must keep the lockout's short-password rules")
	}

	if _, err := bridge.TunnelEnable(); err != nil {
		t.Fatalf("TunnelEnable: %v", err)
	}
	if !lan.strong {
		t.Fatal("the 22-char tunnel password must be armed as strong")
	}

	got, err := bridge.Regenerate()
	if err != nil {
		t.Fatalf("Regenerate while tunneled: %v", err)
	}
	if len(got.Password) != mobilebridge.TunnelPasswordLength {
		t.Fatalf("regenerating while tunneled issued a %d-char password; a short password must never face the public internet", len(got.Password))
	}
	if !lan.strong {
		t.Fatal("regenerating while tunneled must keep the strong rules")
	}
	state, err := mobilebridge.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !state.TunnelEnabled {
		t.Fatal("regenerating must not silently drop the persisted tunnel intent")
	}

	if _, err := bridge.TunnelDisable(); err != nil {
		t.Fatalf("TunnelDisable: %v", err)
	}
	got, err = bridge.Regenerate()
	if err != nil {
		t.Fatalf("Regenerate after disable: %v", err)
	}
	if len(got.Password) == mobilebridge.TunnelPasswordLength || lan.strong {
		t.Fatal("with the tunnel off, regenerating returns to the short LAN password and its rules")
	}
}

func TestMobileEnableRollsBackPasswordStrengthWhenSaveFails(t *testing.T) {
	blocker := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	lan := &fakeLAN{strong: true}
	b := &BridgeService{LAN: lan, ConfigPath: filepath.Join(blocker, "mobile", "config.json"), DefaultPort: 3011}

	if _, err := b.Enable(); err == nil {
		t.Fatal("expected enable to fail on Save error")
	}
	if !lan.strong {
		t.Fatal("a failed enable must roll password strength back with the hash")
	}
}
