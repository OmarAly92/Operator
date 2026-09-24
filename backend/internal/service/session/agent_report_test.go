package session

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// fakeAgentReporter applies reports to the fake store the way the lifecycle
// manager does, and can be told to fail.
type fakeAgentReporter struct {
	store *fakeStore
	err   error
	got   []*domain.AgentReport
}

func (f *fakeAgentReporter) SetAgentReport(_ context.Context, id domain.SessionID, report *domain.AgentReport) error {
	if f.err != nil {
		return f.err
	}
	f.got = append(f.got, report)
	f.store.mu.Lock()
	defer f.store.mu.Unlock()
	rec := f.store.sessions[id]
	rec.AgentReport = report
	f.store.sessions[id] = rec
	return nil
}

func agentReportService(t *testing.T) (*Service, *fakeAgentReporter) {
	t.Helper()
	st := newFakeStore()
	st.sessions["opr-1"] = domain.SessionRecord{ID: "opr-1", ProjectID: "opr", Activity: domain.Activity{State: domain.ActivityIdle, LastActivityAt: statusNow}, FirstSignalAt: statusNow}
	reporter := &fakeAgentReporter{store: st}
	return NewWithDeps(Deps{Store: st, AgentReports: reporter}), reporter
}

func TestSetAgentReportMovesTheCardAndExplainsWhy(t *testing.T) {
	svc, reporter := agentReportService(t)

	sess, err := svc.SetAgentReport(context.Background(), "opr-1", domain.AgentReportNeedsYou, "  Which database?\x1b[31m  ")
	if err != nil {
		t.Fatal(err)
	}
	if got := reporter.got[0]; got == nil || got.Reason != "Which database?[31m" || got.At.IsZero() {
		t.Fatalf("stored report = %+v, want trimmed, control characters stripped, stamped", got)
	}
	if sess.Status != domain.StatusNeedsInput || sess.BoardColumn != domain.BoardColumnNeedsYou {
		t.Fatalf("status = %s column = %s, want needs_input / needs_you", sess.Status, sess.BoardColumn)
	}
	if !strings.HasPrefix(sess.StatusReason, "Agent needs you: Which database?") {
		t.Fatalf("status reason = %q", sess.StatusReason)
	}

	sess, err = svc.SetAgentReport(context.Background(), "opr-1", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if reporter.got[1] != nil || sess.AgentReport != nil || sess.Status != domain.StatusIdle {
		t.Fatalf("clear left report=%+v status=%s", sess.AgentReport, sess.Status)
	}
}

func TestSetAgentReportValidates(t *testing.T) {
	svc, reporter := agentReportService(t)
	for _, tc := range []struct {
		name   string
		state  domain.AgentReportState
		reason string
	}{
		{"unknown state", "done", "x"},
		{"needs_you without reason", domain.AgentReportNeedsYou, "   "},
		{"reason too long", domain.AgentReportReadyForReview, strings.Repeat("é", domain.AgentReportReasonMaxRunes+1)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := svc.SetAgentReport(context.Background(), "opr-1", tc.state, tc.reason)
			var apiErr *apierr.Error
			if !errors.As(err, &apiErr) || apiErr.Code != "INVALID_AGENT_REPORT" {
				t.Fatalf("err = %v, want INVALID_AGENT_REPORT", err)
			}
		})
	}
	if len(reporter.got) != 0 {
		t.Fatalf("invalid reports reached the store: %+v", reporter.got)
	}
	if _, err := svc.SetAgentReport(context.Background(), "opr-1", domain.AgentReportReadyForReview, ""); err != nil {
		t.Fatalf("ready_for_review without a reason must be accepted: %v", err)
	}
}

func TestSetAgentReportMapsLifecycleErrors(t *testing.T) {
	for _, tc := range []struct {
		err  error
		code string
	}{
		{fmt.Errorf("%w: opr-1", ports.ErrSessionNotFound), "SESSION_NOT_FOUND"},
		{fmt.Errorf("%w: opr-1", ports.ErrSessionTerminated), "SESSION_TERMINATED"},
	} {
		svc, reporter := agentReportService(t)
		reporter.err = tc.err
		_, err := svc.SetAgentReport(context.Background(), "opr-1", domain.AgentReportNeedsYou, "x")
		var apiErr *apierr.Error
		if !errors.As(err, &apiErr) || apiErr.Code != tc.code {
			t.Fatalf("err = %v, want %s", err, tc.code)
		}
	}
}
