package integration

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/lifecycle"
	"github.com/OmarAly92/operator/backend/internal/notify"
	"github.com/OmarAly92/operator/backend/internal/ports"
	sessionmanager "github.com/OmarAly92/operator/backend/internal/session_manager"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/sqlitetest"
)

type alertSink struct {
	mu          sync.Mutex
	intents     []ports.NotificationIntent
	resolutions []ports.NotificationResolution
}

func (s *alertSink) Notify(_ context.Context, intent ports.NotificationIntent) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.intents = append(s.intents, intent)
	return nil
}

func (s *alertSink) Resolve(_ context.Context, res ports.NotificationResolution) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.resolutions = append(s.resolutions, res)
	return nil
}

func (s *alertSink) intentsOf(typ domain.NotificationType) []ports.NotificationIntent {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []ports.NotificationIntent
	for _, in := range s.intents {
		if in.Type == typ {
			out = append(out, in)
		}
	}
	return out
}

type hookRuntime struct {
	*stubRuntime
	onDestroy func(ports.RuntimeHandle)
}

func (r *hookRuntime) Destroy(ctx context.Context, h ports.RuntimeHandle) error {
	if r.onDestroy != nil {
		r.onDestroy(h)
	}
	return r.stubRuntime.Destroy(ctx, h)
}

type alertStack struct {
	store *sqlite.Store
	mgr   *sessionmanager.Manager
	lcm   *lifecycle.Manager
	rt    *hookRuntime
	sink  *alertSink
}

type lifecycleSink interface {
	Notify(context.Context, ports.NotificationIntent) error
	Resolve(context.Context, ports.NotificationResolution) error
}

func newAlertStack(t *testing.T) *alertStack {
	t.Helper()
	sink := &alertSink{}
	s := buildAlertStack(t, func(*sqlite.Store) lifecycleSink { return sink })
	s.sink = sink
	return s
}

func newPersistedAlertStack(t *testing.T) *alertStack {
	t.Helper()
	return buildAlertStack(t, func(store *sqlite.Store) lifecycleSink {
		return notify.New(notify.Deps{Store: store, Publisher: notify.NewHub()})
	})
}

func buildAlertStack(t *testing.T, sinkFor func(*sqlite.Store) lifecycleSink) *alertStack {
	t.Helper()
	ctx := context.Background()
	store, err := sqlitetest.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	if err := store.UpsertProject(ctx, domain.ProjectRecord{
		ID:           "mer",
		Path:         "/repo/mer",
		RegisteredAt: time.Now(),
		Config:       domain.ProjectConfig{Harness: domain.HarnessClaudeCode},
	}); err != nil {
		t.Fatal(err)
	}
	msg := &captureMessenger{}
	lcm := lifecycle.New(store, msg, lifecycle.WithNotificationSink(sinkFor(store)))
	rt := &hookRuntime{stubRuntime: &stubRuntime{}}
	mgr := sessionmanager.New(sessionmanager.Deps{Runtime: rt, Agents: stubAgents{}, Workspace: &stubWorkspace{}, Store: store, Messenger: msg, Lifecycle: lcm, LookPath: func(string) (string, error) { return "/usr/bin/true", nil }})
	lcm.SetCompletionTerminator(mgr)
	lcm.SetSessionOperationGate(mgr)
	return &alertStack{store: store, mgr: mgr, lcm: lcm, rt: rt}
}

func (s *alertStack) spawnActive(t *testing.T) domain.SessionID {
	t.Helper()
	ctx := context.Background()
	sess, _, _, err := s.mgr.Spawn(ctx, ports.SpawnConfig{ProjectID: "mer", Branch: "b", Prompt: "do it"})
	if err != nil {
		t.Fatal(err)
	}
	rec := s.session(t, sess.ID)
	if err := s.lcm.ApplyActivitySignal(ctx, sess.ID, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LaunchID: rec.Metadata.RuntimeLaunchID}); err != nil {
		t.Fatal(err)
	}
	if got := s.session(t, sess.ID).Activity.State; got != domain.ActivityActive {
		t.Fatalf("seeded state = %s, want active", got)
	}
	return sess.ID
}

func (s *alertStack) session(t *testing.T, id domain.SessionID) domain.SessionRecord {
	t.Helper()
	rec, ok, err := s.store.GetSession(context.Background(), id)
	if err != nil || !ok {
		t.Fatalf("get %s: ok=%v err=%v", id, ok, err)
	}
	return rec
}

type exitSource struct {
	name string
	fire func(t *testing.T, s *alertStack, id domain.SessionID, launchID string)
}

var exitSources = []exitSource{
	{name: "workload-dead", fire: func(t *testing.T, s *alertStack, id domain.SessionID, launchID string) {
		t.Helper()
		if err := s.lcm.ApplyRuntimeObservation(context.Background(), id, ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: launchID}); err != nil {
			t.Fatal(err)
		}
	}},
	{name: "session-end", fire: func(t *testing.T, s *alertStack, id domain.SessionID, launchID string) {
		t.Helper()
		if err := s.lcm.ApplyActivitySignal(context.Background(), id, ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "session-end", LaunchID: launchID}); err != nil {
			t.Fatal(err)
		}
	}},
	{name: "process-exited", fire: func(t *testing.T, s *alertStack, id domain.SessionID, launchID string) {
		t.Helper()
		if err := s.lcm.ApplyActivitySignal(context.Background(), id, ports.ActivitySignal{Valid: true, State: domain.ActivityExited, Event: "process-exited", LaunchID: launchID}); err != nil {
			t.Fatal(err)
		}
	}},
}

func (s *alertStack) fireDuringDestroy(t *testing.T, id domain.SessionID, src exitSource) *bool {
	t.Helper()
	fired := false
	s.rt.onDestroy = func(ports.RuntimeHandle) {
		if fired {
			return
		}
		fired = true
		if !s.mgr.SessionMutationInProgress(id) {
			t.Errorf("%s: runtime stopped without the session mutation held", src.name)
		}
		src.fire(t, s, id, s.session(t, id).Metadata.RuntimeLaunchID)
		if got := s.session(t, id).Activity.State; got != domain.ActivityExited {
			t.Errorf("%s: state = %s, want exited recorded during the operation", src.name, got)
		}
	}
	return &fired
}

func TestAgentAlerts_UngatedExitSourcesAlert(t *testing.T) {
	for _, src := range exitSources {
		t.Run(src.name, func(t *testing.T) {
			s := newAlertStack(t)
			id := s.spawnActive(t)
			src.fire(t, s, id, s.session(t, id).Metadata.RuntimeLaunchID)
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != 1 || got[0].SessionID != id {
				t.Fatalf("agent_exited intents = %+v, want 1", got)
			}
		})
	}
}

func TestAgentAlerts_KillIsSilent(t *testing.T) {
	for _, src := range exitSources {
		t.Run(src.name, func(t *testing.T) {
			ctx := context.Background()
			s := newAlertStack(t)
			id := s.spawnActive(t)
			launchID := s.session(t, id).Metadata.RuntimeLaunchID
			fired := s.fireDuringDestroy(t, id, src)
			if _, err := s.mgr.Kill(ctx, id); err != nil {
				t.Fatal(err)
			}
			if !*fired {
				t.Fatal("Kill never stopped the runtime")
			}
			if !s.session(t, id).IsTerminated {
				t.Fatal("Kill did not terminate the session")
			}
			src.fire(t, s, id, launchID)
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != 0 {
				t.Fatalf("agent_exited intents = %+v, want none for Kill", got)
			}
		})
	}
}

func TestAgentAlerts_RollbackIsSilent(t *testing.T) {
	for _, src := range exitSources {
		t.Run(src.name, func(t *testing.T) {
			s := newAlertStack(t)
			id := s.spawnActive(t)
			fired := s.fireDuringDestroy(t, id, src)
			deleted, killed, err := s.mgr.RollbackSpawn(context.Background(), id)
			if err != nil {
				t.Fatal(err)
			}
			if deleted || !killed || !*fired {
				t.Fatalf("rollback deleted=%v killed=%v stopped=%v, want a kill that stops the runtime", deleted, killed, *fired)
			}
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != 0 {
				t.Fatalf("agent_exited intents = %+v, want none for rollback", got)
			}
		})
	}
}

func TestAgentAlerts_RelaunchIsSilent(t *testing.T) {
	for _, src := range exitSources {
		t.Run(src.name, func(t *testing.T) {
			ctx := context.Background()
			s := newAlertStack(t)
			id := s.spawnActive(t)
			oldLaunch := s.session(t, id).Metadata.RuntimeLaunchID
			fired := s.fireDuringDestroy(t, id, src)
			if _, err := s.mgr.RelaunchAgentFresh(ctx, id, sessionmanager.RelaunchAgentConfig{KeepPrompt: true}); err != nil {
				t.Fatal(err)
			}
			if !*fired {
				t.Fatal("relaunch never stopped the old runtime")
			}
			rec := s.session(t, id)
			if rec.IsTerminated || rec.Metadata.RuntimeLaunchID == oldLaunch {
				t.Fatalf("relaunch did not install a new generation: %+v", rec.Metadata)
			}
			src.fire(t, s, id, oldLaunch)
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != 0 {
				t.Fatalf("agent_exited intents = %+v, want none for relaunch", got)
			}
		})
	}
}

func TestAgentAlerts_CleanupIsSilent(t *testing.T) {
	for _, src := range exitSources {
		t.Run(src.name, func(t *testing.T) {
			ctx := context.Background()
			s := newAlertStack(t)
			id := s.spawnActive(t)
			launchID := s.session(t, id).Metadata.RuntimeLaunchID
			if _, err := s.mgr.Kill(ctx, id); err != nil {
				t.Fatal(err)
			}
			fired := false
			s.rt.onDestroy = func(ports.RuntimeHandle) {
				fired = true
				src.fire(t, s, id, launchID)
			}
			if _, err := s.mgr.Cleanup(ctx, "mer"); err != nil {
				t.Fatal(err)
			}
			if !fired {
				t.Fatal("cleanup never stopped the runtime")
			}
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != 0 {
				t.Fatalf("agent_exited intents = %+v, want none for cleanup", got)
			}
		})
	}
}

func TestAgentAlerts_SessionEndReasons(t *testing.T) {
	for _, tc := range []struct {
		reason string
		want   int
	}{
		{reason: "clear", want: 0},
		{reason: "resume", want: 0},
		{reason: "logout", want: 1},
		{reason: "prompt_input_exit", want: 1},
		{reason: "other", want: 1},
	} {
		t.Run(tc.reason, func(t *testing.T) {
			s := newAlertStack(t)
			id := s.spawnActive(t)
			state, ok := claudecode.DeriveActivityState("session-end", []byte(`{"reason":"`+tc.reason+`"}`))
			sig := ports.ActivitySignal{Valid: ok, State: state, Event: "session-end", AgentSessionID: "native-" + tc.reason, LaunchID: s.session(t, id).Metadata.RuntimeLaunchID}
			if err := s.lcm.ApplyActivitySignal(context.Background(), id, sig); err != nil {
				t.Fatal(err)
			}
			if got := s.sink.intentsOf(domain.NotificationAgentExited); len(got) != tc.want {
				t.Fatalf("agent_exited intents for reason %q = %+v, want %d", tc.reason, got, tc.want)
			}
			if tc.want == 0 {
				if got := s.session(t, id).Activity.State; got != domain.ActivityActive {
					t.Fatalf("state = %s, want active kept for reason %q", got, tc.reason)
				}
			}
		})
	}
}

func (s *alertStack) agentExitedRows(t *testing.T, id domain.SessionID) []domain.NotificationRecord {
	t.Helper()
	rows, err := s.store.ListNotifications(context.Background(), domain.NotificationListAll, time.Time{}, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	var out []domain.NotificationRecord
	for _, row := range rows {
		if row.Type == domain.NotificationAgentExited && row.SessionID == id {
			out = append(out, row)
		}
	}
	return out
}

func TestAgentAlerts_RespawnResolvesAgentExitedSoTheNextCrashAlerts(t *testing.T) {
	for _, tc := range []struct {
		name    string
		respawn func(ctx context.Context, s *alertStack, id domain.SessionID) error
	}{
		{name: "relaunch", respawn: func(ctx context.Context, s *alertStack, id domain.SessionID) error {
			_, err := s.mgr.RelaunchAgentFresh(ctx, id, sessionmanager.RelaunchAgentConfig{KeepPrompt: true})
			return err
		}},
		{name: "resume", respawn: func(ctx context.Context, s *alertStack, id domain.SessionID) error {
			_, err := s.mgr.ResumeAgentWithMode(ctx, id)
			return err
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			s := newPersistedAlertStack(t)
			id := s.spawnActive(t)
			crash := func() {
				t.Helper()
				if err := s.lcm.ApplyRuntimeObservation(ctx, id, ports.RuntimeFacts{Runtime: ports.ProbeAlive, Workload: ports.ProbeDead, LaunchID: s.session(t, id).Metadata.RuntimeLaunchID}); err != nil {
					t.Fatal(err)
				}
			}
			crash()
			rows := s.agentExitedRows(t, id)
			if len(rows) != 1 || rows[0].Resolved() {
				t.Fatalf("after first crash agent_exited rows = %+v, want 1 open", rows)
			}
			if err := tc.respawn(ctx, s, id); err != nil {
				t.Fatal(err)
			}
			rows = s.agentExitedRows(t, id)
			if len(rows) != 1 || !rows[0].Resolved() {
				t.Fatalf("after %s agent_exited rows = %+v, want 1 resolved", tc.name, rows)
			}
			if err := s.lcm.ApplyActivitySignal(ctx, id, ports.ActivitySignal{Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LaunchID: s.session(t, id).Metadata.RuntimeLaunchID}); err != nil {
				t.Fatal(err)
			}
			crash()
			if rows := s.agentExitedRows(t, id); len(rows) != 2 {
				t.Fatalf("after second crash agent_exited rows = %+v, want 2", rows)
			}
		})
	}
}
