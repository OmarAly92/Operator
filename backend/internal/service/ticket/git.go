package ticket

import (
	"context"
	"fmt"
	"strings"

	aoprocess "github.com/OmarAly92/operator/backend/internal/process"
)

func gitOutput(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := aoprocess.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git -C %s %s: %w: %s", dir, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return string(out), nil
}

func gitCurrentBranch(ctx context.Context, repo string) (string, error) {
	out, err := gitOutput(ctx, repo, "rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func gitPathDirty(ctx context.Context, repo, rel string) (bool, error) {
	out, err := gitOutput(ctx, repo, "status", "--porcelain", "--untracked-files=all", "--", rel)
	if err != nil {
		return false, err
	}
	return strings.TrimSpace(out) != "", nil
}

func gitCommitPath(ctx context.Context, repo, rel, message string) error {
	if _, err := gitOutput(ctx, repo, "add", "-A", "--", rel); err != nil {
		return err
	}
	staged, err := gitOutput(ctx, repo, "diff", "--cached", "--name-only", "--", rel)
	if err != nil {
		return err
	}
	if strings.TrimSpace(staged) == "" {
		return nil
	}
	_, err = gitOutput(ctx, repo, "commit", "-q", "-m", message, "--", rel)
	return err
}

func splitLines(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	return strings.Split(s, "\n")
}
