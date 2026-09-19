package tunnel

import "time"

type State string

const (
	StateOff          State = "off"
	StateDownloading  State = "downloading"
	StateStarting     State = "starting"
	StateLive         State = "live"
	StateReconnecting State = "reconnecting"
	StateFailed       State = "failed"
)

type Status struct {
	State          State
	Provider       string
	URL            string
	Error          string
	Since          time.Time
	Restarts       int
	NeedsAuthtoken bool
	LastProvider   string
	FallbackReason string
}

type FailureClass int

const (
	FailureUnknown FailureClass = iota
	FailureCredential
	FailureRefused
	FailureNetwork
)

type Failure struct {
	Class   FailureClass
	Message string
}
