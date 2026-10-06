package ptyhost

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/ptyregistry"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func waitUntilGone(t *testing.T, rt *Runtime, handle ports.RuntimeHandle) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		alive, err := rt.IsAlive(context.Background(), handle)
		if err == nil && !alive {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("host never reported gone: alive=%v err=%v", alive, err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func registryEntriesFor(t *testing.T, id string) []ptyregistry.Entry {
	t.Helper()
	entries, err := ptyregistry.List()
	if err != nil {
		t.Fatalf("registry list: %v", err)
	}
	var out []ptyregistry.Entry
	for _, e := range entries {
		if e.SessionID == id {
			out = append(out, e)
		}
	}
	return out
}

func TestCreateReplacesAHostThatDiedWithoutDestroy(t *testing.T) {
	isolateRegistry(t)
	const id = "sess-died"
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	ctx := context.Background()

	handle, err := rt.Create(ctx, ports.RuntimeConfig{
		SessionID:     domain.SessionID(id),
		WorkspacePath: t.TempDir(),
		Argv:          []string{"sh"},
	})
	if err != nil {
		t.Fatalf("first Create: %v", err)
	}
	dead := hosts[id]
	dead.cleanup(t)
	waitUntilGone(t, rt, handle)
	historyFile := seedHistoryFile(t, id)

	relaunched, err := rt.Create(ctx, ports.RuntimeConfig{
		SessionID:      domain.SessionID(id),
		WorkspacePath:  t.TempDir(),
		Argv:           []string{"sh"},
		RestoreHistory: true,
	})
	if err != nil {
		t.Fatalf("Create after the host died = %v, want a fresh host", err)
	}
	fresh := hosts[id]
	defer fresh.cleanup(t)
	if fresh == dead || fresh.addr == dead.addr {
		t.Fatalf("Create reused the dead host at %s", dead.addr)
	}
	if alive, err := rt.IsAlive(ctx, relaunched); err != nil || !alive {
		t.Fatalf("IsAlive on the fresh host = %v, %v; want true", alive, err)
	}
	entries := registryEntriesFor(t, id)
	if len(entries) != 1 || entries[0].PipePath != fresh.addr {
		t.Fatalf("registry entries for %s = %+v, want only the fresh host at %s", id, entries, fresh.addr)
	}
	if _, err := os.Stat(historyFile); err != nil {
		t.Fatalf("replacing the dead host lost the history the new host must read: %v", err)
	}
}

func TestCreateStillRefusesADuplicateOfALiveHost(t *testing.T) {
	isolateRegistry(t)
	const id = "sess-live-dup"
	hosts := map[string]*inProcHost{}
	rt := New(Options{Spawner: fakeSpawnerFor(t, hosts, livePID())})
	ctx := context.Background()
	cfg := ports.RuntimeConfig{SessionID: domain.SessionID(id), WorkspacePath: t.TempDir(), Argv: []string{"sh"}}

	if _, err := rt.Create(ctx, cfg); err != nil {
		t.Fatalf("first Create: %v", err)
	}
	live := hosts[id]
	defer live.cleanup(t)

	_, err := rt.Create(ctx, cfg)
	if !errors.Is(err, ports.ErrRuntimeSessionExists) {
		t.Fatalf("duplicate Create of a live host = %v, want ports.ErrRuntimeSessionExists", err)
	}
	if hosts[id] != live {
		t.Fatal("a refused duplicate Create spawned another host")
	}
	entries := registryEntriesFor(t, id)
	if len(entries) != 1 || entries[0].PipePath != live.addr {
		t.Fatalf("registry entries for %s = %+v, want the live host at %s", id, entries, live.addr)
	}
}

func TestCreateRefusesADuplicateOfAnInFlightCreate(t *testing.T) {
	isolateRegistry(t)
	rt := New(Options{Spawner: fakeSpawnerFor(t, nil, livePID())})
	rt.mu.Lock()
	rt.sessions["sess-in-flight"] = nil
	rt.mu.Unlock()

	_, err := rt.Create(context.Background(), ports.RuntimeConfig{
		SessionID:     "sess-in-flight",
		WorkspacePath: t.TempDir(),
		Argv:          []string{"sh"},
	})
	if !errors.Is(err, ports.ErrRuntimeSessionExists) {
		t.Fatalf("Create while another Create holds the slot = %v, want ports.ErrRuntimeSessionExists", err)
	}
}
