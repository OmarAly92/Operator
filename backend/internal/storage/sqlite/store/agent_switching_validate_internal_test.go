package store

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func activationFixture() domain.AgentSwitchTargetActivation {
	return domain.AgentSwitchTargetActivation{
		SwitchID: "switch-1", SessionID: "s-1",
		SourceHarness: domain.HarnessClaudeCode, SourceClaudeAccountID: "default",
		SourceGenerationID: "g-1", TargetGenerationID: "g-2",
		TargetHarness: domain.HarnessClaudeCode, TargetClaudeAccountID: "personal",
		TargetNativeSessionRef: "n-1", RuntimeHandleID: "h-1", ActivatedAt: time.Now(),
	}
}

func TestValidateActivationAllowsSameHarnessAcrossAccounts(t *testing.T) {
	if err := validateAgentSwitchTargetActivation(activationFixture()); err != nil {
		t.Fatalf("err = %v", err)
	}
}

func TestValidateActivationRejectsSameHarnessSameAccount(t *testing.T) {
	a := activationFixture()
	a.TargetClaudeAccountID = a.SourceClaudeAccountID
	if err := validateAgentSwitchTargetActivation(a); err == nil {
		t.Fatal("expected error for identical harness and account")
	}
}
