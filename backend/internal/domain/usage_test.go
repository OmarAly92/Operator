package domain_test

import (
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
)

func TestSessionContextFraction(t *testing.T) {
	cases := []struct {
		name   string
		ctx    domain.SessionContext
		want   float64
		wantOK bool
	}{
		{"window known", domain.SessionContext{Used: 50, Window: 200}, 0.25, true},
		{"window unknown is not zero percent", domain.SessionContext{Used: 64880, Window: 0}, 0, false},
		{"empty context with a known window", domain.SessionContext{Used: 0, Window: 200}, 0, true},
		{"over window clamps to one", domain.SessionContext{Used: 300, Window: 200}, 1, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := tc.ctx.Fraction()
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if ok && got != tc.want {
				t.Fatalf("fraction = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestUsageQuotaWindowIsStaleAfterItsWindowRolls(t *testing.T) {
	reset := time.Date(2026, 9, 5, 22, 23, 55, 0, time.UTC)
	w := domain.UsageQuotaWindow{UsedPercent: 77, WindowMinutes: 300, ResetsAt: reset}

	if w.IsStale(reset.Add(-time.Minute)) {
		t.Fatal("a reading inside its own window is current")
	}
	if !w.IsStale(reset.Add(time.Minute)) {
		t.Fatal("once the window rolls the stored percentage is known-meaningless")
	}
}

func TestUsageQuotaWindowWithNoResetTimeIsNeverStale(t *testing.T) {
	w := domain.UsageQuotaWindow{UsedPercent: 12, WindowMinutes: 10080}
	if w.IsStale(time.Now()) {
		t.Fatal("with no reset time there is no evidence of staleness, so do not invent it")
	}
}

func TestUsageQuotaIsEmptyWhenNoWindowReported(t *testing.T) {
	if !(domain.UsageQuota{LimitID: "premium"}).IsEmpty() {
		t.Fatal("an observation with neither window carries nothing and must be discarded")
	}
	if (domain.UsageQuota{Primary: &domain.UsageQuotaWindow{UsedPercent: 0}}).IsEmpty() {
		t.Fatal("0% used is a real reading, not an absent one")
	}
}
