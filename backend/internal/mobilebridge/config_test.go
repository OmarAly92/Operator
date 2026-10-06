package mobilebridge

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"testing"
)

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	p := Path(dir)
	want := State{Enabled: true, Password: "abc", LastPort: 3011}
	if err := Save(p, want); err != nil {
		t.Fatalf("save: %v", err)
	}
	got, err := Load(p)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if got != want {
		t.Fatalf("round trip: got %+v want %+v", got, want)
	}
	info, _ := os.Stat(p)
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %v want 0600", info.Mode().Perm())
	}
}

func TestLoadMissingIsZero(t *testing.T) {
	got, err := Load(filepath.Join(t.TempDir(), "mobile", "config.json"))
	if err != nil || got != (State{}) {
		t.Fatalf("missing file: got %+v err %v", got, err)
	}
}

func TestGeneratePasswordFormat(t *testing.T) {
	pw, err := GeneratePassword()
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^[A-Za-z0-9]{8}$`).MatchString(pw) {
		t.Fatalf("password %q not 8 alnum", pw)
	}
}

func TestPasswordMatches(t *testing.T) {
	pw, _ := GeneratePassword()
	h := HashPassword(pw)
	if !PasswordMatches(h, pw) {
		t.Fatal("expected match")
	}
	if PasswordMatches(h, pw+"x") {
		t.Fatal("expected mismatch")
	}
}

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

func TestUpdateReadModifyWritesUnderOneLock(t *testing.T) {
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := Save(path, State{Enabled: true, Password: "pw", NgrokDomain: "x.ngrok.app"}); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, _ = Update(path, func(s *State) error { s.LastPort++; return nil })
		}(i)
	}
	wg.Wait()
	got, err := Load(path)
	if err != nil || got.LastPort != 20 || got.NgrokDomain != "x.ngrok.app" {
		t.Fatalf("state = %+v err=%v", got, err)
	}
}

func TestGenerateAlertTopic(t *testing.T) {
	a, err := GenerateAlertTopic()
	if err != nil {
		t.Fatal(err)
	}
	b, _ := GenerateAlertTopic()
	if len(a) != AlertTopicLength || a == b || strings.Trim(a, pwAlphabet) != "" {
		t.Fatalf("topics %q %q", a, b)
	}
}
