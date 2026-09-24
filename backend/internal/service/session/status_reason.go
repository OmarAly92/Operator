package session

import (
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// deriveStatusReason explains, in one line, why a session has the status
// deriveStatus gave it. Like the status it is computed at read time and never
// stored. It feeds the board card and the Operator MCP server, which tells an
// agent why its card sits in its column.
func deriveStatusReason(status domain.SessionStatus, rec domain.SessionRecord, prs []domain.PRFacts) string {
	reason := baseStatusReason(status, rec, prs)
	if status == domain.StatusMerged || status == domain.StatusTerminated {
		return reason
	}
	if conflicts := prNumbers(openPRs(prs), func(p domain.PRFacts) bool {
		return p.Mergeability == domain.MergeConflicting
	}); conflicts != "" {
		reason += "; merge conflict on " + conflicts
	}
	return reason
}

func baseStatusReason(status domain.SessionStatus, rec domain.SessionRecord, prs []domain.PRFacts) string {
	switch status {
	case domain.StatusWorking:
		return "Agent is working"
	case domain.StatusIdle:
		return "Agent finished its turn and is waiting for the next instruction"
	case domain.StatusNeedsInput:
		switch {
		case rec.Activity.State == domain.ActivityBlocked:
			return "Agent is waiting on a permission prompt"
		case rec.Activity.State != domain.ActivityWaitingInput && rec.AgentReport.NeedsYou():
			return agentReportReason("Agent needs you", rec.AgentReport)
		}
		return "Agent is waiting for your input"
	case domain.StatusExited:
		return "Agent process exited"
	case domain.StatusNoSignal:
		return "No activity signal from the agent since launch"
	case domain.StatusTerminated:
		return "Session terminated"
	case domain.StatusMerged:
		return "Merged " + prNumbers(prs, func(p domain.PRFacts) bool { return p.Merged })
	}
	if status == domain.StatusReviewPending && len(openPRs(prs)) == 0 && rec.AgentReport != nil {
		return agentReportReason("Agent reports ready for review", rec.AgentReport)
	}
	open := openPRs(prs)
	matching := prNumbers(open, func(p domain.PRFacts) bool { return prPipelineStatus(p) == status })
	if matching == "" {
		matching = prNumbers(open, func(domain.PRFacts) bool { return true })
	}
	switch status {
	case domain.StatusCIFailed:
		return "CI failing on " + matching
	case domain.StatusChangesRequested:
		return "Changes requested or unresolved review comments on " + matching
	case domain.StatusDraft:
		return "Draft " + matching
	case domain.StatusReviewPending:
		return "Review pending on " + matching
	case domain.StatusApproved:
		return "Approved: " + matching
	case domain.StatusMergeable:
		return "Ready to merge: " + matching
	case domain.StatusPROpen:
		return "Open: " + matching
	default:
		return string(status)
	}
}

func agentReportReason(prefix string, r *domain.AgentReport) string {
	if r.Reason == "" {
		return prefix
	}
	return prefix + ": " + r.Reason
}

// prNumbers renders the PRs that satisfy keep as "PR #1, PR #2". A PR without a
// number (not yet observed) falls back to its URL.
func prNumbers(prs []domain.PRFacts, keep func(domain.PRFacts) bool) string {
	var parts []string
	for _, p := range prs {
		if !keep(p) {
			continue
		}
		if p.Number > 0 {
			parts = append(parts, fmt.Sprintf("PR #%d", p.Number))
		} else if p.URL != "" {
			parts = append(parts, p.URL)
		}
	}
	return strings.Join(parts, ", ")
}
