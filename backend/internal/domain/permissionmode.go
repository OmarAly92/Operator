package domain

import "encoding/json"

type PermissionModeObservation struct {
	Mode    PermissionMode `json:"mode"`
	Version string         `json:"version,omitempty"`
}

func (o PermissionModeObservation) Detail() string {
	encoded, err := json.Marshal(o)
	if err != nil {
		return ""
	}
	return string(encoded)
}

func ParsePermissionModeObservation(detail string) (PermissionModeObservation, bool) {
	var observation PermissionModeObservation
	if err := json.Unmarshal([]byte(detail), &observation); err != nil {
		return PermissionModeObservation{}, false
	}
	if observation.Mode == "" || !observation.Mode.Valid() {
		return PermissionModeObservation{}, false
	}
	return observation, true
}
