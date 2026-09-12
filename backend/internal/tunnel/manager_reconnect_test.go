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
	if d < backoffFloor {
		s.mu.Lock()
		s.waits = append(s.waits, d)
		s.mu.Unlock()
		return nil
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-s.resume:
		s.mu.Lock()
		s.waits = append(s.waits, d)
		s.mu.Unlock()
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
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		ticker := time.NewTicker(20 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				sleeper.release(1)
			}
		}
	}()

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
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		status := m.Status()
		if status.State == StateLive && status.Restarts >= 1 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("status = %+v, want live with at least 1 restart", m.Status())
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
	restarted := false
	for time.Now().Before(deadline) {
		if m.Status().URL == "https://second-url.example" {
			return
		}
		if m.Status().Restarts >= 1 {
			restarted = true
		}
		if restarted {
			provider.setHealthy(true)
		}
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
