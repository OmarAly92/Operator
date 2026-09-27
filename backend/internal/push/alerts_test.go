package push

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

type fakeSender struct {
	mu     sync.Mutex
	sent   []Alert
	topics []string
	err    error
}

func (f *fakeSender) Send(_ context.Context, topic string, a Alert) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, a)
	f.topics = append(f.topics, topic)
	return f.err
}

type flag bool

func (f flag) Running() bool         { return bool(f) }
func (f flag) PhoneForeground() bool { return bool(f) }

func setup(t *testing.T, st mobilebridge.State, bridgeUp, foreground bool) (*Alerts, *fakeSender, *time.Time) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := mobilebridge.Save(path, st); err != nil {
		t.Fatal(err)
	}
	sender := &fakeSender{}
	now := time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC)
	a := NewAlerts(AlertsDeps{Sender: sender, ConfigPath: path, Presence: flag(foreground), Clock: func() time.Time { return now }})
	a.SetBridge(flag(bridgeUp))
	return a, sender, &now
}

var paired = mobilebridge.State{Enabled: true, Password: "pw", AlertTopic: strings.Repeat("t", 32), AlertTopicClaimed: true}

func record(typ domain.NotificationType, session string) domain.NotificationRecord {
	return domain.NotificationRecord{ID: "n-" + session, SessionID: domain.SessionID(session), ProjectID: "p", Type: typ, Title: session + " finished", Body: "Implemented X in /secret/path.go", CreatedAt: time.Now()}
}

func TestAlertsSendsWhenPairedAndBackgrounded(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "operator-4"))
	if len(sender.sent) != 1 || sender.topics[0] != paired.AlertTopic {
		t.Fatalf("sent=%+v topics=%v", sender.sent, sender.topics)
	}
	got := sender.sent[0]
	if got.Title != "operator-4 finished" || got.Message != "Implemented X in /secret/path.go" || got.Click != "operator://session/operator-4" {
		t.Fatalf("alert = %+v, want the notification body as the message", got)
	}
}

func TestAlertsGate(t *testing.T) {
	unclaimed := paired
	unclaimed.AlertTopicClaimed = false
	disabled := paired
	disabled.Enabled = false
	for _, tc := range []struct {
		name       string
		st         mobilebridge.State
		bridgeUp   bool
		foreground bool
		quiet      bool
	}{
		{"listener down", paired, false, false, false},
		{"connect mobile off", disabled, true, false, false},
		{"topic not claimed", unclaimed, true, false, false},
		{"phone app open", paired, true, true, false},
		{"quiet", paired, true, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a, sender, _ := setup(t, tc.st, tc.bridgeUp, tc.foreground)
			rec := record(domain.NotificationTurnFinished, "s")
			rec.Quiet = tc.quiet
			a.dispatch(context.Background(), rec)
			if len(sender.sent) != 0 {
				t.Fatalf("sent %+v, want nothing", sender.sent)
			}
		})
	}
}

func TestAlertsCoalescePerSessionAndTypeForTenSeconds(t *testing.T) {
	a, sender, now := setup(t, paired, true, false)
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s2"))
	if len(sender.sent) != 3 {
		t.Fatalf("sent %d, want 3 (a needs-you alert is not swallowed by a finished one)", len(sender.sent))
	}
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	if len(sender.sent) != 3 {
		t.Fatalf("sent %d, want the second needs-you inside the window coalesced", len(sender.sent))
	}
	*now = now.Add(11 * time.Second)
	a.dispatch(context.Background(), record(domain.NotificationNeedsInput, "s1"))
	if len(sender.sent) != 4 {
		t.Fatalf("sent %d after the window, want 4", len(sender.sent))
	}
}

func TestAlertsTwoDifferentNeedsInputQuestionsInTheWindowAreBothSent(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	first := record(domain.NotificationNeedsInput, "s1")
	first.Body = "Overwrite file A?"
	a.dispatch(context.Background(), first)
	second := record(domain.NotificationNeedsInput, "s1")
	second.Body = "Delete branch B?"
	a.dispatch(context.Background(), second)
	if len(sender.sent) != 2 || sender.sent[0].Message == sender.sent[1].Message {
		t.Fatalf("sent %+v, want two different needs-you alerts", sender.sent)
	}
	third := record(domain.NotificationNeedsInput, "s1")
	third.Body = "Delete branch B?"
	a.dispatch(context.Background(), third)
	if len(sender.sent) != 2 {
		t.Fatalf("sent %d, want the repeated question coalesced", len(sender.sent))
	}
}

func TestAlertsRecordsDeliveries(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	sender.err = errors.New("ntfy answered 429 Too Many Requests")
	a.dispatch(context.Background(), record(domain.NotificationTurnFinished, "s"))
	st := a.Status()
	if !st.Enabled || !st.Claimed || st.LastDelivery == nil || st.LastDelivery.OK || !strings.Contains(st.LastDelivery.Error, "429") {
		t.Fatalf("status = %+v", st)
	}
}

func TestAlertsPRTypesNeverCarryThePRTitle(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationReadyToMerge, "s")
	rec.Title = "Secret refactor · PR #12"
	rec.PRURL = "https://github.com/o/r/pull/12"
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 || strings.Contains(sender.sent[0].Title, "Secret") || sender.sent[0].Message != "ready to merge" {
		t.Fatalf("sent = %+v", sender.sent)
	}
}

func TestAlertsPRTypesClickThroughToPullRequests(t *testing.T) {
	for _, typ := range []domain.NotificationType{domain.NotificationReadyToMerge, domain.NotificationPRMerged, domain.NotificationPRClosedUnmerged} {
		a, sender, _ := setup(t, paired, true, false)
		a.dispatch(context.Background(), record(typ, "s"))
		if len(sender.sent) != 1 || sender.sent[0].Click != "operator://prs" {
			t.Fatalf("%s: sent = %+v, want click operator://prs", typ, sender.sent)
		}
	}
}

func TestAlertsPriorityIsHighOnlyForNeedsInput(t *testing.T) {
	for typ, want := range map[domain.NotificationType]string{
		domain.NotificationNeedsInput:   PriorityHigh,
		domain.NotificationTurnFinished: PriorityDefault,
		domain.NotificationAgentExited:  PriorityDefault,
	} {
		a, sender, _ := setup(t, paired, true, false)
		a.dispatch(context.Background(), record(typ, "s"))
		if len(sender.sent) != 1 || sender.sent[0].Priority != want {
			t.Fatalf("%s: sent = %+v, want priority %q", typ, sender.sent, want)
		}
	}
	a, sender, _ := setup(t, paired, true, false)
	a.Test(context.Background())
	if len(sender.sent) != 1 || sender.sent[0].Priority != PriorityDefault {
		t.Fatalf("test alert = %+v, want priority %q", sender.sent, PriorityDefault)
	}
}

func TestClaimReturnsTheTopicAndMarksItClaimed(t *testing.T) {
	st := paired
	st.AlertTopicClaimed = false
	a, _, _ := setup(t, st, true, false)
	topic, server, err := a.Claim()
	if err != nil || topic != paired.AlertTopic || server != DefaultNtfyServer {
		t.Fatalf("topic=%q server=%q err=%v", topic, server, err)
	}
	if !a.Status().Claimed {
		t.Fatal("claim did not persist")
	}
}

func TestClaimWithoutConnectMobileFails(t *testing.T) {
	a, _, _ := setup(t, mobilebridge.State{}, false, false)
	if _, _, err := a.Claim(); !errors.Is(err, ErrAlertsUnavailable) {
		t.Fatalf("err = %v, want ErrAlertsUnavailable", err)
	}
}

func TestTestIgnoresForegroundButNotPairing(t *testing.T) {
	a, sender, _ := setup(t, paired, true, true)
	if d, err := a.Test(context.Background()); err != nil || !d.OK || len(sender.sent) != 1 {
		t.Fatalf("delivery=%+v err=%v sent=%d", d, err, len(sender.sent))
	}
	b, sender2, _ := setup(t, mobilebridge.State{}, false, false)
	if _, err := b.Test(context.Background()); !errors.Is(err, ErrAlertsUnavailable) || len(sender2.sent) != 0 {
		t.Fatalf("unpaired test err=%v sent=%d", err, len(sender2.sent))
	}
}

func TestTestWhenNotReadyIsNotRecordedAsADelivery(t *testing.T) {
	a, _, _ := setup(t, mobilebridge.State{Enabled: true, Password: "pw", AlertTopic: strings.Repeat("t", 32)}, true, false)
	if _, err := a.Test(context.Background()); !errors.Is(err, ErrAlertsUnavailable) {
		t.Fatalf("err = %v, want ErrAlertsUnavailable", err)
	}
	if st := a.Status(); st.LastDelivery != nil {
		t.Fatalf("last delivery = %+v, want none", st.LastDelivery)
	}
}

func TestAlertsMaskSecretsAndStripControlsInTheBody(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationNeedsInput, "s1")
	rec.Body = "Run \x1b[31mcurl -H 'Authorization: Bearer abcdefghijklmnop1234'\x1b[0m with password=hunter2hunter2?\x07\nnext line"
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 || sender.sent[0].Message != "Run curl -H 'Authorization: Bearer [redacted]' with password=[redacted] next line" {
		t.Fatalf("sent = %+v", sender.sent)
	}
	a.dispatch(context.Background(), record(domain.NotificationAgentExited, "s2"))
	if len(sender.sent) != 2 || sender.sent[1].Message != "exited" {
		t.Fatalf("exited alert = %+v, want the event word", sender.sent)
	}
	blank := record(domain.NotificationTurnFinished, "s3")
	blank.Body = "\x1b[0m\x07 "
	a.dispatch(context.Background(), blank)
	if len(sender.sent) != 3 || sender.sent[2].Message != "finished" {
		t.Fatalf("blank body alert = %+v, want the event word", sender.sent)
	}
}

func TestAlertsCapTheBodyAtNtfysMessageLimit(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationTurnFinished, "s1")
	rec.Body = strings.Repeat("é", ntfyMessageBytes)
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 {
		t.Fatalf("sent %d, want 1", len(sender.sent))
	}
	msg := sender.sent[0].Message
	if len(msg) > ntfyMessageBytes || !utf8.ValidString(msg) || !strings.HasPrefix(msg, "éé") || !strings.HasSuffix(msg, "…") {
		t.Fatalf("message is %d bytes, valid UTF-8 %v, want at most %d ending in …", len(msg), utf8.ValidString(msg), ntfyMessageBytes)
	}
}

func TestAlertsCleanAndMaskTheTitle(t *testing.T) {
	a, sender, _ := setup(t, paired, true, false)
	rec := record(domain.NotificationTurnFinished, "s1")
	rec.Title = "\x1b[31mfix\x1b[0m\u202e sk-abcdefghijklmnopqrstuvwxyz\x07 finished"
	a.dispatch(context.Background(), rec)
	if len(sender.sent) != 1 || sender.sent[0].Title != "fix [redacted] finished" {
		t.Fatalf("sent = %+v", sender.sent)
	}
}
