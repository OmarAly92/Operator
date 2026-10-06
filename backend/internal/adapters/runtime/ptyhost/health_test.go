package ptyhost

import (
	"context"
	"net"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type healthEvent struct {
	id     string
	health ports.TerminalHealth
}

type healthRecorder struct {
	mu     sync.Mutex
	events []healthEvent
}

func (h *healthRecorder) record(id string, health ports.TerminalHealth) {
	h.mu.Lock()
	h.events = append(h.events, healthEvent{id: id, health: health})
	h.mu.Unlock()
}

func (h *healthRecorder) snapshot() []healthEvent {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]healthEvent(nil), h.events...)
}

func silentHost(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	var mu sync.Mutex
	var conns []net.Conn
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			mu.Lock()
			conns = append(conns, c)
			mu.Unlock()
		}
	}()
	t.Cleanup(func() {
		_ = ln.Close()
		mu.Lock()
		for _, c := range conns {
			_ = c.Close()
		}
		mu.Unlock()
	})
	return ln.Addr().String()
}

const silentProbeTimeout = 50 * time.Millisecond

func probingRuntime(t *testing.T, id, addr string) (*Runtime, *healthRecorder) {
	t.Helper()
	isolateRegistry(t)
	rt := New(Options{})
	rt.probeTimeout = silentProbeTimeout
	rt.sessions[id] = &hostSession{addr: addr, pid: livePID()}
	rec := &healthRecorder{}
	stop := rt.WatchTerminalHealth(rec.record)
	t.Cleanup(stop)
	return rt, rec
}

func probeAt(t *testing.T, rt *Runtime, id, addr string, timeout time.Duration) (bool, error) {
	t.Helper()
	rt.mu.Lock()
	rt.sessions[id].addr = addr
	rt.mu.Unlock()
	rt.probeTimeout = timeout
	return rt.IsAlive(context.Background(), ports.RuntimeHandle{ID: id})
}

func TestAHostThatStopsAnsweringIsHungAfterThreeFailedProbesNotBefore(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	handle := ports.RuntimeHandle{ID: "stuck"}
	for i := 1; i <= 2; i++ {
		if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
			t.Fatalf("probe %d of a silent host returned no error", i)
		}
		if got := rt.TerminalHealth(handle); got != ports.TerminalHealthy {
			t.Fatalf("after %d failed probes health = %q, want %q", i, got, ports.TerminalHealthy)
		}
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events before the third failed probe = %v, want none", events)
	}
	if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
		t.Fatal("third probe of a silent host returned no error")
	}
	if got := rt.TerminalHealth(handle); got != ports.TerminalHung {
		t.Fatalf("after 3 failed probes health = %q, want %q", got, ports.TerminalHung)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
	if _, err := probeAt(t, rt, "stuck", silent, silentProbeTimeout); err == nil {
		t.Fatal("fourth probe of a silent host returned no error")
	}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("a fourth failed probe announced again: %v", events)
	}
}

func TestAHungHostThatAnswersAgainIsHealthy(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	live := startServe(t, 4101)
	defer live.cancel()
	alive, err := probeAt(t, rt, "stuck", live.addr, isAliveTimeout)
	if err != nil || !alive {
		t.Fatalf("probe of the answering host = (%v, %v), want (true, nil)", alive, err)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHealthy {
		t.Fatalf("health after an answered probe = %q, want %q", got, ports.TerminalHealthy)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}, {id: "stuck", health: ports.TerminalHealthy}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
}

func TestSlowProbesBetweenAnswersNeverMarkAHostHung(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "slow", silent)
	live := startServe(t, 4102)
	defer live.cancel()
	sequence := []string{silent, silent, live.addr, silent, silent, live.addr, silent}
	for i, addr := range sequence {
		timeout := silentProbeTimeout
		if addr == live.addr {
			timeout = isAliveTimeout
		}
		_, _ = probeAt(t, rt, "slow", addr, timeout)
		if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "slow"}); got != ports.TerminalHealthy {
			t.Fatalf("after probe %d health = %q, want %q", i+1, got, ports.TerminalHealthy)
		}
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events = %v, want none", events)
	}
}

func TestARefusedHostIsGoneNotHung(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	refused := ln.Addr().String()
	_ = ln.Close()
	rt, rec := probingRuntime(t, "gone", refused)
	for i := 1; i <= hungAfterFailedProbes+1; i++ {
		alive, err := probeAt(t, rt, "gone", refused, silentProbeTimeout)
		if alive || err != nil {
			t.Fatalf("probe %d of a refused host = (%v, %v), want (false, nil)", i, alive, err)
		}
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "gone"}); got != ports.TerminalHealthy {
		t.Fatalf("health of a refused host = %q, want %q", got, ports.TerminalHealthy)
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("health events = %v, want none", events)
	}
}

func TestDestroyingAHungHostAnnouncesItHealthy(t *testing.T) {
	silent := silentHost(t)
	rt, rec := probingRuntime(t, "stuck", silent)
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	rt.killHost = func(string) error { return nil }
	rt.pidIsAlive = func(int) bool { return false }
	if err := rt.Destroy(context.Background(), ports.RuntimeHandle{ID: "stuck"}); err != nil {
		t.Fatalf("Destroy: %v", err)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHealthy {
		t.Fatalf("health after Destroy = %q, want %q", got, ports.TerminalHealthy)
	}
	want := []healthEvent{{id: "stuck", health: ports.TerminalHung}, {id: "stuck", health: ports.TerminalHealthy}}
	if events := rec.snapshot(); !reflect.DeepEqual(events, want) {
		t.Fatalf("health events = %v, want %v", events, want)
	}
}

func TestAStoppedHealthWatcherHearsNothing(t *testing.T) {
	isolateRegistry(t)
	silent := silentHost(t)
	rt := New(Options{})
	rt.sessions["stuck"] = &hostSession{addr: silent, pid: livePID()}
	rec := &healthRecorder{}
	stop := rt.WatchTerminalHealth(rec.record)
	stop()
	for range hungAfterFailedProbes {
		_, _ = probeAt(t, rt, "stuck", silent, silentProbeTimeout)
	}
	if got := rt.TerminalHealth(ports.RuntimeHandle{ID: "stuck"}); got != ports.TerminalHung {
		t.Fatalf("health = %q, want %q", got, ports.TerminalHung)
	}
	if events := rec.snapshot(); len(events) != 0 {
		t.Fatalf("a stopped watcher heard %v", events)
	}
}
