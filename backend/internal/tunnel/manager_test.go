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

func waitForCallCount(t *testing.T, provider *fakeProvider, want int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if provider.callCount() >= want {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("callCount = %d, want >= %d", provider.callCount(), want)
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

func TestManagerDisableWaitsOutAnInFlightPublicURLBeforeReturning(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	provider.setURLDelay(300 * time.Millisecond)
	m := newTestManager(t, provider)

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}
	waitForState(t, m, StateStarting)
	waitForCallCount(t, provider, 1)

	start := time.Now()
	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}
	elapsed := time.Since(start)
	if elapsed < 200*time.Millisecond {
		t.Errorf("Disable returned after %s, want it to wait out the in-flight PublicURL call", elapsed)
	}

	status := m.Status()
	if status.State != StateOff {
		t.Errorf("state = %q immediately after Disable, want off", status.State)
	}

	time.Sleep(500 * time.Millisecond)
	status = m.Status()
	if status.State != StateOff {
		t.Errorf("state = %q after the delayed PublicURL resolved, want off (must not resurrect StateLive)", status.State)
	}
	if status.URL != "" {
		t.Errorf("URL = %q after Disable, want cleared", status.URL)
	}
}

func TestManagerDisableDoesNotResurrectTrustedHeaderAfterInFlightPublicURL(t *testing.T) {
	provider := newFakeProvider(t, "ngrok", sleepForeverScript)
	provider.setURLDelay(300 * time.Millisecond)
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
	waitForState(t, m, StateStarting)
	waitForCallCount(t, provider, 1)

	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}

	select {
	case got := <-headers:
		if got != "" {
			t.Errorf("header = %q on stop, want empty", got)
		}
	case <-time.After(time.Second):
		t.Fatal("Disable did not call OnProvider(\"\")")
	}

	select {
	case got := <-headers:
		t.Errorf("unexpected OnProvider call after Disable returned: %q", got)
	case <-time.After(500 * time.Millisecond):
	}
}
