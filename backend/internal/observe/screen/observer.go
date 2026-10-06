package screen

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

const (
	stepEvery        = 250 * time.Millisecond
	reassertEvery    = 5 * time.Second
	maxQueued        = 32
	untrackedRecheck = 30 * time.Second
)

type sessionSource interface {
	ListAllSessions(ctx context.Context) ([]domain.SessionRecord, error)
	GetSession(ctx context.Context, id domain.SessionID) (domain.SessionRecord, bool, error)
}

type activitySink interface {
	ApplyActivitySignal(ctx context.Context, id domain.SessionID, signal ports.ActivitySignal) error
}

type programSource interface {
	WatchTerminalPrograms(fn func(handleID string, event ports.TerminalProgramEvent)) (stop func())
}

type Config struct {
	Clock  func() time.Time
	Logger *slog.Logger
}

type tracked struct {
	session   domain.SessionID
	harness   domain.AgentHarness
	debouncer Debouncer
	confirmed *Decision
	checkAt   time.Time
}

type Observer struct {
	sessions sessionSource
	sink     activitySink
	programs programSource
	agents   ports.AgentResolver
	clock    func() time.Time
	logger   *slog.Logger

	mu     sync.Mutex
	queued map[string][]ports.TerminalProgramEvent
	wake   chan struct{}

	tracked   map[string]*tracked
	untracked map[string]time.Time

	watchMu  sync.Mutex
	watching map[domain.SessionID]domain.AgentHarness
}

func New(sessions sessionSource, sink activitySink, programs programSource, agents ports.AgentResolver, cfg Config) *Observer {
	o := &Observer{
		sessions:  sessions,
		sink:      sink,
		programs:  programs,
		agents:    agents,
		clock:     cfg.Clock,
		logger:    cfg.Logger,
		queued:    map[string][]ports.TerminalProgramEvent{},
		wake:      make(chan struct{}, 1),
		tracked:   map[string]*tracked{},
		untracked: map[string]time.Time{},
		watching:  map[domain.SessionID]domain.AgentHarness{},
	}
	if o.clock == nil {
		o.clock = func() time.Time { return time.Now().UTC() }
	}
	if o.logger == nil {
		o.logger = slog.Default()
	}
	return o
}

func (o *Observer) Start(ctx context.Context) <-chan struct{} {
	done := make(chan struct{})
	stop := o.programs.WatchTerminalPrograms(o.Enqueue)
	go func() {
		defer close(done)
		defer stop()
		ticker := time.NewTicker(stepEvery)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-o.wake:
				o.Drain(ctx)
			case <-ticker.C:
				o.Drain(ctx)
				o.Step(ctx, o.clock())
			}
		}
	}()
	return done
}

func (o *Observer) Enqueue(handleID string, event ports.TerminalProgramEvent) {
	if event.Kind != ports.TerminalProgramActivity {
		return
	}
	o.mu.Lock()
	o.queued[handleID] = append(o.queued[handleID], event)
	if queue := o.queued[handleID]; len(queue) > maxQueued {
		o.queued[handleID] = queue[len(queue)-maxQueued:]
	}
	o.mu.Unlock()
	select {
	case o.wake <- struct{}{}:
	default:
	}
}

func (o *Observer) Drain(ctx context.Context) {
	o.mu.Lock()
	queued := o.queued
	o.queued = map[string][]ports.TerminalProgramEvent{}
	o.mu.Unlock()
	for handleID, events := range queued {
		t := o.track(ctx, handleID, o.clock())
		if t == nil {
			continue
		}
		agent := o.agentFor(t.harness)
		for _, event := range events {
			at := event.At
			if at.IsZero() {
				at = o.clock()
			}
			o.apply(ctx, t, t.debouncer.Observe(Classify(agent, event), at))
		}
	}
}

func (o *Observer) Step(ctx context.Context, now time.Time) {
	for handleID, missed := range o.untracked {
		if now.Sub(missed) >= untrackedRecheck {
			delete(o.untracked, handleID)
		}
	}
	for handleID, t := range o.tracked {
		o.apply(ctx, t, t.debouncer.Due(now))
		if now.Before(t.checkAt) {
			continue
		}
		t.checkAt = now.Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil {
			continue
		}
		if !owns(rec, ok, handleID) {
			delete(o.tracked, handleID)
			o.unwatchUntracked(t.session)
			continue
		}
		if t.confirmed != nil && t.debouncer.Holds() {
			o.send(ctx, t, rec, *t.confirmed, true)
		}
	}
}

func (o *Observer) apply(ctx context.Context, t *tracked, decisions []Decision) {
	for _, decision := range decisions {
		confirmed := decision
		t.confirmed = &confirmed
		t.checkAt = o.clock().Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil || !ok || rec.IsTerminated {
			continue
		}
		o.send(ctx, t, rec, decision, false)
	}
}

func (o *Observer) send(ctx context.Context, t *tracked, rec domain.SessionRecord, decision Decision, reassert bool) {
	t.harness = rec.Harness
	o.watch(t.session, rec.Harness)
	target, ok := decision.Reading.State()
	if !ok {
		return
	}
	if rec.Activity.State == target && (reassert || decision.Reading != domain.ScreenQuestion) {
		return
	}
	err := o.sink.ApplyActivitySignal(ctx, rec.ID, ports.ActivitySignal{
		Valid:             true,
		State:             target,
		Timestamp:         o.clock(),
		ExpectedUpdatedAt: rec.UpdatedAt,
		Event:             ports.ScreenEvent(decision.Reading),
		LaunchID:          rec.Metadata.RuntimeLaunchID,
		ScreenReading:     decision.Reading,
		ScreenIdentity:    decision.Identity,
		ScreenText:        decision.Text,
		ScreenReassert:    reassert,
	})
	if err != nil {
		o.logger.Error("screen observer: apply failed", "session", rec.ID, "reading", decision.Reading, "err", err)
	}
}

func (o *Observer) track(ctx context.Context, handleID string, now time.Time) *tracked {
	if t, ok := o.tracked[handleID]; ok {
		return t
	}
	if rec, ok, err := o.sessions.GetSession(ctx, domain.SessionID(handleID)); err == nil && owns(rec, ok, handleID) {
		return o.adopt(handleID, rec)
	}
	if missed, ok := o.untracked[handleID]; ok && now.Sub(missed) < untrackedRecheck {
		return nil
	}
	sessions, err := o.sessions.ListAllSessions(ctx)
	if err != nil {
		o.logger.Debug("screen observer: sessions unavailable", "err", err)
		return nil
	}
	for _, rec := range sessions {
		if owns(rec, true, handleID) {
			return o.adopt(handleID, rec)
		}
	}
	o.untracked[handleID] = now
	return nil
}

func (o *Observer) adopt(handleID string, rec domain.SessionRecord) *tracked {
	delete(o.untracked, handleID)
	t := &tracked{session: rec.ID, harness: rec.Harness, checkAt: o.clock().Add(reassertEvery)}
	o.tracked[handleID] = t
	o.watch(rec.ID, rec.Harness)
	return t
}

func (o *Observer) watch(id domain.SessionID, harness domain.AgentHarness) {
	o.watchMu.Lock()
	defer o.watchMu.Unlock()
	o.watching[id] = harness
}

func (o *Observer) unwatchUntracked(id domain.SessionID) {
	for _, t := range o.tracked {
		if t.session == id {
			return
		}
	}
	o.watchMu.Lock()
	defer o.watchMu.Unlock()
	delete(o.watching, id)
}

func (o *Observer) WatchesQuestions(id domain.SessionID) bool {
	o.watchMu.Lock()
	harness, ok := o.watching[id]
	o.watchMu.Unlock()
	if !ok {
		return false
	}
	_, reads := o.agentFor(harness).(ports.TerminalQuestionReader)
	return reads
}

func owns(rec domain.SessionRecord, ok bool, handleID string) bool {
	return ok && !rec.IsTerminated && rec.Metadata.RuntimeHandleID == handleID
}

func (o *Observer) agentFor(harness domain.AgentHarness) any {
	if o.agents == nil {
		return nil
	}
	agent, ok := o.agents.Agent(harness)
	if !ok {
		return nil
	}
	return agent
}
