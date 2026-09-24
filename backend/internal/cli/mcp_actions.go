package cli

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"path"
	"strings"
	"unicode/utf8"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// maxDisplayNameRunes mirrors the daemon's display-name cap (SpawnSessionRequest).
const maxDisplayNameRunes = 20

// registerActions adds the self-scoped action tools. None takes a session id:
// each acts on the calling session only, which is the whole guardrail — the
// loopback API itself is unauthenticated by design.
func (t *mcpTools) registerActions(server *mcp.Server) {
	mcp.AddTool(server, &mcp.Tool{
		Name:        "session_rename",
		Title:       "Rename your card",
		Description: "Rename your own card on the Operator board (at most 20 characters). Use a short name for what you are working on.",
		Annotations: selfActionTool,
	}, t.sessionRename)
	mcp.AddTool(server, &mcp.Tool{
		Name:  "pr_claim",
		Title: "Claim a pull request",
		Description: "Attribute a pull request to your session so it shows on your card and drives your column. Only needed for a PR whose branch is outside " +
			"your session's branch namespace. Refuses a PR already claimed by another live session.",
		Annotations: selfActionTool,
	}, t.prClaim)
	mcp.AddTool(server, &mcp.Tool{
		Name:  "review_request",
		Title: "Request an Operator review",
		Description: "Ask Operator's internal code reviewer to review your session's open pull request(s) at their current head. Reuses a review already " +
			"running for the same commit. The reviewer's verdict reaches you as a message.",
		Annotations: selfActionTool,
	}, t.reviewRequest)
	mcp.AddTool(server, &mcp.Tool{
		Name:  "ticket_mark_merge_ready",
		Title: "Mark a ticket plan merge-ready",
		Description: "Only for the session reviewing a ticket plan: report that the implementation branch is verified and ready to merge, with one line on " +
			"what you verified. The user then confirms the merge from the board and you receive the go-ahead as a message.",
		Annotations: selfActionTool,
	}, t.ticketMarkMergeReady)
}

type sessionRenameInput struct {
	Name string `json:"name" jsonschema:"The new card name, at most 20 characters."`
}

type sessionRenameOutput struct {
	SessionID string `json:"session_id"`
	Name      string `json:"name"`
}

func (t *mcpTools) sessionRename(ctx context.Context, _ *mcp.CallToolRequest, in sessionRenameInput) (*mcp.CallToolResult, sessionRenameOutput, error) {
	name := strings.TrimSpace(in.Name)
	if name == "" {
		return nil, sessionRenameOutput{}, errors.New("name is required")
	}
	if utf8.RuneCountInString(name) > maxDisplayNameRunes {
		return nil, sessionRenameOutput{}, fmt.Errorf("name must be at most %d characters", maxDisplayNameRunes)
	}
	var res renameSessionResponse
	if err := t.ctx.patchJSON(ctx, "sessions/"+url.PathEscape(t.id.SessionID), sessionRenameRequest{DisplayName: name}, &res); err != nil {
		return nil, sessionRenameOutput{}, err
	}
	return nil, sessionRenameOutput{SessionID: t.id.SessionID, Name: res.DisplayName}, nil
}

type prClaimInput struct {
	PR string `json:"pr" jsonschema:"The pull request number or URL."`
}

type prClaimOutput struct {
	SessionID     string  `json:"session_id"`
	PRs           []mcpPR `json:"prs"`
	BranchChanged bool    `json:"branch_changed"`
}

func (t *mcpTools) prClaim(ctx context.Context, _ *mcp.CallToolRequest, in prClaimInput) (*mcp.CallToolResult, prClaimOutput, error) {
	pr := strings.TrimSpace(in.PR)
	if pr == "" {
		return nil, prClaimOutput{}, errors.New("pr is required")
	}
	var res claimPRResponse
	// Never take a PR over from another live session: that would move a card
	// the agent does not own.
	req := claimPRRequest{PR: pr, AllowTakeover: false}
	if err := t.ctx.postJSON(ctx, "sessions/"+url.PathEscape(t.id.SessionID)+"/pr/claim", req, &res); err != nil {
		return nil, prClaimOutput{}, err
	}
	out := prClaimOutput{SessionID: t.id.SessionID, PRs: make([]mcpPR, 0, len(res.PRs)), BranchChanged: res.BranchChanged}
	for _, p := range res.PRs {
		out.PRs = append(out.PRs, mcpPR{
			Number: p.Number, URL: p.URL, State: p.State, CI: p.CI, Review: p.Review,
			Mergeability: p.Mergeability, UnresolvedReviewComments: p.ReviewComments,
		})
	}
	return nil, out, nil
}

type reviewRequestInput struct{}

type reviewRequestOutput struct {
	Started bool   `json:"started"`
	Runs    int    `json:"runs"`
	Note    string `json:"note"`
}

type reviewTriggerWireResponse struct {
	Created bool  `json:"created"`
	Runs    []any `json:"runs"`
}

func (t *mcpTools) reviewRequest(ctx context.Context, _ *mcp.CallToolRequest, _ reviewRequestInput) (*mcp.CallToolResult, reviewRequestOutput, error) {
	var res reviewTriggerWireResponse
	if err := t.ctx.postJSON(ctx, "sessions/"+url.PathEscape(t.id.SessionID)+"/reviews/trigger", struct{}{}, &res); err != nil {
		return nil, reviewRequestOutput{}, err
	}
	out := reviewRequestOutput{Started: res.Created, Runs: len(res.Runs), Note: "A review is already running for this commit; its verdict will reach you as a message."}
	if res.Created {
		out.Note = "Review started; its verdict will reach you as a message."
	}
	return nil, out, nil
}

type ticketMarkMergeReadyInput struct {
	Summary string `json:"summary" jsonschema:"One line: what you verified."`
}

type ticketMarkMergeReadyOutput struct {
	Slug       string `json:"slug"`
	PlanFile   string `json:"plan_file"`
	PlanStatus string `json:"plan_status"`
}

func (t *mcpTools) ticketMarkMergeReady(ctx context.Context, _ *mcp.CallToolRequest, in ticketMarkMergeReadyInput) (*mcp.CallToolResult, ticketMarkMergeReadyOutput, error) {
	summary := strings.TrimSpace(in.Summary)
	if summary == "" {
		return nil, ticketMarkMergeReadyOutput{}, errors.New("summary is required")
	}
	self, err := t.session(ctx, t.id.SessionID)
	if err != nil {
		return nil, ticketMarkMergeReadyOutput{}, err
	}
	if self.Ticket == nil {
		return nil, ticketMarkMergeReadyOutput{}, errors.New("this session was not started from a ticket")
	}
	base := "projects/" + url.PathEscape(self.ProjectID) + "/tickets/" + url.PathEscape(self.Ticket.Slug)
	var tk mcpTicketWireResponse
	if err := t.ctx.getJSON(ctx, base, &tk); err != nil {
		return nil, ticketMarkMergeReadyOutput{}, err
	}
	// The reviewing session is recorded on the plan itself; that covers both a
	// dedicated reviewer and a planner session asked to review.
	planFile := ""
	for _, p := range tk.Ticket.Plans {
		if p.ReviewerSessionID == t.id.SessionID {
			planFile = p.File
			break
		}
	}
	if planFile == "" {
		return nil, ticketMarkMergeReadyOutput{}, fmt.Errorf("no plan of ticket %s is waiting on this session's review", self.Ticket.Slug)
	}
	var after mcpTicketWireResponse
	if err := t.ctx.postJSON(ctx, base+"/plans/"+url.PathEscape(path.Base(planFile))+"/merge-ready", mergeReadyWire{Summary: summary}, &after); err != nil {
		return nil, ticketMarkMergeReadyOutput{}, err
	}
	out := ticketMarkMergeReadyOutput{Slug: self.Ticket.Slug, PlanFile: planFile}
	for _, p := range after.Ticket.Plans {
		if p.File == planFile {
			out.PlanStatus = p.Status
		}
	}
	return nil, out, nil
}

type mergeReadyWire struct {
	Summary string `json:"summary"`
}
