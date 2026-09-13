package tunnel

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type persistedTunnel struct {
	Provider  string    `json:"provider"`
	PID       int       `json:"pid"`
	StartTime string    `json:"startTime,omitempty"`
	StartedAt time.Time `json:"startedAt"`
}

func registryPath(dir string) string { return filepath.Join(dir, "tunnel-processes.json") }

func (m *Manager) Reap() {
	path := registryPath(m.dir)
	body, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	if err != nil {
		m.log.Warn("read tunnel process registry", "err", err)
		return
	}
	var entries []persistedTunnel
	if err := json.Unmarshal(body, &entries); err != nil {
		m.log.Warn("decode tunnel process registry", "err", err)
		if removeErr := os.Remove(path); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
			m.log.Warn("remove tunnel process registry", "err", removeErr)
		}
		return
	}
	for _, entry := range entries {
		if entry.PID <= 0 {
			continue
		}
		if entry.StartTime == "" {
			m.log.Warn("skip reaping tunnel process without a recorded start time",
				"provider", entry.Provider, "pid", entry.PID)
			continue
		}
		if err := forceKillPID(entry.PID, entry.StartTime); err != nil {
			m.log.Warn("reap orphaned tunnel process",
				"provider", entry.Provider, "pid", entry.PID, "err", err)
		}
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		m.log.Warn("remove stale tunnel process registry", "err", err)
	}
}

func (m *Manager) writeRegistry(entries []persistedTunnel) {
	if err := os.MkdirAll(m.dir, 0o700); err != nil {
		m.log.Warn("create tunnel state dir", "err", err)
		return
	}
	body, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		m.log.Warn("encode tunnel process registry", "err", err)
		return
	}
	tmp, err := os.CreateTemp(m.dir, ".tunnel-processes-*.tmp")
	if err != nil {
		m.log.Warn("create tunnel process registry temp file", "err", err)
		return
	}
	tmpName := tmp.Name()
	defer func() { _ = os.Remove(tmpName) }()
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		m.log.Warn("chmod tunnel process registry temp file", "err", err)
		return
	}
	if _, err := tmp.Write(body); err != nil {
		_ = tmp.Close()
		m.log.Warn("write tunnel process registry temp file", "err", err)
		return
	}
	if err := tmp.Close(); err != nil {
		m.log.Warn("close tunnel process registry temp file", "err", err)
		return
	}
	if err := os.Rename(tmpName, registryPath(m.dir)); err != nil {
		m.log.Warn("rename tunnel process registry into place", "err", err)
	}
}

func (m *Manager) clearRegistry() {
	if err := os.Remove(registryPath(m.dir)); err != nil && !errors.Is(err, os.ErrNotExist) {
		m.log.Warn("clear tunnel process registry", "err", err)
	}
}

func pidEntry(provider string, cmd *exec.Cmd, now time.Time) (persistedTunnel, bool) {
	if cmd == nil || cmd.Process == nil {
		return persistedTunnel{}, false
	}
	pid := cmd.Process.Pid
	return persistedTunnel{
		Provider:  provider,
		PID:       pid,
		StartTime: processStartTime(pid),
		StartedAt: now,
	}, true
}
