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

func TestSetAuthtokenNeverPutsTheTokenInAnErrorEvenWhenBinaryIsMissing(t *testing.T) {
	dir := t.TempDir()
	missing := filepath.Join(dir, "does-not-exist")
	provider := newFakeProvider(t, "ngrok", "#!/bin/sh\nexit 0\n")
	m := New(Deps{Dir: t.TempDir(), Providers: []Provider{provider}, Binaries: fakeStore{path: missing}})

	err := m.SetAuthtoken(context.Background(), "2abc_supersecret")
	if err == nil {
		t.Fatal("want an error when the binary cannot be run")
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

func TestHasAuthtokenSeesATokenInTheUsersOwnNgrokConfig(t *testing.T) {
	dir := t.TempDir()
	userConfig := filepath.Join(t.TempDir(), "ngrok.yml")
	if err := os.WriteFile(userConfig, []byte("version: \"3\"\nagent:\n    authtoken: x\n"), 0o600); err != nil {
		t.Fatalf("write user config: %v", err)
	}
	m := New(Deps{
		Dir: dir,
		Providers: []Provider{NgrokProvider(NgrokConfig{
			UserConfigPath: userConfig,
			OwnConfigPath:  ngrokConfigPath(dir),
		})},
	})

	if !m.HasAuthtoken() {
		t.Error("ngrok authenticates from the user's own config, so a token there must count")
	}
}

func TestHasAuthtokenFalseWhenNeitherConfigCarriesOne(t *testing.T) {
	dir := t.TempDir()
	userConfig := filepath.Join(t.TempDir(), "ngrok.yml")
	if err := os.WriteFile(userConfig, []byte("version: \"3\"\n"), 0o600); err != nil {
		t.Fatalf("write user config: %v", err)
	}
	if err := os.WriteFile(ngrokConfigPath(dir), []byte("version: \"3\"\nagent:\n    web_addr: 127.0.0.1:50893\n"), 0o600); err != nil {
		t.Fatalf("write own config: %v", err)
	}
	m := New(Deps{
		Dir: dir,
		Providers: []Provider{NgrokProvider(NgrokConfig{
			UserConfigPath: userConfig,
			OwnConfigPath:  ngrokConfigPath(dir),
		})},
	})

	if m.HasAuthtoken() {
		t.Error("a web_addr-only config and a version-only user config carry no token")
	}
}

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

func TestHasAuthtokenToleratesAMissingUserConfig(t *testing.T) {
	dir := t.TempDir()
	m := New(Deps{
		Dir: dir,
		Providers: []Provider{NgrokProvider(NgrokConfig{
			UserConfigPath: filepath.Join(t.TempDir(), "absent.yml"),
			OwnConfigPath:  ngrokConfigPath(dir),
		})},
	})

	if m.HasAuthtoken() {
		t.Error("no config files means no token")
	}
}
