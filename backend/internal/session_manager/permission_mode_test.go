package sessionmanager

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

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

type fakePermissionModeObserver struct {
	observation domain.PermissionModeObservation
	ok          bool
	err         error
}

func (f fakePermissionModeObserver) LatestPermissionMode(context.Context, domain.SessionID) (domain.PermissionModeObservation, bool, error) {
	return f.observation, f.ok, f.err
}

var verifiedObservation = fakePermissionModeObserver{
	observation: domain.PermissionModeObservation{Mode: domain.PermissionModeDefault, Version: "2.1.280"},
	ok:          true,
}

func newPermissionDriveManager(t *testing.T, state domain.ActivityState, panes ...string) (*Manager, *fakeRuntime) {
	t.Helper()
	m, rt := newCommandTestManager(t, state)
	m.permissionModeReader = fakePermissionModeReader{
		verified: "2.1.280",
		cycle:    append(slices.Clone(threeModeCycle), domain.PermissionModeBypassPermissions),
	}
	m.SetPermissionModeObserver(verifiedObservation)
	m.permissionModeTiming = permissionModeTiming{appear: 20 * time.Millisecond, poll: time.Millisecond}
	rt.panes = panes
	return m, rt
}

func shiftTabs(inputs []string) int {
	count := 0
	for _, input := range inputs {
		if input == "\x1b[Z" {
			count++
		}
	}
	return count
}

func TestPermissionModeDriveStopsAtTheTargetWithoutOvershoot(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle,
		"MODE:default", "MODE:accept-edits", "MODE:plan", "MODE:bypass-permissions")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if result != (PermissionModeResult{Mode: domain.PermissionModePlan}) {
		t.Fatalf("result = %+v", result)
	}
	if len(rt.inputs) != 2 || shiftTabs(rt.inputs) != 2 {
		t.Fatalf("inputs = %q, want exactly two Shift+Tab presses", rt.inputs)
	}
}

func TestPermissionModeDriveIsANoOpWhenAlreadyThere(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:plan")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil || result.Mode != domain.PermissionModePlan {
		t.Fatalf("result = %+v, %v", result, err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveStopsWhenTheFooterDisappears(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "DIALOG")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 1 {
		t.Fatalf("inputs = %q, want the single press that preceded the dialog", rt.inputs)
	}
}

func TestPermissionModeDriveNeverPressesWithoutAFooter(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "DIALOG")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveGivesUpWhenTheCycleReturnsToTheStart(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "MODE:accept-edits", "MODE:default")

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModeBypassPermissions)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if result.Mode != domain.PermissionModeDefault || len(rt.inputs) != 2 {
		t.Fatalf("result = %+v inputs = %q; want back at default after two presses", result, rt.inputs)
	}
}

func TestPermissionModeDriveGivesUpWhenAPressChangesNothing(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) || len(rt.inputs) != 1 {
		t.Fatalf("err = %v inputs = %q; want one unconfirmed press", err, rt.inputs)
	}
}

func TestPermissionModeDrivePressesAtMostSixTimes(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle,
		"MODE:default", "MODE:m1", "MODE:m2", "MODE:m3", "MODE:m4", "MODE:m5", "MODE:m6", "MODE:m7")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 6 {
		t.Fatalf("pressed %d times, want 6", len(rt.inputs))
	}
}

func TestPermissionModeDriveIsRefusedWhileTheAgentWorks(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityActive, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("err = %v, want ErrWrongActivityState", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeDriveWaitsOnABlockedSession(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityBlocked, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("err = %v, want ErrAwaitingDecision", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("inputs = %q, want none", rt.inputs)
	}
}

func TestPermissionModeIsUnsupportedOnAnUnverifiedVersion(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	m.SetPermissionModeObserver(fakePermissionModeObserver{
		observation: domain.PermissionModeObservation{Mode: domain.PermissionModeDefault, Version: "2.1.279"},
		ok:          true,
	})

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
	if len(rt.inputs) != 0 || rt.outputCalls != 0 {
		t.Fatalf("an unsupported change touched the pane: inputs=%q reads=%d", rt.inputs, rt.outputCalls)
	}
}

func TestPermissionModeIsUnsupportedBeforeTheTranscriptReports(t *testing.T) {
	m, _ := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	m.SetPermissionModeObserver(fakePermissionModeObserver{})

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
}

func TestPermissionModeRejectsAnUnknownTarget(t *testing.T) {
	m, _ := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")

	if _, err := m.SetPermissionMode(ctx, "s1", "yolo"); !errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported", err)
	}
}

func newPermissionRestartManager(t *testing.T) (*Manager, *fakeStore, *fakeRuntime, *recordingAgent) {
	t.Helper()
	agent := &recordingAgent{}
	m, st, runtime := newRelaunchManager(t, agent)
	rec := st.sessions["mer-1"]
	rec.Harness = domain.HarnessClaudeCode
	rec.LaunchPermissionMode = domain.PermissionModeDefault
	st.sessions["mer-1"] = rec
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280", cycle: threeModeCycle}
	m.SetPermissionModeObserver(verifiedObservation)
	m.permissionRestartSettle = func(context.Context) error { return nil }
	return m, st, runtime, agent
}

func TestPermissionModeRestartResumesWithTheNewMode(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)

	result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if result != (PermissionModeResult{Mode: domain.PermissionModeAuto, Restarted: true}) {
		t.Fatalf("result = %+v", result)
	}
	if agent.restoreCalls != 1 || agent.lastRestore.Permissions != domain.PermissionModeAuto {
		t.Fatalf("restore calls = %d permissions = %q; want one --resume with auto", agent.restoreCalls, agent.lastRestore.Permissions)
	}
	if !slices.Contains(runtime.lastCfg.Argv, "resume") {
		t.Fatalf("relaunch argv = %#v, want the resume command", runtime.lastCfg.Argv)
	}
	if got := st.sessions["mer-1"].LaunchPermissionMode; got != domain.PermissionModeAuto {
		t.Fatalf("launch mode = %q, want auto", got)
	}
	if len(runtime.inputs) != 0 {
		t.Fatalf("a restart typed into the pane: %q", runtime.inputs)
	}
}

func TestPermissionModeRestartsForBypassWhenNotLaunchedWithIt(t *testing.T) {
	m, _, _, agent := newPermissionRestartManager(t)

	result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeBypassPermissions)
	if err != nil || !result.Restarted || agent.lastRestore.Permissions != domain.PermissionModeBypassPermissions {
		t.Fatalf("result = %+v err = %v permissions = %q", result, err, agent.lastRestore.Permissions)
	}
}

func TestPermissionModeRestartIsRefusedWhileTheAgentWorks(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityActive
	st.sessions["mer-1"] = rec

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("err = %v, want ErrSessionBusy", err)
	}
	if runtime.destroyed != 0 || agent.restoreCalls != 0 {
		t.Fatalf("a refused restart touched the runtime: destroyed=%d restores=%d", runtime.destroyed, agent.restoreCalls)
	}
}

func TestPermissionModeRestartRefusesATurnThatStartedWhileInputClosed(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	m.permissionRestartSettle = func(context.Context) error {
		if _, ok := m.AcquireSessionInput("mer-1"); ok {
			t.Error("input was admitted while the restart held the session")
		}
		rec := st.sessions["mer-1"]
		rec.Activity.State = domain.ActivityActive
		st.sessions["mer-1"] = rec
		return nil
	}

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("err = %v, want ErrSessionBusy", err)
	}
	if runtime.destroyed != 0 || runtime.created != 0 || agent.restoreCalls != 0 {
		t.Fatalf("the restart went ahead: destroyed=%d created=%d restores=%d", runtime.destroyed, runtime.created, agent.restoreCalls)
	}
	if st.sessions["mer-1"].LaunchPermissionMode != domain.PermissionModeDefault {
		t.Fatal("a refused restart rewrote the launch mode")
	}
}

func TestPermissionModeRestartWaitsOnABlockedSession(t *testing.T) {
	m, st, _, _ := newPermissionRestartManager(t)
	rec := st.sessions["mer-1"]
	rec.Activity.State = domain.ActivityBlocked
	st.sessions["mer-1"] = rec

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrAwaitingDecision) {
		t.Fatalf("err = %v, want ErrAwaitingDecision", err)
	}
}
