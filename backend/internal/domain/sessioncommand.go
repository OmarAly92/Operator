package domain

type SessionCommand string

const (
	CommandStop    SessionCommand = "stop"
	CommandCompact SessionCommand = "compact"
	CommandModel   SessionCommand = "model"
)

func ParseSessionCommand(raw string) (SessionCommand, bool) {
	switch SessionCommand(raw) {
	case CommandStop:
		return CommandStop, true
	case CommandCompact:
		return CommandCompact, true
	case CommandModel:
		return CommandModel, true
	default:
		return "", false
	}
}
