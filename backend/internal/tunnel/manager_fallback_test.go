package tunnel

import (
	"context"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func newFallbackManager(t *testing.T, first, second *fakeProvider) (*Manager, *perProviderStore) {
	t.Helper()
	store := &perProviderStore{paths: map[string]string{
		first.name:  first.binary,
		second.name: second.binary,
	}, launches: map[string]int{}}
	m := New(Deps{
		Dir:         t.TempDir(),
		Providers:   []Provider{first, second},
		Binaries:    store,
		Now:         time.Now,
		Sleep:       func(ctx context.Context, _ time.Duration) error { return yieldSleep(ctx) },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m, store
}

type perProviderStore struct {
	mu       sync.Mutex
	paths    map[string]string
	launches map[string]int
}

func (s *perProviderStore) Ensure(_ context.Context, spec BinarySpec) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.launches[spec.Name]++
	return s.paths[spec.Name], nil
}

func (s *perProviderStore) launchCount(name string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.launches[name]
}

func TestFallbackOnMissingAuthtokenSwitchesAndFlagsTheDialog(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{
		Class:   FailureCredential,
		Message: "authentication failed: ERR_NGROK_4018",
	})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURL("https://fallback.trycloudflare.com")

	m, _ := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Errorf("provider = %q, want cloudflared", status.Provider)
	}
	if status.URL != "https://fallback.trycloudflare.com" {
		t.Errorf("URL = %q", status.URL)
	}
	if !status.NeedsAuthtoken {
		t.Error("ERR_NGROK_4018 must flag that the authtoken dialog is wanted")
	}
	if status.Error == "" {
		t.Error("want ngrok's own message carried through")
	}
}

func TestFallbackOnLimitAfterServingSwitchesAndKeepsTheMessage(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m, _ := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Errorf("provider = %q, want cloudflared", status.Provider)
	}
	if status.Error != "account limit exceeded" {
		t.Errorf("error = %q, want the provider's message verbatim", status.Error)
	}
	if status.NeedsAuthtoken {
		t.Error("a quota refusal is not an authtoken problem")
	}
}

func TestFallbackIsStickyAndDoesNotFlapBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m, store := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)

	before := store.launchCount("ngrok")
	cloudflared.setHealthy(false)
	time.Sleep(100 * time.Millisecond)
	cloudflared.setHealthy(true)

	if store.launchCount("ngrok") > before {
		t.Error("a refused provider must not be retried until Disable")
	}
	if got := m.Status().Provider; got != "cloudflared" {
		t.Errorf("provider = %q, want the sticky fallback", got)
	}
}

func TestDisableClearsTheStickyFallback(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "account limit exceeded"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m, store := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}

	before := store.launchCount("ngrok")
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if store.launchCount("ngrok") == before {
		t.Error("after Disable, ngrok must be attempted again")
	}
}

func TestAFailedTunnelCanBeEnabledAgainWithoutADaemonRestart(t *testing.T) {
	cfMarker := filepath.Join(t.TempDir(), "cloudflared-attempted")
	t.Setenv("TUNNEL_TEST_CF_MARKER", cfMarker)

	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "ngrok refused"})
	cloudflared := newFakeProvider(t, "cloudflared",
		"#!/bin/sh\nif [ -f \"$TUNNEL_TEST_CF_MARKER\" ]; then while true; do sleep 1; done; fi\ntouch \"$TUNNEL_TEST_CF_MARKER\"\necho 'boom' >&2\nexit 1\n")
	cloudflared.setFailure(Failure{Class: FailureRefused, Message: "cloudflared refused"})

	m, _ := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && m.Status().State != StateFailed {
		time.Sleep(5 * time.Millisecond)
	}
	if got := m.Status().State; got != StateFailed {
		t.Fatalf("state = %q, want failed before the retry can be exercised", got)
	}

	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable after a failed tunnel: %v", err)
	}
	status := waitForState(t, m, StateLive)
	if status.State != StateLive {
		t.Fatalf("state = %q after re-enabling a failed tunnel, want live: Enable must not be a silent no-op once the async path has failed", status.State)
	}
}

func TestNoFallbackWhenBothProvidersAreRefused(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", exitImmediatelyScript)
	ngrok.setFailure(Failure{Class: FailureRefused, Message: "ngrok refused"})
	cloudflared := newFakeProvider(t, "cloudflared", exitImmediatelyScript)
	cloudflared.setFailure(Failure{Class: FailureRefused, Message: "cloudflared refused"})

	m, _ := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if m.Status().State == StateFailed {
			if m.Status().Error == "" {
				t.Error("want an error message when every provider is refused")
			}
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("state = %q, want failed", m.Status().State)
}

func newTimeoutFallbackManager(t *testing.T, first, second *fakeProvider, clock *fakeClock) (*Manager, *perProviderStore) {
	t.Helper()
	store := &perProviderStore{paths: map[string]string{
		first.name:  first.binary,
		second.name: second.binary,
	}, launches: map[string]int{}}
	m := New(Deps{
		Dir:       t.TempDir(),
		Providers: []Provider{first, second},
		Binaries:  store,
		Now:       clock.Now,
		Sleep: func(ctx context.Context, _ time.Duration) error {
			clock.advance(startTimeout / 4)
			return yieldSleep(ctx)
		},
		ReservePort: func() (int, error) { return 45998, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m, store
}

const crlLoggingScript = "#!/bin/sh\necho '{\"err\":\"failed to send authentication request: failed to fetch CRL. errors encountered: asn1: structure error: length too large\",\"lvl\":\"eror\",\"msg\":\"failed to reconnect session\"}'\nwhile true; do sleep 1; done\n"

func TestStartTimeoutSurfacesTheProviderLogAndFallsBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", crlLoggingScript)
	ngrok.setURLErr(ErrNoURLYet)
	ngrok.setFailure(Failure{Class: FailureNetwork, Message: "ngrok could not fetch its certificate revocation list"})
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURL("https://fallback.trycloudflare.com")

	m, store := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable: %v", err)
	}

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Fatalf("provider = %q, want cloudflared after ngrok never published", status.Provider)
	}
	if status.LastProvider != "ngrok" {
		t.Errorf("LastProvider = %q, want ngrok", status.LastProvider)
	}
	if status.FallbackReason != "ngrok could not fetch its certificate revocation list" {
		t.Errorf("FallbackReason = %q, want the classified log message", status.FallbackReason)
	}
	if status.NeedsAuthtoken {
		t.Error("a network failure is not an authtoken problem")
	}
	if store.launchCount("ngrok") != 1 {
		t.Errorf("ngrok launched %d times, want exactly one attempt before fallback", store.launchCount("ngrok"))
	}
}

func TestStartTimeoutWithoutAnyLogStillFallsBack(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", sleepForeverScript)
	ngrok.setURLErr(ErrNoURLYet)
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)

	m, _ := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateLive)
	if status.Provider != "cloudflared" {
		t.Fatalf("provider = %q, want cloudflared", status.Provider)
	}
	want := "tunnel: ngrok published no url within 1m0s"
	if status.FallbackReason != want {
		t.Errorf("FallbackReason = %q, want %q", status.FallbackReason, want)
	}
}

func TestStartTimeoutOnTheLastProviderFailsTerminally(t *testing.T) {
	ngrok := newFakeProvider(t, "ngrok", sleepForeverScript)
	ngrok.setURLErr(ErrNoURLYet)
	cloudflared := newFakeProvider(t, "cloudflared", sleepForeverScript)
	cloudflared.setURLErr(ErrNoURLYet)

	m, _ := newTimeoutFallbackManager(t, ngrok, cloudflared, newFakeClock())
	_ = m.Enable(context.Background())

	status := waitForState(t, m, StateFailed)
	if status.Error != "tunnel: cloudflared published no url within 1m0s" {
		t.Errorf("Error = %q, want the last provider's timeout", status.Error)
	}
	cloudflared.setURLErr(nil)
	if err := m.Enable(context.Background()); err != nil {
		t.Fatalf("Enable after terminal failure: %v", err)
	}
	if got := waitForState(t, m, StateLive); got.LastProvider != "" || got.FallbackReason != "" {
		t.Errorf("a fresh Enable must clear LastProvider/FallbackReason, got %q / %q", got.LastProvider, got.FallbackReason)
	}
}
