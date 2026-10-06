package push

import (
	"context"
	"io"
	"mime"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestNtfySendsTitleMessageAndClick(t *testing.T) {
	var gotPath, gotTitle, gotClick, gotPriority, gotBody string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotTitle = r.Header.Get("Title")
		gotClick = r.Header.Get("Click")
		gotPriority = r.Header.Get("Priority")
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
	}))
	defer srv.Close()
	s := NewNtfySender(srv.URL, srv.Client())
	err := s.Send(context.Background(), "topic123", Alert{Click: "operator://session/operator-4", Title: "split fix finished", Message: "finished", Priority: "high"})
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != "/topic123" || gotTitle != "split fix finished" || gotBody != "finished" || gotClick != "operator://session/operator-4" || gotPriority != "high" {
		t.Fatalf("path=%q title=%q click=%q priority=%q body=%q", gotPath, gotTitle, gotClick, gotPriority, gotBody)
	}
}

func TestNtfyDefaultsThePriority(t *testing.T) {
	var gotPriority string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPriority = r.Header.Get("Priority")
	}))
	defer srv.Close()
	if err := NewNtfySender(srv.URL, srv.Client()).Send(context.Background(), "t", Alert{Title: "x", Message: "y"}); err != nil {
		t.Fatal(err)
	}
	if gotPriority != "default" {
		t.Fatalf("priority = %q, want default", gotPriority)
	}
}

func TestNtfyRetriesOnceThenReportsTheStatus(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()
	s := NewNtfySender(srv.URL, srv.Client())
	s.retryDelay = time.Millisecond
	err := s.Send(context.Background(), "t", Alert{Title: "x", Message: "y"})
	if err == nil || calls.Load() != 2 {
		t.Fatalf("err=%v calls=%d, want an error after 2 calls", err, calls.Load())
	}
}

func TestNtfyEncodesNonASCIITitles(t *testing.T) {
	var raw string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw = r.Header.Get("Title")
	}))
	defer srv.Close()
	if err := NewNtfySender(srv.URL, srv.Client()).Send(context.Background(), "t", Alert{Title: "café fix finished", Message: "finished"}); err != nil {
		t.Fatal(err)
	}
	decoded, err := new(mime.WordDecoder).DecodeHeader(raw)
	if err != nil || decoded != "café fix finished" || raw == decoded {
		t.Fatalf("raw=%q decoded=%q err=%v", raw, decoded, err)
	}
}
