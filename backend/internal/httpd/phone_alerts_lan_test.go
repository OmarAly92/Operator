package httpd

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/coder/websocket/wsjson"

	"github.com/OmarAly92/operator/backend/internal/config"
	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/mobilebridge"
	"github.com/OmarAly92/operator/backend/internal/notify"
	"github.com/OmarAly92/operator/backend/internal/push"
	"github.com/OmarAly92/operator/backend/internal/terminal"
)

type ntfyRequest struct {
	path, title, click, priority, tags, body string
}

func (r ntfyRequest) String() string {
	return fmt.Sprintf("path=%q title=%q click=%q priority=%q tags=%q body=%q", r.path, r.title, r.click, r.priority, r.tags, r.body)
}

func fakeNtfy(t *testing.T) (*httptest.Server, <-chan ntfyRequest) {
	t.Helper()
	got := make(chan ntfyRequest, 64)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		got <- ntfyRequest{path: r.URL.Path, title: r.Header.Get("Title"), click: r.Header.Get("Click"), priority: r.Header.Get("Priority"), tags: r.Header.Get("Tags"), body: string(b)}
	}))
	t.Cleanup(srv.Close)
	return srv, got
}

func nextNtfy(t *testing.T, got <-chan ntfyRequest) ntfyRequest {
	t.Helper()
	select {
	case r := <-got:
		return r
	case <-time.After(5 * time.Second):
		t.Fatal("no ntfy request arrived")
		return ntfyRequest{}
	}
}

func lanRequest(t *testing.T, method string, port int, path, password string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(method, fmt.Sprintf("http://127.0.0.1:%d%s", port, path), nil)
	if err != nil {
		t.Fatal(err)
	}
	if password != "" {
		req.Header.Set("Authorization", "Bearer "+password)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var body map[string]any
	_ = json.NewDecoder(res.Body).Decode(&body)
	return res.StatusCode, body
}

func TestPhoneAlertsThroughTheLANListenerAndTheRealHub(t *testing.T) {
	const password = "secret12"
	topic := strings.Repeat("a", mobilebridge.AlertTopicLength)
	cfgPath := filepath.Join(t.TempDir(), "mobile", "config.json")
	if err := mobilebridge.Save(cfgPath, mobilebridge.State{Enabled: true, Password: password, AlertTopic: topic}); err != nil {
		t.Fatal(err)
	}

	ntfy, sent := fakeNtfy(t)
	hub := notify.NewHub()
	mgr := terminal.NewManager(nil, nil, discardLogger(), terminal.WithHeartbeat(0), terminal.WithNotificationFeed(hub))
	defer mgr.Close()
	writer := notify.New(notify.Deps{Store: memoryNotificationStore{}, Publisher: hub})
	alerts := push.NewAlerts(push.AlertsDeps{
		Subscriber: hub,
		Sender:     push.NewNtfySender(ntfy.URL, nil),
		ConfigPath: cfgPath,
		Presence:   mgr,
		Log:        discardLogger(),
	})

	router := NewRouterWithControl(config.Config{}, discardLogger(), mgr, APIDeps{PhoneAlerts: alerts, NotificationStream: hub}, ControlDeps{})
	st := &authState{}
	st.setHash(mobilebridge.HashPassword(password))
	lan := NewLANManager(router, st, 0, discardLogger(), nil)
	port, err := lan.Start(0)
	if err != nil {
		t.Fatalf("start: %v", err)
	}
	defer lan.Stop(context.Background())
	alerts.SetBridge(lan)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	go alerts.Run(ctx)

	notifyTurn := func(typ domain.NotificationType, session string) {
		t.Helper()
		err := writer.Notify(ctx, notify.Intent{
			Type:               typ,
			SessionID:          domain.SessionID(session),
			ProjectID:          "mer",
			SessionDisplayName: "split fix",
			AssistantUpdate:    "Implemented X in /secret/path.go",
		})
		if err != nil {
			t.Fatalf("notify: %v", err)
		}
	}

	if code, _ := lanRequest(t, http.MethodPost, port, "/api/v1/phone-alerts/subscribe", ""); code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated subscribe = %d, want 401", code)
	}
	if code, body := lanRequest(t, http.MethodGet, port, "/api/v1/phone-alerts", password); code != http.StatusOK || body["enabled"] != true || body["claimed"] != false {
		t.Fatalf("status before claim = %d %v", code, body)
	}

	code, body := lanRequest(t, http.MethodPost, port, "/api/v1/phone-alerts/subscribe", password)
	if code != http.StatusOK || body["topic"] != topic || body["server"] != push.DefaultNtfyServer {
		t.Fatalf("subscribe = %d %v", code, body)
	}

	var probe string
	probeDeadline := time.Now().Add(10 * time.Second)
	for i := 0; ; i++ {
		if time.Now().After(probeDeadline) {
			t.Fatal("alert runner never delivered a probe alert")
		}
		probe = fmt.Sprintf("probe-%d", i)
		notifyTurn(domain.NotificationTurnFinished, probe)
		select {
		case r := <-sent:
			for r.click != "operator://session/"+probe {
				r = nextNtfy(t, sent)
			}
		case <-time.After(100 * time.Millisecond):
			continue
		}
		break
	}

	notifyTurn(domain.NotificationTurnFinished, "mer-1")
	r := nextNtfy(t, sent)
	if r.path != "/"+topic || r.title != "split fix finished" || r.body != "finished" || r.click != "operator://session/mer-1" || r.priority != "default" || r.tags != "robot" {
		t.Fatalf("turn finished request: %s", r)
	}
	if strings.Contains(r.String(), "secret") || strings.Contains(r.String(), "Implemented") {
		t.Fatalf("request leaked assistant text: %s", r)
	}

	header := http.Header{}
	header.Set("Authorization", "Bearer "+password)
	c, _, err := websocket.Dial(ctx, fmt.Sprintf("ws://127.0.0.1:%d/mux", port), &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatalf("dial LAN /mux: %v", err)
	}
	if err := wsjson.Write(ctx, c, map[string]string{"ch": "notifications", "type": "subscribe"}); err != nil {
		t.Fatalf("subscribe: %v", err)
	}
	waitFor(t, 2*time.Second, mgr.PhoneForeground)
	notifyTurn(domain.NotificationNeedsInput, "mer-2")
	time.Sleep(200 * time.Millisecond)
	_ = c.Close(websocket.StatusNormalClosure, "backgrounded")
	waitFor(t, 2*time.Second, func() bool { return !mgr.PhoneForeground() })

	notifyTurn(domain.NotificationNeedsInput, "mer-3")
	r = nextNtfy(t, sent)
	if r.click != "operator://session/mer-3" || r.title != "split fix needs your input" || r.body != "needs input" || r.priority != "high" {
		t.Fatalf("after backgrounding, want mer-3 (mer-2 skipped while foreground): %s", r)
	}

	code, body = lanRequest(t, http.MethodGet, port, "/api/v1/phone-alerts", password)
	last, _ := body["lastDelivery"].(map[string]any)
	if code != http.StatusOK || body["claimed"] != true || last == nil || last["ok"] != true {
		t.Fatalf("status after deliveries = %d %v", code, body)
	}
	if _, leaked := body["topic"]; leaked {
		t.Fatalf("status exposed the topic: %v", body)
	}
}
