package tunnel

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type preparingProvider struct {
	*fakeProvider
	mu         sync.Mutex
	prepared   []int
	polled     []int
	prepareErr error
}

func newPreparingProvider(t *testing.T, name, script string) *preparingProvider {
	t.Helper()
	return &preparingProvider{fakeProvider: newFakeProvider(t, name, script)}
}

func (p *preparingProvider) Prepare(_, controlPort int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.prepareErr != nil {
		return p.prepareErr
	}
	p.prepared = append(p.prepared, controlPort)
	return nil
}

func (p *preparingProvider) PublicURL(ctx context.Context, controlPort int) (string, error) {
	p.mu.Lock()
	p.polled = append(p.polled, controlPort)
	p.mu.Unlock()
	return p.fakeProvider.PublicURL(ctx, controlPort)
}

func (p *preparingProvider) snapshot() (prepared, polled []int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]int{}, p.prepared...), append([]int{}, p.polled...)
}

func TestLaunchPreparesTheProviderWithThePortItWillPoll(t *testing.T) {
	provider := newPreparingProvider(t, "ngrok", sleepForeverScript)
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 46123, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateLive)

	prepared, polled := provider.snapshot()
	if len(prepared) == 0 {
		t.Fatal("the manager never prepared the provider before launching it")
	}
	if len(polled) == 0 {
		t.Fatal("the manager never polled the provider's control port")
	}
	if prepared[0] != polled[0] {
		t.Fatalf("prepared control port %d but polled %d: the launch-time preparation must use the port that is actually polled",
			prepared[0], polled[0])
	}
	if prepared[0] != 46123 {
		t.Fatalf("prepared control port = %d, want the reserved port 46123", prepared[0])
	}
}

func TestLaunchFailsWhenTheProviderCannotBePrepared(t *testing.T) {
	provider := newPreparingProvider(t, "ngrok", sleepForeverScript)
	provider.prepareErr = errors.New("cannot write ngrok config")

	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 46124, nil },
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err == nil {
		t.Fatal("a provider that cannot be prepared must not be launched")
	}
	if got := m.Status().State; got != StateFailed {
		t.Errorf("state = %q, want failed", got)
	}
}
