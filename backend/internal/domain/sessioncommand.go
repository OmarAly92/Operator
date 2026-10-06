package domain

type SessionCommand string

const (
	CommandStop           SessionCommand = "stop"
	CommandCompact        SessionCommand = "compact"
	CommandModel          SessionCommand = "model"
	CommandPermissionMode SessionCommand = "permission-mode"
)

func ParseSessionCommand(raw string) (SessionCommand, bool) {
	switch SessionCommand(raw) {
	case CommandStop, CommandCompact, CommandModel, CommandPermissionMode:
		return SessionCommand(raw), true
	default:
		return "", false
	}
}
