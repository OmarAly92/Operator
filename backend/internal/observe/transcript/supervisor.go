package transcript

import (
	"context"
	"log/slog"
	"os"
	"sort"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/blocktranscript"
	"github.com/OmarAly92/operator/backend/internal/domain"
	usagepipeline "github.com/OmarAly92/operator/backend/internal/observe/usage"
)

// DefaultInterval is how often the supervisor re-reads the live session set and
// re-checks every tracked file. The filesystem watch is a latency optimisation
// on top of it, so a dropped filesystem event costs a tick, not a block.
const DefaultInterval = 2 * time.Second

// unknownRecordLogEvery bounds how often an unrecognised-record count is
// reported. A harness release that renames a record type would otherwise log
// once per record.
const unknownRecordLogEvery = 100

// SessionSource is the slice of the store the supervisor needs.
type SessionSource interface {
	ListAllSessions(ctx context.Context) ([]domain.SessionRecord, error)
}

// Watcher is the filesystem watch the supervisor drives. usage.TranscriptWatcher
// satisfies it; the supervisor constructs its own instance so no state is shared
// with usage accounting.
type Watcher interface {
	Events() <-chan usagepipeline.TranscriptEvent
	Errors() <-chan error
	Rebuild(ctx context.Context, sourcePaths []string) error
	Start(ctx context.Context) <-chan struct{}
}

// Deps are the supervisor's collaborators. Watcher may be nil, in which case
// projection still works on the reconcile interval alone.
type Deps struct {
	Sessions SessionSource
	Offsets  OffsetStore
	Sink     Sink
	Resolver *Resolver
	Watcher  Watcher
	Interval time.Duration
	Logger   *slog.Logger
	Clock    func() time.Time
}

// Supervisor owns one tail per live session whose harness has a transcript
// mapper.
type Supervisor struct {
	deps  Deps
	tails map[domain.SessionID]*tail
}

// NewSupervisor constructs the transcript projection supervisor.
func NewSupervisor(deps Deps) *Supervisor {
	if deps.Interval <= 0 {
		deps.Interval = DefaultInterval
	}
	if deps.Logger == nil {
		deps.Logger = slog.Default()
	}
	if deps.Clock == nil {
		deps.Clock = func() time.Time { return time.Now().UTC() }
	}
	return &Supervisor{deps: deps, tails: map[domain.SessionID]*tail{}}
}

// Start runs until ctx is cancelled. The returned channel closes after the
// goroutine exits.
func (s *Supervisor) Start(ctx context.Context) <-chan struct{} {
	done := make(chan struct{})
	go func() {
		defer close(done)
		var events <-chan usagepipeline.TranscriptEvent
		var errs <-chan error
		if s.deps.Watcher != nil {
			watcherDone := s.deps.Watcher.Start(ctx)
			defer func() { <-watcherDone }()
			events = s.deps.Watcher.Events()
			errs = s.deps.Watcher.Errors()
		}
		s.tick(ctx)
		ticker := time.NewTicker(s.deps.Interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.tick(ctx)
			case event, ok := <-events:
				if !ok {
					events = nil
					continue
				}
				s.pumpPath(ctx, event.Path)
			case err, ok := <-errs:
				if !ok {
					errs = nil
					continue
				}
				if err != nil {
					s.deps.Logger.Warn("transcript watcher", "err", err)
				}
			}
		}
	}()
	return done
}

func (s *Supervisor) tick(ctx context.Context) {
	s.reconcile(ctx)
	s.pumpAll(ctx)
}

func (s *Supervisor) reconcile(ctx context.Context) {
	if s.deps.Sessions == nil || s.deps.Resolver == nil {
		return
	}
	sessions, err := s.deps.Sessions.ListAllSessions(ctx)
	if err != nil {
		s.deps.Logger.Warn("transcript projection could not list sessions", "err", err)
		return
	}
	seen := make(map[domain.SessionID]struct{}, len(sessions))
	paths := make([]string, 0, len(sessions))
	for _, rec := range sessions {
		if ctx.Err() != nil {
			return
		}
		if rec.IsTerminated || !blocktranscript.Supports(string(rec.Harness)) {
			continue
		}
		existing, tracked := s.tails[rec.ID]
		var path string
		if tracked && fileStillReadable(existing.path) {
			path = existing.path
		} else {
			path = s.deps.Resolver.Path(ctx, rec)
		}
		if path == "" {
			continue
		}
		seen[rec.ID] = struct{}{}
		paths = append(paths, path)
		if tracked && existing.path == path {
			continue
		}
		if tracked {
			existing.path = path
			existing.offset = 0
			existing.lastModel = ""
			continue
		}
		s.tails[rec.ID] = s.newTail(ctx, rec, path)
	}
	for id := range s.tails {
		if _, live := seen[id]; !live {
			delete(s.tails, id)
		}
	}
	if s.deps.Watcher != nil {
		sort.Strings(paths)
		if err := s.deps.Watcher.Rebuild(ctx, paths); err != nil {
			s.deps.Logger.Warn("transcript watch rebuild", "err", err)
		}
	}
}

// fileStillReadable is a cheap check that a previously resolved transcript
// path still exists, letting reconcile skip the full hook/adapter resolution
// for a session it already tracks. A Codex adapter's fallback resolution
// walks the whole ~/.codex/sessions tree, which every-tick re-resolution
// would otherwise pay for regardless of whether anything changed.
func fileStillReadable(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func (s *Supervisor) newTail(ctx context.Context, rec domain.SessionRecord, path string) *tail {
	created := &tail{sessionID: rec.ID, harness: string(rec.Harness), path: path}
	if s.deps.Offsets == nil {
		return created
	}
	storedPath, offset, found, err := s.deps.Offsets.GetTranscriptOffset(ctx, string(rec.ID))
	if err != nil {
		s.deps.Logger.Warn("transcript cursor read", "session", rec.ID, "err", err)
		return created
	}
	if found && storedPath == path {
		created.offset = offset
	}
	return created
}

func (s *Supervisor) pumpAll(ctx context.Context) {
	for _, tracked := range s.tails {
		if ctx.Err() != nil {
			return
		}
		s.pump(ctx, tracked)
	}
}

func (s *Supervisor) pumpPath(ctx context.Context, path string) {
	for _, tracked := range s.tails {
		if tracked.path == path {
			s.pump(ctx, tracked)
		}
	}
}

func (s *Supervisor) pump(ctx context.Context, tracked *tail) {
	if s.deps.Sink == nil || s.deps.Offsets == nil {
		return
	}
	if err := tracked.pump(ctx, s.deps.Sink, s.deps.Offsets, s.deps.Clock); err != nil && ctx.Err() == nil {
		s.deps.Logger.Warn("transcript projection", "session", tracked.sessionID, "err", err)
	}
	if tracked.unknown-tracked.logged >= unknownRecordLogEvery {
		tracked.logged = tracked.unknown
		s.deps.Logger.Info(
			"transcript records not recognised",
			"session", tracked.sessionID,
			"harness", tracked.harness,
			"count", tracked.unknown,
		)
	}
}
