package github

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

var _ ports.SCMThreadResolver = (*Provider)(nil)

const resolveReviewThreadMutation = `mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }`

// ResolveReviewThread marks one pull request review thread resolved. threadID
// is the GraphQL node id the observer records for the thread.
func (p *Provider) ResolveReviewThread(ctx context.Context, pr ports.SCMPRRef, threadID string) error {
	if p == nil || p.client == nil {
		return fmt.Errorf("github scm: resolve provider is not configured")
	}
	threadID = strings.TrimSpace(threadID)
	if threadID == "" {
		return fmt.Errorf("github scm: review thread id is required")
	}
	data, err := p.client.doGraphQL(ctx, resolveReviewThreadMutation, map[string]any{"id": threadID})
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return fmt.Errorf("%w: %w", ports.ErrSCMNotFound, err)
		}
		return fmt.Errorf("github scm: resolve review thread on %s: %w", pr.URL, err)
	}
	result, _ := data["resolveReviewThread"].(map[string]any)
	thread, _ := result["thread"].(map[string]any)
	if resolved, _ := thread["isResolved"].(bool); !resolved {
		return fmt.Errorf("github scm: review thread %s was not resolved", threadID)
	}
	return nil
}
