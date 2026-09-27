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
	stepEvery     = 250 * time.Millisecond
	reassertEvery = 5 * time.Second
	maxQueued     = 32
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
	session    domain.SessionID
	harness    domain.AgentHarness
	debouncer  Debouncer
	confirmed  *Decision
	reassertAt time.Time
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

	tracked map[string]*tracked
}

func New(sessions sessionSource, sink activitySink, programs programSource, agents ports.AgentResolver, cfg Config) *Observer {
	o := &Observer{
		sessions: sessions,
		sink:     sink,
		programs: programs,
		agents:   agents,
		clock:    cfg.Clock,
		logger:   cfg.Logger,
		queued:   map[string][]ports.TerminalProgramEvent{},
		wake:     make(chan struct{}, 1),
		tracked:  map[string]*tracked{},
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
		t := o.track(ctx, handleID)
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
	for handleID, t := range o.tracked {
		o.apply(ctx, t, t.debouncer.Due(now))
		if t.confirmed == nil || now.Before(t.reassertAt) {
			continue
		}
		t.reassertAt = now.Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil {
			continue
		}
		if !ok || rec.IsTerminated {
			delete(o.tracked, handleID)
			continue
		}
		o.send(ctx, t, rec, *t.confirmed)
	}
}

func (o *Observer) apply(ctx context.Context, t *tracked, decisions []Decision) {
	for _, decision := range decisions {
		confirmed := decision
		t.confirmed = &confirmed
		t.reassertAt = o.clock().Add(reassertEvery)
		rec, ok, err := o.sessions.GetSession(ctx, t.session)
		if err != nil || !ok || rec.IsTerminated {
			continue
		}
		o.send(ctx, t, rec, decision)
	}
}

func (o *Observer) send(ctx context.Context, t *tracked, rec domain.SessionRecord, decision Decision) {
	t.harness = rec.Harness
	target, ok := decision.Reading.State()
	if !ok || rec.Activity.State == target {
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
	})
	if err != nil {
		o.logger.Error("screen observer: apply failed", "session", rec.ID, "reading", decision.Reading, "err", err)
	}
}

func (o *Observer) track(ctx context.Context, handleID string) *tracked {
	if t, ok := o.tracked[handleID]; ok {
		return t
	}
	sessions, err := o.sessions.ListAllSessions(ctx)
	if err != nil {
		o.logger.Debug("screen observer: sessions unavailable", "err", err)
		return nil
	}
	for _, rec := range sessions {
		if rec.Metadata.RuntimeHandleID == handleID && !rec.IsTerminated {
			t := &tracked{session: rec.ID, harness: rec.Harness}
			o.tracked[handleID] = t
			return t
		}
	}
	return nil
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
