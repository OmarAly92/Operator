package gitworktree

import (
	"context"
	"fmt"
	"strings"

	"github.com/OmarAly92/operator/backend/internal/ports"
)

type BranchLister struct {
	binary string
	run    commandRunner
}

var _ ports.BranchLister = (*BranchLister)(nil)

func NewBranchLister(binary string) *BranchLister {
	if binary == "" {
		binary = defaultGitBinary
	}
	return &BranchLister{binary: binary, run: runCommand}
}

func (l *BranchLister) ListBranches(ctx context.Context, repoPath string) (ports.BranchListing, error) {
	refs, err := l.run(ctx, l.binary, "-C", repoPath, "for-each-ref", "--sort=-committerdate", "--format=%(refname)", "refs/heads")
	if err != nil {
		return ports.BranchListing{}, fmt.Errorf("gitworktree: list branches: %w", err)
	}
	worktrees, err := l.run(ctx, l.binary, worktreeListPorcelainArgs(repoPath)...)
	if err != nil {
		return ports.BranchListing{}, fmt.Errorf("gitworktree: worktree list: %w", err)
	}
	records, err := parseWorktreePorcelain(string(worktrees))
	if err != nil {
		return ports.BranchListing{}, fmt.Errorf("gitworktree: parse worktree list: %w", err)
	}

	var listing ports.BranchListing
	if len(records) > 0 && !records[0].Detached {
		listing.Current = records[0].Branch
	}
	checkedOutAt := make(map[string]string, len(records))
	for _, rec := range records {
		if rec.Branch == "" {
			continue
		}
		if _, seen := checkedOutAt[rec.Branch]; !seen {
			checkedOutAt[rec.Branch] = rec.Path
		}
	}
	for _, line := range strings.Split(string(refs), "\n") {
		name, ok := strings.CutPrefix(strings.TrimSpace(line), "refs/heads/")
		if !ok || name == "" {
			continue
		}
		listing.Branches = append(listing.Branches, ports.BranchInfo{
			Name:           name,
			CheckedOutAt:   checkedOutAt[name],
			IsMainCheckout: listing.Current != "" && name == listing.Current,
		})
	}
	return listing, nil
}
