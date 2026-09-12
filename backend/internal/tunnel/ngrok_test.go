package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
)

func controlPortOf(t *testing.T, srv *httptest.Server) int {
	t.Helper()
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parse test server url: %v", err)
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		t.Fatalf("parse test server port: %v", err)
	}
	return port
}

func TestNgrokPublicURL(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/tunnels" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"tunnels":[{"name":"command_line","public_url":"https://imagines-livestock-widely.ngrok-free.dev","proto":"https"}]}`))
	}))
	defer srv.Close()

	got, err := NgrokProvider(nil).PublicURL(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("PublicURL: %v", err)
	}
	if want := "https://imagines-livestock-widely.ngrok-free.dev"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestNgrokPublicURLEmptyTunnelsIsNotReadyYet(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"tunnels":[]}`))
	}))
	defer srv.Close()

	if _, err := NgrokProvider(nil).PublicURL(context.Background(), controlPortOf(t, srv)); err != ErrNoURLYet {
		t.Fatalf("got %v, want ErrNoURLYet", err)
	}
}

func TestNgrokHealthyReadsSessionStatus(t *testing.T) {
	body := `{"status":"online","agent_version":"3.39.6","session":{"legs":[{"region":"eu","latency":"0ms"}]}}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/status" {
			t.Errorf("unexpected path %q", r.URL.Path)
		}
		_, _ = w.Write([]byte(body))
	}))
	defer srv.Close()

	ok, err := NgrokProvider(nil).Healthy(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Healthy: %v", err)
	}
	if !ok {
		t.Error("want healthy for status online")
	}
}

func TestNgrokHealthyFalseWhenNotOnline(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"status":"reconnecting"}`))
	}))
	defer srv.Close()

	ok, err := NgrokProvider(nil).Healthy(context.Background(), controlPortOf(t, srv))
	if err != nil {
		t.Fatalf("Healthy: %v", err)
	}
	if ok {
		t.Error("want not healthy for status reconnecting")
	}
}

func TestNgrokClassifyFailureCredential(t *testing.T) {
	lines := []string{
		`{"lvl":"info","msg":"starting web service","obj":"web"}`,
		`{"err":"authentication failed: This ngrok session is not authenticated. ngrok requires an account and a valid credential to start a session.\n\nERR_NGROK_4018\r\n","lvl":"eror","msg":"failed to reconnect session"}`,
	}
	got := NgrokProvider(nil).ClassifyFailure(lines)
	if got.Class != FailureCredential {
		t.Errorf("class = %v, want FailureCredential", got.Class)
	}
	if got.Message == "" {
		t.Error("want the provider's own error text carried through")
	}
}

func TestNgrokClassifyFailureRefusedCarriesUnknownErrorVerbatim(t *testing.T) {
	lines := []string{`{"err":"account limit exceeded: ERR_NGROK_9999","lvl":"eror","msg":"session closing"}`}
	got := NgrokProvider(nil).ClassifyFailure(lines)
	if got.Class != FailureRefused {
		t.Errorf("class = %v, want FailureRefused", got.Class)
	}
	if got.Message != "account limit exceeded: ERR_NGROK_9999" {
		t.Errorf("message = %q, want the err field verbatim", got.Message)
	}
}

func TestNgrokClassifyFailureUnknownWithoutAnyError(t *testing.T) {
	lines := []string{`{"lvl":"info","msg":"tunnel session started"}`}
	if got := NgrokProvider(nil).ClassifyFailure(lines); got.Class != FailureUnknown {
		t.Errorf("class = %v, want FailureUnknown", got.Class)
	}
}

func TestNgrokArgsPointAtLocalPortAndOurConfigs(t *testing.T) {
	args := NgrokProvider([]string{"/u/ngrok.yml", "/o/ngrok.yml"}).Args(3011, 50893)
	joined := " " + stringsJoin(args, " ") + " "
	for _, want := range []string{" http ", " 3011 ", " --config /u/ngrok.yml ", " --config /o/ngrok.yml ", " --log=stdout ", " --log-format=json ", " --inspect=false "} {
		if !containsString(joined, want) {
			t.Errorf("args %v missing %q", args, want)
		}
	}
}

func stringsJoin(parts []string, sep string) string {
	out := ""
	for i, p := range parts {
		if i > 0 {
			out += sep
		}
		out += p
	}
	return out
}

func containsString(haystack, needle string) bool {
	return len(needle) <= len(haystack) && indexOf(haystack, needle) >= 0
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}
