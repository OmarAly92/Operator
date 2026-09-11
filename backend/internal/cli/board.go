package cli

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type boardOptions struct {
	project string
	json    bool
}

type boardOutput struct {
	Data []sessionDTO `json:"data"`
}

func newBoardCommand(ctx *commandContext) *cobra.Command {
	var opts boardOptions
	cmd := &cobra.Command{
		Use:   "board",
		Short: "Show every live worker in a project with its brief, state and PRs",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return ctx.showBoard(cmd.Context(), cmd, opts)
		},
	}
	cmd.Flags().StringVar(&opts.project, "project", "", "Project id (defaults to the current session's project)")
	cmd.Flags().BoolVar(&opts.json, "json", false, "Output as JSON")
	return cmd
}

func (c *commandContext) showBoard(ctx context.Context, cmd *cobra.Command, opts boardOptions) error {
	project, err := c.resolveBoardProject(ctx, opts.project)
	if err != nil {
		return err
	}
	params := url.Values{}
	params.Set("project", project)
	params.Set("active", "true")
	var res sessionListResponse
	if err := c.getJSON(ctx, apiPath("sessions", params), &res); err != nil {
		return err
	}
	workers := make([]sessionDTO, 0, len(res.Sessions))
	for _, sess := range res.Sessions {
		if sess.Kind == "orchestrator" {
			continue
		}
		workers = append(workers, sess)
	}
	sort.Slice(workers, func(i, j int) bool { return workers[i].ID < workers[j].ID })
	if opts.json {
		return writeJSON(cmd.OutOrStdout(), boardOutput{Data: workers})
	}
	return writeBoard(cmd, workers)
}

func (c *commandContext) resolveBoardProject(ctx context.Context, flag string) (string, error) {
	if trimmed := strings.TrimSpace(flag); trimmed != "" {
		return trimmed, nil
	}
	sessionID := strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID"))
	if !sessionIDPattern.MatchString(sessionID) {
		return "", usageError{fmt.Errorf("--project is required outside an Operator session")}
	}
	var res sessionResponse
	if err := c.getJSON(ctx, "sessions/"+url.PathEscape(sessionID), &res); err != nil {
		return "", err
	}
	if res.Session.ProjectID == "" {
		return "", usageError{fmt.Errorf("--project is required: session %s has no project", sessionID)}
	}
	return res.Session.ProjectID, nil
}

func writeBoard(cmd *cobra.Command, workers []sessionDTO) error {
	out := cmd.OutOrStdout()
	if len(workers) == 0 {
		_, err := fmt.Fprintln(out, "(no live workers)")
		return err
	}
	for i, w := range workers {
		if i > 0 {
			if _, err := fmt.Fprintln(out); err != nil {
				return err
			}
		}
		header := w.ID
		if w.DisplayName != "" {
			header += "  " + w.DisplayName
		}
		if w.Status != "" {
			header += "  [" + w.Status + "]"
		}
		if !w.Activity.LastActivityAt.IsZero() {
			header += "  (" + formatSessionAge(time.Since(w.Activity.LastActivityAt)) + ")"
		}
		if _, err := fmt.Fprintln(out, header); err != nil {
			return err
		}
		for _, line := range [][2]string{
			{"brief", w.Brief},
			{"last prompt", w.LatestUserPrompt},
			{"last update", w.LatestAssistantUpdate},
		} {
			if line[1] == "" {
				continue
			}
			if _, err := fmt.Fprintf(out, "  %s: %s\n", line[0], line[1]); err != nil {
				return err
			}
		}
		for _, pr := range w.PRs {
			if _, err := fmt.Fprintf(out, "  #%d %s ci=%s review=%s\n", pr.Number, pr.State, pr.CI, pr.Review); err != nil {
				return err
			}
		}
	}
	return nil
}
