package domain

import "errors"

type BackgroundTaskKind string

const (
	BackgroundTaskShell   BackgroundTaskKind = "shell"
	BackgroundTaskAgent   BackgroundTaskKind = "agent"
	BackgroundTaskMonitor BackgroundTaskKind = "monitor"
)

type BackgroundTaskStatus string

const (
	BackgroundTaskRunning   BackgroundTaskStatus = "running"
	BackgroundTaskCompleted BackgroundTaskStatus = "completed"
	BackgroundTaskFailed    BackgroundTaskStatus = "failed"
	BackgroundTaskKilled    BackgroundTaskStatus = "killed"
	BackgroundTaskStopped   BackgroundTaskStatus = "stopped"
)

func ParseBackgroundTaskStatus(s string) (BackgroundTaskStatus, bool) {
	switch BackgroundTaskStatus(s) {
	case BackgroundTaskRunning, BackgroundTaskCompleted, BackgroundTaskFailed, BackgroundTaskKilled, BackgroundTaskStopped:
		return BackgroundTaskStatus(s), true
	default:
		return "", false
	}
}

func (s BackgroundTaskStatus) Finished() bool {
	return s != "" && s != BackgroundTaskRunning
}

type BackgroundTask struct {
	TaskID      string               `json:"taskId"`
	Kind        BackgroundTaskKind   `json:"kind"`
	Status      BackgroundTaskStatus `json:"status"`
	ToolUseID   string               `json:"toolUseId,omitempty"`
	Description string               `json:"description,omitempty"`
	Command     string               `json:"command,omitempty"`
	Summary     string               `json:"summary,omitempty"`
	ExitCode    *int                 `json:"exitCode,omitempty"`
	DurationMs  *int64               `json:"durationMs,omitempty"`
	OutputFile  string               `json:"outputFile,omitempty"`
	StartedAt   string               `json:"startedAt,omitempty"`
	EndedAt     string               `json:"endedAt,omitempty"`
}

var (
	ErrTaskNotFound        = errors.New("background task not found")
	ErrTaskProcessNotFound = errors.New("background task process not found")
	ErrTaskFinished        = errors.New("background task already finished")
	ErrTaskAmbiguous       = errors.New("background task matches more than one target")
	ErrTaskStopUnsupported = errors.New("background task cannot be stopped")
	ErrTaskStopUnconfirmed = errors.New("background task stop was not confirmed")
)
