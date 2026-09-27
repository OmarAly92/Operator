package ports

import "time"

type TerminalProgramEventKind string

const (
	TerminalProgramTitle        TerminalProgramEventKind = "title"
	TerminalProgramNotification TerminalProgramEventKind = "notification"
	TerminalProgramActivity     TerminalProgramEventKind = "activity"
)

type TerminalActivity string

const (
	TerminalActivityActive    TerminalActivity = "active"
	TerminalActivityIdle      TerminalActivity = "idle"
	TerminalActivityPrompting TerminalActivity = "prompting"
)

type TerminalProgramEvent struct {
	Kind       TerminalProgramEventKind
	Title      string
	Body       string
	Activity   TerminalActivity
	At         time.Time
	Tail       string
	CursorLine string
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
