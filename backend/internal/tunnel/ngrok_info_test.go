package tunnel

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestParseNgrokLogLinesRedactsSecretsAndKeepsPlainLines(t *testing.T) {
	lines := []string{
		`{"t":"2026-09-19T20:05:59.864169+03:00","lvl":"eror","msg":"failed to reconnect session","err":"bad token sekret123"}`,
		`{"t":"2026-09-19T20:06:00.1+03:00","lvl":"info","msg":"open config file","err":"<nil>"}`,
		`plain text line`,
	}
	got := parseNgrokLogLines(lines, "sekret123")
	if len(got) != 3 {
		t.Fatalf("len = %d", len(got))
	}
	if got[0].Level != "eror" || got[0].Message != "failed to reconnect session: bad token [redacted]" {
		t.Errorf("line 0 = %+v", got[0])
	}
	if got[1].Message != "open config file" {
		t.Errorf("line 1 must drop a nil err, got %+v", got[1])
	}
	if got[2].Level != "" || got[2].Message != "plain text line" || got[2].Time != "" {
		t.Errorf("line 2 = %+v", got[2])
	}
}

func TestNgrokInfoReportsCredentialSourceAndSuffix(t *testing.T) {
	dir := t.TempDir()
	system := filepath.Join(dir, "system.yml")
	if err := os.WriteFile(system, []byte("version: \"3\"\nagent:\n    authtoken: systok_abcd\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := New(Deps{Dir: dir, Binaries: fakeStore{}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{UserConfigPath: system, OwnConfigPath: filepath.Join(dir, "ngrok.yml")}),
	}})
	info := m.NgrokInfo(context.Background())
	if !info.Credential.Present || info.Credential.Source != "system" || info.Credential.Suffix != "abcd" {
		t.Fatalf("credential = %+v", info.Credential)
	}
	if info.Credential.SystemConfigPath != system {
		t.Errorf("SystemConfigPath = %q", info.Credential.SystemConfigPath)
	}
	if err := os.WriteFile(filepath.Join(dir, "ngrok.yml"), []byte("version: \"3\"\nagent:\n    authtoken: optok_wxyz\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	info = m.NgrokInfo(context.Background())
	if info.Credential.Source != "operator" || info.Credential.Suffix != "wxyz" {
		t.Fatalf("operator token must win: %+v", info.Credential)
	}
}

func TestNgrokInfoReadsTheControlAPI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/status":
			_, _ = w.Write([]byte(`{"status":"online","agent_version":"3.39.6","session":{"legs":[{"region":"eu","latency":61600000}]}}`))
		case "/api/tunnels":
			_, _ = w.Write([]byte(`{"tunnels":[{"public_url":"https://x.ngrok.app","metrics":{"conns":{"count":4},"http":{"count":9}}}]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	port := controlPortOf(t, srv)
	got := readNgrokSession(context.Background(), port)
	if got.Status != "online" || got.Region != "eu" || got.Latency != "62ms" || got.PublicURL != "https://x.ngrok.app" || got.Connections != 4 || got.HTTPRequests != 9 {
		t.Fatalf("session = %+v", got)
	}
}
