package ticket

import "github.com/OmarAly92/operator/backend/internal/domain"

func currentAssignments(rows []domain.PlanAssignmentRecord) map[string]domain.PlanAssignmentRecord {
	out := make(map[string]domain.PlanAssignmentRecord, len(rows))
	for _, row := range rows {
		if _, seen := out[row.PlanFile]; !seen {
			out[row.PlanFile] = row
		}
	}
	return out
}

func planStatus(a domain.PlanAssignmentRecord, ok bool, sess *domain.Session) domain.PlanStatus {
	if !ok {
		return domain.PlanStatusTodo
	}
	if !a.DoneAt.IsZero() {
		return domain.PlanStatusDone
	}
	if sess != nil && sess.Status == domain.StatusMerged {
		return domain.PlanStatusMerged
	}
	if !a.MergeReadyAt.IsZero() {
		if a.MergeApprovedAt.IsZero() {
			return domain.PlanStatusAwaitMerge
		}
		return domain.PlanStatusMerging
	}
	if !a.ReviewRequestedAt.IsZero() {
		return domain.PlanStatusReviewing
	}
	if sess == nil {
		return domain.PlanStatusTerminated
	}
	switch sess.Status {
	case domain.StatusWorking:
		return domain.PlanStatusWorking
	case domain.StatusNeedsInput:
		return domain.PlanStatusNeedsYou
	case domain.StatusPROpen, domain.StatusDraft, domain.StatusCIFailed, domain.StatusReviewPending,
		domain.StatusChangesRequested, domain.StatusApproved, domain.StatusMergeable:
		return domain.PlanStatusInReview
	case domain.StatusMerged:
		return domain.PlanStatusMerged
	case domain.StatusTerminated, domain.StatusExited:
		return domain.PlanStatusTerminated
	default:
		return domain.PlanStatusIdle
	}
}

func planLive(status domain.PlanStatus) bool {
	switch status {
	case domain.PlanStatusIdle, domain.PlanStatusWorking, domain.PlanStatusNeedsYou, domain.PlanStatusInReview,
		domain.PlanStatusReviewing, domain.PlanStatusAwaitMerge, domain.PlanStatusMerging:
		return true
	default:
		return false
	}
}

func ticketStatus(rec domain.TicketRecord, plans []domain.Plan, planning *domain.Session) domain.TicketStatus {
	if !rec.ArchivedAt.IsZero() {
		return domain.TicketStatusArchived
	}
	if len(plans) > 0 {
		allSettled := true
		for _, p := range plans {
			if p.Status != domain.PlanStatusMerged && p.Status != domain.PlanStatusDone {
				allSettled = false
				break
			}
		}
		if allSettled {
			return domain.TicketStatusDone
		}
		for _, p := range plans {
			if p.Status == domain.PlanStatusAwaitMerge {
				return domain.TicketStatusAwaitMerge
			}
		}
		for _, p := range plans {
			if planLive(p.Status) {
				return domain.TicketStatusInProgress
			}
		}
	}
	if planning != nil && planning.Status != domain.StatusTerminated && planning.Status != domain.StatusMerged {
		return domain.TicketStatusPlanning
	}
	if len(plans) > 0 {
		return domain.TicketStatusReady
	}
	return domain.TicketStatusDraft
}
