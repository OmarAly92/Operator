package tunnel

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeNgrokAPI struct {
	t       *testing.T
	key     string
	created []string
	deleted []string
	server  *httptest.Server
}

func newFakeNgrokAPI(t *testing.T, key string) *fakeNgrokAPI {
	f := &fakeNgrokAPI{t: t, key: key}
	f.server = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.server.Close)
	prev := ngrokAPIBase
	ngrokAPIBase = f.server.URL
	t.Cleanup(func() { ngrokAPIBase = prev })
	return f
}

func (f *fakeNgrokAPI) handle(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Ngrok-Version") != "2" {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if r.Header.Get("Authorization") != "Bearer "+f.key {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error_code":"ERR_NGROK_10005","msg":"Invalid API key"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json")
	switch {
	case r.Method == http.MethodGet && r.URL.Path == "/api_keys":
		_, _ = w.Write([]byte(`{"keys":[{"id":"ak_1","created_at":"2026-09-01T00:00:00Z"}]}`))
	case r.Method == http.MethodGet && r.URL.Path == "/credentials":
		_, _ = w.Write([]byte(`{"credentials":[{"id":"cr_old","description":"` + operatorCredentialDescription() + `","created_at":"2026-08-01T00:00:00Z"},{"id":"cr_other","description":"laptop","created_at":"2026-07-01T00:00:00Z"}]}`))
	case r.Method == http.MethodPost && r.URL.Path == "/credentials":
		var body struct {
			Description string `json:"description"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		f.created = append(f.created, body.Description)
		_, _ = w.Write([]byte(`{"id":"cr_new","token":"2mintedtoken_zz99","description":"` + body.Description + `"}`))
	case r.Method == http.MethodDelete && strings.HasPrefix(r.URL.Path, "/credentials/"):
		f.deleted = append(f.deleted, strings.TrimPrefix(r.URL.Path, "/credentials/"))
		w.WriteHeader(http.StatusNoContent)
	case r.Method == http.MethodGet && r.URL.Path == "/tunnel_sessions":
		_, _ = w.Write([]byte(`{"tunnel_sessions":[{"id":"ts_1","region":"eu","ip":"1.2.3.4","agent_version":"3.39.6","os":"darwin","started_at":"2026-09-19T17:00:00Z"}]}`))
	case r.Method == http.MethodGet && r.URL.Path == "/endpoints":
		_, _ = w.Write([]byte(`{"endpoints":[{"id":"ep_1","public_url":"https://a.ngrok.app","proto":"https","created_at":"2026-09-19T17:00:01Z"}]}`))
	case r.Method == http.MethodGet && r.URL.Path == "/reserved_domains":
		_, _ = w.Write([]byte(`{"reserved_domains":[{"id":"rd_1","domain":"phone.example.ngrok.app"}]}`))
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func newAPIKeyManager(t *testing.T) (*Manager, string) {
	t.Helper()
	dir := t.TempDir()
	m := New(Deps{Dir: dir, Binaries: fakeStore{path: "/bin/sh"}, Now: time.Now, Providers: []Provider{
		NgrokProvider(NgrokConfig{OwnConfigPath: filepath.Join(dir, "ngrok.yml")}),
	}})
	return m, dir
}

func TestSetAPIKeyVerifiesBeforeStoring(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, dir := newAPIKeyManager(t)
	if err := m.SetAPIKey(context.Background(), "bad"); err == nil || !errors.Is(err, ErrNgrokAPIUnauthorized) {
		t.Fatalf("want ErrNgrokAPIUnauthorized, got %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "ngrok-api-key")); !os.IsNotExist(err) {
		t.Fatal("a rejected key must not be written")
	}
	if err := m.SetAPIKey(context.Background(), " good \n"); err != nil {
		t.Fatalf("SetAPIKey: %v", err)
	}
	info, err := os.Stat(filepath.Join(dir, "ngrok-api-key"))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("key file: %v mode %v", err, info.Mode())
	}
	if key, _ := m.readAPIKey(); key != "good" {
		t.Errorf("readAPIKey = %q", key)
	}
	if err := m.RemoveAPIKey(); err != nil {
		t.Fatal(err)
	}
	if key, _ := m.readAPIKey(); key != "" {
		t.Error("key must be gone")
	}
}

func TestNgrokAccountAggregatesTheFourLists(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, _ := newAPIKeyManager(t)
	if acc := m.NgrokAccount(context.Background()); acc.Valid || acc.Error == "" {
		t.Fatalf("without a key the account must be invalid with a reason: %+v", acc)
	}
	_ = m.SetAPIKey(context.Background(), "good")
	acc := m.NgrokAccount(context.Background())
	if !acc.Valid {
		t.Fatalf("account = %+v", acc)
	}
	if len(acc.Credentials) != 2 || !acc.Credentials[0].IsOperator || acc.Credentials[1].IsOperator {
		t.Errorf("credentials = %+v", acc.Credentials)
	}
	if len(acc.Sessions) != 1 || acc.Sessions[0].Region != "eu" {
		t.Errorf("sessions = %+v", acc.Sessions)
	}
	if len(acc.Endpoints) != 1 || acc.Endpoints[0].PublicURL != "https://a.ngrok.app" {
		t.Errorf("endpoints = %+v", acc.Endpoints)
	}
	if len(acc.ReservedDomains) != 1 || acc.ReservedDomains[0].Domain != "phone.example.ngrok.app" {
		t.Errorf("domains = %+v", acc.ReservedDomains)
	}
}

func TestMintOperatorCredentialStoresTheTokenAndRevokesThePreviousOne(t *testing.T) {
	api := newFakeNgrokAPI(t, "good")
	m, dir := newAPIKeyManager(t)
	_ = m.SetAPIKey(context.Background(), "good")
	if err := m.MintOperatorCredential(context.Background()); err != nil {
		t.Fatalf("Mint: %v", err)
	}
	if len(api.created) != 1 || api.created[0] != operatorCredentialDescription() {
		t.Errorf("created = %v", api.created)
	}
	if len(api.deleted) != 1 || api.deleted[0] != "cr_old" {
		t.Errorf("deleted = %v, want the previous Operator credential only", api.deleted)
	}
	body, _ := os.ReadFile(filepath.Join(dir, "ngrok.yml"))
	if !strings.Contains(string(body), "authtoken: 2mintedtoken_zz99") {
		t.Errorf("minted token must be stored, got %q", body)
	}
	if !m.HasAuthtoken() {
		t.Error("HasAuthtoken must be true after minting")
	}
}

func TestSetStableDomainRequiresAReservedDomain(t *testing.T) {
	newFakeNgrokAPI(t, "good")
	m, _ := newAPIKeyManager(t)
	_ = m.SetAPIKey(context.Background(), "good")
	if err := m.SetStableDomain(context.Background(), "not-mine.ngrok.app"); err == nil {
		t.Fatal("an unreserved domain must be rejected")
	}
	if err := m.SetStableDomain(context.Background(), "phone.example.ngrok.app"); err != nil {
		t.Fatalf("SetStableDomain: %v", err)
	}
	if m.NgrokDomain() != "phone.example.ngrok.app" {
		t.Error("domain not applied")
	}
	if err := m.SetStableDomain(context.Background(), ""); err != nil || m.NgrokDomain() != "" {
		t.Errorf("clearing: err=%v domain=%q", err, m.NgrokDomain())
	}
}
