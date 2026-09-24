package ports

type TerminalHealth string

const (
	TerminalHealthy TerminalHealth = "ok"
	TerminalHung    TerminalHealth = "hung"
)

type TerminalHealthReader interface {
	TerminalHealth(handle RuntimeHandle) TerminalHealth
	WatchTerminalHealth(fn func(handleID string, health TerminalHealth)) (stop func())
}
