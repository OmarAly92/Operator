package domain_test

import (
	"testing"

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
