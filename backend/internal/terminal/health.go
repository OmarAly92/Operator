package terminal

import "github.com/OmarAly92/operator/backend/internal/ports"

func (m *Manager) startHealthWatch() {
	reader, ok := m.src.(ports.TerminalHealthReader)
	if !ok {
		return
	}
	m.stopHealthWatch = reader.WatchTerminalHealth(m.publishHealth)
}

func (m *Manager) publishHealth(handleID string, health ports.TerminalHealth) {
	if health == ports.TerminalHung {
		m.log.Warn("terminal host stopped responding", "id", handleID)
	} else {
		m.log.Info("terminal host is responding again", "id", handleID)
	}
	m.sharedMu.Lock()
	var conns []*connState
	if s := m.shared[handleID]; s != nil {
		conns = make([]*connState, 0, len(s.members))
		for c := range s.members {
			conns = append(conns, c)
		}
	}
	m.sharedMu.Unlock()
	for _, c := range conns {
		c.enqueue(healthFrame(handleID, health))
	}
}

func (m *Manager) terminalHealth(handleID string) ports.TerminalHealth {
	reader, ok := m.src.(ports.TerminalHealthReader)
	if !ok {
		return ports.TerminalHealthy
	}
	return reader.TerminalHealth(ports.RuntimeHandle{ID: handleID})
}

func healthFrame(handleID string, health ports.TerminalHealth) serverMsg {
	return serverMsg{Ch: chTerminal, ID: handleID, Type: msgHealth, Health: string(health)}
}
