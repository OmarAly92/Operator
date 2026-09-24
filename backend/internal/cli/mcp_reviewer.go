package cli

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// registerReviewer adds the reviewer role's tools. The worker they act for is
// the one this reviewer pane reviews (mcpReviewerIdentity), never an argument.
func (t *mcpTools) registerReviewer(server *mcp.Server) {
	mcp.AddTool(server, &mcp.Tool{
		Name:  "review_submit",
		Title: "Record review results",
		Description: "Record your review results with Operator, after posting each review on its pull request. Pass one entry per review task in " +
			"the queue: its run id, the verdict, the full review markdown and the GitHub review id you captured (empty if posting failed). " +
			"Submit every task in one call. A changes_requested verdict needs a body; it is delivered to the worker.",
		Annotations: selfActionTool,
	}, t.reviewSubmit)
}

type reviewSubmitEntry struct {
	RunID          string `json:"run_id" jsonschema:"The review run id from the task queue."`
	Verdict        string `json:"verdict" jsonschema:"approved or changes_requested."`
	Body           string `json:"body,omitempty" jsonschema:"Your full review markdown. Required for changes_requested."`
	GithubReviewID string `json:"github_review_id,omitempty" jsonschema:"The id of the GitHub review you posted; empty if posting failed."`
}

type reviewSubmitInput struct {
	Reviews []reviewSubmitEntry `json:"reviews" jsonschema:"One entry per review task in the queue."`
}

type reviewSubmitRun struct {
	RunID   string `json:"run_id"`
	PRURL   string `json:"pr_url,omitempty"`
	Status  string `json:"status,omitempty"`
	Verdict string `json:"verdict,omitempty"`
}

type reviewSubmitOutput struct {
	WorkerSessionID string            `json:"worker_session_id"`
	Recorded        []reviewSubmitRun `json:"recorded"`
}

type reviewSubmitWireRun struct {
	ID      string `json:"id"`
	PRURL   string `json:"prUrl"`
	Status  string `json:"status"`
	Verdict string `json:"verdict"`
}

type reviewSubmitWireResponse struct {
	Reviews []reviewSubmitWireRun `json:"reviews"`
}

func (t *mcpTools) reviewSubmit(ctx context.Context, _ *mcp.CallToolRequest, in reviewSubmitInput) (*mcp.CallToolResult, reviewSubmitOutput, error) {
	if t.id.Reviewer == nil {
		return nil, reviewSubmitOutput{}, errors.New("review_submit is only served to Operator reviewer panes")
	}
	if len(in.Reviews) == 0 {
		return nil, reviewSubmitOutput{}, errors.New("reviews is required: one entry per review task")
	}
	items := make([]submitReviewItem, 0, len(in.Reviews))
	for i, r := range in.Reviews {
		item := submitReviewItem{
			RunID:          strings.TrimSpace(r.RunID),
			Verdict:        strings.TrimSpace(r.Verdict),
			Body:           r.Body,
			GithubReviewID: strings.TrimSpace(r.GithubReviewID),
		}
		if item.RunID == "" {
			return nil, reviewSubmitOutput{}, fmt.Errorf("reviews[%d].run_id is required", i)
		}
		if item.Verdict != "approved" && item.Verdict != "changes_requested" {
			return nil, reviewSubmitOutput{}, fmt.Errorf("reviews[%d].verdict must be approved or changes_requested, got %q", i, item.Verdict)
		}
		items = append(items, item)
	}
	worker := t.id.Reviewer.WorkerSessionID
	var res reviewSubmitWireResponse
	if err := t.ctx.postJSON(ctx, "sessions/"+url.PathEscape(worker)+"/reviews/submit", submitReviewRequest{Reviews: items}, &res); err != nil {
		return nil, reviewSubmitOutput{}, err
	}
	out := reviewSubmitOutput{WorkerSessionID: worker, Recorded: make([]reviewSubmitRun, 0, len(res.Reviews))}
	for _, run := range res.Reviews {
		out.Recorded = append(out.Recorded, reviewSubmitRun{RunID: run.ID, PRURL: run.PRURL, Status: run.Status, Verdict: run.Verdict})
	}
	return nil, out, nil
}
