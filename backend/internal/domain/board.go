package domain

// BoardColumn is the kanban column a session card sits in. Like SessionStatus it
// is derived at read time and never stored.
type BoardColumn string

// The board columns, in board order.
const (
	BoardColumnWorking      BoardColumn = "working"
	BoardColumnNeedsYou     BoardColumn = "needs_you"
	BoardColumnInReview     BoardColumn = "in_review"
	BoardColumnReadyToMerge BoardColumn = "ready_to_merge"
	BoardColumnArchive      BoardColumn = "archive"
)

// BoardColumnOrder is the left-to-right order of the live columns on the board.
// The archive sits below the board rather than beside it.
var BoardColumnOrder = []BoardColumn{
	BoardColumnWorking,
	BoardColumnNeedsYou,
	BoardColumnInReview,
	BoardColumnReadyToMerge,
}

// BoardColumnFor places a session on the board. It mirrors the desktop's
// attentionZone (frontend/src/renderer/lib/session-presentation.ts) plus the
// board's archive rule (a terminated runtime is archived even when its PR
// merged); testdata/board/columns.json pins both sides to the same table.
func BoardColumnFor(status SessionStatus, isTerminated bool) BoardColumn {
	if isTerminated {
		return BoardColumnArchive
	}
	switch status {
	case StatusMerged, StatusApproved, StatusMergeable:
		return BoardColumnReadyToMerge
	case StatusTerminated:
		return BoardColumnArchive
	case StatusNeedsInput, StatusExited, StatusNoSignal, StatusCIFailed, StatusChangesRequested:
		return BoardColumnNeedsYou
	case StatusReviewPending, StatusPROpen, StatusDraft:
		return BoardColumnInReview
	default:
		return BoardColumnWorking
	}
}
