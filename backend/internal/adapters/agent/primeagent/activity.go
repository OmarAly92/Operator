package primeagent

import (
	"encoding/json"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// DeriveActivityState maps the normalized events emitted by the Operator-managed
// Prime Agent extension to durable Operator activity state.
func DeriveActivityState(event string, payload []byte) (domain.ActivityState, bool) {
	switch event {
	case "session-start":
		return domain.ActivityIdle, true
	case "user-prompt-submit":
		return domain.ActivityActive, true
	case "stop":
		return domain.ActivityIdle, true
	case "session-end":
		var shutdown struct {
			Reason string `json:"reason"`
		}
		if err := json.Unmarshal(payload, &shutdown); err != nil || shutdown.Reason != "quit" {
			return "", false
		}
		return domain.ActivityExited, true
	default:
		return "", false
	}
}
