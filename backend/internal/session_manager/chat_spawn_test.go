package sessionmanager

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

// newChatManager mirrors newManager() with a chat launcher injected, so both
// branches can be exercised against the same fakes.
func newChatManager(chat ChatLauncher) (*Manager, *fakeStore, *fakeRuntime) {
	st := newFakeStore()
	st.projects["mer"] = domain.ProjectRecord{ID: "mer", Config: testRoleAgents()}
	rt := &fakeRuntime{}
	lookPath := func(string) (string, error) { return "/bin/true", nil }
	m := New(Deps{
		Runtime:   rt,
		Agents:    fakeAgents{},
		Workspace: &fakeWorkspace{},
		Store:     st,
		Messenger: &fakeMessenger{},
		Chat:      chat,
		Lifecycle: &fakeLCM{store: st},
		DataDir:   "/opr-test-data",
		LookPath:  lookPath,
	})
	return m, st, rt
}

const chatTestProject = domain.ProjectID("mer")

// The load-bearing property of the split: exactly one controller starts. A chat
// spawn must not touch the terminal runtime, and a TUI spawn must not touch the
// chat launcher. Anything else means two writers on one conversation.

type recordingLauncher struct {
	preflightErr error
	startErr     error
	turnErr      error
	live         bool
	afterReady   func()

	preflighted []domain.AgentHarness
	started     []ChatStart
	turns       []string
	// relayed is what arrived through Manager.Send rather than as an initial
	// prompt, kept separate so a test can tell the two apart.
	relayed []string
	stopped []domain.SessionID
}

func (l *recordingLauncher) PreflightChat(_ context.Context, harness domain.AgentHarness) error {
	l.preflighted = append(l.preflighted, harness)
	return l.preflightErr
}

func (l *recordingLauncher) StartChat(_ context.Context, cfg ChatStart) (ChatStarted, error) {
	l.started = append(l.started, cfg)
	if l.startErr != nil {
		return ChatStarted{}, l.startErr
	}
	started := ChatStarted{
		ProviderConversationID: "thread-1",
		ControllerGeneration:   "gen-1",
	}
	if cfg.ControllerReady != nil {
		if err := cfg.ControllerReady(started); err != nil {
			return ChatStarted{}, err
		}
	}
	if l.afterReady != nil {
		l.afterReady()
	}
	return started, nil
}

func (l *recordingLauncher) StartChatTurn(_ context.Context, _ domain.SessionID, text string) (string, error) {
	l.turns = append(l.turns, text)
	return "turn-1", l.turnErr
}

func (l *recordingLauncher) RelayChatTurn(_ context.Context, _ domain.SessionID, text string) (string, error) {
	l.relayed = append(l.relayed, text)
	return "turn-relay", l.turnErr
}

func (l *recordingLauncher) RelayChatTurnWithID(_ context.Context, _ domain.SessionID, text, _ string) (string, error) {
	l.relayed = append(l.relayed, text)
	return "turn-relay", l.turnErr
}

func (l *recordingLauncher) StopChat(_ context.Context, id domain.SessionID) error { //nolint:unparam

	l.stopped = append(l.stopped, id)
	return nil
}

func (l *recordingLauncher) HasLiveChatController(domain.SessionID) bool {
	return l.live
}

func seedChatResumeSession(store *fakeStore, state domain.ActivityState) {
	store.sessions["mer-1"] = domain.SessionRecord{
		ID:        "mer-1",
		ProjectID: chatTestProject,
		Kind:      domain.KindWorker,
		Harness:   domain.HarnessCodex,
		Mode:      domain.SessionModeChat,
		Activity:  domain.Activity{State: state},
		Metadata: domain.SessionMetadata{
			WorkspacePath:          "/ws/mer-1",
			Branch:                 "opr/mer-1",
			ProviderConversationID: "thread-existing",
		},
	}
}

func TestResumeExitedChatSessionDoesNotRequireTerminalRuntimeHandle(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, runtime := newChatManager(launcher)
	seedChatResumeSession(store, domain.ActivityExited)

	result, err := mgr.ResumeAgentWithMode(context.Background(), "mer-1")
	if err != nil {
		t.Fatalf("ResumeAgentWithMode: %v", err)
	}
	if len(launcher.started) != 1 {
		t.Fatalf("started %d chat controllers, want 1", len(launcher.started))
	}
	if got := launcher.started[0].ProviderConversationID; got != "thread-existing" {
		t.Fatalf("provider conversation id = %q, want thread-existing", got)
	}
	if runtime.created != 0 || runtime.destroyed != 0 {
		t.Fatalf("chat resume touched terminal runtime: created=%d destroyed=%d", runtime.created, runtime.destroyed)
	}
	if result.Session.Activity.State != domain.ActivityIdle {
		t.Fatalf("resumed activity = %q, want idle", result.Session.Activity.State)
	}
}

func TestResumeChatKeepsExitReportedBeforeStartReturns(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, _ := newChatManager(launcher)
	seedChatResumeSession(store, domain.ActivityExited)
	launcher.afterReady = func() {
		rec := store.sessions["mer-1"]
		rec.Activity = domain.Activity{State: domain.ActivityExited}
		store.sessions["mer-1"] = rec
	}

	result, err := mgr.ResumeAgentWithMode(context.Background(), "mer-1")
	if err != nil {
		t.Fatalf("ResumeAgentWithMode: %v", err)
	}
	if result.Session.Activity.State != domain.ActivityExited {
		t.Fatalf("activity after immediate controller exit = %q, want exited", result.Session.Activity.State)
	}
}

func TestResumeStaleChatSessionWhenNoControllerIsLive(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, _ := newChatManager(launcher)
	seedChatResumeSession(store, domain.ActivityIdle)

	if _, err := mgr.ResumeAgentWithMode(context.Background(), "mer-1"); err != nil {
		t.Fatalf("ResumeAgentWithMode: %v", err)
	}
	if len(launcher.started) != 1 {
		t.Fatalf("started %d chat controllers, want 1", len(launcher.started))
	}
}

func TestResumeChatSessionRejectsLiveController(t *testing.T) {
	for _, state := range []domain.ActivityState{domain.ActivityIdle, domain.ActivityExited} {
		t.Run(string(state), func(t *testing.T) {
			launcher := &recordingLauncher{live: true}
			mgr, store, _ := newChatManager(launcher)
			seedChatResumeSession(store, state)

			if _, err := mgr.ResumeAgentWithMode(context.Background(), "mer-1"); !errors.Is(err, ErrAgentNotExited) {
				t.Fatalf("ResumeAgentWithMode error = %v, want ErrAgentNotExited", err)
			}
			if len(launcher.started) != 0 {
				t.Fatalf("duplicate resume started %d controllers", len(launcher.started))
			}
		})
	}
}

func TestResumeBranchlessScratchChatSession(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, _ := newChatManager(launcher)
	store.projects["scratch"] = domain.ProjectRecord{
		ID: "scratch", Kind: domain.ProjectKindScratch, Config: testRoleAgents(),
	}
	store.sessions["scratch-1"] = domain.SessionRecord{
		ID: "scratch-1", ProjectID: "scratch", Kind: domain.KindWorker,
		Harness: domain.HarnessCodex, Mode: domain.SessionModeChat,
		Activity: domain.Activity{State: domain.ActivityExited},
		Metadata: domain.SessionMetadata{
			WorkspacePath:          "/ws/scratch-1",
			ProviderConversationID: "thread-existing",
		},
	}

	if _, err := mgr.ResumeAgentWithMode(context.Background(), "scratch-1"); err != nil {
		t.Fatalf("ResumeAgentWithMode: %v", err)
	}
	if len(launcher.started) != 1 {
		t.Fatalf("started %d chat controllers, want 1", len(launcher.started))
	}
}

func TestResumeChatSessionRequiresProviderConversation(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, _ := newChatManager(launcher)
	seedChatResumeSession(store, domain.ActivityExited)
	rec := store.sessions["mer-1"]
	rec.Metadata.ProviderConversationID = ""
	store.sessions["mer-1"] = rec

	if _, err := mgr.ResumeAgentWithMode(context.Background(), "mer-1"); !errors.Is(err, ErrIncompleteHandle) {
		t.Fatalf("ResumeAgentWithMode error = %v, want ErrIncompleteHandle", err)
	}
	if len(launcher.started) != 0 {
		t.Fatalf("missing provider handle started %d controllers", len(launcher.started))
	}
}

func TestRestoreChatSessionRequiresProviderConversation(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, store, _ := newChatManager(launcher)
	seedChatResumeSession(store, domain.ActivityExited)
	rec := store.sessions["mer-1"]
	rec.IsTerminated = true
	rec.Metadata.ProviderConversationID = ""
	store.sessions["mer-1"] = rec

	if _, err := mgr.RestoreWithMode(context.Background(), "mer-1"); !errors.Is(err, ErrIncompleteHandle) {
		t.Fatalf("RestoreWithMode error = %v, want ErrIncompleteHandle", err)
	}
	if len(launcher.started) != 0 {
		t.Fatalf("missing provider handle started %d controllers", len(launcher.started))
	}
}

// A TUI spawn must never reach the chat launcher, even when one is wired.
func TestTUISpawnNeverTouchesTheChatLauncher(t *testing.T) {
	launcher := &recordingLauncher{}
	mgr, _, runtime := newChatManager(launcher)

	rec, _, _, err := mgr.Spawn(context.Background(), ports.SpawnConfig{
		ProjectID: chatTestProject,
		Kind:      domain.KindWorker,
		Harness:   domain.HarnessClaudeCode,
		Prompt:    "hello",
		// No requested mode: resolution must land on TUI.
	})
	if err != nil {
		t.Fatalf("Spawn: %v", err)
	}
	if rec.Mode != domain.SessionModeTUI {
		t.Fatalf("mode = %q, want tui when none was requested", rec.Mode)
	}
	if len(launcher.preflighted) != 0 || len(launcher.started) != 0 {
		t.Fatalf("a TUI spawn reached the chat launcher: preflight=%v started=%d",
			launcher.preflighted, len(launcher.started))
	}
	if runtime.created == 0 {
		t.Error("a TUI spawn created no runtime")
	}
}
