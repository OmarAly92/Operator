package terminal

import (
	"context"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	blockeventsvc "github.com/OmarAly92/operator/backend/internal/service/blockevent"
)

func TestPublishBlockEventReachesSubscribedConnection(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}

	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{
		Seq:       7,
		SessionID: "s-1",
		Kind:      domain.BlockEventToolComplete,
		ToolName:  "Bash",
		CreatedAt: time.Now().UTC(),
	})

	msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second)
	if msg.ID != "s-1" {
		t.Fatalf("frame id = %q, want s-1", msg.ID)
	}
	if msg.Block == nil {
		t.Fatal("frame carried no block payload")
	}
	if msg.Block.Seq != 7 || msg.Block.ToolName != "Bash" {
		t.Fatalf("block = %+v, want seq 7 / Bash", msg.Block)
	}
}

func TestPublishBlockEventIgnoresOtherSessions(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)
	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-2", blockeventsvc.Record{Seq: 1, SessionID: "s-2"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("received a block frame for an unsubscribed session: %+v", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

func TestPublishBlockEventIgnoresUnsubscribedConnection(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("a connection that never subscribed received %+v", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

// waitForBlockSubscriber blocks until the manager has registered a subscriber
// for id. Serve reads the subscribe frame on its own goroutine, so publishing
// immediately after sending it would race.
func waitForBlockSubscriber(t *testing.T, m *Manager, id string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		if m.blockSubscriberCount(id) > 0 {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("no block subscriber for %q appeared", id)
		case <-time.After(5 * time.Millisecond):
		}
	}
}

func waitForNoBlockSubscriber(t *testing.T, m *Manager, id string) {
	t.Helper()
	deadline := time.After(2 * time.Second)
	for {
		if m.blockSubscriberCount(id) == 0 {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("block subscriber for %q never went away", id)
		case <-time.After(5 * time.Millisecond):
		}
	}
}

func TestBlockUnsubscribeStopsDelivery(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})
	if msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second); msg.Block == nil || msg.Block.Seq != 1 {
		t.Fatalf("first block = %+v, want seq 1", msg.Block)
	}

	conn.in <- clientMsg{Ch: chBlocks, Type: msgUnsubscribe, ID: "s-1"}
	waitForNoBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 2, SessionID: "s-1"})

	select {
	case got := <-conn.out:
		if got.Ch == chBlocks {
			t.Fatalf("received %+v after unsubscribe, want nothing", got)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

func TestBlockUnsubscribeBeforeSubscribeIsHarmless(t *testing.T) {
	src := &fakeSource{alive: true, spawner: &fakeSpawner{}}
	m := NewManager(src, nil, nil)
	t.Cleanup(m.Close)

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	conn := newFakeConn()
	go m.Serve(ctx, conn)

	conn.in <- clientMsg{Ch: chBlocks, Type: msgUnsubscribe, ID: "s-1"}
	conn.in <- clientMsg{Ch: chBlocks, Type: msgSubscribe, ID: "s-1"}
	waitForBlockSubscriber(t, m, "s-1")

	m.PublishBlockEvent("s-1", blockeventsvc.Record{Seq: 1, SessionID: "s-1"})
	if msg := recv(t, conn, chBlocks, msgBlock, 2*time.Second); msg.Block == nil {
		t.Fatal("subscribe after a stray unsubscribe delivered nothing")
	}
}
