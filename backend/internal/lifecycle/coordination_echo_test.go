package lifecycle

import (
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

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
