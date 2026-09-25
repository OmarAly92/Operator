package sessionmanager

import (
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func (m *Manager) permissionModeReaderFor(harness domain.AgentHarness) (ports.TerminalPermissionModeReader, bool) {
	if m.permissionModeReader != nil {
		return m.permissionModeReader, true
	}
	agent, found := m.agents.Agent(harness)
	if !found {
		return nil, false
	}
	reader, ok := agent.(ports.TerminalPermissionModeReader)
	return reader, ok
}

func (m *Manager) PermissionModeSupport(harness domain.AgentHarness, launch domain.PermissionMode, version string) (bool, []domain.PermissionMode) {
	reader, ok := m.permissionModeReaderFor(harness)
	if !ok || !reader.PermissionModeVerified(version) {
		return false, nil
	}
	return true, reader.PermissionModeCycle(ports.NormalizePermissionMode(launch))
}
