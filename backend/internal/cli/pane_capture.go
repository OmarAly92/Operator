package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/spf13/cobra"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/terminalcapture"
)

func newPaneCaptureCommand(deps Deps) *cobra.Command {
	var dir, epoch string
	cmd := &cobra.Command{
		Use:    "pane-capture",
		Short:  "Journal a shell pane byte stream from stdin (internal)",
		Hidden: true,
		Args:   noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runPaneCapture(cmd, deps, dir, epoch)
		},
	}
	cmd.Flags().StringVar(&dir, "dir", "", "absolute per-terminal journal directory inside the capture root")
	cmd.Flags().StringVar(&epoch, "epoch", "", "capture epoch UUID")
	return cmd
}

func runPaneCapture(cmd *cobra.Command, deps Deps, dir, epoch string) error {
	if strings.TrimSpace(dir) == "" {
		return usageError{errors.New("pane-capture: --dir is required")}
	}
	parsedEpoch, err := uuid.Parse(strings.TrimSpace(epoch))
	if err != nil {
		return usageError{fmt.Errorf("pane-capture: --epoch must be a valid UUID: %w", err)}
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	root := terminalcapture.CaptureRoot(cfg.DataDir)
	journalDir, err := resolveWithinCaptureRoot(root, dir)
	if err != nil {
		return usageError{err}
	}

	j, err := terminalcapture.Open(filepath.Join(journalDir, parsedEpoch.String()))
	if err != nil {
		return err
	}

	ctx := cmd.Context()
	if ctx == nil {
		ctx = context.Background()
	}
	in := deps.In
	if in == nil {
		in = os.Stdin
	}
	return terminalcapture.NewSink(j).Run(ctx, in)
}

func resolveWithinCaptureRoot(root, target string) (string, error) {
	target = filepath.Clean(target)
	if !filepath.IsAbs(target) {
		return "", fmt.Errorf("pane-capture: --dir %q must be absolute", target)
	}
	realRoot := realExistingPath(filepath.Clean(root))
	realTarget := realExistingPath(target)
	rel, err := filepath.Rel(realRoot, realTarget)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("pane-capture: --dir %q is outside the capture root %q", target, realRoot)
	}
	return target, nil
}

func realExistingPath(p string) string {
	p = filepath.Clean(p)
	var tail []string
	for {
		if resolved, err := filepath.EvalSymlinks(p); err == nil {
			for i := len(tail) - 1; i >= 0; i-- {
				resolved = filepath.Join(resolved, tail[i])
			}
			return resolved
		}
		parent := filepath.Dir(p)
		if parent == p {
			return p
		}
		tail = append(tail, filepath.Base(p))
		p = parent
	}
}
