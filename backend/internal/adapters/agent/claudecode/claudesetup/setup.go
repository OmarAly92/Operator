package claudesetup

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type ItemState string

const (
	ItemLinked   ItemState = "linked"
	ItemReplaced ItemState = "replaced"
	ItemMissing  ItemState = "missing"
	ItemSkipped  ItemState = "skipped"
)

var SharedItems = []string{"CLAUDE.md", "settings.json", "skills", "commands", "agents", "plugins"}

type Report map[string]ItemState

func (r Report) Replaced() []string {
	out := make([]string, 0)
	for name, state := range r {
		if state == ItemReplaced {
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

func Ensure(defaultDir, accountDir string) (Report, error) {
	return walk(defaultDir, accountDir, true)
}

func Inspect(defaultDir, accountDir string) (Report, error) {
	return walk(defaultDir, accountDir, false)
}

func Relink(defaultDir, accountDir string, now time.Time) (Report, error) {
	for _, name := range SharedItems {
		source := filepath.Join(defaultDir, name)
		target := filepath.Join(accountDir, name)
		if _, err := os.Stat(source); errors.Is(err, os.ErrNotExist) {
			continue
		} else if err != nil {
			return nil, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		info, err := os.Lstat(target)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		backup := fmt.Sprintf("%s.bak-%d", target, now.Unix())
		if err := os.Rename(target, backup); err != nil {
			return nil, fmt.Errorf("claudesetup: back up %s: %w", name, err)
		}
	}
	return Ensure(defaultDir, accountDir)
}

func walk(defaultDir, accountDir string, repair bool) (Report, error) {
	report := make(Report, len(SharedItems))
	for _, name := range SharedItems {
		state, err := item(filepath.Join(defaultDir, name), filepath.Join(accountDir, name), repair)
		if err != nil {
			return report, fmt.Errorf("claudesetup: %s: %w", name, err)
		}
		report[name] = state
	}
	return report, nil
}

func item(source, target string, repair bool) (ItemState, error) {
	if _, err := os.Stat(source); errors.Is(err, os.ErrNotExist) {
		return ItemSkipped, nil
	} else if err != nil {
		return "", err
	}
	info, err := os.Lstat(target)
	switch {
	case errors.Is(err, os.ErrNotExist):
		if !repair {
			return ItemMissing, nil
		}
		return ItemLinked, os.Symlink(source, target)
	case err != nil:
		return "", err
	case info.Mode()&os.ModeSymlink == 0:
		return ItemReplaced, nil
	}
	current, err := os.Readlink(target)
	if err != nil {
		return "", err
	}
	if current == source {
		return ItemLinked, nil
	}
	if !repair {
		return ItemMissing, nil
	}
	if err := os.Remove(target); err != nil {
		return "", err
	}
	return ItemLinked, os.Symlink(source, target)
}
