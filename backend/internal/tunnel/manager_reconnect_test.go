package tunnel

import (
	"context"
	"sync"
	"testing"
	"time"
)

const fakePollDelay = time.Millisecond

func isBackoffWait(d time.Duration) bool {
	return d >= backoffFloor && d != healthInterval
}

func yieldSleep(ctx context.Context) error {
	timer := time.NewTimer(fakePollDelay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

type recordingSleeper struct {
	mu     sync.Mutex
	waits  []time.Duration
	resume chan struct{}
}

func newRecordingSleeper() *recordingSleeper {
	return &recordingSleeper{resume: make(chan struct{}, 128)}
}

func (s *recordingSleeper) sleep(ctx context.Context, d time.Duration) error {
	if !isBackoffWait(d) {
		return yieldSleep(ctx)
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
	return append([]time.Duration{}, s.waits...)
}

func (s *recordingSleeper) waitForBackoffWaits(t *testing.T, want int) []time.Duration {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	var waits []time.Duration
	for time.Now().Before(deadline) {
		waits = s.backoffWaits()
		if len(waits) >= want {
			return waits
		}
		time.Sleep(5 * time.Millisecond)
	}
	return waits
}

func (s *recordingSleeper) release(n int) {
	for i := 0; i < n; i++ {
		s.resume <- struct{}{}
	}
}

func dripFeed(t *testing.T, sleeper *recordingSleeper, interval time.Duration) {
	t.Helper()
	stop := make(chan struct{})
	t.Cleanup(func() { close(stop) })
	go func() {
		ticker := time.NewTicker(interval)
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
}

func TestManagerRestartsAfterUnexpectedExit(t *testing.T) {
	restartOnce := "#!/bin/sh\nif [ -f \"$TUNNEL_TEST_MARKER\" ]; then while true; do sleep 1; done; fi\ntouch \"$TUNNEL_TEST_MARKER\"\nexit 1\n"
	provider := newFakeProvider(t, "ngrok", restartOnce)
	t.Setenv("TUNNEL_TEST_MARKER", t.TempDir()+"/marker")

	sleeper := newRecordingSleeper()
	dripFeed(t, sleeper, 20*time.Millisecond)

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

	sleeper.release(8)

	waits := sleeper.waitForBackoffWaits(t, 4)
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

	sleeper.release(12)
	sleeper.waitForBackoffWaits(t, 6)

	if got := m.Status().State; got == StateFailed {
		t.Error("a network-shaped failure must stay reconnecting, never failed")
	}
}

func TestManagerRestartsWhenHealthProbeReportsNotOnline(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	sleeper := newRecordingSleeper()
	dripFeed(t, sleeper, time.Millisecond)

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
	dripFeed(t, sleeper, time.Millisecond)

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

func TestReconnectOnSameProviderClearsThePriorErrorOnceLive(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})
	sleeper := newRecordingSleeper()
	dripFeed(t, sleeper, time.Millisecond)

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
	restarted := false
	for time.Now().Before(deadline) {
		if m.Status().Restarts >= 1 {
			restarted = true
		}
		if restarted {
			provider.setHealthy(true)
		}
		if restarted && m.Status().State == StateLive {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}

	status := m.Status()
	if status.State != StateLive {
		t.Fatalf("state = %q, want live after the same provider recovered", status.State)
	}
	if status.Error != "" {
		t.Errorf("Error = %q once the same provider recovered, want cleared", status.Error)
	}
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

type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func newFakeClock() *fakeClock {
	return &fakeClock{now: time.Now()}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func (c *fakeClock) sleep(ctx context.Context, _ time.Duration) error {
	return yieldSleep(ctx)
}

func TestManagerStaleFirstAttemptURLTimeoutDoesNotKillARecoveredTunnel(t *testing.T) {
	restartOnce := "#!/bin/sh\nif [ -f \"$TUNNEL_TEST_MARKER\" ]; then while true; do sleep 1; done; fi\ntouch \"$TUNNEL_TEST_MARKER\"\nexit 1\n"
	provider := newFakeProvider(t, "ngrok", restartOnce)
	t.Setenv("TUNNEL_TEST_MARKER", t.TempDir()+"/marker")
	provider.setFailURLOnPort(45999)
	provider.setFailure(Failure{Class: FailureNetwork, Message: "edge unreachable"})

	nextPort := 45999
	var portMu sync.Mutex
	reservePort := func() (int, error) {
		portMu.Lock()
		defer portMu.Unlock()
		p := nextPort
		nextPort++
		return p, nil
	}

	clock := newFakeClock()
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{provider},
		Binaries:    fakeStore{path: provider.binary},
		Now:         clock.Now,
		Sleep:       clock.sleep,
		ReservePort: reservePort,
	})
	m.SetLocalPort(3011)
	defer m.Close()

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}

	restartDeadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(restartDeadline) {
		if m.Status().Restarts >= 1 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if got := m.Status().Restarts; got < 1 {
		t.Fatalf("restarts = %d, want at least 1 before this regression can be exercised", got)
	}

	status := waitForState(t, m, StateLive)
	if status.State != StateLive {
		t.Fatalf("state = %q, want live", status.State)
	}

	clock.advance(startTimeout + time.Second)
	time.Sleep(300 * time.Millisecond)

	if got := m.Status().State; got != StateLive {
		t.Errorf("state = %q once the original first attempt's url-await window would have elapsed, want live: a stale runAwaitURL must not tear down a since-recovered tunnel", got)
	}
}
