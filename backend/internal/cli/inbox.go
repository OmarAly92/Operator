package cli

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

type inboxOptions struct {
	project string
	json    bool
}

type inboxEntryDTO struct {
	ID         string     `json:"id"`
	Kind       string     `json:"kind"`
	OccurredAt time.Time  `json:"occurredAt"`
	Worker     sessionDTO `json:"worker"`
}

type inboxListResponse struct {
	Entries []inboxEntryDTO `json:"entries"`
}

type inboxAckRequest struct {
	IDs []string `json:"ids"`
}

type inboxAckResponse struct {
	Acked int `json:"acked"`
}

func newInboxCommand(ctx *commandContext) *cobra.Command {
	var opts inboxOptions
	cmd := &cobra.Command{
		Use:   "inbox",
		Short: "Show pending worker-idle digests for this project",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return ctx.showInbox(cmd.Context(), cmd, opts)
		},
	}
	cmd.Flags().StringVar(&opts.project, "project", "", "Project id (defaults to the current session's project)")
	cmd.Flags().BoolVar(&opts.json, "json", false, "Output as JSON")
	cmd.AddCommand(newInboxAckCommand(ctx))
	return cmd
}

func newInboxAckCommand(ctx *commandContext) *cobra.Command {
	var project string
	cmd := &cobra.Command{
		Use:   "ack <id> [<id>...]",
		Short: "Acknowledge one or more inbox items",
		Args:  usageArgs(cobra.MinimumNArgs(1)),
		RunE: func(cmd *cobra.Command, args []string) error {
			return ctx.ackInbox(cmd.Context(), cmd, project, args)
		},
	}
	cmd.Flags().StringVar(&project, "project", "", "Project id (defaults to the current session's project)")
	return cmd
}

func (c *commandContext) showInbox(ctx context.Context, cmd *cobra.Command, opts inboxOptions) error {
	project, err := c.resolveBoardProject(ctx, opts.project)
	if err != nil {
		return err
	}
	var res inboxListResponse
	if err := c.getJSON(ctx, apiPath("projects/"+url.PathEscape(project)+"/inbox", nil), &res); err != nil {
		return err
	}
	if opts.json {
		return writeJSON(cmd.OutOrStdout(), res)
	}
	return writeInbox(cmd, res.Entries)
}

func (c *commandContext) ackInbox(ctx context.Context, cmd *cobra.Command, projectFlag string, ids []string) error {
	project, err := c.resolveBoardProject(ctx, projectFlag)
	if err != nil {
		return err
	}
	var res inboxAckResponse
	if err := c.postJSON(ctx, "projects/"+url.PathEscape(project)+"/inbox/ack", inboxAckRequest{IDs: ids}, &res); err != nil {
		return err
	}
	_, err = fmt.Fprintf(cmd.OutOrStdout(), "acked %d\n", res.Acked)
	return err
}

func writeInbox(cmd *cobra.Command, entries []inboxEntryDTO) error {
	out := cmd.OutOrStdout()
	if len(entries) == 0 {
		_, err := fmt.Fprintln(out, "(no pending inbox items)")
		return err
	}
	var ids []string
	for i, e := range entries {
		if i > 0 {
			if _, err := fmt.Fprintln(out); err != nil {
				return err
			}
		}
		w := e.Worker
		header := fmt.Sprintf("%s  %s", e.ID, e.Kind)
		if w.ID != "" {
			header += "  " + w.ID
		}
		if w.DisplayName != "" {
			header += "  " + w.DisplayName
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
		ids = append(ids, e.ID)
	}
	if _, err := fmt.Fprintln(out); err != nil {
		return err
	}
	_, err := fmt.Fprintf(out, "opr inbox ack %s\n", strings.Join(ids, " "))
	return err
}
