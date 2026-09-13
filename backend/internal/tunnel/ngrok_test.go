package tunnel

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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

	got, err := NgrokProvider(NgrokConfig{}).PublicURL(context.Background(), controlPortOf(t, srv))
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

	if _, err := NgrokProvider(NgrokConfig{}).PublicURL(context.Background(), controlPortOf(t, srv)); !errors.Is(err, ErrNoURLYet) {
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

	ok, err := NgrokProvider(NgrokConfig{}).Healthy(context.Background(), controlPortOf(t, srv))
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

	ok, err := NgrokProvider(NgrokConfig{}).Healthy(context.Background(), controlPortOf(t, srv))
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
	got := NgrokProvider(NgrokConfig{}).ClassifyFailure(lines)
	if got.Class != FailureCredential {
		t.Errorf("class = %v, want FailureCredential", got.Class)
	}
	if got.Message == "" {
		t.Error("want the provider's own error text carried through")
	}
}

func TestNgrokClassifyFailureRefusedCarriesUnknownErrorVerbatim(t *testing.T) {
	lines := []string{`{"err":"account limit exceeded: ERR_NGROK_9999","lvl":"eror","msg":"session closing"}`}
	got := NgrokProvider(NgrokConfig{}).ClassifyFailure(lines)
	if got.Class != FailureRefused {
		t.Errorf("class = %v, want FailureRefused", got.Class)
	}
	if got.Message != "account limit exceeded: ERR_NGROK_9999" {
		t.Errorf("message = %q, want the err field verbatim", got.Message)
	}
}

func TestNgrokClassifyFailureUnknownWithoutAnyError(t *testing.T) {
	lines := []string{`{"lvl":"info","msg":"tunnel session started"}`}
	if got := NgrokProvider(NgrokConfig{}).ClassifyFailure(lines); got.Class != FailureUnknown {
		t.Errorf("class = %v, want FailureUnknown", got.Class)
	}
}

func TestNgrokArgsPointAtLocalPortAndOurConfigs(t *testing.T) {
	dir := t.TempDir()
	userPath := filepath.Join(dir, "user-ngrok.yml")
	ownPath := filepath.Join(dir, "own-ngrok.yml")
	if err := os.WriteFile(userPath, []byte("version: \"3\"\n"), 0o600); err != nil {
		t.Fatalf("seed user config: %v", err)
	}

	args := NgrokProvider(NgrokConfig{UserConfigPath: userPath, OwnConfigPath: ownPath}).Args(3011, 50893)
	joined := " " + stringsJoin(args, " ") + " "
	for _, want := range []string{" http ", " 3011 ", " --config " + userPath + " ", " --config " + ownPath + " ", " --log=stdout ", " --log-format=json ", " --inspect=false "} {
		if !containsString(joined, want) {
			t.Errorf("args %v missing %q", args, want)
		}
	}
	if indexOf(joined, userPath) > indexOf(joined, ownPath) {
		t.Errorf("args %v put our config before the user's; the user's must come first so ours wins on web_addr", args)
	}
}

func TestNgrokArgsOmitAMissingUserConfig(t *testing.T) {
	dir := t.TempDir()
	missing := filepath.Join(dir, "no-such-ngrok.yml")
	ownPath := filepath.Join(dir, "own-ngrok.yml")

	args := NgrokProvider(NgrokConfig{UserConfigPath: missing, OwnConfigPath: ownPath}).Args(3011, 50893)
	if containsString(stringsJoin(args, " "), missing) {
		t.Errorf("args %v reference a config file that does not exist; ngrok exits on that", args)
	}
	if !containsString(stringsJoin(args, " "), ownPath) {
		t.Errorf("args %v dropped our own config", args)
	}
}

func TestNgrokPrepareWritesTheWebAddrIntoTheConfigArgsPointAt(t *testing.T) {
	ownPath := filepath.Join(t.TempDir(), "mobile", "ngrok.yml")
	provider := NgrokProvider(NgrokConfig{OwnConfigPath: ownPath})

	const controlPort = 50893
	preparer, ok := provider.(launchPreparer)
	if !ok {
		t.Fatal("the ngrok provider must prepare its config before every launch")
	}
	if err := preparer.Prepare(3011, controlPort); err != nil {
		t.Fatalf("Prepare: %v", err)
	}

	configPath := configPathFromArgs(t, provider.Args(3011, controlPort))
	body, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("read the config --config points at: %v", err)
	}
	want := fmt.Sprintf("web_addr: 127.0.0.1:%d", controlPort)
	if !strings.Contains(string(body), want) {
		t.Fatalf("config at %s = %q, want it to carry %q: the agent API must move to the port the manager polls", configPath, body, want)
	}
}

func TestNgrokPrepareKeepsAnExistingAuthtokenAndRewritesTheWebAddr(t *testing.T) {
	ownPath := filepath.Join(t.TempDir(), "ngrok.yml")
	seeded := "version: \"3\"\nagent:\n    authtoken: 2secretTokenValue\n    web_addr: 127.0.0.1:4040\n"
	if err := os.WriteFile(ownPath, []byte(seeded), 0o600); err != nil {
		t.Fatalf("seed: %v", err)
	}
	provider := NgrokProvider(NgrokConfig{OwnConfigPath: ownPath})

	preparer, _ := provider.(launchPreparer)
	if err := preparer.Prepare(3011, 51111); err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	body, err := os.ReadFile(ownPath)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	got := string(body)
	if !strings.Contains(got, "authtoken: 2secretTokenValue") {
		t.Errorf("config = %q, want the saved authtoken preserved", got)
	}
	if !strings.Contains(got, "web_addr: 127.0.0.1:51111") {
		t.Errorf("config = %q, want the new web_addr", got)
	}
	if strings.Contains(got, "127.0.0.1:4040") {
		t.Errorf("config = %q, want the stale web_addr replaced, not duplicated", got)
	}
	if strings.Count(got, "agent:") != 1 {
		t.Errorf("config = %q, want exactly one agent block", got)
	}
}

func TestNgrokPrepareRewritesTheWebAddrOnEveryLaunch(t *testing.T) {
	ownPath := filepath.Join(t.TempDir(), "ngrok.yml")
	provider := NgrokProvider(NgrokConfig{OwnConfigPath: ownPath})
	preparer, _ := provider.(launchPreparer)

	for _, port := range []int{50001, 50002} {
		if err := preparer.Prepare(3011, port); err != nil {
			t.Fatalf("Prepare(%d): %v", port, err)
		}
		body, err := os.ReadFile(configPathFromArgs(t, provider.Args(3011, port)))
		if err != nil {
			t.Fatalf("read: %v", err)
		}
		if want := fmt.Sprintf("web_addr: 127.0.0.1:%d", port); !strings.Contains(string(body), want) {
			t.Fatalf("after Prepare(%d) config = %q, want %q", port, body, want)
		}
	}
}

func configPathFromArgs(t *testing.T, args []string) string {
	t.Helper()
	path := ""
	for i, arg := range args {
		if arg == "--config" && i+1 < len(args) {
			path = args[i+1]
		}
	}
	if path == "" {
		t.Fatalf("args %v carry no --config", args)
	}
	return path
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
