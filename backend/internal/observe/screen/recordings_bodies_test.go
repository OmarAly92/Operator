package screen

import (
	"context"
	"reflect"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
	"github.com/OmarAly92/operator/backend/internal/domain"
)

func screenDecisions(t *testing.T, rec signalRecording) []Decision {
	t.Helper()
	p, err := vtwasm.New(context.Background(), vtwasm.Module, rec.sizes[0].Cols, rec.sizes[0].Rows, vtwasm.Limits{Rows: 200_000, Bytes: 128 << 20})
	if err != nil {
		t.Fatalf("parser: %v", err)
	}
	defer p.Close()
	agent := signalAgent(rec.truth.Harness)
	base := time.Date(2026, 9, 27, 0, 0, 0, 0, time.UTC)
	at := func(ms int64) time.Time { return base.Add(time.Duration(ms) * time.Millisecond) }
	clock := vtwasm.NewActivityClock(p)
	var debouncer Debouncer
	var out []Decision
	inputs := append([]int64(nil), rec.truth.Inputs...)
	var pokedAt time.Time
	keep := func(decisions []Decision) {
		for _, d := range decisions {
			if d.Reading != domain.ScreenWorking {
				out = append(out, Decision{Reading: d.Reading, Text: d.Text})
			}
		}
	}
	replayRecording(t, rec, p, func(ms int64) {
		for len(inputs) > 0 && inputs[0] <= ms {
			pokedAt = at(inputs[0])
			inputs = inputs[1:]
		}
		state, changed, err := clock.Step(p, at(ms), pokedAt)
		if err != nil {
			t.Fatalf("clock: %v", err)
		}
		if changed {
			keep(debouncer.Observe(Classify(agent, activityEvent(p, state, at(ms))), at(ms)))
		}
		keep(debouncer.Due(at(ms)))
	})
	return out
}

func TestTheScreenReadsQuestionsAndTurnSummariesFromRealRecordings(t *testing.T) {
	question := func(text string) Decision { return Decision{Reading: domain.ScreenQuestion, Text: text} }
	settled := func(text string) Decision { return Decision{Reading: domain.ScreenSettled, Text: text} }
	want := map[string][]Decision{
		"claude-permission": {
			question("touch approved.txt · Create empty approved.txt file · Do you want to proceed?"),
			settled("I ran touch approved.txt and it finished without errors, so the file is now in this directory."),
		},
		"claude-question": {
			question("☐ Indentation · Do you prefer tabs or spaces?"),
			settled("Tabs"),
		},
		"claude-think": {
			settled("80946558459881\n18627168311323"),
		},
		"claude-two-permissions": {
			question("touch first-call.txt · Create first-call.txt · Do you want to proceed?"),
			question("touch second-call.txt · Create second-call.txt · Do you want to proceed?"),
			settled("I ran two separate Bash calls, one after the other: touch first-call.txt, then touch\nsecond-call.txt. Both finished without errors, and the two files are now in the working directory."),
		},
		"codex-approval": {
			settled(""),
			question("Environment: local · Reason: May I create approved.txt in the workspace as requested? · $ touch approved.txt"),
			settled("• Done. approved.txt was created."),
		},
		"codex-think": {
			settled(""),
			settled("• A B-tree keeps several sorted keys in each node. A node with k keys has up to k+1 children, whose key ranges fall\n" +
				"between those keys. All leaves stay at the same depth, so the tree remains balanced.\n" +
				"To insert a key, start at the root and follow the child whose range contains it. Continue until you reach a leaf, then\n" +
				"place the key in sorted order. If that leaf has room, the insertion is done.\n" +
				"When a node is full, it must be split. Suppose the B-tree has minimum degree t, so a node can hold at most 2t-1 keys.\n" +
				"A split moves the middle key into the parent. The t-1 smaller keys stay in one node, and the t-1 larger keys go into a"),
		},
		"shell-pause": {
			question("Overwrite build.log? (y/n)"),
			settled("building\nwrote build.log\nOverwrite build.log? (y/n) y\nanswered y\nall done"),
		},
	}
	recordings := map[string]signalRecording{}
	for _, rec := range loadSignals(t) {
		recordings[rec.name] = rec
	}
	for name, wantDecisions := range want {
		rec, ok := recordings[name]
		if !ok {
			t.Fatalf("no recording %s", name)
		}
		if got := screenDecisions(t, rec); !reflect.DeepEqual(got, wantDecisions) {
			t.Errorf("%s decisions:\n got %#v\nwant %#v", name, got, wantDecisions)
		}
	}
}
