package screen

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/agent/claudecode"
	"github.com/OmarAly92/operator/backend/internal/adapters/agent/codex"
	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type truthInterval struct {
	From     int64  `json:"from"`
	To       int64  `json:"to"`
	State    string `json:"state"`
	Question string `json:"question"`
}

type signalTruth struct {
	Harness   string          `json:"harness"`
	Intervals []truthInterval `json:"intervals"`
	Inputs    []int64         `json:"inputs"`
}

type signalSize struct {
	Offset int    `json:"offset"`
	Cols   uint32 `json:"cols"`
	Rows   uint32 `json:"rows"`
}

type signalRecording struct {
	name      string
	recording []byte
	sizes     []signalSize
	timing    [][2]int64
	truth     signalTruth
}

type simMode string

const (
	modeHookless   simMode = "hookless"
	modeHooks      simMode = "hooks"
	modeMissedStop simMode = "missed-stop"
)

const (
	simTickMs          = 250
	simTailMs          = 90_000
	hookDelayMs        = 300
	flickerGraceMs     = 5_000
	quietGraceMs       = 65_000
	missedBudgetMs     = 4_000
	correctionBudgetMs = 40_000
)

type simTransition struct {
	at     int64
	to     domain.ActivityState
	alert  bool
	screen bool
}

type simHook struct {
	at    int64
	state domain.ActivityState
}

type simulator struct {
	state           domain.ActivityState
	lastHookAt      time.Time
	screenChangedAt time.Time
	alerted         string
	alertedAt       time.Time
	out             []simTransition
}

func (s *simulator) set(ms int64, at time.Time, to domain.ActivityState, screen bool, identity string) {
	if to == s.state {
		return
	}
	alert := false
	if !s.state.NeedsInput() && to.NeedsInput() {
		alert = identity == "" || identity != s.alerted || at.Sub(s.alertedAt) >= 2*time.Minute
		if identity != "" {
			s.alerted, s.alertedAt = identity, at
		}
	}
	if to == domain.ActivityIdle {
		s.alerted = ""
	}
	s.out = append(s.out, simTransition{at: ms, to: to, alert: alert, screen: screen})
	s.state = to
	if screen {
		s.screenChangedAt = at
	}
}

func (s *simulator) merge(reading domain.ScreenReading, reassert bool) domain.ScreenMerge {
	return domain.ScreenMerge{Current: s.state, Reading: reading, LastHookAt: s.lastHookAt, ScreenChangedAt: s.screenChangedAt, Reassert: reassert}
}

func signalsDir() string {
	return filepath.Join("..", "..", "..", "..", "packages", "terminal", "bench", "agent-session", "signals")
}

func readJSON(t *testing.T, path string, into any) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if err := json.Unmarshal(raw, into); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
}

func loadSignals(t *testing.T) []signalRecording {
	t.Helper()
	entries, err := os.ReadDir(signalsDir())
	if err != nil {
		t.Fatalf("signals: %v", err)
	}
	var out []signalRecording
	for _, entry := range entries {
		if !entry.IsDir() || entry.Name() == "scenarios" {
			continue
		}
		dir := filepath.Join(signalsDir(), entry.Name())
		rec := signalRecording{name: entry.Name()}
		raw, err := os.ReadFile(filepath.Join(dir, "recording"))
		if err != nil {
			t.Fatalf("read %s: %v", entry.Name(), err)
		}
		rec.recording = raw
		readJSON(t, filepath.Join(dir, "size.json"), &rec.sizes)
		readJSON(t, filepath.Join(dir, "timing.json"), &rec.timing)
		readJSON(t, filepath.Join(dir, "truth.json"), &rec.truth)
		out = append(out, rec)
	}
	if len(out) == 0 {
		t.Fatal("no signal recordings (Task 2 records them)")
	}
	return out
}

func signalAgent(harness string) any {
	switch harness {
	case "claude-code":
		return claudecode.New()
	case "codex":
		return codex.New()
	default:
		return nil
	}
}

func simHooks(truth signalTruth, mode simMode) []simHook {
	if mode == modeHookless || truth.Harness == "" {
		return nil
	}
	var out []simHook
	for _, interval := range truth.Intervals {
		switch interval.State {
		case "working":
			out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityActive})
		case "asking":
			out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityBlocked})
		case "settled":
			if mode != modeMissedStop {
				out = append(out, simHook{interval.From + hookDelayMs, domain.ActivityIdle})
			}
		}
	}
	return out
}

func simulate(t *testing.T, rec signalRecording, mode simMode) []simTransition {
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
	var confirmed *Decision
	var reassertAt int64
	sim := &simulator{state: domain.ActivityIdle}
	hooks := simHooks(rec.truth, mode)
	inputs := append([]int64(nil), rec.truth.Inputs...)
	var pokedAt time.Time
	decide := func(ms int64, decisions []Decision) {
		for _, d := range decisions {
			decision := d
			confirmed = &decision
			reassertAt = ms + reassertEvery.Milliseconds()
			if d.Reading == domain.ScreenQuestion && d.Identity != "" && sim.state.NeedsInput() && sim.alerted != d.Identity {
				sim.alerted, sim.alertedAt = d.Identity, at(ms)
			}
			if merged, ok := domain.MergeScreenReading(sim.merge(d.Reading, false), at(ms)); ok {
				sim.set(ms, at(ms), merged, true, d.Identity)
			}
		}
	}
	step := func(ms int64) {
		for len(inputs) > 0 && inputs[0] <= ms {
			pokedAt = at(inputs[0])
			inputs = inputs[1:]
		}
		for len(hooks) > 0 && hooks[0].at <= ms {
			sim.lastHookAt = at(hooks[0].at)
			sim.set(hooks[0].at, at(hooks[0].at), hooks[0].state, false, "")
			hooks = hooks[1:]
		}
		state, changed, err := clock.Step(p, at(ms), pokedAt)
		if err != nil {
			t.Fatalf("clock: %v", err)
		}
		if changed {
			decide(ms, debouncer.Observe(Classify(agent, activityEvent(p, state, at(ms))), at(ms)))
		}
		decide(ms, debouncer.Due(at(ms)))
		if confirmed != nil && ms >= reassertAt {
			reassertAt = ms + reassertEvery.Milliseconds()
			if !debouncer.Holds() {
				return
			}
			if merged, ok := domain.MergeScreenReading(sim.merge(confirmed.Reading, true), at(ms)); ok {
				sim.set(ms, at(ms), merged, true, confirmed.Identity)
			}
		}
	}
	replayRecording(t, rec, p, step)
	return sim.out
}

func activityEvent(p *vtwasm.Parser, state vtwasm.AgentActivity, at time.Time) ports.TerminalProgramEvent {
	event := ports.TerminalProgramEvent{Kind: ports.TerminalProgramActivity, Activity: ports.TerminalActivity(state.String()), At: at}
	if state != vtwasm.ActivityActive {
		event.Tail, _ = p.RenderTail(40)
		event.CursorLine, _ = p.CursorLine()
		event.Summary, _ = p.TailOutput(200, 40)
	}
	return event
}

func replayRecording(t *testing.T, rec signalRecording, p *vtwasm.Parser, step func(ms int64)) {
	t.Helper()
	at := func(ms int64) time.Time {
		return time.Date(2026, 9, 27, 0, 0, 0, 0, time.UTC).Add(time.Duration(ms) * time.Millisecond)
	}
	next := 1
	var ticked int64
	for i, entry := range rec.timing {
		offset, ms := int(entry[0]), entry[1]
		for ; ticked+simTickMs < ms; ticked += simTickMs {
			step(ticked + simTickMs)
		}
		end := len(rec.recording)
		if i+1 < len(rec.timing) {
			end = int(rec.timing[i+1][0])
		}
		for offset < end {
			stop := end
			if next < len(rec.sizes) && rec.sizes[next].Offset >= offset && rec.sizes[next].Offset < stop {
				stop = rec.sizes[next].Offset
			}
			if stop > offset {
				if err := p.FeedAt(rec.recording[offset:stop], at(ms).UnixMilli()); err != nil {
					t.Fatalf("feed: %v", err)
				}
				offset = stop
			}
			if next < len(rec.sizes) && rec.sizes[next].Offset == offset {
				if err := p.Resize(rec.sizes[next].Cols, rec.sizes[next].Rows); err != nil {
					t.Fatalf("resize: %v", err)
				}
				next++
			}
		}
		step(ms)
	}
	last := rec.timing[len(rec.timing)-1][1]
	for ms := ticked + simTickMs; ms <= last+simTailMs; ms += simTickMs {
		step(ms)
	}
}

func expectedState(state string) domain.ActivityState {
	switch state {
	case "working":
		return domain.ActivityActive
	case "asking":
		return domain.ActivityBlocked
	default:
		return domain.ActivityIdle
	}
}

func stateAt(transitions []simTransition, ms int64) domain.ActivityState {
	state := domain.ActivityIdle
	for _, tr := range transitions {
		if tr.at > ms {
			break
		}
		state = tr.to
	}
	return state
}

type signalMetrics struct {
	alerts, falseAlerts, duplicates, missed, flips, screen int
	correctionMs                                           int64
}

func measure(rec signalRecording, mode simMode, transitions []simTransition) signalMetrics {
	intervals := append([]truthInterval(nil), rec.truth.Intervals...)
	intervals[len(intervals)-1].To += simTailMs
	var m signalMetrics
	perAsking := map[int]int{}
	for _, tr := range transitions {
		if tr.screen {
			m.screen++
		}
		if !tr.alert {
			continue
		}
		m.alerts++
		asking := -1
		for i, interval := range intervals {
			if interval.State == "asking" && tr.at >= interval.From && tr.at <= interval.To {
				asking = i
			}
		}
		if asking < 0 {
			m.falseAlerts++
		} else {
			perAsking[asking]++
		}
	}
	for _, n := range perAsking {
		m.duplicates += max(0, n-1)
	}
	noDetector := signalAgent(rec.truth.Harness) == nil
	for i, interval := range intervals {
		grace := int64(flickerGraceMs)
		if interval.State == "settled" && noDetector {
			grace = quietGraceMs
		}
		for _, tr := range transitions {
			if tr.at > interval.From+grace && tr.at < interval.To && tr.to != expectedState(interval.State) {
				m.flips++
			}
		}
		if interval.State == "asking" && interval.To-interval.From >= missedBudgetMs && !stateAt(transitions, interval.From+missedBudgetMs).NeedsInput() {
			m.missed++
		}
		if interval.State == "settled" && i > 0 {
			latency := interval.To - interval.From
			for ms := interval.From; ms <= interval.To; ms += simTickMs {
				if stateAt(transitions, ms) == domain.ActivityIdle {
					latency = ms - interval.From
					break
				}
			}
			m.correctionMs = max(m.correctionMs, latency)
		}
	}
	return m
}

func TestAgentSignalsOnRecordings(t *testing.T) {
	for _, rec := range loadSignals(t) {
		modes := []simMode{modeHookless}
		if rec.truth.Harness != "" {
			modes = append(modes, modeHooks, modeMissedStop)
		}
		for _, mode := range modes {
			m := measure(rec, mode, simulate(t, rec, mode))
			t.Logf("%-24s %-11s alerts=%d false=%d dup=%d missed=%d flips=%d screen=%d correction=%dms",
				rec.name, mode, m.alerts, m.falseAlerts, m.duplicates, m.missed, m.flips, m.screen, m.correctionMs)
			if m.falseAlerts != 0 || m.duplicates != 0 {
				t.Errorf("%s/%s: %d false and %d duplicate alerts", rec.name, mode, m.falseAlerts, m.duplicates)
			}
			if mode == modeHookless && m.missed != 0 {
				t.Errorf("%s/%s: %d questions missed", rec.name, mode, m.missed)
			}
			if mode != modeMissedStop && m.flips != 0 {
				t.Errorf("%s/%s: %d flips", rec.name, mode, m.flips)
			}
			if mode == modeHooks && m.screen != 0 {
				t.Errorf("%s/%s: the screen changed %d states while hooks were timely", rec.name, mode, m.screen)
			}
			if mode == modeMissedStop && m.correctionMs > correctionBudgetMs {
				t.Errorf("%s/%s: a lost Stop hook took %d ms to correct", rec.name, mode, m.correctionMs)
			}
		}
	}
}
