package ptyhost

import "github.com/OmarAly92/operator/backend/internal/ports"

const hungAfterFailedProbes = 3

var _ ports.TerminalHealthReader = (*Runtime)(nil)

func (r *Runtime) TerminalHealth(handle ports.RuntimeHandle) ports.TerminalHealth {
	r.mu.Lock()
	defer r.mu.Unlock()
	if sess := r.sessions[handle.ID]; sess != nil && sess.failedProbes >= hungAfterFailedProbes {
		return ports.TerminalHung
	}
	return ports.TerminalHealthy
}

func (r *Runtime) WatchTerminalHealth(fn func(handleID string, health ports.TerminalHealth)) func() {
	r.watchMu.Lock()
	id := r.nextWatcher
	r.nextWatcher++
	r.watchers[id] = fn
	r.watchMu.Unlock()
	return func() {
		r.watchMu.Lock()
		delete(r.watchers, id)
		r.watchMu.Unlock()
	}
}

func (r *Runtime) recordProbe(handleID string, sess *hostSession, probeErr error) {
	r.mu.Lock()
	wasHung := sess.failedProbes >= hungAfterFailedProbes
	if probeErr != nil {
		sess.failedProbes++
	} else {
		sess.failedProbes = 0
	}
	isHung := sess.failedProbes >= hungAfterFailedProbes
	r.mu.Unlock()
	if wasHung == isHung {
		return
	}
	if isHung {
		r.notifyHealth(handleID, ports.TerminalHung)
		return
	}
	r.notifyHealth(handleID, ports.TerminalHealthy)
}

func (r *Runtime) notifyHealth(handleID string, health ports.TerminalHealth) {
	r.watchMu.Lock()
	fns := make([]func(string, ports.TerminalHealth), 0, len(r.watchers))
	for _, fn := range r.watchers {
		fns = append(fns, fn)
	}
	r.watchMu.Unlock()
	for _, fn := range fns {
		fn(handleID, health)
	}
}
