package domain

import "testing"

func TestNotificationTypeClassification(t *testing.T) {
	for _, tc := range []struct {
		typ             NotificationType
		valid, resolves bool
		sessionScoped   bool
	}{
		{NotificationNeedsInput, true, true, true},
		{NotificationTurnFinished, true, true, true},
		{NotificationAgentExited, true, true, true},
		{NotificationReadyToMerge, true, true, false},
		{NotificationPRMerged, true, false, false},
		{NotificationPRClosedUnmerged, true, false, false},
		{"bogus", false, false, false},
	} {
		if got := tc.typ.Valid(); got != tc.valid {
			t.Errorf("%s Valid = %v, want %v", tc.typ, got, tc.valid)
		}
		if got := tc.typ.NeedsResolution(); got != tc.resolves {
			t.Errorf("%s NeedsResolution = %v, want %v", tc.typ, got, tc.resolves)
		}
		if got := tc.typ.SessionScoped(); got != tc.sessionScoped {
			t.Errorf("%s SessionScoped = %v, want %v", tc.typ, got, tc.sessionScoped)
		}
	}
}
