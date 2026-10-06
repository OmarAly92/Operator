package vtwasm

import (
	"bytes"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestTitleFollowsTheLatestOSC2(t *testing.T) {
	p := newTestParser(t, 80, 24)
	title, err := p.Title()
	if err != nil || title != "" {
		t.Fatalf("fresh title = %q, %v; want empty", title, err)
	}
	before, _ := p.ProgramGeneration()
	feed(t, p, "\x1b]0;◐ Working\x07\x1b]2;✳ Idle\x1b\\")
	title, err = p.Title()
	if err != nil || title != "✳ Idle" {
		t.Fatalf("title = %q, %v", title, err)
	}
	after, _ := p.ProgramGeneration()
	if after-before != 2 {
		t.Fatalf("generation moved %d, want 2", after-before)
	}
}

func TestNotificationsAreTakenOnceInOrder(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b]9;hello\x07\x1b]777;notify;Build;done\x07\x1b]99;;Kitty\x1b\\")
	got, err := p.TakeNotifications()
	if err != nil {
		t.Fatalf("take: %v", err)
	}
	want := []Notification{{Title: "", Body: "hello"}, {Title: "Build", Body: "done"}, {Title: "Kitty", Body: ""}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("notifications = %#v, want %#v", got, want)
	}
	again, err := p.TakeNotifications()
	if err != nil || len(again) != 0 {
		t.Fatalf("second take = %#v, %v; want none", again, err)
	}
}

func TestTheMirrorAnswersSizeAndColourQueries(t *testing.T) {
	p := newTestParser(t, 100, 30)
	if _, err := p.TakeQueryReplies(); err != nil {
		t.Fatalf("drain: %v", err)
	}
	feed(t, p, "\x1b[18t\x1b[16t\x1b]11;?\x07")
	replies, _ := p.TakeQueryReplies()
	if !bytes.Equal(replies, []byte("\x1b[8;30;100t")) {
		t.Fatalf("replies before appearance = %q", replies)
	}
	if err := p.SetCellPixels(9, 18); err != nil {
		t.Fatalf("cell pixels: %v", err)
	}
	if err := p.SetDefaultColors(0xd8dee9, 0x0a0b0d); err != nil {
		t.Fatalf("colours: %v", err)
	}
	feed(t, p, "\x1b[14t\x1b[16t\x1b]10;?\x07\x1b]11;?\x1b\\")
	replies, _ = p.TakeQueryReplies()
	want := "\x1b[4;540;900t\x1b[6;18;9t\x1b]10;rgb:d8d8/dede/e9e9\x07\x1b]11;rgb:0a0a/0b0b/0d0d\x1b\\"
	if string(replies) != want {
		t.Fatalf("replies = %q, want %q", replies, want)
	}
	if err := p.SetDefaultColors(-1, -1); err != nil {
		t.Fatalf("clear colours: %v", err)
	}
	feed(t, p, "\x1b]10;?\x07")
	if replies, _ := p.TakeQueryReplies(); len(replies) != 0 {
		t.Fatalf("cleared colours still answered: %q", replies)
	}
}

func TestMode2048ReportsOnResize(t *testing.T) {
	p := newTestParser(t, 80, 24)
	if err := p.SetCellPixels(8, 16); err != nil {
		t.Fatalf("cell pixels: %v", err)
	}
	_, _ = p.TakeQueryReplies()
	feed(t, p, "\x1b[?2048h")
	if replies, _ := p.TakeQueryReplies(); string(replies) != "\x1b[48;24;80;384;640t" {
		t.Fatalf("enable report = %q", replies)
	}
	if err := p.Resize(100, 30); err != nil {
		t.Fatalf("resize: %v", err)
	}
	if replies, _ := p.TakeQueryReplies(); string(replies) != "\x1b[48;30;100;480;800t" {
		t.Fatalf("resize report = %q", replies)
	}
}

func TestTheClaudeRecordingEndsOnItsIdleTitle(t *testing.T) {
	fixture := filepath.Join("..", "..", "..", "..", "..", "..", "packages", "terminal", "bench", "agent-session", "fixtures", "claude-long-50k")
	recording, sizes := readAgentFixture(t, fixture)
	p := feedAgentFixture(t, recording, sizes, productMirrorLimits)
	defer p.Close()
	title, err := p.Title()
	if err != nil {
		t.Fatalf("title: %v", err)
	}
	if title != "✳ Number list 1 to 3000" {
		t.Fatalf("final title = %q", title)
	}
	notes, err := p.TakeNotifications()
	if err != nil || len(notes) != 0 {
		t.Fatalf("notifications = %#v, %v; want none", notes, err)
	}
}

func TestAnAgentEventIsNeitherATitleNorANotificationInTheMirror(t *testing.T) {
	p := newTestParser(t, 80, 24)
	feed(t, p, "\x1b]2;kept\x07\x1b]777;agent-state;v=1;state=waiting;detail=Allow%20Bash%3F\x07after")
	title, err := p.Title()
	if err != nil || title != "kept" {
		t.Fatalf("title = %q, %v; want kept", title, err)
	}
	notes, err := p.TakeNotifications()
	if err != nil || len(notes) != 0 {
		t.Fatalf("notifications = %#v, %v; want none", notes, err)
	}
	text, err := p.RenderTail(5)
	if err != nil || !strings.Contains(text, "after") || strings.Contains(text, "agent-state") {
		t.Fatalf("output = %q, %v; want only the text around the event", text, err)
	}
}
