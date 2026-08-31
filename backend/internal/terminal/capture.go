package terminal

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/OmarAly92/operator/packages/terminal/go/marks"
)

const (
	defaultMaxCaptureBytes int64 = 1 << 20

	defaultPollInterval = 50 * time.Millisecond
)

type BlockEventRecorder interface {
	RecordShellBlock(ctx context.Context, sessionID string, block ShellBlock) error
}

type ShellBlock struct {
	SourceID   string
	Command    string
	Workdir    string
	ExitCode   *int
	StartedAt  time.Time
	FinishedAt time.Time
	Tier1Only  bool
	Branch     string
	BlockID    string
}

type Capture struct {
	Path              string
	MaxBytes          int64
	PollInterval      time.Duration
	SessionID         string
	Recorder          BlockEventRecorder
	StartedInAltScreen bool
	decoder           *marks.Decoder
	state             *blockState
}

func NewCapture(path, sessionID string, rec BlockEventRecorder) *Capture {
	return &Capture{
		Path:              path,
		MaxBytes:          defaultMaxCaptureBytes,
		PollInterval:      defaultPollInterval,
		SessionID:         sessionID,
		Recorder:          rec,
		StartedInAltScreen: false,
		decoder:           marks.NewDecoder(),
		state:             newBlockState(false),
	}
}

func OpenSink(path string) (*os.File, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("capture: ensure sink dir: %w", err)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return nil, fmt.Errorf("capture: open sink %s: %w", path, err)
	}
	return f, nil
}

func (c *Capture) Drain(ctx context.Context, r io.Reader) error {
	if !c.state.bound {
		*c.state = blockState{altScreen: c.StartedInAltScreen}
		c.state.bound = true
	}
	buf := make([]byte, 16*1024)
	br := bufio.NewReader(r)
	for {
		if err := ctx.Err(); err != nil {
			return nil
		}
		n, err := br.Read(buf)
		if n > 0 {
			events := c.decoder.Feed(buf[:n])
			for _, ev := range events {
				emitted, e := c.state.apply(ctx, c.SessionID, c.Recorder, ev)
				if e != nil {
					return e
				}
				if emitted && c.Path != "" {
					if err := c.boundSink(c.Path); err != nil {
						return err
					}
				}
			}
		}
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
	}
}

func (c *Capture) Run(ctx context.Context) error {
	if c.Path == "" {
		return errors.New("capture: sink path is empty")
	}
	if c.MaxBytes <= 0 {
		c.MaxBytes = defaultMaxCaptureBytes
	}
	if c.PollInterval <= 0 {
		c.PollInterval = defaultPollInterval
	}

	offset := int64(0)
	for {
		if err := ctx.Err(); err != nil {
			return nil
		}
		info, err := os.Stat(c.Path)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				if !sleep(ctx, c.PollInterval) {
					return nil
				}
				continue
			}
			return fmt.Errorf("capture: stat sink: %w", err)
		}
		size := info.Size()
		if size < offset {
			offset = 0
		}
		if size > offset {
			f, err := os.Open(c.Path)
			if err != nil {
				return fmt.Errorf("capture: open sink: %w", err)
			}
			_, serr := f.Seek(offset, io.SeekStart)
			if serr != nil {
				f.Close()
				return fmt.Errorf("capture: seek sink: %w", serr)
			}
			if err := c.Drain(ctx, f); err != nil {
				f.Close()
				return err
			}
			if err := f.Close(); err != nil {
				return fmt.Errorf("capture: close sink: %w", err)
			}
			next, statErr := os.Stat(c.Path)
			if statErr == nil {
				offset = next.Size()
			} else {
				offset = size
			}
		}
		if !sleep(ctx, c.PollInterval) {
			return nil
		}
	}
}

func (c *Capture) boundSink(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("capture: stat sink: %w", err)
	}
	if info.Size() <= c.MaxBytes {
		return nil
	}
	drop := info.Size() - c.MaxBytes
	if err := rotateHead(path, drop); err != nil {
		return err
	}
	return nil
}

func rotateHead(path string, drop int64) error {
	if err := os.Rename(path, path+".tmp"); err != nil {
		return fmt.Errorf("capture: rotate sink: %w", err)
	}
	old, err := os.Open(path + ".tmp")
	if err != nil {
		return fmt.Errorf("capture: open rotated sink: %w", err)
	}
	defer old.Close()
	if _, err := old.Seek(drop, io.SeekStart); err != nil {
		return fmt.Errorf("capture: seek rotated sink: %w", err)
	}
	newF, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return fmt.Errorf("capture: reopen sink: %w", err)
	}
	if _, err := io.Copy(newF, old); err != nil {
		newF.Close()
		return fmt.Errorf("capture: copy rotated sink: %w", err)
	}
	if err := newF.Close(); err != nil {
		return fmt.Errorf("capture: close rotated sink: %w", err)
	}
	if err := os.Remove(path + ".tmp"); err != nil {
		return fmt.Errorf("capture: remove rotated sink: %w", err)
	}
	return nil
}

func sleep(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

type blockState struct {
	promptOpen    bool
	commandOpen   bool
	current       ShellBlock
	currentCwd    string
	currentBranch string
	currentID     string
	startedAt     time.Time
	tier1Only     bool
	altScreen     bool
	bound         bool
}

func newBlockState(startedInAltScreen bool) *blockState {
	return &blockState{altScreen: startedInAltScreen}
}

func (s *blockState) apply(ctx context.Context, sessionID string, rec BlockEventRecorder, ev marks.Event) (emitted bool, err error) {
	if ev.Kind == "alt_screen_enter" {
		if !s.altScreen {
			s.altScreen = true
			s.promptOpen = false
			s.commandOpen = false
		}
		return false, nil
	}
	if ev.Kind == "alt_screen_leave" {
		s.altScreen = false
		return true, nil
	}
	if s.altScreen {
		return false, nil
	}
	switch ev.Kind {
	case "prompt_start":
		s.promptOpen = true
		s.commandOpen = false
		s.current = ShellBlock{}
		s.currentCwd = ""
		s.currentBranch = ""
		s.currentID = ""
		s.startedAt = time.Time{}
		s.tier1Only = true
	case "command_start":
		s.commandOpen = true
	case "output_start":
		s.commandOpen = true
	case "cwd_changed":
		if s.promptOpen {
			s.currentCwd = ev.Path
		}
	case "extension":
		s.tier1Only = false
		if s.promptOpen {
			if v, ok := ev.Fields["cwd"]; ok && v != "" {
				s.currentCwd = v
			}
			if v, ok := ev.Fields["branch"]; ok && v != "" {
				s.currentBranch = v
			}
			if v, ok := ev.Fields["id"]; ok && v != "" {
				s.currentID = v
			}
			if v, ok := ev.Fields["start_ms"]; ok && v != "" {
				if t, ok := parseMillis(v); ok {
					s.startedAt = t
				}
			}
			if v, ok := ev.Fields["cmd"]; ok && v != "" {
				s.current.Command = v
			}
		}
	case "command_end":
		if !s.promptOpen {
			return false, nil
		}
		s.current.ExitCode = ev.ExitCode
		s.current.Workdir = s.currentCwd
		s.current.Branch = s.currentBranch
		s.current.SourceID = s.currentID
		s.current.Tier1Only = s.tier1Only
		s.current.BlockID = s.currentID
		if !s.startedAt.IsZero() {
			s.current.StartedAt = s.startedAt
		}
		s.current.FinishedAt = time.Now().UTC()
		if rec != nil {
			if err := rec.RecordShellBlock(ctx, sessionID, s.current); err != nil {
				return false, err
			}
		}
		s.promptOpen = false
		s.commandOpen = false
		return true, nil
	}
	return false, nil
}

func parseMillis(s string) (time.Time, bool) {
	var n int64
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return time.Time{}, false
		}
		n = n*10 + int64(c-'0')
	}
	return time.UnixMilli(n).UTC(), true
}
