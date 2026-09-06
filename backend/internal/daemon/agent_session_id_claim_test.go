package daemon

import (
	"context"
	"errors"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type claimingAgent struct {
	ports.Agent
	claimed map[domain.SessionID]bool
	err     error
}

func (a claimingAgent) IsSessionIDClaimed(_ context.Context, id domain.SessionID) (bool, error) {
	if a.err != nil {
		return false, a.err
	}
	return a.claimed[id], nil
}

type plainAgent struct{ ports.Agent }

type stubResolver map[domain.AgentHarness]ports.Agent

func (r stubResolver) Agent(harness domain.AgentHarness) (ports.Agent, bool) {
	agent, ok := r[harness]
	return agent, ok
}

func TestAgentClaimsReportTheProviderNamespace(t *testing.T) {
	claims := agentSessionIDClaims{agents: stubResolver{
		domain.HarnessClaudeCode: claimingAgent{claimed: map[domain.SessionID]bool{"scratch-16": true}},
	}}

	claimed, err := claims.IsSessionIDClaimed(context.Background(), "scratch-16")
	if err != nil || !claimed {
		t.Fatalf("claimed=%v err=%v, want true/nil", claimed, err)
	}
	free, err := claims.IsSessionIDClaimed(context.Background(), "scratch-18")
	if err != nil || free {
		t.Fatalf("claimed=%v err=%v, want false/nil", free, err)
	}
}

func TestAgentClaimsIgnoreAdaptersWithoutTheCapability(t *testing.T) {
	claims := agentSessionIDClaims{agents: stubResolver{domain.HarnessCodex: plainAgent{}}}
	claimed, err := claims.IsSessionIDClaimed(context.Background(), "scratch-16")
	if err != nil || claimed {
		t.Fatalf("claimed=%v err=%v, want false/nil", claimed, err)
	}
}

func TestAgentClaimsKeepProbingAfterOneAdapterFails(t *testing.T) {
	claims := agentSessionIDClaims{agents: stubResolver{
		domain.HarnessCodex:      claimingAgent{err: errors.New("unreadable")},
		domain.HarnessClaudeCode: claimingAgent{claimed: map[domain.SessionID]bool{"scratch-16": true}},
	}}
	claimed, err := claims.IsSessionIDClaimed(context.Background(), "scratch-16")
	if err != nil || !claimed {
		t.Fatalf("a later adapter's claim must win over an earlier error: claimed=%v err=%v", claimed, err)
	}
}

func TestAgentClaimsSurfaceTheErrorWhenNothingClaimed(t *testing.T) {
	want := errors.New("unreadable")
	claims := agentSessionIDClaims{agents: stubResolver{domain.HarnessClaudeCode: claimingAgent{err: want}}}
	claimed, err := claims.IsSessionIDClaimed(context.Background(), "scratch-16")
	if claimed || !errors.Is(err, want) {
		t.Fatalf("an inconclusive probe must not be reported as free: claimed=%v err=%v", claimed, err)
	}
}

func TestAgentClaimsAreSafeWithoutAResolver(t *testing.T) {
	claimed, err := agentSessionIDClaims{}.IsSessionIDClaimed(context.Background(), "scratch-16")
	if err != nil || claimed {
		t.Fatalf("claimed=%v err=%v, want false/nil", claimed, err)
	}
}
