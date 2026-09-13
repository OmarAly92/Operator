package tunnel

import (
	"context"
	"path/filepath"
	"testing"
	"time"
)

func newFallbackManager(t *testing.T, first, second *fakeProvider) *Manager {
	t.Helper()
	m := New(Deps{
		Dir:       t.TempDir(),
		Providers: []Provider{first, second},
		Binaries: perProviderStore{paths: map[string]string{
			first.name:  first.binary,
			second.name: second.binary,
		}},
		Now:         time.Now,
		Sleep:       func(context.Context, time.Duration) error { return nil },
		ReservePort: func() (int, error) { return 45999, nil },
	})
	m.SetLocalPort(3011)
	t.Cleanup(m.Close)
	return m
}

type perProviderStore struct{ paths map[string]string }

func (s perProviderStore) Ensure(_ context.Context, spec BinarySpec) (string, error) {
	return s.paths[spec.Name], nil
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

	m := newFallbackManager(t, ngrok, cloudflared)
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

	m := newFallbackManager(t, ngrok, cloudflared)
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

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)

	before := ngrok.urlCalls
	cloudflared.setHealthy(false)
	time.Sleep(100 * time.Millisecond)
	cloudflared.setHealthy(true)

	if ngrok.urlCalls > before {
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

	m := newFallbackManager(t, ngrok, cloudflared)
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if err := m.Disable(context.Background()); err != nil {
		t.Fatalf("Disable: %v", err)
	}

	before := ngrok.urlCalls
	_ = m.Enable(context.Background())
	waitForState(t, m, StateLive)
	if ngrok.urlCalls == before {
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

	m := newFallbackManager(t, ngrok, cloudflared)
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

	m := newFallbackManager(t, ngrok, cloudflared)
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
