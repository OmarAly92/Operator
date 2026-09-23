package daemon

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

// fakeLAN is a minimal httpd.LANController fake for exercising
// restoreMobileOnBoot without a real listener.
type fakeLAN struct {
	started    bool
	hash       string
	strong     bool
	port       int
	forcedPort int
}

func (f *fakeLAN) Start(port int) (int, error) {
	f.started = true
	f.port = port
	if f.forcedPort != 0 {
		f.port = f.forcedPort
	}
	return f.port, nil
}
func (f *fakeLAN) Stop(ctx context.Context) error { return nil }
func (f *fakeLAN) Running() bool                  { return f.started }
func (f *fakeLAN) BoundPort() int                 { return f.port }
func (f *fakeLAN) SetPasswordHash(hash string)    { f.hash = hash }
func (f *fakeLAN) PasswordHash() string           { return f.hash }
func (f *fakeLAN) SetPasswordStrong(strong bool)  { f.strong = strong }
func (f *fakeLAN) PasswordStrong() bool           { return f.strong }
func (f *fakeLAN) SetTrustedForwardHeader(string) {}

func TestRestoreEnabledStartsListener(t *testing.T) {
	dir := t.TempDir()
	path := mobilebridge.Path(dir)
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: "secret12", LastPort: 3011}); err != nil {
		t.Fatalf("save state: %v", err)
	}
	lan := &fakeLAN{}
	if err := restoreMobileOnBoot(path, lan, nil); err != nil {
		t.Fatalf("restoreMobileOnBoot: %v", err)
	}
	if !lan.started {
		t.Fatal("expected LAN listener started from persisted enabled state")
	}
	// Restore derives the auth hash from the persisted plaintext password (no
	// rotation), so the fake must have received HashPassword(persisted password).
	if want := mobilebridge.HashPassword("secret12"); lan.hash != want {
		t.Fatalf("expected hash derived from persisted password %q, got %q", want, lan.hash)
	}
	if lan.port != 3011 {
		t.Fatalf("expected persisted port reused, got %d", lan.port)
	}
}

func TestRestoreDisabledDoesNotStart(t *testing.T) {
	dir := t.TempDir()
	path := mobilebridge.Path(dir)
	if err := mobilebridge.Save(path, mobilebridge.State{Enabled: false}); err != nil {
		t.Fatalf("save state: %v", err)
	}
	lan := &fakeLAN{}
	if err := restoreMobileOnBoot(path, lan, nil); err != nil {
		t.Fatalf("restoreMobileOnBoot: %v", err)
	}
	if lan.started {
		t.Fatal("expected LAN listener NOT started when persisted state is disabled")
	}
}

type fakeTunnelStarter struct {
	enabled   int
	localPort int
	err       error
}

func (f *fakeTunnelStarter) Enable(context.Context) error {
	f.enabled++
	return f.err
}

func (f *fakeTunnelStarter) SetLocalPort(port int) { f.localPort = port }

func TestRestoreTargetsTheTunnelAtThePortActuallyBound(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := mobilebridge.Save(path, mobilebridge.State{
		Enabled: true, Password: "pw", LastPort: 3011, TunnelEnabled: true,
	}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	lan := &fakeLAN{forcedPort: 49321}
	starter := &fakeTunnelStarter{}

	if err := restoreMobileOnBoot(path, lan, starter); err != nil {
		t.Fatalf("restore: %v", err)
	}
	if starter.localPort != 49321 {
		t.Fatalf("tunnel local port = %d, want the port the listener actually bound (49321), not the persisted 3011", starter.localPort)
	}
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

func TestRestoreKeepsTheClaimedTopic(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	want := mobilebridge.State{Enabled: true, Password: "abcdefgh", LastPort: 0, AlertTopic: strings.Repeat("a", mobilebridge.AlertTopicLength), AlertTopicClaimed: true}
	if err := mobilebridge.Save(path, want); err != nil {
		t.Fatal(err)
	}
	if err := restoreMobileOnBoot(path, &fakeLAN{}, nil); err != nil {
		t.Fatal(err)
	}
	got, _ := mobilebridge.Load(path)
	if got.AlertTopic != want.AlertTopic || !got.AlertTopicClaimed {
		t.Fatalf("restore changed the topic: %+v", got)
	}
}

func TestRestoreArmsPasswordStrengthFromThePersistedPassword(t *testing.T) {
	for name, tc := range map[string]struct {
		password string
		strong   bool
	}{
		"short LAN password":   {password: "secret12", strong: false},
		"long tunnel password": {password: "averylongtunnelpasswor", strong: true},
	} {
		path := filepath.Join(t.TempDir(), "config.json")
		if err := mobilebridge.Save(path, mobilebridge.State{Enabled: true, Password: tc.password, LastPort: 3011}); err != nil {
			t.Fatalf("%s: seed: %v", name, err)
		}
		lan := &fakeLAN{strong: !tc.strong}
		if err := restoreMobileOnBoot(path, lan, nil); err != nil {
			t.Fatalf("%s: restore: %v", name, err)
		}
		if lan.strong != tc.strong {
			t.Errorf("%s: strong = %v, want %v", name, lan.strong, tc.strong)
		}
	}
}
