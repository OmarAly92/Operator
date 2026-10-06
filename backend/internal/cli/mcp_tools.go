package cli

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"time"
	"unicode/utf8"

	"github.com/google/jsonschema-go/jsonschema"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

// mcpTools holds the Operator MCP tool handlers. Every handler is a thin wrapper
// over daemon HTTP routes; none touches storage, runtimes or adapters.
type mcpTools struct {
	ctx *commandContext
	id  mcpIdentity
}

// mcpCardBriefLimit bounds the brief board_get repeats per card: enough to tell
// what another session is doing without flooding the agent's context.
const mcpCardBriefLimit = 280

var readOnlyTool = &mcp.ToolAnnotations{ReadOnlyHint: true, OpenWorldHint: new(bool)}

// selfActionTool marks the self-scoped actions: they change only the calling
// session's own card, never destructively.
var selfActionTool = &mcp.ToolAnnotations{DestructiveHint: new(bool), IdempotentHint: true, OpenWorldHint: new(bool)}

func (t *mcpTools) register(server *mcp.Server) {
	mcp.AddTool(server, &mcp.Tool{
		Name:        "board_get",
		Title:       "Get board",
		Description: "Get an Operator project's kanban board: every live session card grouped by column (Working, Needs you, In review, Ready to merge), each with its status, the reason it is in that column, branch, PRs and brief, plus the project's open tickets. Defaults to your own project. Use it before starting broad work to see what other sessions are doing.",
		Annotations: readOnlyTool,
	}, t.boardGet)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "session_get",
		Title:       "Get session",
		Description: "Get one session card in detail: status, board column, the reason it is in that column, branch, workspace path, and each attributed PR with CI (failing checks), review (decision, unresolved comments) and mergeability (conflicts). Defaults to your own session.",
		Annotations: readOnlyTool,
	}, t.sessionGet)
	mcp.AddTool(server, &mcp.Tool{
		Name:        "ticket_get",
		Title:       "Get ticket",
		Description: "Get an Operator ticket: title, brief, status, its folder and files, and each plan phase with its status and sessions. Defaults to the ticket your session was started from, including your role (planning, implementing, reviewing) and plan file.",
		Annotations: readOnlyTool,
	}, t.ticketGet)
	mcp.AddTool(server, &mcp.Tool{
		Name:  "session_report",
		Title: "Report your state",
		Description: "Report your own card's state on the Operator board. state needs_you: call this BEFORE ending a turn in which you are waiting on the user " +
			"(a question, a decision, missing access); reason is required and is shown on the card and in the user's alert. " +
			"state ready_for_review: the work is complete and there is no pull request to review; reason is a one-line summary. " +
			"state clear: withdraw a report made by mistake (a report also clears itself when the user next messages you). " +
			"Affects only your own session.",
		InputSchema: sessionReportSchema(),
		Annotations: selfActionTool,
	}, t.sessionReport)
}

// ---- wire shapes (hand-mirrored from the daemon DTOs, as elsewhere in the CLI) ----

type mcpSessionWire struct {
	ID                    string           `json:"id"`
	ProjectID             string           `json:"projectId"`
	Harness               string           `json:"harness,omitempty"`
	DisplayName           string           `json:"displayName,omitempty"`
	Activity              sessionActivity  `json:"activity"`
	IsTerminated          bool             `json:"isTerminated"`
	Status                string           `json:"status"`
	BoardColumn           string           `json:"boardColumn"`
	StatusReason          string           `json:"statusReason"`
	Branch                string           `json:"branch,omitempty"`
	WorkspacePath         string           `json:"workspacePath,omitempty"`
	PRs                   []sessionPRDTO   `json:"prs"`
	Brief                 string           `json:"brief,omitempty"`
	LatestUserPrompt      string           `json:"latestUserPrompt,omitempty"`
	LatestAssistantUpdate string           `json:"latestAssistantUpdate,omitempty"`
	Ticket                *mcpTicketRef    `json:"ticket,omitempty"`
	AgentReport           *agentReportWire `json:"agentReport,omitempty"`
}

type mcpSessionWireResponse struct {
	Session mcpSessionWire `json:"session"`
}

type mcpSessionListWireResponse struct {
	Sessions []mcpSessionWire `json:"sessions"`
}

type mcpProjectWireResponse struct {
	Project struct {
		ID   string `json:"id"`
		Name string `json:"name"`
		Kind string `json:"kind"`
	} `json:"project"`
}

type mcpPRSummaryWire struct {
	URL          string `json:"url"`
	Number       int    `json:"number"`
	Title        string `json:"title"`
	State        string `json:"state"`
	SourceBranch string `json:"sourceBranch"`
	TargetBranch string `json:"targetBranch"`
	HeadSHA      string `json:"headSha"`
	CI           struct {
		State         string `json:"state"`
		FailingChecks []struct {
			Name       string `json:"name"`
			Conclusion string `json:"conclusion"`
			URL        string `json:"url,omitempty"`
		} `json:"failingChecks"`
	} `json:"ci"`
	Review struct {
		Decision                   string `json:"decision"`
		HasUnresolvedHumanComments bool   `json:"hasUnresolvedHumanComments"`
		UnresolvedBy               []struct {
			ReviewerID string `json:"reviewerId"`
			Count      int    `json:"count"`
		} `json:"unresolvedBy"`
	} `json:"review"`
	Mergeability struct {
		State         string   `json:"state"`
		Reasons       []string `json:"reasons"`
		ConflictFiles []struct {
			Path string `json:"path"`
		} `json:"conflictFiles"`
	} `json:"mergeability"`
}

type mcpPRListWireResponse struct {
	PRs []mcpPRSummaryWire `json:"prs"`
}

type mcpTicketWire struct {
	Slug              string `json:"slug"`
	Title             string `json:"title"`
	Brief             string `json:"brief,omitempty"`
	Status            string `json:"status"`
	PlanningSessionID string `json:"planningSessionId,omitempty"`
	Plans             []struct {
		File              string `json:"file"`
		Order             int    `json:"order"`
		Title             string `json:"title"`
		Status            string `json:"status"`
		SessionID         string `json:"sessionId,omitempty"`
		ReviewerSessionID string `json:"reviewerSessionId,omitempty"`
	} `json:"plans"`
	Files []string `json:"files"`
}

type mcpTicketWireResponse struct {
	Ticket mcpTicketWire `json:"ticket"`
}

type mcpTicketListWireResponse struct {
	Tickets []mcpTicketWire `json:"tickets"`
}

// ---- tool inputs and outputs (snake_case: what the agent reads) ----

type mcpTicketRef struct {
	Slug     string `json:"slug"`
	PlanFile string `json:"planFile,omitempty"`
	Role     string `json:"role"`
}

type mcpPR struct {
	Number                   int    `json:"number,omitempty"`
	URL                      string `json:"url"`
	State                    string `json:"state"`
	CI                       string `json:"ci"`
	Review                   string `json:"review"`
	Mergeability             string `json:"mergeability"`
	UnresolvedReviewComments bool   `json:"unresolved_review_comments"`
}

type mcpCardTicket struct {
	Slug     string `json:"slug"`
	PlanFile string `json:"plan_file,omitempty"`
	Role     string `json:"role"`
}

type mcpCard struct {
	SessionID      string          `json:"session_id"`
	Name           string          `json:"name"`
	IsSelf         bool            `json:"is_self"`
	Harness        string          `json:"harness,omitempty"`
	Status         string          `json:"status"`
	Column         string          `json:"column"`
	StatusReason   string          `json:"status_reason"`
	Branch         string          `json:"branch,omitempty"`
	Brief          string          `json:"brief,omitempty"`
	PRs            []mcpPR         `json:"prs"`
	Ticket         *mcpCardTicket  `json:"ticket,omitempty"`
	AgentReport    *mcpAgentReport `json:"agent_report,omitempty"`
	LastActivityAt string          `json:"last_activity_at,omitempty"`
}

type mcpAgentReport struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`
}

type mcpBoardProject struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Kind string `json:"kind"`
}

type mcpBoardColumn struct {
	Column string    `json:"column"`
	Title  string    `json:"title"`
	Cards  []mcpCard `json:"cards"`
}

type mcpPlannedTicket struct {
	Slug   string `json:"slug"`
	Title  string `json:"title"`
	Status string `json:"status"`
}

type boardGetInput struct {
	ProjectID string `json:"project_id,omitempty" jsonschema:"Operator project id. Omit for your own project."`
}

type boardGetOutput struct {
	Project        mcpBoardProject    `json:"project"`
	Columns        []mcpBoardColumn   `json:"columns"`
	PlannedTickets []mcpPlannedTicket `json:"planned_tickets"`
}

type sessionGetInput struct {
	SessionID string `json:"session_id,omitempty" jsonschema:"Operator session id. Omit for your own session."`
}

type mcpFailingCheck struct {
	Name       string `json:"name"`
	Conclusion string `json:"conclusion,omitempty"`
	URL        string `json:"url,omitempty"`
}

type mcpUnresolvedBy struct {
	Reviewer string `json:"reviewer"`
	Count    int    `json:"count"`
}

type mcpPRDetail struct {
	Number              int               `json:"number,omitempty"`
	URL                 string            `json:"url"`
	Title               string            `json:"title,omitempty"`
	State               string            `json:"state"`
	SourceBranch        string            `json:"source_branch,omitempty"`
	TargetBranch        string            `json:"target_branch,omitempty"`
	HeadSHA             string            `json:"head_sha,omitempty"`
	CI                  string            `json:"ci"`
	FailingChecks       []mcpFailingCheck `json:"failing_checks"`
	ReviewDecision      string            `json:"review_decision"`
	UnresolvedComments  bool              `json:"unresolved_human_comments"`
	UnresolvedBy        []mcpUnresolvedBy `json:"unresolved_by"`
	Mergeability        string            `json:"mergeability"`
	MergeabilityReasons []string          `json:"mergeability_reasons"`
	ConflictFiles       []string          `json:"conflict_files"`
}

type sessionGetOutput struct {
	mcpCard
	WorkspacePath         string        `json:"workspace_path,omitempty"`
	LatestUserPrompt      string        `json:"latest_user_prompt,omitempty"`
	LatestAssistantUpdate string        `json:"latest_assistant_update,omitempty"`
	PRDetails             []mcpPRDetail `json:"pr_details"`
}

type ticketGetInput struct {
	Slug      string `json:"slug,omitempty" jsonschema:"Ticket slug. Omit for the ticket your session was started from."`
	ProjectID string `json:"project_id,omitempty" jsonschema:"Project the ticket belongs to. Omit for your own project."`
}

type mcpPlan struct {
	File              string `json:"file"`
	Order             int    `json:"order"`
	Title             string `json:"title"`
	Status            string `json:"status"`
	SessionID         string `json:"session_id,omitempty"`
	ReviewerSessionID string `json:"reviewer_session_id,omitempty"`
}

type ticketGetOutput struct {
	ProjectID string    `json:"project_id"`
	Slug      string    `json:"slug"`
	Title     string    `json:"title"`
	Brief     string    `json:"brief,omitempty"`
	Status    string    `json:"status"`
	Folder    string    `json:"folder"`
	Files     []string  `json:"files"`
	Plans     []mcpPlan `json:"plans"`
	YourRole  string    `json:"your_role,omitempty"`
	YourPlan  string    `json:"your_plan_file,omitempty"`
}

type sessionReportInput struct {
	State  string `json:"state" jsonschema:"needs_you, ready_for_review or clear"`
	Reason string `json:"reason,omitempty" jsonschema:"One line (at most 280 characters) shown on your card and in the Needs you alert. Required for needs_you."`
}

// sessionReportSchema is the inferred input schema with state narrowed to its
// three values, which the struct tags cannot express.
func sessionReportSchema() *jsonschema.Schema {
	schema, err := jsonschema.For[sessionReportInput](nil)
	if err != nil {
		panic(fmt.Sprintf("session_report schema: %v", err))
	}
	schema.Properties["state"].Enum = []any{string(domain.AgentReportNeedsYou), string(domain.AgentReportReadyForReview), "clear"}
	return schema
}

type agentReportWire struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`
}

// ---- handlers ----

func (t *mcpTools) sessionReport(ctx context.Context, _ *mcp.CallToolRequest, in sessionReportInput) (*mcp.CallToolResult, mcpCard, error) {
	path := "sessions/" + url.PathEscape(t.id.SessionID) + "/agent-report"
	var res mcpSessionWireResponse
	var err error
	switch in.State {
	case string(domain.AgentReportNeedsYou), string(domain.AgentReportReadyForReview):
		err = t.ctx.putJSON(ctx, path, agentReportWire(in), &res)
	case "clear":
		err = t.ctx.deleteJSON(ctx, path, &res)
	default:
		return nil, mcpCard{}, fmt.Errorf("state must be needs_you, ready_for_review or clear, got %q", in.State)
	}
	if err != nil {
		return nil, mcpCard{}, err
	}
	return nil, t.card(res.Session, false), nil
}

func (t *mcpTools) boardGet(ctx context.Context, _ *mcp.CallToolRequest, in boardGetInput) (*mcp.CallToolResult, boardGetOutput, error) {
	projectID, err := t.resolveProjectID(ctx, in.ProjectID)
	if err != nil {
		return nil, boardGetOutput{}, err
	}
	var project mcpProjectWireResponse
	if err := t.ctx.getJSON(ctx, "projects/"+url.PathEscape(projectID), &project); err != nil {
		return nil, boardGetOutput{}, err
	}
	var list mcpSessionListWireResponse
	params := url.Values{"project": {projectID}, "active": {"true"}}
	if err := t.ctx.getJSON(ctx, apiPath("sessions", params), &list); err != nil {
		return nil, boardGetOutput{}, err
	}
	byColumn := map[string][]mcpCard{}
	for _, s := range list.Sessions {
		card := t.card(s, true)
		byColumn[card.Column] = append(byColumn[card.Column], card)
	}
	out := boardGetOutput{
		Project:        mcpBoardProject{ID: project.Project.ID, Name: project.Project.Name, Kind: project.Project.Kind},
		Columns:        make([]mcpBoardColumn, 0, len(domain.BoardColumnOrder)),
		PlannedTickets: []mcpPlannedTicket{},
	}
	for _, column := range domain.BoardColumnOrder {
		cards := byColumn[string(column)]
		if cards == nil {
			cards = []mcpCard{}
		}
		out.Columns = append(out.Columns, mcpBoardColumn{Column: string(column), Title: boardColumnTitle(column), Cards: cards})
	}
	if project.Project.Kind == string(domain.ProjectKindSingleRepo) {
		var tickets mcpTicketListWireResponse
		if err := t.ctx.getJSON(ctx, "projects/"+url.PathEscape(projectID)+"/tickets", &tickets); err != nil {
			return nil, boardGetOutput{}, err
		}
		for _, tk := range tickets.Tickets {
			if tk.Status == "archived" || tk.Status == "done" {
				continue
			}
			out.PlannedTickets = append(out.PlannedTickets, mcpPlannedTicket{Slug: tk.Slug, Title: tk.Title, Status: tk.Status})
		}
	}
	return nil, out, nil
}

func (t *mcpTools) sessionGet(ctx context.Context, _ *mcp.CallToolRequest, in sessionGetInput) (*mcp.CallToolResult, sessionGetOutput, error) {
	sessionID := t.id.SessionID
	if in.SessionID != "" {
		sessionID = in.SessionID
	}
	sess, err := t.session(ctx, sessionID)
	if err != nil {
		return nil, sessionGetOutput{}, err
	}
	var prs mcpPRListWireResponse
	if err := t.ctx.getJSON(ctx, "sessions/"+url.PathEscape(sessionID)+"/pr", &prs); err != nil {
		return nil, sessionGetOutput{}, err
	}
	out := sessionGetOutput{
		mcpCard:               t.card(sess, false),
		WorkspacePath:         sess.WorkspacePath,
		LatestUserPrompt:      sess.LatestUserPrompt,
		LatestAssistantUpdate: sess.LatestAssistantUpdate,
		PRDetails:             make([]mcpPRDetail, 0, len(prs.PRs)),
	}
	for _, pr := range prs.PRs {
		out.PRDetails = append(out.PRDetails, prDetail(pr))
	}
	return nil, out, nil
}

func (t *mcpTools) ticketGet(ctx context.Context, _ *mcp.CallToolRequest, in ticketGetInput) (*mcp.CallToolResult, ticketGetOutput, error) {
	slug, projectID := in.Slug, in.ProjectID
	var ownRef *mcpTicketRef
	if slug == "" || projectID == "" {
		self, err := t.session(ctx, t.id.SessionID)
		if err != nil {
			return nil, ticketGetOutput{}, err
		}
		if projectID == "" {
			projectID = self.ProjectID
		}
		if slug == "" {
			if self.Ticket == nil {
				return nil, ticketGetOutput{}, errors.New("this session was not started from a ticket; pass slug to read one")
			}
			slug = self.Ticket.Slug
		}
		if self.Ticket != nil && self.Ticket.Slug == slug && self.ProjectID == projectID {
			ownRef = self.Ticket
		}
	}
	var res mcpTicketWireResponse
	if err := t.ctx.getJSON(ctx, "projects/"+url.PathEscape(projectID)+"/tickets/"+url.PathEscape(slug), &res); err != nil {
		return nil, ticketGetOutput{}, err
	}
	tk := res.Ticket
	out := ticketGetOutput{
		ProjectID: projectID,
		Slug:      tk.Slug,
		Title:     tk.Title,
		Brief:     tk.Brief,
		Status:    tk.Status,
		Folder:    domain.TicketsDir + "/" + tk.Slug,
		Files:     nonNil(tk.Files),
		Plans:     make([]mcpPlan, 0, len(tk.Plans)),
	}
	for _, p := range tk.Plans {
		out.Plans = append(out.Plans, mcpPlan{
			File: p.File, Order: p.Order, Title: p.Title, Status: p.Status,
			SessionID: p.SessionID, ReviewerSessionID: p.ReviewerSessionID,
		})
	}
	if ownRef != nil {
		out.YourRole = ownRef.Role
		out.YourPlan = ownRef.PlanFile
	}
	return nil, out, nil
}

// ---- helpers ----

func (t *mcpTools) session(ctx context.Context, id string) (mcpSessionWire, error) {
	var res mcpSessionWireResponse
	if err := t.ctx.getJSON(ctx, "sessions/"+url.PathEscape(id), &res); err != nil {
		return mcpSessionWire{}, err
	}
	return res.Session, nil
}

// resolveProjectID defaults to the calling session's project. The launch env
// carries it; the session read is the fallback for an env without it.
func (t *mcpTools) resolveProjectID(ctx context.Context, explicit string) (string, error) {
	if explicit != "" {
		return explicit, nil
	}
	if t.id.ProjectID != "" {
		return t.id.ProjectID, nil
	}
	self, err := t.session(ctx, t.id.SessionID)
	if err != nil {
		return "", err
	}
	return self.ProjectID, nil
}

func (t *mcpTools) card(s mcpSessionWire, capBrief bool) mcpCard {
	column := s.BoardColumn
	if column == "" {
		column = string(domain.BoardColumnFor(domain.SessionStatus(s.Status), s.IsTerminated))
	}
	name := s.DisplayName
	if name == "" {
		name = s.ID
	}
	brief := s.Brief
	if capBrief {
		brief = truncateRunes(brief, mcpCardBriefLimit)
	}
	card := mcpCard{
		SessionID:    s.ID,
		Name:         name,
		IsSelf:       s.ID == t.id.SessionID,
		Harness:      s.Harness,
		Status:       s.Status,
		Column:       column,
		StatusReason: s.StatusReason,
		Branch:       s.Branch,
		Brief:        brief,
		PRs:          make([]mcpPR, 0, len(s.PRs)),
	}
	if !s.Activity.LastActivityAt.IsZero() {
		card.LastActivityAt = s.Activity.LastActivityAt.UTC().Format(time.RFC3339)
	}
	for _, pr := range s.PRs {
		card.PRs = append(card.PRs, mcpPR{
			Number: pr.Number, URL: pr.URL, State: pr.State, CI: pr.CI, Review: pr.Review,
			Mergeability: pr.Mergeability, UnresolvedReviewComments: pr.ReviewComments,
		})
	}
	if s.Ticket != nil {
		card.Ticket = &mcpCardTicket{Slug: s.Ticket.Slug, PlanFile: s.Ticket.PlanFile, Role: s.Ticket.Role}
	}
	if s.AgentReport != nil {
		card.AgentReport = &mcpAgentReport{State: s.AgentReport.State, Reason: s.AgentReport.Reason}
	}
	return card
}

func prDetail(pr mcpPRSummaryWire) mcpPRDetail {
	d := mcpPRDetail{
		Number: pr.Number, URL: pr.URL, Title: pr.Title, State: pr.State,
		SourceBranch: pr.SourceBranch, TargetBranch: pr.TargetBranch, HeadSHA: pr.HeadSHA,
		CI:                  pr.CI.State,
		FailingChecks:       make([]mcpFailingCheck, 0, len(pr.CI.FailingChecks)),
		ReviewDecision:      pr.Review.Decision,
		UnresolvedComments:  pr.Review.HasUnresolvedHumanComments,
		UnresolvedBy:        make([]mcpUnresolvedBy, 0, len(pr.Review.UnresolvedBy)),
		Mergeability:        pr.Mergeability.State,
		MergeabilityReasons: nonNil(pr.Mergeability.Reasons),
		ConflictFiles:       make([]string, 0, len(pr.Mergeability.ConflictFiles)),
	}
	for _, c := range pr.CI.FailingChecks {
		d.FailingChecks = append(d.FailingChecks, mcpFailingCheck{Name: c.Name, Conclusion: c.Conclusion, URL: c.URL})
	}
	for _, u := range pr.Review.UnresolvedBy {
		d.UnresolvedBy = append(d.UnresolvedBy, mcpUnresolvedBy{Reviewer: u.ReviewerID, Count: u.Count})
	}
	for _, f := range pr.Mergeability.ConflictFiles {
		d.ConflictFiles = append(d.ConflictFiles, f.Path)
	}
	return d
}

func boardColumnTitle(c domain.BoardColumn) string {
	switch c {
	case domain.BoardColumnWorking:
		return "Working"
	case domain.BoardColumnNeedsYou:
		return "Needs you"
	case domain.BoardColumnInReview:
		return "In review"
	case domain.BoardColumnReadyToMerge:
		return "Ready to merge"
	default:
		return fmt.Sprint(c)
	}
}

func truncateRunes(s string, limit int) string {
	if utf8.RuneCountInString(s) <= limit {
		return s
	}
	r := []rune(s)
	return string(r[:limit-1]) + "…"
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
