package screen

import (
	"reflect"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

var t0 = time.Date(2026, 9, 27, 12, 0, 0, 0, time.UTC)

func working() Observation {
	return Observation{Reading: domain.ScreenWorking, Confirm: ScreenActiveConfirm}
}

func question(identity string) Observation {
	return Observation{Reading: domain.ScreenQuestion, Identity: identity, Text: identity, Confirm: ScreenQuestionConfirm}
}

func settled(confirm time.Duration) Observation {
	return Observation{Reading: domain.ScreenSettled, Confirm: confirm}
}

func readings(decisions []Decision) []domain.ScreenReading {
	var out []domain.ScreenReading
	for _, d := range decisions {
		out = append(out, d.Reading)
	}
	return out
}

func TestDebouncerConfirmsAfterEachHoldTime(t *testing.T) {
	var d Debouncer
	if got := d.Observe(working(), t0); got != nil {
		t.Fatalf("working confirmed at once: %+v", got)
	}
	if got := d.Due(t0.Add(ScreenActiveConfirm - time.Millisecond)); got != nil {
		t.Fatalf("working confirmed early: %+v", got)
	}
	if got := readings(d.Due(t0.Add(ScreenActiveConfirm))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenWorking}) {
		t.Fatalf("working = %v", got)
	}
	d.Observe(question("q"), t0.Add(10*time.Second))
	if got := readings(d.Due(t0.Add(11 * time.Second))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenQuestion}) {
		t.Fatalf("question = %v", got)
	}
}

func TestDebouncerARepaintBurstDoesNotLeaveTheQuestion(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(5*time.Second))
	if got := d.Observe(question("q"), t0.Add(6500*time.Millisecond)); got != nil {
		t.Fatalf("a repaint changed the reading: %+v", got)
	}
	if got := d.Due(t0.Add(time.Minute)); got != nil {
		t.Fatalf("a repaint left a pending reading: %+v", got)
	}
}

func TestDebouncerTheSameQuestionAfterARepaintIsNotNew(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	first := d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(2*time.Second))
	d.Observe(question("q"), t0.Add(3*time.Second))
	if len(first) != 1 || d.Due(t0.Add(10*time.Second)) != nil {
		t.Fatalf("first=%+v and a second decision for the same question", first)
	}
}

func TestDebouncerTwoDifferentQuestionsAreTwoDecisions(t *testing.T) {
	var d Debouncer
	d.Observe(question("first"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(working(), t0.Add(5*time.Second))
	d.Observe(question("second"), t0.Add(6*time.Second))
	got := d.Due(t0.Add(7 * time.Second))
	want := []Decision{{Reading: domain.ScreenWorking}, {Reading: domain.ScreenQuestion, Identity: "second", Text: "second"}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("decisions = %+v, want %+v", got, want)
	}
}

func TestDebouncerAFortySecondSilenceIsNotSettledWithoutADetector(t *testing.T) {
	var d Debouncer
	d.Observe(working(), t0)
	d.Due(t0.Add(ScreenActiveConfirm))
	d.Observe(settled(ScreenQuietSettle), t0.Add(5*time.Second))
	if got := d.Due(t0.Add(45 * time.Second)); got != nil {
		t.Fatalf("a 40 s silence settled: %+v", got)
	}
	d.Observe(working(), t0.Add(45*time.Second))
	if got := d.Due(t0.Add(5 * time.Minute)); got != nil {
		t.Fatalf("output after the silence left a decision: %+v", got)
	}
}

func TestDebouncerLeavingAnAnsweredQuestionSettlesQuickly(t *testing.T) {
	var d Debouncer
	d.Observe(question("q"), t0)
	d.Due(t0.Add(time.Second))
	d.Observe(settled(ScreenQuietSettle), t0.Add(4*time.Second))
	if got := readings(d.Due(t0.Add(4*time.Second + ScreenSettleConfirm))); !reflect.DeepEqual(got, []domain.ScreenReading{domain.ScreenSettled}) {
		t.Fatalf("after the question went away = %v, want settled within %v", got, ScreenSettleConfirm)
	}
}

func TestDebouncerAnUnreadableScreenCancelsWhatWasPending(t *testing.T) {
	var d Debouncer
	d.Observe(settled(ScreenSettleConfirm), t0)
	d.Observe(Observation{}, t0.Add(time.Second))
	if got := d.Due(t0.Add(time.Minute)); got != nil {
		t.Fatalf("pending reading survived an unreadable screen: %+v", got)
	}
}

func TestDebouncerHoldsOnlyWhileTheScreenStillReadsTheAppliedDecision(t *testing.T) {
	var d Debouncer
	if d.Holds() {
		t.Fatal("holds before any decision")
	}
	d.Observe(question("q"), t0)
	d.Due(t0.Add(time.Second))
	if !d.Holds() {
		t.Fatal("does not hold the question it just applied")
	}
	d.Observe(working(), t0.Add(2*time.Second))
	if d.Holds() {
		t.Fatal("holds the question while working is pending")
	}
	d.Observe(question("q"), t0.Add(3*time.Second))
	if !d.Holds() {
		t.Fatal("does not hold the question after a repaint")
	}
	d.Observe(Observation{}, t0.Add(4*time.Second))
	if d.Holds() {
		t.Fatal("holds the question on an unreadable screen")
	}
}

func TestDebouncerASettledDecisionCarriesTheNewestSummary(t *testing.T) {
	var d Debouncer
	first := settled(ScreenSettleConfirm)
	first.Text = "Reading files"
	d.Observe(first, t0)
	newest := settled(ScreenSettleConfirm)
	newest.Text = "Removed build/."
	d.Observe(newest, t0.Add(time.Second))
	got := d.Due(t0.Add(ScreenSettleConfirm))
	if len(got) != 1 || got[0].Reading != domain.ScreenSettled || got[0].Text != "Removed build/." {
		t.Fatalf("decision = %+v", got)
	}
}
