package cli

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

type mergePRRequest struct {
	PRURL           string `json:"prUrl"`
	ExpectedHeadSHA string `json:"expectedHeadSha"`
}

type mergePRResponse struct {
	OK       bool   `json:"ok"`
	PRNumber int    `json:"prNumber"`
	Method   string `json:"method"`
}

type resolveCommentsRequest struct {
	PRURL      string   `json:"prUrl"`
	CommentIDs []string `json:"commentIds,omitempty"`
}

type resolveCommentsResponse struct {
	OK       bool `json:"ok"`
	Resolved int  `json:"resolved"`
}

type sessionPRSummaryWire struct {
	URL     string `json:"url"`
	Number  int    `json:"number"`
	HeadSHA string `json:"headSha"`
}

type listSessionPRsWire struct {
	PRs []sessionPRSummaryWire `json:"prs"`
}

// prTarget selects the pull request a `opr pr` command acts on. The daemon
// needs the PR URL (a number alone is ambiguous across repositories) and, to
// merge, the head commit the caller saw. Both come from the session's PR list,
// as the desktop's merge button reads them, unless given explicitly.
type prTarget struct {
	url     string
	headSHA string
	session string
}

func (f *prTarget) addFlags(cmd *cobra.Command, withHeadSHA bool) {
	cmd.Flags().StringVar(&f.url, "url", "", "URL of the pull request (default: looked up from the session)")
	cmd.Flags().StringVar(&f.session, "session", "", "session whose pull request this is (default: $OPERATOR_SESSION_ID)")
	if withHeadSHA {
		cmd.Flags().StringVar(&f.headSHA, "head-sha", "", "head commit to merge; the merge is refused if the PR moved (default: the head the session last observed)")
	}
}

// resolve returns the PR's URL and, when needHeadSHA, its head SHA. Flags win;
// anything missing is read from the session's PR list.
func (f *prTarget) resolve(ctx context.Context, c *commandContext, number int, needHeadSHA bool) (sessionPRSummaryWire, error) {
	out := sessionPRSummaryWire{URL: strings.TrimSpace(f.url), Number: number, HeadSHA: strings.TrimSpace(f.headSHA)}
	if out.URL != "" && (!needHeadSHA || out.HeadSHA != "") {
		return out, nil
	}
	session := strings.TrimSpace(f.session)
	if session == "" {
		session = strings.TrimSpace(os.Getenv("OPERATOR_SESSION_ID"))
	}
	if session == "" {
		need := "--url"
		if needHeadSHA {
			need = "--url and --head-sha"
		}
		return out, usageError{fmt.Errorf("pass --session (or run inside a session) so the pull request can be looked up, or pass %s", need)}
	}
	var list listSessionPRsWire
	if err := c.getJSON(ctx, "sessions/"+url.PathEscape(session)+"/pr", &list); err != nil {
		return out, err
	}
	var matches []sessionPRSummaryWire
	for _, pr := range list.PRs {
		if pr.Number == number && (out.URL == "" || strings.EqualFold(strings.TrimRight(pr.URL, "/"), strings.TrimRight(out.URL, "/"))) {
			matches = append(matches, pr)
		}
	}
	switch len(matches) {
	case 0:
		return out, fmt.Errorf("session %s has no pull request #%d; pass --url and --session of the session that owns it", session, number)
	case 1:
	default:
		return out, usageError{fmt.Errorf("session %s has several pull requests #%d; pass --url", session, number)}
	}
	out.URL = matches[0].URL
	if out.HeadSHA == "" {
		out.HeadSHA = matches[0].HeadSHA
	}
	if needHeadSHA && out.HeadSHA == "" {
		return out, fmt.Errorf("pull request #%d has no observed head commit yet; pass --head-sha", number)
	}
	return out, nil
}

func newPRCommand(ctx *commandContext) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "pr",
		Short: "Manage pull requests",
	}
	cmd.AddCommand(newPRMergeCommand(ctx))
	cmd.AddCommand(newPRResolveCommentsCommand(ctx))
	return cmd
}

func newPRMergeCommand(ctx *commandContext) *cobra.Command {
	var target prTarget
	cmd := &cobra.Command{
		Use:   "merge <pr-number>",
		Short: "Merge a pull request",
		Long: "Squash-merge a tracked pull request, pinned to its head commit so a push made\n" +
			"since cannot be merged unseen. The URL and head come from the session's PR list\n" +
			"($OPERATOR_SESSION_ID or --session) unless --url and --head-sha are given.",
		Args: usageArgs(cobra.ExactArgs(1)),
		RunE: func(cmd *cobra.Command, args []string) error {
			prNumber, err := normalizePRNumber(args[0])
			if err != nil {
				return err
			}
			number, _ := strconv.Atoi(prNumber)
			pr, err := target.resolve(cmd.Context(), ctx, number, true)
			if err != nil {
				return err
			}
			var res mergePRResponse
			req := mergePRRequest{PRURL: pr.URL, ExpectedHeadSHA: pr.HeadSHA}
			if err := ctx.postJSON(cmd.Context(), "prs/"+url.PathEscape(prNumber)+"/merge", req, &res); err != nil {
				return err
			}
			if method := strings.TrimSpace(res.Method); method != "" {
				_, err = fmt.Fprintf(cmd.OutOrStdout(), "merged PR #%d using %s\n", res.PRNumber, method)
				return err
			}
			_, err = fmt.Fprintf(cmd.OutOrStdout(), "merged PR #%d\n", res.PRNumber)
			return err
		},
	}
	target.addFlags(cmd, true)
	return cmd
}

func newPRResolveCommentsCommand(ctx *commandContext) *cobra.Command {
	var target prTarget
	cmd := &cobra.Command{
		Use:   "resolve-comments <pr-number> [comment-id...]",
		Short: "Resolve review threads on a pull request",
		Long: "Resolve review threads on a tracked pull request. With no comment ids, every\n" +
			"unresolved thread is resolved; otherwise only the threads that contain one of\n" +
			"the comment ids (or are named by a thread id). The URL comes from the session's\n" +
			"PR list ($OPERATOR_SESSION_ID or --session) unless --url is given.",
		Args: usageArgs(cobra.MinimumNArgs(1)),
		RunE: func(cmd *cobra.Command, args []string) error {
			prNumber, err := normalizePRNumber(args[0])
			if err != nil {
				return err
			}
			commentIDs := make([]string, 0, len(args)-1)
			for _, id := range args[1:] {
				id = strings.TrimSpace(id)
				if id == "" {
					return usageError{errors.New("comment id must not be blank")}
				}
				commentIDs = append(commentIDs, id)
			}
			number, _ := strconv.Atoi(prNumber)
			pr, err := target.resolve(cmd.Context(), ctx, number, false)
			if err != nil {
				return err
			}
			var res resolveCommentsResponse
			if err := ctx.postJSON(
				cmd.Context(),
				"prs/"+url.PathEscape(prNumber)+"/resolve-comments",
				resolveCommentsRequest{PRURL: pr.URL, CommentIDs: commentIDs},
				&res,
			); err != nil {
				return err
			}
			_, err = fmt.Fprintf(cmd.OutOrStdout(), "resolved %d review thread(s) on PR #%s\n", res.Resolved, prNumber)
			return err
		},
	}
	target.addFlags(cmd, false)
	return cmd
}

func normalizePRNumber(raw string) (string, error) {
	raw = strings.TrimPrefix(strings.TrimSpace(raw), "#")
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return "", usageError{errors.New("PR number must be a positive integer")}
	}
	return strconv.Itoa(n), nil
}
