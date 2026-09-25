package ptyhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/adapters/runtime/ptyhost/vtwasm"
)

var ringLimits = vtwasm.Limits{Rows: 50, Bytes: 0xffffffff, ColdRingBytes: 1 << 20}

func readStreamUntil(t *testing.T, c *testClient, want string) string {
	t.Helper()
	var stream strings.Builder
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(stream.String(), want) {
		typ, payload := c.readFrame(t)
		if typ == MsgTerminalData {
			stream.Write(payload)
		}
	}
	if !strings.Contains(stream.String(), want) {
		t.Fatalf("stream never carried %q:\n%q", want, stream.String())
	}
	return stream.String()
}

func requestOlder(t *testing.T, c *testClient, before uint64) {
	t.Helper()
	payload, err := json.Marshal(OlderReq{Before: before})
	if err != nil {
		t.Fatalf("marshal older request: %v", err)
	}
	if err := c.send(MsgOlderReq, payload); err != nil {
		t.Fatalf("send older request: %v", err)
	}
}

func fillPastTheCap(t *testing.T, f *serveFixture, rows int) {
	t.Helper()
	for i := 0; i < rows; i++ {
		writeOutput(t, f, fmt.Sprintf("row %05d\r\n", i))
	}
	waitForParsedOutput(t, f, fmt.Sprintf("row %05d", rows-1))
}

func TestAHistoryStreamEndsWithTheOlderFloor(t *testing.T) {
	f := startServeWithLimits(t, 760, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)

	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=")
	mark := strings.LastIndex(stream, "\x1b]7000;v=1;older=0\x1b\\")
	if mark < 0 {
		t.Fatalf("the floor mark is not older=0:\n%q", stream)
	}
	if last := strings.LastIndex(stream, "\x1b]7000;v=1;history="); last > mark {
		t.Fatalf("a history chunk followed the floor mark:\n%q", stream)
	}
}

func TestAClientWithoutHistoryGetsTheOlderFloorAfterItsFrame(t *testing.T) {
	f := startServeWithLimits(t, 761, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)

	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if strings.Index(stream, readyMark) > strings.Index(stream, "older=") {
		t.Fatalf("the floor mark came before the frame:\n%q", stream)
	}
	if strings.Contains(stream, "history=") {
		t.Fatalf("a client that did not opt in was sent history:\n%q", stream)
	}
}

func TestAHostWithoutARingSendsNoOlderFloor(t *testing.T) {
	f := startServeParsed(t, 762, 20, 4)
	defer f.cancel()
	fillPastTheCap(t, f, 60)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)
	_ = readReplay(t, c)
	writeOutput(t, f, "live after attach\r\n")
	stream := readStreamUntil(t, c, "live after attach")
	if strings.Contains(stream, "older=") {
		t.Fatalf("a host without a ring sent a floor mark:\n%q", stream)
	}
}

func TestAnOlderRequestFetchesEvictedRowsOverTheLiveStream(t *testing.T) {
	f := startServeWithLimits(t, 763, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResizeWithHistory(t, c, 20, 4, true)
	stream := readStreamUntil(t, c, "\x1b]7000;v=1;older=")

	cold, err := f.host.currentParser().ColdStats()
	if err != nil {
		t.Fatalf("cold stats: %v", err)
	}
	front := cold.FirstStableRow + uint64(cold.Rows)
	requestOlder(t, c, front)
	answer := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if !strings.Contains(answer, fmt.Sprintf("\x1b]7000;v=1;history=0,%d;cols=9\x1b\\", cold.Rows)) {
		t.Fatalf("the answer does not carry every evicted row:\n%q", answer)
	}
	stream += answer

	receiver, err := vtwasm.New(context.Background(), vtwasm.Module, 20, 4, vtwasm.Limits{Rows: 200_000, Bytes: 0xffffffff})
	if err != nil {
		t.Fatalf("new receiver: %v", err)
	}
	defer receiver.Close()
	if err := receiver.Feed([]byte(stream)); err != nil {
		t.Fatalf("feed: %v", err)
	}
	rendered, err := receiver.RenderTail(200_000)
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	rows := strings.Split(strings.TrimRight(rendered, "\n"), "\n")
	if rows[0] != "row 00000" {
		t.Fatalf("the evicted rows were not prepended; first rows = %q", rows[:min(len(rows), 3)])
	}
	if !strings.Contains(rows[len(rows)-1], "row 00299") && !strings.Contains(rendered, "row 00299") {
		t.Fatalf("the live rows are missing:\n%q", rendered)
	}
}

func TestAnOlderRequestBelowTheFloorAnswersWithTheFloorAlone(t *testing.T) {
	f := startServeWithLimits(t, 764, 20, 4, ringLimits)
	defer f.cancel()
	fillPastTheCap(t, f, 300)

	c := newTestClient(t, f.addr)
	defer c.close()
	sendResize(t, c, 20, 4)
	_ = readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")

	requestOlder(t, c, 0)
	answer := readStreamUntil(t, c, "\x1b]7000;v=1;older=0\x1b\\")
	if strings.Contains(answer, "history=") {
		t.Fatalf("nothing is older than row 0, yet a chunk came back:\n%q", answer)
	}
}

func TestRequestOlderWritesOneOlderFrame(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	s := &loopbackStream{conn: client}
	got := make(chan []byte, 1)
	go func() {
		parser := NewMessageParser(func(msgType byte, payload []byte) {
			if msgType == MsgOlderReq {
				got <- payload
			}
		})
		buf := make([]byte, 256)
		n, _ := server.Read(buf)
		parser.Feed(buf[:n])
	}()
	if err := s.RequestOlder(4096); err != nil {
		t.Fatalf("request older: %v", err)
	}
	select {
	case payload := <-got:
		if string(payload) != `{"before":4096}` {
			t.Fatalf("payload = %s", payload)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("no older request frame")
	}
}
