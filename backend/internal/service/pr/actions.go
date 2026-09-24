package pr

import "context"

// ActionManager is the controller-facing contract for guarded PR mutations.
type ActionManager interface {
	Merge(ctx context.Context, request MergeRequest) (MergeResult, error)
	ResolveComments(ctx context.Context, request ResolveRequest) (ResolveResult, error)
}

// MergeRequest identifies the tracked PR and pins the mutation to the exact
// head the user saw when they clicked Merge.
type MergeRequest struct {
	PRID            string
	PRURL           string
	ExpectedHeadSHA string
}

// MergeResult is the successful outcome of a PR merge.
type MergeResult struct {
	PRNumber       int
	Method         string
	MergeCommitSHA string
}

// ResolveRequest identifies the tracked PR (number plus URL, as for Merge) and
// the review comments whose threads to resolve. Empty CommentIDs resolves every
// unresolved thread. An ID may also name a thread directly.
type ResolveRequest struct {
	PRID       string
	PRURL      string
	CommentIDs []string
}

// ResolveResult is the successful outcome of a resolve-comments operation.
type ResolveResult struct {
	Resolved int
}
