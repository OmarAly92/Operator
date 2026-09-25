package ports

type TerminalProgramEventKind string

const (
	TerminalProgramTitle        TerminalProgramEventKind = "title"
	TerminalProgramNotification TerminalProgramEventKind = "notification"
)

type TerminalProgramEvent struct {
	Kind  TerminalProgramEventKind
	Title string
	Body  string
}

type TerminalProgramReader interface {
	TerminalTitles() map[string]string
	WatchTerminalPrograms(fn func(handleID string, event TerminalProgramEvent)) (stop func())
}

type TerminalAppearance struct {
	CellWidth  int
	CellHeight int
	Foreground string
	Background string
}

type AppearanceSetter interface {
	SetAppearance(appearance TerminalAppearance) error
}
