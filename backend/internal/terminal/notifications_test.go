package terminal

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

type fakeFeed struct{ ch chan domain.NotificationEvent }

func newFakeFeed() *fakeFeed { return &fakeFeed{ch: make(chan domain.NotificationEvent, 8)} }

func (f *fakeFeed) Subscribe(domain.ProjectID) (<-chan domain.NotificationEvent, func()) {
	return f.ch, func() {}
}

func created(id string) domain.NotificationEvent {
	return domain.NotificationEvent{Kind: domain.NotificationCreated, Record: domain.NotificationRecord{
		ID: id, SessionID: "mer-1", ProjectID: "mer", Type: domain.NotificationTurnFinished,
		Title: "split fix finished", Body: "done", CreatedAt: time.Date(2026, 9, 23, 10, 0, 0, 0, time.UTC),
	}}
}

func serveConn(t *testing.T, mgr *Manager, remote bool) *fakeConn {
	t.Helper()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	if remote {
		ctx = WithRemoteOrigin(ctx)
	}
	go mgr.Serve(ctx, conn)
	return conn
}

func TestNotificationsReachOnlySubscribedConnections(t *testing.T) {
	feed := newFakeFeed()
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(feed))
	defer mgr.Close()
	subscribed := serveConn(t, mgr, true)
	other := serveConn(t, mgr, true)
	subscribed.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)

	feed.ch <- created("ntf_1")
	got := recv(t, subscribed, chNotifications, msgNotification, time.Second)
	if got.Notification == nil || got.Notification.ID != "ntf_1" || got.Notification.SessionID != "mer-1" || got.Notification.Type != "turn_finished" {
		t.Fatalf("frame = %+v", got.Notification)
	}
	select {
	case m := <-other.out:
		if m.Ch == chNotifications {
			t.Fatalf("unsubscribed connection received %+v", m)
		}
	case <-time.After(100 * time.Millisecond):
	}
}

func TestResolvedEventsAreNotForwarded(t *testing.T) {
	feed := newFakeFeed()
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(feed))
	defer mgr.Close()
	conn := serveConn(t, mgr, true)
	conn.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	ev := created("ntf_1")
	ev.Kind = domain.NotificationResolved
	feed.ch <- ev
	select {
	case m := <-conn.out:
		if m.Ch == chNotifications {
			t.Fatalf("resolved event forwarded: %+v", m)
		}
	case <-time.After(100 * time.Millisecond):
	}
}

func TestPhoneForegroundCountsOnlyRemoteSubscriptions(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(newFakeFeed()))
	defer mgr.Close()
	local := serveConn(t, mgr, false)
	local.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	time.Sleep(50 * time.Millisecond)
	if mgr.PhoneForeground() {
		t.Fatal("a loopback subscription must not count as the phone")
	}
	phone := serveConn(t, mgr, true)
	phone.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	phone.in <- clientMsg{Ch: chNotifications, Type: msgUnsubscribe}
	eventually(t, time.Second, func() bool { return !mgr.PhoneForeground() })
}

func TestPhoneForegroundClearsWhenTheConnectionCloses(t *testing.T) {
	mgr := NewManager(&fakeSource{}, nil, testLogger(), WithHeartbeat(0), WithNotificationFeed(newFakeFeed()))
	defer mgr.Close()
	conn := newFakeConn()
	ctx, cancel := context.WithCancel(WithRemoteOrigin(context.Background()))
	done := make(chan struct{})
	go func() { mgr.Serve(ctx, conn); close(done) }()
	conn.in <- clientMsg{Ch: chNotifications, Type: msgSubscribe}
	eventually(t, time.Second, mgr.PhoneForeground)
	cancel()
	<-done
	if mgr.PhoneForeground() {
		t.Fatal("closed connection still counted as foreground")
	}
}
