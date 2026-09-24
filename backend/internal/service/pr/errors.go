package pr

import "errors"

// Sentinel errors returned by the PR action service.
var (
	ErrInvalidPR       = errors.New("pr: invalid identity")
	ErrPRNotFound      = errors.New("pr: not found")
	ErrPRNotMergeable  = errors.New("pr: not mergeable")
	ErrPRHeadChanged   = errors.New("pr: head changed")
	ErrPRPreconditions = errors.New("pr: merge preconditions unmet")
	// ErrCommentsNotFound: none of the requested comment or thread ids is on an
	// unresolved review thread of the pull request.
	ErrCommentsNotFound = errors.New("pr: no unresolved review thread matches the requested comments")
	ErrNothingToResolve = errors.New("pr: nothing to resolve")
)
