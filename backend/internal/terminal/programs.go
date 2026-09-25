package terminal

import "github.com/OmarAly92/operator/backend/internal/ports"

func (m *Manager) startProgramWatch() {
	reader, ok := m.src.(ports.TerminalProgramReader)
	if !ok {
		return
	}
	m.stopProgramWatch = reader.WatchTerminalPrograms(m.publishProgramEvent)
}

func (m *Manager) terminalTitles() map[string]string {
	reader, ok := m.src.(ports.TerminalProgramReader)
	if !ok {
		return nil
	}
	return reader.TerminalTitles()
}

func programFrame(handleID string, event ports.TerminalProgramEvent) serverMsg {
	if event.Kind == ports.TerminalProgramNotification {
		return serverMsg{Ch: chPrograms, ID: handleID, Type: msgNotification, Title: event.Title, Body: event.Body}
	}
	return serverMsg{Ch: chPrograms, ID: handleID, Type: msgTitle, Title: event.Title}
}

func (m *Manager) publishProgramEvent(handleID string, event ports.TerminalProgramEvent) {
	frame := programFrame(handleID, event)
	m.mu.Lock()
	defer m.mu.Unlock()
	for c := range m.conns {
		c.mu.Lock()
		subscribed := c.programsSubscribed && !c.closed
		c.mu.Unlock()
		if subscribed {
			c.enqueue(frame)
		}
	}
}

func (c *connState) handlePrograms(msg clientMsg) {
	switch msg.Type {
	case msgSubscribe:
		c.mu.Lock()
		already := c.programsSubscribed
		c.programsSubscribed = true
		c.mu.Unlock()
		if already {
			return
		}
		for id, title := range c.mgr.terminalTitles() {
			c.enqueue(programFrame(id, ports.TerminalProgramEvent{Kind: ports.TerminalProgramTitle, Title: title}))
		}
	case msgUnsubscribe:
		c.mu.Lock()
		c.programsSubscribed = false
		c.mu.Unlock()
	}
}

func appearanceOf(msg clientMsg) ports.TerminalAppearance {
	return ports.TerminalAppearance{
		CellWidth:  msg.CellWidth,
		CellHeight: msg.CellHeight,
		Foreground: msg.Foreground,
		Background: msg.Background,
	}
}

func (a *attachment) setAppearance(appearance ports.TerminalAppearance) error {
	a.mu.Lock()
	a.appearance = &appearance
	pty := a.pty
	a.mu.Unlock()
	return applyAppearance(pty, appearance)
}

func applyAppearance(pty ports.Stream, appearance ports.TerminalAppearance) error {
	setter, ok := pty.(ports.AppearanceSetter)
	if !ok {
		return nil
	}
	return setter.SetAppearance(appearance)
}
