package httpd

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
	"github.com/OmarAly92/operator/backend/internal/notify"
	"github.com/OmarAly92/operator/backend/internal/terminal"
)

type memoryNotificationStore struct{}

func (memoryNotificationStore) CreateNotification(_ context.Context, rec domain.NotificationRecord) (domain.NotificationRecord, bool, error) {
	return rec, true, nil
}

func (memoryNotificationStore) ResolveSessionNotifications(context.Context, domain.SessionID, domain.NotificationType, time.Time) ([]domain.NotificationRecord, error) {
	return nil, nil
}

func (memoryNotificationStore) ResolvePRNotifications(context.Context, string, domain.NotificationType, time.Time) ([]domain.NotificationRecord, error) {
	return nil, nil
}

func (memoryNotificationStore) ReconcileResolvedNotifications(context.Context, time.Time) ([]domain.NotificationRecord, error) {
	return nil, nil
}

type notificationMuxFrame struct {
	Ch           string `json:"ch"`
	Type         string `json:"type"`
	Notification *struct {
		ID        string    `json:"id"`
		SessionID string    `json:"sessionId"`
		ProjectID string    `json:"projectId"`
		Type      string    `json:"type"`
		Title     string    `json:"title"`
		Body      string    `json:"body"`
		Quiet     bool      `json:"quiet"`
		CreatedAt time.Time `json:"createdAt"`
	} `json:"notification"`
}

func waitFor(t *testing.T, d time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(d)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met in time")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestLANMuxReceivesNotificationsFromTheRealHub(t *testing.T) {
	hub := notify.NewHub()
	mgr := terminal.NewManager(nil, nil, discardLogger(), terminal.WithHeartbeat(0), terminal.WithNotificationFeed(hub))
	defer mgr.Close()
	writer := notify.New(notify.Deps{Store: memoryNotificationStore{}, Publisher: hub, NewID: func() string { return "ntf_live" }})

	st := &authState{}
	st.setHash(mobilebridge.HashPassword("secret12"))
	lan := NewLANManager(terminalMuxHandler(mgr, discardLogger()), st, 0, slog.Default(), nil)
	port, err := lan.Start(0)
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	defer lan.Stop(context.Background())

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	header := http.Header{}
	header.Set("Authorization", "Bearer secret12")
	c, _, err := websocket.Dial(ctx, fmt.Sprintf("ws://127.0.0.1:%d/mux", port), &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatalf("dial LAN /mux: %v", err)
	}
	if err := wsjson.Write(ctx, c, map[string]string{"ch": "notifications", "type": "subscribe"}); err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	waitFor(t, 2*time.Second, mgr.PhoneForeground)

	err = writer.Notify(ctx, notify.Intent{
		Type:               domain.NotificationTurnFinished,
		SessionID:          "mer-1",
		ProjectID:          "mer",
		Quiet:              true,
		SessionDisplayName: "split fix",
		CreatedAt:          time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC),
	})
	if err != nil {
		t.Fatalf("notify: %v", err)
	}

	var f notificationMuxFrame
	for f.Ch != "notifications" {
		if err := wsjson.Read(ctx, c, &f); err != nil {
			t.Fatalf("read: %v", err)
		}
	}
	if f.Type != "notification" || f.Notification == nil {
		t.Fatalf("frame = %+v", f)
	}
	n := f.Notification
	if n.ID != "ntf_live" || n.SessionID != "mer-1" || n.ProjectID != "mer" || n.Type != "turn_finished" || !n.Quiet || n.Title == "" {
		t.Fatalf("notification = %+v", *n)
	}

	_ = c.Close(websocket.StatusNormalClosure, "backgrounded")
	waitFor(t, 2*time.Second, func() bool { return !mgr.PhoneForeground() })
}

func TestLoopbackMuxSubscriptionIsNotThePhone(t *testing.T) {
	mgr := terminal.NewManager(nil, nil, discardLogger(), terminal.WithHeartbeat(0), terminal.WithNotificationFeed(notify.NewHub()))
	defer mgr.Close()
	ts := httptest.NewServer(terminalMuxHandler(mgr, discardLogger()))
	defer ts.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(ts.URL, "http"), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.Close(websocket.StatusNormalClosure, "done")
	if err := wsjson.Write(ctx, c, map[string]string{"ch": "notifications", "type": "subscribe"}); err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	if err := wsjson.Write(ctx, c, map[string]string{"ch": "system", "type": "ping"}); err != nil {
		t.Fatalf("ping: %v", err)
	}
	var f notificationMuxFrame
	for f.Ch != "system" {
		if err := wsjson.Read(ctx, c, &f); err != nil {
			t.Fatalf("read: %v", err)
		}
	}
	if mgr.PhoneForeground() {
		t.Fatal("a loopback subscription must not count as the phone")
	}
}
