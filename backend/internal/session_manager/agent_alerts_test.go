package sessionmanager

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/lifecycle"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type alertLifecycleStore struct {
	mu       sync.Mutex
	sessions map[domain.SessionID]domain.SessionRecord
}

func (s *alertLifecycleStore) GetSession(_ context.Context, id domain.SessionID) (domain.SessionRecord, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.sessions[id]
	return rec, ok, nil
}

func (s *alertLifecycleStore) UpdateSession(_ context.Context, rec domain.SessionRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[rec.ID] = rec
	return nil
}

func (s *alertLifecycleStore) UpdateSessionFromActivitySignal(ctx context.Context, rec domain.SessionRecord) (bool, error) {
	return true, s.UpdateSession(ctx, rec)
}

func (s *alertLifecycleStore) ListSessions(context.Context, domain.ProjectID) ([]domain.SessionRecord, error) {
	return nil, nil
}

func (s *alertLifecycleStore) ListPRsBySession(context.Context, domain.SessionID) ([]domain.PullRequest, error) {
	return nil, nil
}

func (s *alertLifecycleStore) ListPRReviews(context.Context, string) ([]domain.PullRequestReview, error) {
	return nil, nil
}

func (s *alertLifecycleStore) ListPRComments(context.Context, string) ([]domain.PullRequestComment, error) {
	return nil, nil
}

func (s *alertLifecycleStore) GetPRLastNudgeSignature(context.Context, string) (string, error) {
	return "", nil
}

func (s *alertLifecycleStore) UpdatePRLastNudgeSignature(context.Context, string, string) error {
	return nil
}

type switchAlertSink struct {
	mu      sync.Mutex
	intents []ports.NotificationIntent
}

func (s *switchAlertSink) Notify(_ context.Context, intent ports.NotificationIntent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.intents = append(s.intents, intent)
	return nil
}

func (s *switchAlertSink) Resolve(context.Context, ports.NotificationResolution) error {
	return nil
}

func (s *switchAlertSink) exitedFor(id domain.SessionID) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, in := range s.intents {
		if in.Type == domain.NotificationAgentExited && in.SessionID == id {
			n++
		}
	}
	return n
}

func TestAgentSwitchSourceStopDoesNotAlertAgentExited(t *testing.T) {
	sources := []struct {
		name string
		fire func(ctx context.Context, lcm *lifecycle.Manager, id domain.SessionID, launchID string) error
	}{
		{name: "workload-dead", fire: func(ctx context.Context, lcm *lifecycle.Manager, id domain.SessionID, launchID string) error {
			return lcm.ApplyRuntimeObservation(ctx, id, ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: launchID})
		}},
		{name: "session-end", fire: func(ctx context.Context, lcm *lifecycle.Manager, id domain.SessionID, launchID string) error {
			return lcm.ApplyActivitySignal(ctx, id, ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end", LaunchID: launchID})
		}},
		{name: "process-exited", fire: func(ctx context.Context, lcm *lifecycle.Manager, id domain.SessionID, launchID string) error {
			return lcm.ApplyActivitySignal(ctx, id, ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited", LaunchID: launchID})
		}},
	}
	for _, src := range sources {
		t.Run(src.name, func(t *testing.T) {
			runtime := &fakeRestartRuntime{fakeRuntime: &fakeRuntime{}}
			manager, _, _ := newSwitchTestManager(t, runtime)
			now := time.Now().UTC()
			lcStore := &alertLifecycleStore{sessions: map[domain.SessionID]domain.SessionRecord{}}
			for _, id := range []domain.SessionID{"proj-1", "proj-2"} {
				lcStore.sessions[id] = domain.SessionRecord{
					ID: id, ProjectID: "proj", Harness: domain.HarnessClaudeCode,
					Activity:      domain.Activity{State: domain.ActivityIdle, LastActivityAt: now.Add(-time.Minute)},
					FirstSignalAt: now.Add(-time.Hour),
					Metadata:      domain.SessionMetadata{RuntimeHandleID: string(id), RuntimeLaunchID: "source-generation"},
				}
			}
			sink := &switchAlertSink{}
			lcm := lifecycle.New(lcStore, nil, lifecycle.WithNotificationSink(sink))
			lcm.SetSessionOperationGate(manager)

			stopped := false
			runtime.onDestroy = func(call int, _ ports.RuntimeHandle) {
				if call != 0 {
					return
				}
				stopped = true
				if !manager.SessionMutationInProgress("proj-1") {
					t.Error("source stopped without the switch holding the session")
				}
				if err := src.fire(context.Background(), lcm, "proj-1", "source-generation"); err != nil {
					t.Error(err)
				}
				if got := lcStore.sessions["proj-1"].Activity.State; got != domain.ActivityExited {
					t.Errorf("state = %s, want exited recorded during the switch", got)
				}
			}

			sw, err := manager.SwitchAgent(context.Background(), "proj-1", SwitchAgentConfig{TargetHarness: domain.HarnessCodex, IdempotencyKey: "alerts-" + src.name})
			if err != nil {
				t.Fatal(err)
			}
			if sw.State != domain.AgentSwitchCompleted || !stopped {
				t.Fatalf("switch state=%q stopped=%v, want a completed switch that stopped the source", sw.State, stopped)
			}
			if got := sink.exitedFor("proj-1"); got != 0 {
				t.Fatalf("agent_exited for the switched session = %d, want none", got)
			}
			if err := src.fire(context.Background(), lcm, "proj-2", "source-generation"); err != nil {
				t.Fatal(err)
			}
			if got := sink.exitedFor("proj-2"); got != 1 {
				t.Fatalf("control agent_exited for an unheld session = %d, want 1", got)
			}
		})
	}
}
