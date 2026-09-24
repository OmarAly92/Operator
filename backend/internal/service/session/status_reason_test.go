package session

import (
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestDeriveStatusReasonExplainsTheDerivedStatus(t *testing.T) {
	failing := domain.PRFacts{URL: "u/12", Number: 12, CI: domain.CIFailing}
	passing := domain.PRFacts{URL: "u/13", Number: 13, CI: domain.CIPassing, Review: domain.ReviewRequired}
	tests := []struct {
		name string
		rec  domain.SessionRecord
		prs  []domain.PRFacts
		want string
	}{
		{"working", statusRec(domain.ActivityActive, false), nil, "Agent is working"},
		{"idle", statusRec(domain.ActivityIdle, false), nil, "Agent finished its turn and is waiting for the next instruction"},
		{"permission prompt", statusRec(domain.ActivityBlocked, false), nil, "Agent is waiting on a permission prompt"},
		{"waiting input", statusRec(domain.ActivityWaitingInput, false), nil, "Agent is waiting for your input"},
		{"exited", statusRec(domain.ActivityExited, false), nil, "Agent process exited"},
		{"no signal", silentRec(2 * noSignalGrace), nil, "No activity signal from the agent since launch"},
		{"terminated", statusRec(domain.ActivityIdle, true), nil, "Session terminated"},
		{
			"merged",
			statusRec(domain.ActivityIdle, true),
			statusPR(domain.PRFacts{URL: "u/7", Number: 7, Merged: true}),
			"Merged PR #7",
		},
		{
			"ci failing names only the failing PR",
			statusRec(domain.ActivityIdle, false),
			[]domain.PRFacts{failing, passing},
			"CI failing on PR #12",
		},
		{
			"review pending",
			statusRec(domain.ActivityIdle, false),
			[]domain.PRFacts{passing},
			"Review pending on PR #13",
		},
		{
			"merge conflict is appended",
			statusRec(domain.ActivityIdle, false),
			statusPR(domain.PRFacts{URL: "u/9", Number: 9, Mergeability: domain.MergeConflicting}),
			"Open: PR #9; merge conflict on PR #9",
		},
		{
			"unobserved PR falls back to its URL",
			statusRec(domain.ActivityIdle, false),
			statusPR(domain.PRFacts{URL: "https://example.test/pr/1"}),
			"Open: https://example.test/pr/1",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			status := deriveStatus(tc.rec, tc.prs, statusNow, true)
			if got := deriveStatusReason(status, tc.rec, tc.prs); got != tc.want {
				t.Fatalf("reason for %s = %q, want %q", status, got, tc.want)
			}
		})
	}
}
