package sessionmanager

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

type fakePermissionModeReader struct {
	verified string
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

func (f fakePermissionModeReader) PermissionModeVerified(version string) bool {
	return version == f.verified
}

var observedShiftTabLoop = []string{
	"MODE:bypass-permissions", "MODE:auto", "MODE:default", "MODE:accept-edits", "MODE:plan", "MODE:bypass-permissions",
}

var loopWithoutAutoOrBypass = []string{"MODE:default", "MODE:accept-edits", "MODE:plan", "MODE:default"}

func TestPermissionModeSupportNeedsAVerifiedVersion(t *testing.T) {
	m, _, _, _ := newManager()
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280"}

	if !m.PermissionModeSupport(domain.HarnessClaudeCode, "2.1.280") {
		t.Fatal("a verified version reported no support")
	}
	if m.PermissionModeSupport(domain.HarnessClaudeCode, "2.1.279") {
		t.Fatal("an unverified version reported support")
	}
}

func TestPermissionModeSupportIsOffForAHarnessWithoutAReader(t *testing.T) {
	m, _, _, _ := newManager()
	if m.PermissionModeSupport(domain.HarnessCodex, "2.1.280") {
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
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280"}
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

func TestPermissionModeDriveReachesAutoFromBypassInOnePress(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, observedShiftTabLoop...)

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModeAuto)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if result != (PermissionModeResult{Mode: domain.PermissionModeAuto}) {
		t.Fatalf("result = %+v, want auto without a restart", result)
	}
	if len(rt.inputs) != 1 || shiftTabs(rt.inputs) != 1 {
		t.Fatalf("inputs = %q, want exactly one Shift+Tab press", rt.inputs)
	}
}

func TestPermissionModeDriveWalksTheObservedLoopToPlan(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, observedShiftTabLoop...)

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil || result != (PermissionModeResult{Mode: domain.PermissionModePlan}) {
		t.Fatalf("result = %+v err = %v", result, err)
	}
	if shiftTabs(rt.inputs) != 4 {
		t.Fatalf("inputs = %q, want four Shift+Tab presses", rt.inputs)
	}
}

func TestPermissionModeDriveGivesUpWhenAPressChangesNothing(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) || len(rt.inputs) != 1 {
		t.Fatalf("err = %v inputs = %q; want one unconfirmed press", err, rt.inputs)
	}
}

func TestPermissionModeDrivePressesAtMostEightTimes(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle,
		"MODE:default", "MODE:m1", "MODE:m2", "MODE:m3", "MODE:m4", "MODE:m5", "MODE:m6", "MODE:m7", "MODE:m8", "MODE:m9")

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnconfirmed) {
		t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
	}
	if len(rt.inputs) != 8 {
		t.Fatalf("pressed %d times, want 8", len(rt.inputs))
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
	m.permissionModeReader = fakePermissionModeReader{verified: "2.1.280"}
	m.SetPermissionModeObserver(verifiedObservation)
	m.permissionModeTiming = permissionModeTiming{appear: 20 * time.Millisecond, poll: time.Millisecond}
	m.permissionRestartSettle = func(context.Context) error { return nil }
	runtime.panes = slices.Clone(loopWithoutAutoOrBypass)
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
	if len(runtime.inputs) != 3 || shiftTabs(runtime.inputs) != 3 {
		t.Fatalf("inputs = %q, want the three Shift+Tab presses of the loop and nothing typed by the restart", runtime.inputs)
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

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("err = %v, want ErrWrongActivityState", err)
	}
	if len(runtime.inputs) != 0 || runtime.destroyed != 0 || agent.restoreCalls != 0 {
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

type hookedPermissionModeReader struct {
	fakePermissionModeReader
	onRead func()
}

func (h hookedPermissionModeReader) ReadPermissionMode(pane string) (domain.PermissionMode, bool) {
	if h.onRead != nil {
		h.onRead()
	}
	return h.fakePermissionModeReader.ReadPermissionMode(pane)
}

func TestPermissionModeRestartIsRefusedWhileAPaneDriveHoldsTheSession(t *testing.T) {
	m, _, runtime, agent := newPermissionRestartManager(t)
	end, err := m.beginPaneDrive(ctx, "mer-1")
	if err != nil {
		t.Fatalf("beginPaneDrive: %v", err)
	}
	defer end()

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("err = %v, want ErrSessionBusy", err)
	}
	if len(runtime.inputs) != 0 || runtime.destroyed != 0 || runtime.created != 0 || agent.restoreCalls != 0 {
		t.Fatalf("the restart went ahead under a pane drive: destroyed=%d created=%d restores=%d", runtime.destroyed, runtime.created, agent.restoreCalls)
	}
}

func TestPermissionModeIsBusyWhileAnotherOperationOwnsTheSession(t *testing.T) {
	m, _, runtime, agent := newPermissionRestartManager(t)
	if err := m.beginAgentOperation(ctx, "mer-1", agentOperationRetire); err != nil {
		t.Fatalf("beginAgentOperation: %v", err)
	}
	defer m.endAgentOperation("mer-1", agentOperationRetire)

	for _, target := range []domain.PermissionMode{domain.PermissionModePlan, domain.PermissionModeAuto} {
		if _, err := m.SetPermissionMode(ctx, "mer-1", target); !errors.Is(err, ErrSessionBusy) {
			t.Fatalf("%s: err = %v, want ErrSessionBusy", target, err)
		}
	}
	if len(runtime.inputs) != 0 || runtime.destroyed != 0 || agent.restoreCalls != 0 {
		t.Fatalf("a busy change touched the session: inputs=%q destroyed=%d restores=%d", runtime.inputs, runtime.destroyed, agent.restoreCalls)
	}
}

func TestPermissionModeDriveHoldsInputWhilePressing(t *testing.T) {
	m, _ := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "MODE:accept-edits", "MODE:plan")
	admitted := 0
	m.permissionModeReader = hookedPermissionModeReader{
		fakePermissionModeReader: fakePermissionModeReader{verified: "2.1.280"},
		onRead: func() {
			if release, ok := m.AcquireSessionInput("s1"); ok {
				admitted++
				release()
			}
		},
	}

	if _, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan); err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if admitted != 0 {
		t.Fatalf("input was admitted %d times during the drive", admitted)
	}
	release, ok := m.AcquireSessionInput("s1")
	if !ok {
		t.Fatal("input stayed closed after the drive")
	}
	release()
}

func TestPermissionModeDriveStopsWhenATurnStartsMidDrive(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "MODE:accept-edits")
	st := m.store.(*fakeStore)
	m.permissionModeReader = hookedPermissionModeReader{
		fakePermissionModeReader: fakePermissionModeReader{verified: "2.1.280"},
		onRead: func() {
			if len(rt.inputs) == 1 {
				rec := st.sessions["s1"]
				rec.Activity.State = domain.ActivityActive
				st.sessions["s1"] = rec
			}
		},
	}

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrWrongActivityState) {
		t.Fatalf("err = %v, want ErrWrongActivityState", err)
	}
	if result.Mode != domain.PermissionModeAcceptEdits || len(rt.inputs) != 1 {
		t.Fatalf("result = %+v inputs = %q; want one press, stopped at accept-edits", result, rt.inputs)
	}
}

func TestPermissionModeDriveReleasesThePaneWhenCancelled(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	driveCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	m.permissionModeReader = hookedPermissionModeReader{
		fakePermissionModeReader: fakePermissionModeReader{verified: "2.1.280"},
		onRead: func() {
			if len(rt.inputs) == 1 {
				cancel()
			}
		},
	}

	if _, err := m.SetPermissionMode(driveCtx, "s1", domain.PermissionModePlan); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
	waitCtx, stop := context.WithTimeout(ctx, time.Second)
	defer stop()
	end, err := m.beginPaneDrive(waitCtx, "s1")
	if err != nil {
		t.Fatalf("the cancelled drive kept the pane: %v", err)
	}
	end()
}

func TestPermissionModeRestartsOnlyAfterTheLoopReturnsToItsStart(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	rec := st.sessions["mer-1"]
	rec.LaunchPermissionMode = domain.PermissionModeBypassPermissions
	st.sessions["mer-1"] = rec
	runtime.panes = []string{"MODE:bypass-permissions", "MODE:default", "MODE:accept-edits", "MODE:plan", "MODE:bypass-permissions"}

	result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if !result.Restarted || agent.restoreCalls != 1 || agent.lastRestore.Permissions != domain.PermissionModeAuto {
		t.Fatalf("result = %+v restores = %d permissions = %q; want one --resume with auto", result, agent.restoreCalls, agent.lastRestore.Permissions)
	}
	if shiftTabs(runtime.inputs) != 4 {
		t.Fatalf("inputs = %q, want the full four-press loop before restarting", runtime.inputs)
	}
}

func TestPermissionModeNeverRestartsAfterAnUnconfirmedDrive(t *testing.T) {
	tests := []struct {
		name  string
		panes []string
	}{
		{"a dialog replaces the footer", []string{"MODE:default", "DIALOG"}},
		{"no footer before the first press", []string{"DIALOG"}},
		{"a press changes nothing", []string{"MODE:default"}},
		{"the loop never ends", []string{"MODE:default", "MODE:m1", "MODE:m2", "MODE:m3", "MODE:m4", "MODE:m5", "MODE:m6", "MODE:m7", "MODE:m8", "MODE:m9"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m, _, runtime, agent := newPermissionRestartManager(t)
			runtime.panes = tt.panes

			result, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto)
			if !errors.Is(err, ErrPermissionModeUnconfirmed) {
				t.Fatalf("err = %v, want ErrPermissionModeUnconfirmed", err)
			}
			if result.Restarted || agent.restoreCalls != 0 || runtime.destroyed != 0 || runtime.created != 0 {
				t.Fatalf("an unconfirmed drive restarted: result = %+v restores = %d destroyed = %d created = %d", result, agent.restoreCalls, runtime.destroyed, runtime.created)
			}
			if shiftTabs(runtime.inputs) > maxPermissionModePresses {
				t.Fatalf("pressed %d times, want at most %d", shiftTabs(runtime.inputs), maxPermissionModePresses)
			}
		})
	}
}

func TestPermissionModeRestartRefusesASendAsBusy(t *testing.T) {
	m, _, _, _ := newPermissionRestartManager(t)
	var sendErr error
	m.permissionRestartSettle = func(context.Context) error {
		sendErr = m.Send(ctx, "mer-1", "hello", nil)
		return nil
	}

	if _, err := m.SetPermissionMode(ctx, "mer-1", domain.PermissionModeAuto); err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if !errors.Is(sendErr, ErrSessionBusy) || errors.Is(sendErr, ErrSwitchInProgress) {
		t.Fatalf("send during the restart = %v, want ErrSessionBusy", sendErr)
	}
}

func TestPermissionModeIsUnsupportedWhenTheObservationCannotBeRead(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	readErr := errors.New("block events unavailable")
	m.SetPermissionModeObserver(fakePermissionModeObserver{err: readErr})

	_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, ErrPermissionModeUnsupported) || !errors.Is(err, readErr) {
		t.Fatalf("err = %v, want ErrPermissionModeUnsupported wrapping the read error", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("an unreadable observation touched the pane: %q", rt.inputs)
	}
}

func TestPermissionModeRestartFinishesWhenTheClientDropsMidway(t *testing.T) {
	m, st, runtime, agent := newPermissionRestartManager(t)
	callCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	m.permissionRestartSettle = func(settleCtx context.Context) error {
		cancel()
		return settleCtx.Err()
	}

	result, err := m.SetPermissionMode(callCtx, "mer-1", domain.PermissionModeAuto)
	if err != nil {
		t.Fatalf("SetPermissionMode: %v", err)
	}
	if !result.Restarted || agent.restoreCalls != 1 || runtime.created != 1 {
		t.Fatalf("result = %+v restores = %d created = %d; want one finished relaunch", result, agent.restoreCalls, runtime.created)
	}
	if got := st.sessions["mer-1"].LaunchPermissionMode; got != domain.PermissionModeAuto {
		t.Fatalf("launch mode = %q, want auto", got)
	}
}

func TestPermissionModeKeepsACancelledObservationReadAsACancellation(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default")
	callCtx, cancel := context.WithCancel(ctx)
	cancel()
	m.SetPermissionModeObserver(fakePermissionModeObserver{err: context.Canceled})

	_, err := m.SetPermissionMode(callCtx, "s1", domain.PermissionModePlan)
	if !errors.Is(err, context.Canceled) || errors.Is(err, ErrPermissionModeUnsupported) {
		t.Fatalf("err = %v, want context.Canceled and not ErrPermissionModeUnsupported", err)
	}
	if len(rt.inputs) != 0 {
		t.Fatalf("a cancelled read touched the pane: %q", rt.inputs)
	}
}

func TestPermissionModeASecondChangeMidDriveIsBusyAtOnce(t *testing.T) {
	m, rt := newPermissionDriveManager(t, domain.ActivityIdle, "MODE:default", "MODE:accept-edits", "MODE:plan")
	second := make(chan error, 1)
	var once sync.Once
	m.permissionModeReader = hookedPermissionModeReader{
		fakePermissionModeReader: fakePermissionModeReader{verified: "2.1.280"},
		onRead: func() {
			once.Do(func() {
				go func() {
					_, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModeAuto)
					second <- err
				}()
				select {
				case err := <-second:
					second <- err
				case <-time.After(time.Second):
					second <- errors.New("the second change waited on the running drive")
				}
			})
		},
	}

	result, err := m.SetPermissionMode(ctx, "s1", domain.PermissionModePlan)
	if err != nil || result != (PermissionModeResult{Mode: domain.PermissionModePlan}) {
		t.Fatalf("first change = %+v, %v", result, err)
	}
	if err := <-second; !errors.Is(err, ErrSessionBusy) {
		t.Fatalf("second change = %v, want ErrSessionBusy", err)
	}
	if shiftTabs(rt.inputs) != 2 {
		t.Fatalf("inputs = %q, want only the first change's two presses", rt.inputs)
	}
}
