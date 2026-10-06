package session

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// SetAgentReport records what the agent reported about its own card (the
// Operator MCP server's session_report tool) and returns the refreshed read
// model. state "" clears the report.
func (s *Service) SetAgentReport(ctx context.Context, id domain.SessionID, state domain.AgentReportState, reason string) (domain.Session, error) {
	if s.agentReports == nil {
		return domain.Session{}, errors.New("agent reports are not wired")
	}
	var report *domain.AgentReport
	if state != "" {
		reason = strings.TrimSpace(domain.SanitizeControlChars(reason))
		switch {
		case !state.Valid():
			return domain.Session{}, apierr.Invalid("INVALID_AGENT_REPORT", "state must be needs_you or ready_for_review", nil)
		case state == domain.AgentReportNeedsYou && reason == "":
			return domain.Session{}, apierr.Invalid("INVALID_AGENT_REPORT", "a needs_you report requires a reason", nil)
		case !domain.ValidAgentReportReason(reason):
			return domain.Session{}, apierr.Invalid("INVALID_AGENT_REPORT",
				fmt.Sprintf("reason must be at most %d characters", domain.AgentReportReasonMaxRunes), nil)
		}
		report = &domain.AgentReport{State: state, Reason: reason, At: s.now()}
	}
	if err := s.agentReports.SetAgentReport(ctx, id, report); err != nil {
		switch {
		case errors.Is(err, ports.ErrSessionNotFound):
			return domain.Session{}, apierr.NotFound("SESSION_NOT_FOUND", "Unknown session")
		case errors.Is(err, ports.ErrSessionTerminated):
			return domain.Session{}, apierr.Conflict("SESSION_TERMINATED", "The session has ended", nil)
		}
		return domain.Session{}, fmt.Errorf("agent report %s: %w", id, err)
	}
	return s.Get(ctx, id)
}
