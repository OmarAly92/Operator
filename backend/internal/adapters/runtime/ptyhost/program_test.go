package ptyhost

import (
	"encoding/json"
	"testing"
	"time"
)

func newWatcher(t *testing.T, addr string) *testClient {
	t.Helper()
	w := newTestClient(t, addr)
	if err := w.send(MsgWatchReq, nil); err != nil {
		t.Fatalf("send watch: %v", err)
	}
	return w
}

func readProgramEvent(t *testing.T, c *testClient) ProgramEventPayload {
	t.Helper()
	typ, payload := c.readFrame(t)
	if typ != MsgProgramEvent {
		t.Fatalf("frame type 0x%02x, want MsgProgramEvent (payload %q)", typ, payload)
	}
	var event ProgramEventPayload
	if err := json.Unmarshal(payload, &event); err != nil {
		t.Fatalf("decode program event: %v", err)
	}
	return event
}

func expectNoFrame(t *testing.T, c *testClient, within time.Duration) {
	t.Helper()
	select {
	case frame, ok := <-c.frameC:
		if ok {
			t.Fatalf("unexpected frame type 0x%02x payload %q", frame.typ, frame.payload)
		}
	case <-time.After(within):
	}
}

func readPTYInput(t *testing.T, f *serveFixture, want string) {
	t.Helper()
	got := make([]byte, 0, len(want))
	buf := make([]byte, 256)
	deadline := time.After(2 * time.Second)
	for len(got) < len(want) {
		readC := make(chan int, 1)
		go func() {
			n, _ := f.pty.ReadInput(buf)
			readC <- n
		}()
		select {
		case n := <-readC:
			got = append(got, buf[:n]...)
		case <-deadline:
			t.Fatalf("pty input = %q, want %q", got, want)
		}
	}
	if string(got) != want {
		t.Fatalf("pty input = %q, want %q", got, want)
	}
}

func sendAppearance(t *testing.T, c *testClient, appearance AppearancePayload) {
	t.Helper()
	payload, _ := json.Marshal(appearance)
	if err := c.send(MsgAppearance, payload); err != nil {
		t.Fatalf("send appearance: %v", err)
	}
	if err := c.send(MsgStatusReq, nil); err != nil {
		t.Fatalf("send status: %v", err)
	}
	for {
		if typ, _ := c.readFrame(t); typ == MsgStatusRes {
			return
		}
	}
}

func watcherCount(f *serveFixture) int {
	f.host.mu.Lock()
	defer f.host.mu.Unlock()
	return len(f.host.watchers)
}

func TestAWatcherGetsTheCurrentTitleThenEachStrippedChange(t *testing.T) {
	f := startServeParsed(t, 901, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()

	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "" {
		t.Fatalf("first event = %+v, want an empty title", event)
	}
	writeOutput(t, f, "\x1b]0;◐ Number list\x07")
	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "Number list" {
		t.Fatalf("event = %+v, want the stripped title", event)
	}
	writeOutput(t, f, "\x1b]0;◑ Number list\x07")
	writeOutput(t, f, "\x1b]0;✳ Number list done\x07")
	if event := readProgramEvent(t, w); event.Title != "Number list done" {
		t.Fatalf("event = %+v, want only the next distinct stripped title", event)
	}
}

func TestAWatcherThatJoinsLateGetsTheTitleAlreadyShown(t *testing.T) {
	f := startServeParsed(t, 902, 80, 24)
	defer f.cancel()
	first := newWatcher(t, f.addr)
	defer first.close()
	readProgramEvent(t, first)
	writeOutput(t, f, "\x1b]2;◐ Refactor\x07")
	readProgramEvent(t, first)

	late := newWatcher(t, f.addr)
	defer late.close()
	if event := readProgramEvent(t, late); event.Title != "Refactor" {
		t.Fatalf("late watcher first event = %+v", event)
	}
}

func TestAWatcherGetsProgramNotifications(t *testing.T) {
	f := startServeParsed(t, 903, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	writeOutput(t, f, "\x1b]9;hello\x07\x1b]777;notify;Build;done\x07")
	first := readProgramEvent(t, w)
	second := readProgramEvent(t, w)
	if first != (ProgramEventPayload{Kind: ProgramEventNotification, Body: "hello"}) {
		t.Fatalf("first notification = %+v", first)
	}
	if second != (ProgramEventPayload{Kind: ProgramEventNotification, Title: "Build", Body: "done"}) {
		t.Fatalf("second notification = %+v", second)
	}
}

func TestAWatcherGetsNoTerminalBytes(t *testing.T) {
	f := startServeParsed(t, 904, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	writeOutput(t, f, "plain output\r\n")
	expectNoFrame(t, w, 150*time.Millisecond)
}

func TestAClosedWatcherIsForgotten(t *testing.T) {
	f := startServeParsed(t, 905, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	readProgramEvent(t, w)
	if got := watcherCount(f); got != 1 {
		t.Fatalf("watchers = %d, want 1", got)
	}
	w.close()
	deadline := time.Now().Add(2 * time.Second)
	for watcherCount(f) != 0 {
		if time.Now().After(deadline) {
			t.Fatalf("watcher still registered after close")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestShutdownClosesEveryWatcher(t *testing.T) {
	f := startServeParsed(t, 906, 80, 24)
	w := newWatcher(t, f.addr)
	readProgramEvent(t, w)
	f.cancel()
	f.waitDone(t)
	select {
	case _, ok := <-w.frameC:
		if ok {
			t.Fatal("watcher received a frame instead of a close")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("watcher connection was not closed by shutdown")
	}
	if got := watcherCount(f); got != 0 {
		t.Fatalf("watchers after shutdown = %d, want 0", got)
	}
}

func TestResetProgramTellsWatchersTheTitleIsGone(t *testing.T) {
	f := startServeParsed(t, 907, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)
	writeOutput(t, f, "\x1b]2;◐ Old task\x07")
	readProgramEvent(t, w)

	f.host.mu.Lock()
	f.host.resetProgramLocked()
	f.host.mu.Unlock()
	if event := readProgramEvent(t, w); event.Kind != ProgramEventTitle || event.Title != "" {
		t.Fatalf("event after reset = %+v, want an empty title", event)
	}
}

func TestAppearanceAnswersPixelAndColourQueriesOnThePty(t *testing.T) {
	f := startServeParsed(t, 908, 80, 24)
	defer f.cancel()
	c := newTestClient(t, f.addr)
	defer c.close()
	syncResize(t, c, 80, 24)

	sendAppearance(t, c, AppearancePayload{CellWidth: 9, CellHeight: 18, Foreground: "#ffffff", Background: "#1d2022"})
	writeOutput(t, f, "\x1b[16t\x1b]11;?\x07")
	readPTYInput(t, f, "\x1b[6;18;9t\x1b]11;rgb:1d1d/2020/2222\x07")
}

func TestMode2048ReportsReachThePtyOnEnableAndOnResize(t *testing.T) {
	f := startServeParsed(t, 909, 80, 24)
	defer f.cancel()
	c := newTestClient(t, f.addr)
	defer c.close()
	syncResize(t, c, 80, 24)

	sendAppearance(t, c, AppearancePayload{CellWidth: 8, CellHeight: 16})
	writeOutput(t, f, "\x1b[?2048h")
	readPTYInput(t, f, "\x1b[48;24;80;384;640t")

	resize, _ := json.Marshal(ResizePayload{Cols: 100, Rows: 30})
	if err := c.send(MsgResize, resize); err != nil {
		t.Fatalf("send resize: %v", err)
	}
	readPTYInput(t, f, "\x1b[48;30;100;480;800t")
}

func TestParseHexColor(t *testing.T) {
	cases := map[string]int32{"#1d2022": 0x1d2022, "#FFFFFF": 0xffffff, " #000000 ": 0, "": -1, "#fff": -1, "red": -1, "#gggggg": -1}
	for input, want := range cases {
		if got := parseHexColor(input); got != want {
			t.Errorf("parseHexColor(%q) = %d, want %d", input, got, want)
		}
	}
}

func TestAFloodOfProgramNotificationsIsCapped(t *testing.T) {
	window := programNotificationWindow
	programNotificationWindow = 300 * time.Millisecond
	defer func() { programNotificationWindow = window }()
	f := startServeParsed(t, 911, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	flood := ""
	for i := 0; i < 50; i++ {
		flood += "\x1b]9;spam\x07"
	}
	writeOutput(t, f, flood)
	for i := 0; i < programNotificationBurst; i++ {
		if got := readProgramEvent(t, w); got.Kind != ProgramEventNotification {
			t.Fatalf("event %d = %+v, want a notification", i, got)
		}
	}
	expectNoFrame(t, w, 150*time.Millisecond)

	time.Sleep(programNotificationWindow)
	writeOutput(t, f, "\x1b]9;later\x07")
	if got := readProgramEvent(t, w); got != (ProgramEventPayload{Kind: ProgramEventNotification, Body: "later"}) {
		t.Fatalf("after the window = %+v, want the new notification", got)
	}
}

func TestACappedFloodStillDeliversTitleChanges(t *testing.T) {
	f := startServeParsed(t, 912, 80, 24)
	defer f.cancel()
	w := newWatcher(t, f.addr)
	defer w.close()
	readProgramEvent(t, w)

	flood := ""
	for i := 0; i < 20; i++ {
		flood += "\x1b]9;spam\x07"
	}
	writeOutput(t, f, flood)
	for i := 0; i < programNotificationBurst; i++ {
		readProgramEvent(t, w)
	}
	writeOutput(t, f, "\x1b]2;◐ Still titled\x07")
	if got := readProgramEvent(t, w); got != (ProgramEventPayload{Kind: ProgramEventTitle, Title: "Still titled"}) {
		t.Fatalf("title after a capped flood = %+v", got)
	}
}

func TestAQueryParsedWhenASyncBlockTimesOutIsAnswered(t *testing.T) {
	f := startServeParsed(t, 913, 80, 24)
	defer f.cancel()
	writeOutput(t, f, "\x1b[?2026h\x1b[18t")
	readPTYInput(t, f, "\x1b[8;24;80t")
}
