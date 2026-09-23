package push

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/url"
	"sync"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
)

const (
	coalesceWindow = 10 * time.Second
	deliveryLog    = 20
)

var ErrAlertsUnavailable = errors.New("phone alerts need Connect Mobile to be on")

type PhoneSender interface {
	Send(ctx context.Context, topic string, alert Alert) error
}

type Bridge interface{ Running() bool }

type Presence interface{ PhoneForeground() bool }

type Subscriber interface {
	Subscribe(projectID domain.ProjectID) (<-chan domain.NotificationEvent, func())
}

type Delivery struct {
	At    time.Time
	OK    bool
	Error string
}

type Status struct {
	Enabled      bool
	Claimed      bool
	LastDelivery *Delivery
}

type AlertsDeps struct {
	Subscriber Subscriber
	Sender     PhoneSender
	ConfigPath string
	Presence   Presence
	Server     string
	Clock      func() time.Time
	Log        *slog.Logger
}

type Alerts struct {
	d AlertsDeps

	mu         sync.Mutex
	bridge     Bridge
	lastSent   map[domain.SessionID]time.Time
	deliveries []Delivery
}

func NewAlerts(d AlertsDeps) *Alerts {
	if d.Clock == nil {
		d.Clock = time.Now
	}
	if d.Log == nil {
		d.Log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	if d.Server == "" {
		d.Server = DefaultNtfyServer
	}
	return &Alerts{d: d, lastSent: map[domain.SessionID]time.Time{}}
}

func (a *Alerts) SetBridge(b Bridge) {
	a.mu.Lock()
	a.bridge = b
	a.mu.Unlock()
}

func (a *Alerts) Run(ctx context.Context) {
	if a.d.Subscriber == nil {
		return
	}
	events, unsubscribe := a.d.Subscriber.Subscribe("")
	defer unsubscribe()
	for {
		select {
		case <-ctx.Done():
			return
		case ev, ok := <-events:
			if !ok {
				return
			}
			if ev.Kind == domain.NotificationCreated {
				a.dispatch(ctx, ev.Record)
			}
		}
	}
}

func (a *Alerts) Status() Status {
	st, _ := mobilebridge.Load(a.d.ConfigPath)
	a.mu.Lock()
	defer a.mu.Unlock()
	out := Status{Enabled: a.enabledLocked(st), Claimed: st.AlertTopicClaimed}
	if n := len(a.deliveries); n > 0 {
		last := a.deliveries[n-1]
		out.LastDelivery = &last
	}
	return out
}

func (a *Alerts) Claim() (string, string, error) {
	a.mu.Lock()
	bridgeUp := a.bridge != nil && a.bridge.Running()
	a.mu.Unlock()
	if !bridgeUp {
		return "", "", ErrAlertsUnavailable
	}
	st, err := mobilebridge.Update(a.d.ConfigPath, func(s *mobilebridge.State) error {
		if !s.Enabled || s.AlertTopic == "" {
			return ErrAlertsUnavailable
		}
		s.AlertTopicClaimed = true
		return nil
	})
	if err != nil {
		return "", "", err
	}
	return st.AlertTopic, a.d.Server, nil
}

func (a *Alerts) Test(ctx context.Context) (Delivery, error) {
	st, _ := mobilebridge.Load(a.d.ConfigPath)
	a.mu.Lock()
	ready := a.enabledLocked(st) && st.AlertTopicClaimed
	a.mu.Unlock()
	if !ready {
		return Delivery{}, ErrAlertsUnavailable
	}
	err := a.d.Sender.Send(ctx, st.AlertTopic, Alert{Title: "Operator", Message: "Test alert from your desktop", Priority: PriorityDefault})
	return a.recordDelivery(err), nil
}

func (a *Alerts) dispatch(ctx context.Context, rec domain.NotificationRecord) {
	if rec.Quiet {
		return
	}
	st, err := mobilebridge.Load(a.d.ConfigPath)
	if err != nil {
		a.d.Log.Warn("phone alert skipped: mobile config unreadable", "err", err)
		return
	}
	now := a.d.Clock()
	a.mu.Lock()
	if !a.enabledLocked(st) || !st.AlertTopicClaimed {
		a.mu.Unlock()
		return
	}
	if a.d.Presence != nil && a.d.Presence.PhoneForeground() {
		a.mu.Unlock()
		return
	}
	if last, ok := a.lastSent[rec.SessionID]; ok && now.Sub(last) < coalesceWindow {
		a.mu.Unlock()
		return
	}
	a.lastSent[rec.SessionID] = now
	a.mu.Unlock()
	a.recordDelivery(a.d.Sender.Send(ctx, st.AlertTopic, alertFor(rec)))
}

func (a *Alerts) enabledLocked(st mobilebridge.State) bool {
	return st.Enabled && st.AlertTopic != "" && a.bridge != nil && a.bridge.Running()
}

func (a *Alerts) recordDelivery(err error) Delivery {
	d := Delivery{At: a.d.Clock(), OK: err == nil}
	if err != nil {
		d.Error = err.Error()
		a.d.Log.Warn("phone alert failed", "err", err)
	}
	a.mu.Lock()
	a.deliveries = append(a.deliveries, d)
	if over := len(a.deliveries) - deliveryLog; over > 0 {
		a.deliveries = a.deliveries[over:]
	}
	a.mu.Unlock()
	return d
}

func alertFor(rec domain.NotificationRecord) Alert {
	alert := Alert{Title: rec.Title, Message: eventWord(rec.Type), Priority: PriorityDefault}
	if rec.SessionID != "" {
		alert.Click = "operator://session/" + url.PathEscape(string(rec.SessionID))
	}
	if rec.Type == domain.NotificationNeedsInput {
		alert.Priority = PriorityHigh
	}
	if !rec.Type.SessionScoped() {
		alert.Title = "Pull request " + eventWord(rec.Type)
		alert.Click = "operator://prs"
	}
	return alert
}

func eventWord(t domain.NotificationType) string {
	switch t {
	case domain.NotificationTurnFinished:
		return "finished"
	case domain.NotificationNeedsInput:
		return "needs input"
	case domain.NotificationAgentExited:
		return "exited"
	case domain.NotificationReadyToMerge:
		return "ready to merge"
	case domain.NotificationPRMerged:
		return "merged"
	case domain.NotificationPRClosedUnmerged:
		return "closed"
	default:
		return "update"
	}
}
