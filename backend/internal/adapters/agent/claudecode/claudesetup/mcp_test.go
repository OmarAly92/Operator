package claudesetup

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func testReadObject(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]any{}
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestSyncMCPReplacesOnlyServers(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{"mcpServers":{"pencil":{"command":"pencil"}},"oauthAccount":{"accountUuid":"work"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(acct, []byte(`{"mcpServers":{"old":{}},"oauthAccount":{"accountUuid":"personal"},"userID":"u-2"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	got := testReadObject(t, acct)
	servers := got["mcpServers"].(map[string]any)
	if _, ok := servers["pencil"]; !ok || len(servers) != 1 {
		t.Fatalf("mcpServers = %v", servers)
	}
	if got["oauthAccount"].(map[string]any)["accountUuid"] != "personal" || got["userID"] != "u-2" {
		t.Fatalf("login fields changed: %v", got)
	}
}

func TestSyncMCPCreatesMissingAccountConfig(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{"mcpServers":{"pencil":{}}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	if _, ok := testReadObject(t, acct)["mcpServers"].(map[string]any)["pencil"]; !ok {
		t.Fatal("pencil not copied")
	}
}

func TestSyncMCPNoServersNoWrite(t *testing.T) {
	dir := t.TempDir()
	def := filepath.Join(dir, "default.json")
	acct := filepath.Join(dir, "account.json")
	if err := os.WriteFile(def, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SyncMCP(def, acct); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(acct); !os.IsNotExist(err) {
		t.Fatalf("account config written without servers: %v", err)
	}
}
