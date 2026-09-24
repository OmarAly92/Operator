package store_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionAgentReportRoundTripsAndEmitsCDC(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	seedProject(t, s, "board")
	now := time.Now().UTC().Truncate(time.Second)
	rec, err := s.CreateSession(ctx, domain.SessionRecord{
		ProjectID: "board", Harness: domain.HarnessClaudeCode,
		Activity:  domain.Activity{State: domain.ActivityIdle, LastActivityAt: now},
		Metadata:  domain.SessionMetadata{WorkspaceMode: domain.WorkspaceModeWorktree},
		CreatedAt: now, UpdatedAt: now,
	})
	if err != nil {
		t.Fatal(err)
	}
	head, err := s.LatestSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}

	report := domain.AgentReport{State: domain.AgentReportNeedsYou, Reason: "Which database?", At: now}
	if ok, err := s.SetSessionAgentReport(ctx, rec.ID, report, now); err != nil || !ok {
		t.Fatalf("set: %v, %v", ok, err)
	}
	got, _, err := s.GetSession(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.AgentReport == nil || got.AgentReport.State != report.State || got.AgentReport.Reason != report.Reason || !got.AgentReport.At.Equal(now) {
		t.Fatalf("report = %+v, want %+v", got.AgentReport, report)
	}
	listed, err := s.ListSessions(ctx, "board")
	if err != nil || len(listed) != 1 || listed[0].AgentReport == nil {
		t.Fatalf("list lost the report: %+v, %v", listed, err)
	}

	// A whole-record lifecycle write must not clobber the report.
	got.DisplayName = "renamed"
	if err := s.UpdateSession(ctx, got); err != nil {
		t.Fatal(err)
	}
	if again, _, _ := s.GetSession(ctx, rec.ID); again.AgentReport == nil {
		t.Fatal("UpdateSession cleared the agent report")
	}

	if ok, err := s.ClearSessionAgentReport(ctx, rec.ID, now); err != nil || !ok {
		t.Fatalf("clear: %v, %v", ok, err)
	}
	if ok, err := s.ClearSessionAgentReport(ctx, rec.ID, now); err != nil || ok {
		t.Fatalf("second clear reported a change: %v, %v", ok, err)
	}
	if cleared, _, _ := s.GetSession(ctx, rec.ID); cleared.AgentReport != nil {
		t.Fatalf("report after clear = %+v", cleared.AgentReport)
	}
	if ok, err := s.SetSessionAgentReport(ctx, "ghost", report, now); err != nil || ok {
		t.Fatalf("set on unknown session: %v, %v", ok, err)
	}

	events, err := s.EventsAfter(ctx, head, 100)
	if err != nil {
		t.Fatal(err)
	}
	var reportEvents int
	for _, e := range events {
		if e.Type == "session_updated" && strings.Contains(string(e.Payload), `"agentReportState"`) {
			reportEvents++
		}
	}
	// set, rename (also a session_updated), clear: the set and the clear must
	// each reach the board through the CDC trigger.
	if reportEvents < 2 {
		t.Fatalf("session_updated events carrying the report = %d, want the set and the clear; events=%+v", reportEvents, events)
	}
	var sawSet bool
	for _, e := range events {
		sawSet = sawSet || strings.Contains(string(e.Payload), `"agentReportState":"needs_you"`)
	}
	if !sawSet {
		t.Fatalf("no CDC event carried the needs_you report: %+v", events)
	}
}
