package domain

import "testing"

func TestClaudeAccountApplyEnvDefaultRemovesKey(t *testing.T) {
	env := map[string]string{ClaudeConfigDirEnv: "/project/override", "PATH": "/bin"}
	ClaudeAccount{ID: DefaultClaudeAccountID, IsDefault: true}.ApplyEnv(env)
	if _, ok := env[ClaudeConfigDirEnv]; ok {
		t.Fatalf("default account left %s in env: %q", ClaudeConfigDirEnv, env[ClaudeConfigDirEnv])
	}
	if env["PATH"] != "/bin" {
		t.Fatalf("PATH changed: %q", env["PATH"])
	}
}

func TestClaudeAccountApplyEnvSetsExactFolder(t *testing.T) {
	env := map[string]string{ClaudeConfigDirEnv: "/project/override"}
	ClaudeAccount{ID: "personal", ConfigDir: "/Users/u/.claude-personal"}.ApplyEnv(env)
	if got := env[ClaudeConfigDirEnv]; got != "/Users/u/.claude-personal" {
		t.Fatalf("%s = %q", ClaudeConfigDirEnv, got)
	}
}

func TestNormalizeClaudeAccountID(t *testing.T) {
	if got := NormalizeClaudeAccountID(""); got != DefaultClaudeAccountID {
		t.Fatalf("empty -> %q", got)
	}
	if got := NormalizeClaudeAccountID("personal"); got != "personal" {
		t.Fatalf("personal -> %q", got)
	}
}

func TestAgentSwitchFingerprintIncludesTargetAccount(t *testing.T) {
	a := ComputeAgentSwitchRequestFingerprint("s-1", HarnessClaudeCode, "personal", "")
	b := ComputeAgentSwitchRequestFingerprint("s-1", HarnessClaudeCode, "default", "")
	if a == b {
		t.Fatal("fingerprints for different target accounts are equal")
	}
}
