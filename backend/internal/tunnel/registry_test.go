package tunnel

import (
	"context"
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
