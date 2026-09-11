package lifecycle

import (
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func orchestrator(id domain.SessionID, project domain.ProjectID) domain.SessionRecord {
	return domain.SessionRecord{
		ID: id, ProjectID: project, Kind: domain.KindOrchestrator,
		Activity:      domain.Activity{State: domain.ActivityIdle, LastActivityAt: time.Now()},
		FirstSignalAt: time.Now(),
	}
}

func TestApplyActivitySignal_WorkerIdleNudgesTheLiveOrchestrator(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 || msg.ids[0] != "mer-2" {
		t.Fatalf("messenger calls = %+v / %+v, want exactly one nudge to mer-2", msg.msgs, msg.ids)
	}
	if !strings.Contains(msg.msgs[0], "1 inbox item") || !strings.Contains(msg.msgs[0], "opr inbox") {
		t.Fatalf("nudge text = %q", msg.msgs[0])
	}
}

func TestApplyActivitySignal_NoOrchestratorLeavesRowPendingAndSendsNothing(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none", msg.msgs)
	}
	pending, _ := st.ListPendingInboxEvents(ctx, "mer")
	if len(pending) != 1 {
		t.Fatalf("pending = %v, want the row to stay pending", pending)
	}
}

func TestApplyActivitySignal_OrchestratorNeedsInputSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityWaitingInput
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: orchestrator needs input", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorZeroFirstSignalSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.FirstSignalAt = time.Time{}
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: a restored orchestrator's hooks are not yet proven up", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorActiveOnNonSteeringHarnessSuppressesTheNudge(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	orch.Harness = domain.HarnessClaudeCode
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 0 {
		t.Fatalf("messenger calls = %v, want none: claude-code cannot be steered mid-turn", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorActiveOnSteeringHarnessDelivers(t *testing.T) {
	m, st, msg := newManager()
	m.steerActive = func(h domain.AgentHarness) bool { return h == domain.HarnessCodex }
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	orch.Harness = domain.HarnessCodex
	st.sessions["mer-2"] = orch
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 {
		t.Fatalf("messenger calls = %v, want exactly one: codex steers active turns", msg.msgs)
	}
}

func TestApplyActivitySignal_OrchestratorEnteringIdleDrainsExistingBacklog(t *testing.T) {
	m, st, msg := newManager()
	orch := orchestrator("mer-2", "mer")
	orch.Activity.State = domain.ActivityActive
	st.sessions["mer-2"] = orch
	st.inboxEvents["evt-1"] = domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: "mer", WorkerID: "mer-1", Kind: domain.InboxEventWorkerIdle, State: domain.InboxStatePending,
	}

	if err := m.ApplyActivitySignal(ctx, "mer-2", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 1 || msg.ids[0] != "mer-2" {
		t.Fatalf("messenger calls = %+v / %+v, want the orchestrator nudged about its own pending backlog", msg.msgs, msg.ids)
	}
}

func TestDispatchInboxNudge_DuplicateCallsProduceOneDigestAndOneAckedRow(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}
	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}

	if len(msg.msgs) != 3 {
		t.Fatalf("messenger calls = %d, want 3 (the original plus two duplicate dispatches -- duplicates are safe, not free)", len(msg.msgs))
	}

	digests, err := m.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(digests) != 1 {
		t.Fatalf("digests=%v err=%v, want exactly one despite 3 nudges", digests, err)
	}

	acked, err := m.AckInboxEvents(ctx, "mer", []string{digests[0].ID})
	if err != nil || acked != 1 {
		t.Fatalf("acked=%d err=%v, want 1", acked, err)
	}

	if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
		t.Fatal(err)
	}
	if len(msg.msgs) != 3 {
		t.Fatalf("messenger calls after ack = %d, want still 3: nothing pending, nothing to send", len(msg.msgs))
	}
}

func TestDispatchInboxNudge_ConcurrentCallsAreSerializedPerProject(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.inboxEvents["evt-1"] = domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: "mer", WorkerID: "mer-1", Kind: domain.InboxEventWorkerIdle, State: domain.InboxStatePending,
	}

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := m.dispatchInboxNudge(ctx, "mer"); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()

	if len(msg.msgs) != 8 {
		t.Fatalf("messenger calls = %d, want 8: every dispatch ran, one at a time", len(msg.msgs))
	}
	pending, err := m.ListPendingInboxEvents(ctx, "mer")
	if err != nil || len(pending) != 1 {
		t.Fatalf("pending=%v err=%v, want the single row untouched", pending, err)
	}
}

func TestApplyActivitySignal_TheNudgeIsNotStoredAsTheOrchestratorsOwnLatestUserPrompt(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.sessions["mer-1"] = working("mer-1")

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{Valid: true, State: domain.ActivityIdle, Event: "stop"}); err != nil {
		t.Fatal(err)
	}
	if len(msg.msgs) != 1 {
		t.Fatalf("messenger calls = %v, want the nudge that the harness will echo", msg.msgs)
	}

	nudgeText := msg.msgs[0]
	if err := m.ApplyActivitySignal(ctx, "mer-2", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: nudgeText,
	}); err != nil {
		t.Fatal(err)
	}

	got := st.sessions["mer-2"]
	if got.Metadata.LatestUserPrompt == nudgeText {
		t.Fatalf("orchestrator's own nudge was echoed back as its latestUserPrompt: %q", got.Metadata.LatestUserPrompt)
	}
}

func TestCoordinationEcho_ASecondWriteDoesNotClobberTheFirstPendingEcho(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-1"] = working("mer-1")

	for _, batch := range []string{"batch-1", "batch-2"} {
		outcome, err := m.ApplyReviewBatch(ctx, "mer-1", batch, []ReviewResult{{
			RunID: "run-" + batch, BatchID: batch, WorkerID: "mer-1",
			PRURL: "https://x/pr/1", TargetSHA: batch, Verdict: domain.VerdictChangesRequested,
		}})
		if err != nil || outcome != ReviewDeliverySent {
			t.Fatalf("%s: outcome=%v err=%v", batch, outcome, err)
		}
	}
	if len(msg.msgs) != 2 {
		t.Fatalf("messenger calls = %v, want two coordination writes in flight for one session", msg.msgs)
	}

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: msg.msgs[0],
	}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Metadata.LatestUserPrompt; got != "" {
		t.Fatalf("the FIRST coordination write leaked back as latestUserPrompt after a second write: %q", got)
	}

	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: msg.msgs[1],
	}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-1"].Metadata.LatestUserPrompt; got != "" {
		t.Fatalf("the second coordination write leaked back as latestUserPrompt: %q", got)
	}
}

func TestCoordinationEcho_SentWithMessengerErrorStillRecordsTheEcho(t *testing.T) {
	m, st, msg := newManager()
	st.sessions["mer-2"] = orchestrator("mer-2", "mer")
	st.inboxEvents["evt-1"] = domain.OrchestratorInboxEvent{
		ID: "evt-1", ProjectID: "mer", WorkerID: "mer-1", Kind: domain.InboxEventWorkerIdle, State: domain.InboxStatePending,
	}
	msg.err = errors.New("temporary send failure")

	if err := m.dispatchInboxNudge(ctx, "mer"); err == nil {
		t.Fatal("want the messenger failure surfaced")
	}
	msg.err = nil

	// The guard reports Sent alongside the error: the bytes may already have
	// reached the pane, so the harness may still echo them back.
	nudgeText := "[Operator] 1 inbox item(s). Run `opr inbox`."
	if err := m.ApplyActivitySignal(ctx, "mer-2", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: nudgeText,
	}); err != nil {
		t.Fatal(err)
	}
	if got := st.sessions["mer-2"].Metadata.LatestUserPrompt; got != "" {
		t.Fatalf("a Sent-with-error write was echoed back as latestUserPrompt: %q", got)
	}
}

func TestSendOnceReviewNudgeIsNotStoredAsTheWorkersOwnLatestUserPrompt(t *testing.T) {
	m, st, msg := newManager()
	rec := working("mer-1")
	rec.AutoInjectReview = true
	st.sessions["mer-1"] = rec

	outcome, err := m.ApplyReviewBatch(ctx, "mer-1", "batch-1", []ReviewResult{{
		RunID: "run-1", BatchID: "batch-1", WorkerID: "mer-1", PRURL: "https://x/pr/1", Verdict: domain.VerdictChangesRequested,
	}})
	if err != nil || outcome != ReviewDeliverySent {
		t.Fatalf("outcome=%v err=%v", outcome, err)
	}
	if len(msg.msgs) != 1 {
		t.Fatalf("messenger calls = %v, want the review nudge that the harness will echo", msg.msgs)
	}

	echoed := msg.msgs[0]
	if !strings.HasPrefix(echoed, "[Operator reviewer] Operator's internal code reviewer submitted 1 review(s) requesting changes.") {
		t.Fatalf("review nudge first line changed: %q", echoed)
	}
	if err := m.ApplyActivitySignal(ctx, "mer-1", ports.ActivitySignal{
		Valid: true, State: domain.ActivityActive, Event: "user-prompt-submit", LatestUserPrompt: echoed,
	}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(st.sessions["mer-1"].Metadata.LatestUserPrompt, "Operator reviewer") {
		t.Fatalf("worker's own review nudge was echoed back as its latestUserPrompt: %q", st.sessions["mer-1"].Metadata.LatestUserPrompt)
	}
}
