package sessionmanager

import (
	"slices"
	"strings"
	"testing"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakePermissionModeReader struct {
	verified string
	cycle    []domain.PermissionMode
}

func (f fakePermissionModeReader) ReadPermissionMode(pane string) (domain.PermissionMode, bool) {
	mode, ok := strings.CutPrefix(pane, "MODE:")
	if !ok {
		return "", false
	}
	return domain.PermissionMode(mode), true
}

func (fakePermissionModeReader) PermissionModeKeys() ports.PermissionModeKeys {
	return ports.PermissionModeKeys{Cycle: "\x1b[Z"}
}

func (f fakePermissionModeReader) PermissionModeCycle(domain.PermissionMode) []domain.PermissionMode {
	return f.cycle
}

func (f fakePermissionModeReader) PermissionModeVerified(version string) bool {
	return version == f.verified
}

var threeModeCycle = []domain.PermissionMode{domain.PermissionModeDefault, domain.PermissionModeAcceptEdits, domain.PermissionModePlan}

func TestPermissionModeSupportNeedsAVerifiedVersion(t *testing.T) {
	m, _, _, _ := newManager()
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280", cycle: threeModeCycle}

	ok, cycle := m.PermissionModeSupport(domain.HarnessClaudeCode, domain.PermissionModeDefault, "2.1.280")
	if !ok || !slices.Equal(cycle, threeModeCycle) {
		t.Fatalf("support = %v, %v", ok, cycle)
	}
	if ok, cycle := m.PermissionModeSupport(domain.HarnessClaudeCode, domain.PermissionModeDefault, "2.1.279"); ok || cycle != nil {
		t.Fatalf("unverified version = %v, %v; want unsupported", ok, cycle)
	}
}

func TestPermissionModeSupportIsOffForAHarnessWithoutAReader(t *testing.T) {
	m, _, _, _ := newManager()
	if ok, _ := m.PermissionModeSupport(domain.HarnessCodex, domain.PermissionModeDefault, "2.1.280"); ok {
		t.Fatal("a harness whose adapter has no reader reported support")
	}
	if m.PermissionModeReadable(domain.HarnessCodex) {
		t.Fatal("a harness whose adapter has no reader reported a readable mode")
	}
}
