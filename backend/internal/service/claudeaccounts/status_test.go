package claudeaccounts

import "testing"

func TestParseAuthStatus(t *testing.T) {
	out := []byte("warning: x\n{\"loggedIn\":true,\"subscriptionType\":\"max\",\"email\":\"a@b.c\"}\n")
	status, ok := parseAuthStatus(out)
	if !ok || status.LoggedIn == nil || !*status.LoggedIn || status.SubscriptionType != "max" || status.ReportedEmail != "a@b.c" {
		t.Fatalf("status = %+v ok=%v", status, ok)
	}
	status, ok = parseAuthStatus([]byte(`{"loggedIn":false,"authMethod":"none"}`))
	if !ok || status.LoggedIn == nil || *status.LoggedIn {
		t.Fatalf("logged out = %+v ok=%v", status, ok)
	}
	if _, ok := parseAuthStatus([]byte("garbage")); ok {
		t.Fatal("garbage parsed")
	}
}

func TestProcessEnvDropsInheritedConfigDir(t *testing.T) {
	base := []string{"PATH=/bin", "CLAUDE_CONFIG_DIR=/inherited", "HOME=/h"}
	got := processEnv(base, map[string]string{})
	for _, kv := range got {
		if kv == "CLAUDE_CONFIG_DIR=/inherited" {
			t.Fatalf("inherited value kept: %v", got)
		}
	}
	got = processEnv(base, map[string]string{"CLAUDE_CONFIG_DIR": "/acct"})
	found := false
	for _, kv := range got {
		if kv == "CLAUDE_CONFIG_DIR=/acct" {
			found = true
		}
	}
	if !found {
		t.Fatalf("account value missing: %v", got)
	}
}
