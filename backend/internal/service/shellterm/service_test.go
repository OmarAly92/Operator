package shellterm

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/httpd/apierr"
	"github.com/OmarAly92/operator/backend/internal/ports"
)

func TestOpenShellTerminalHasNoSessionScope(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})
	got, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}
	if got.HandleID == "" {
		t.Fatal("Open() returned an empty handle id")
	}
	if reflect.TypeOf(OpenShellTerminalInput{}).NumField() != 1 {
		t.Fatalf("OpenShellTerminalInput has %d fields, want 1 (ProjectID)",
			reflect.TypeOf(OpenShellTerminalInput{}).NumField())
	}
}

const testAppRunID = "app-run-current"

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// fakeShellRuntime records every runtime call so tests can assert on what was
// spawned and what was torn down.
type fakeShellRuntime struct {
	created   []ports.RuntimeConfig
	destroyed []string
	log       *callLog

	createErr  error
	destroyErr error
	// aliveByHandle answers IsAlive; a handle absent from the map is dead.
	aliveByHandle map[string]bool
	aliveErr      error
}

func newFakeShellRuntime() *fakeShellRuntime {
	return &fakeShellRuntime{aliveByHandle: map[string]bool{}}
}

func (f *fakeShellRuntime) Create(_ context.Context, cfg ports.RuntimeConfig) (ports.RuntimeHandle, error) {
	if f.createErr != nil {
		return ports.RuntimeHandle{}, f.createErr
	}
	f.created = append(f.created, cfg)
	f.aliveByHandle[string(cfg.SessionID)] = true
	return ports.RuntimeHandle{ID: string(cfg.SessionID)}, nil
}

func (f *fakeShellRuntime) Destroy(_ context.Context, handle ports.RuntimeHandle) error {
	f.destroyed = append(f.destroyed, handle.ID)
	f.log.add("destroy:" + handle.ID)
	// Only a successful destroy is modeled as actually killing the runtime — a
	// failed one leaves aliveByHandle as the caller set it up, so tests can
	// distinguish "destroy errored but it was already dead" (aliveByHandle has
	// no entry) from "destroy errored and it is still alive" (pre-seeded true).
	if f.destroyErr == nil {
		delete(f.aliveByHandle, handle.ID)
	}
	return f.destroyErr
}

func (f *fakeShellRuntime) IsAlive(_ context.Context, handle ports.RuntimeHandle) (bool, error) {
	if f.aliveErr != nil {
		return false, f.aliveErr
	}
	return f.aliveByHandle[handle.ID], nil
}

// fakeShellTerminalStore is an in-memory Store keyed by handle id.
type fakeShellTerminalStore struct {
	records   []ShellTerminalRecord
	insertErr error
}

func (f *fakeShellTerminalStore) InsertShellTerminal(_ context.Context, rec ShellTerminalRecord) error {
	if f.insertErr != nil {
		return f.insertErr
	}
	f.records = append(f.records, rec)
	return nil
}

func (f *fakeShellTerminalStore) UpdateShellTerminalTitle(_ context.Context, handleID, title string) (ShellTerminalRecord, bool, error) {
	for i, rec := range f.records {
		if rec.HandleID == handleID {
			f.records[i].Title = title
			return f.records[i], true, nil
		}
	}
	return ShellTerminalRecord{}, false, nil
}

func (f *fakeShellTerminalStore) SelectShellTerminalByHandleID(_ context.Context, handleID string) (ShellTerminalRecord, bool, error) {
	for _, rec := range f.records {
		if rec.HandleID == handleID {
			return rec, true, nil
		}
	}
	return ShellTerminalRecord{}, false, nil
}

func (f *fakeShellTerminalStore) SelectShellTerminalsByAppRunID(_ context.Context, appRunID string) ([]ShellTerminalRecord, error) {
	var out []ShellTerminalRecord
	for _, rec := range f.records {
		if rec.AppRunID == appRunID {
			out = append(out, rec)
		}
	}
	return out, nil
}

func (f *fakeShellTerminalStore) SelectShellTerminalsFromPreviousAppRuns(_ context.Context, appRunID string) ([]ShellTerminalRecord, error) {
	var out []ShellTerminalRecord
	for _, rec := range f.records {
		if rec.AppRunID != appRunID {
			out = append(out, rec)
		}
	}
	return out, nil
}

func (f *fakeShellTerminalStore) DeleteShellTerminalByHandleID(_ context.Context, handleID string) (bool, error) {
	for i, rec := range f.records {
		if rec.HandleID == handleID {
			f.records = append(f.records[:i], f.records[i+1:]...)
			return true, nil
		}
	}
	return false, nil
}

func (f *fakeShellTerminalStore) DeleteShellTerminalsFromPreviousAppRuns(_ context.Context, appRunID string) (int64, error) {
	kept := make([]ShellTerminalRecord, 0, len(f.records))
	var cleared int64
	for _, rec := range f.records {
		if rec.AppRunID == appRunID {
			kept = append(kept, rec)
			continue
		}
		cleared++
	}
	f.records = kept
	return cleared, nil
}

type fakeProjectRootLocator struct {
	roots map[domain.ProjectID]string
	err   error
}

func (f *fakeProjectRootLocator) ProjectRoot(_ context.Context, id domain.ProjectID) (string, error) {
	if f.err != nil {
		return "", f.err
	}
	return f.roots[id], nil
}

type callLog struct {
	mu sync.Mutex
	ev []string
}

func (c *callLog) add(s string) {
	if c == nil {
		return
	}
	c.mu.Lock()
	c.ev = append(c.ev, s)
	c.mu.Unlock()
}

func (c *callLog) snapshot() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string(nil), c.ev...)
}

type fakeCaptureLifecycle struct {
	log         *callLog
	started     []string
	stopped     []string
	live        map[string]bool
	startErr    error
	stopErr     error
	unsupported bool
}

func (f *fakeCaptureLifecycle) Start(_ context.Context, rec ShellTerminalRecord) error {
	f.started = append(f.started, rec.HandleID)
	f.log.add("start:" + rec.HandleID)
	if f.unsupported {
		return ports.ErrCaptureUnsupported
	}
	if f.startErr != nil {
		return f.startErr
	}
	if f.live == nil {
		f.live = map[string]bool{}
	}
	f.live[rec.HandleID] = true
	return nil
}

func (f *fakeCaptureLifecycle) StopAndDrain(_ context.Context, handleID string) error {
	f.stopped = append(f.stopped, handleID)
	f.log.add("stopdrain:" + handleID)
	if f.stopErr != nil {
		return f.stopErr
	}
	delete(f.live, handleID)
	return nil
}

func (f *fakeCaptureLifecycle) Capturing(handleID string) bool {
	return f.live[handleID]
}

func newTestService(t *testing.T, rt *fakeShellRuntime, st *fakeShellTerminalStore, projects ProjectRootLocator) *Service {
	t.Helper()
	return newTestServiceWithCapture(t, rt, st, projects, nil)
}

func newTestServiceWithCapture(t *testing.T, rt *fakeShellRuntime, st *fakeShellTerminalStore, projects ProjectRootLocator, capture BlockCaptureLifecycle) *Service {
	t.Helper()
	svc := NewService(rt, st, projects, capture, t.TempDir(), testAppRunID, testLogger())
	var n int
	svc.newHandleID = func() (string, error) {
		n++
		return "shellterm-test" + string(rune('0'+n)), nil
	}
	svc.now = func() time.Time { return time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC) }
	return svc
}

func TestOpenShellTerminalStartsLoginShellInProjectRoot(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	projects := &fakeProjectRootLocator{roots: map[domain.ProjectID]string{"portfolio": "/repos/portfolio"}}
	svc := newTestService(t, rt, st, projects)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{ProjectID: "portfolio"})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}

	if len(rt.created) != 1 {
		t.Fatalf("runtime creates = %d, want 1", len(rt.created))
	}
	if got := rt.created[0].WorkspacePath; got != "/repos/portfolio" {
		t.Errorf("workspace path = %q, want the project root", got)
	}
	if len(rt.created[0].Argv) == 0 {
		t.Error("argv is empty; a shell terminal must launch a resolved shell")
	}
	if term.WorkingDir != "/repos/portfolio" {
		t.Errorf("working dir = %q, want the project root", term.WorkingDir)
	}
	if term.Title != "portfolio" {
		t.Errorf("title = %q, want the working dir's base name", term.Title)
	}
	if len(st.records) != 1 || st.records[0].AppRunID != testAppRunID {
		t.Fatalf("record not persisted against the current app run: %+v", st.records)
	}
}

func TestOpenShellTerminalFallsBackToDataDirWhenNoProjectGiven(t *testing.T) {
	rt := newFakeShellRuntime()
	svc := newTestService(t, rt, &fakeShellTerminalStore{}, &fakeProjectRootLocator{})

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if term.WorkingDir != svc.dataDir {
		t.Errorf("working dir = %q, want the daemon data dir %q", term.WorkingDir, svc.dataDir)
	}
	if term.ProjectID != "" {
		t.Errorf("project id = %q, want empty", term.ProjectID)
	}
}

func TestOpenShellTerminalWrapsKnownShellWithBootstrapRecipe(t *testing.T) {
	t.Setenv("SHELL", "/bin/zsh")
	rt := newFakeShellRuntime()
	svc := newTestService(t, rt, &fakeShellTerminalStore{}, &fakeProjectRootLocator{})

	if _, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{}); err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}

	if len(rt.created) != 1 {
		t.Fatalf("runtime creates = %d, want 1", len(rt.created))
	}
	cfg := rt.created[0]
	if len(cfg.Argv) == 0 {
		t.Fatal("argv is empty; a shell terminal must launch a resolved shell")
	}
	if cfg.Argv[0] != "/bin/zsh" {
		t.Errorf("argv[0] = %q, want the resolved login shell /bin/zsh", cfg.Argv[0])
	}
	joined := strings.Join(cfg.Argv, " ")
	if !strings.Contains(joined, "source ") {
		t.Errorf("argv = %v, want the bootstrap source form carrying a source line", cfg.Argv)
	}
	if !strings.Contains(joined, "exec zsh") {
		t.Errorf("argv = %v, want the bootstrap source form ending in `exec zsh`", cfg.Argv)
	}
	if cfg.Env["OPERATOR_TERMINAL_INTEGRATION"] != "auto" {
		t.Errorf("env integration = %q, want auto; full env = %v", cfg.Env["OPERATOR_TERMINAL_INTEGRATION"], cfg.Env)
	}
}

func TestOpenShellTerminalFallsBackToOsc133OnlyForUnknownShell(t *testing.T) {
	t.Setenv("SHELL", "/opt/homebrew/bin/nu")
	rt := newFakeShellRuntime()
	svc := newTestService(t, rt, &fakeShellTerminalStore{}, &fakeProjectRootLocator{})

	if _, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{}); err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}

	if len(rt.created) != 1 {
		t.Fatalf("runtime creates = %d, want 1", len(rt.created))
	}
	cfg := rt.created[0]
	if len(cfg.Argv) == 0 || cfg.Argv[0] != "/opt/homebrew/bin/nu" {
		t.Fatalf("argv[0] = %v, want the resolved login shell", cfg.Argv)
	}
	if cfg.Env["OPERATOR_TERMINAL_INTEGRATION"] != "osc133-only" {
		t.Errorf("env integration = %q, want osc133-only; full env = %v", cfg.Env["OPERATOR_TERMINAL_INTEGRATION"], cfg.Env)
	}
}

func TestShellKindForMatchesKnownBasenames(t *testing.T) {
	for _, tt := range []struct {
		path string
		want string
		ok   bool
	}{
		{"/bin/zsh", "zsh", true},
		{"/usr/bin/bash", "bash", true},
		{"/opt/homebrew/bin/fish", "fish", true},
		{"/opt/homebrew/bin/nu", "", false},
		{"/usr/bin/elvish", "", false},
		{"/bin/zsh-5.9", "", false},
		{"", "", false},
	} {
		got, ok := shellKindFor(tt.path)
		if got != tt.want || ok != tt.ok {
			t.Errorf("shellKindFor(%q) = (%q, %v), want (%q, %v)", tt.path, got, ok, tt.want, tt.ok)
		}
	}
}

func TestOpenShellTerminalReturnsNotFoundForUnknownProject(t *testing.T) {
	rt := newFakeShellRuntime()
	svc := newTestService(t, rt, &fakeShellTerminalStore{}, &fakeProjectRootLocator{roots: map[domain.ProjectID]string{}})

	_, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{ProjectID: "ghost"})

	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Kind != apierr.KindNotFound {
		t.Fatalf("error = %v, want a not-found apierr", err)
	}
	if len(rt.created) != 0 {
		t.Error("a runtime was spawned for an unknown project")
	}
}

func TestRenameShellTerminalUpdatesTitle(t *testing.T) {
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{
		{HandleID: "shellterm-1", Title: "portfolio", AppRunID: testAppRunID},
	}}
	svc := newTestService(t, newFakeShellRuntime(), st, &fakeProjectRootLocator{})

	term, err := svc.RenameShellTerminal(context.Background(), "shellterm-1", "  deploy logs  ")
	if err != nil {
		t.Fatalf("RenameShellTerminal: %v", err)
	}
	if term.Title != "deploy logs" {
		t.Errorf("returned title = %q, want the trimmed new title", term.Title)
	}
	if st.records[0].Title != "deploy logs" {
		t.Errorf("stored title = %q, want the trimmed new title", st.records[0].Title)
	}
}

func TestRenameShellTerminalRejectsEmptyTitle(t *testing.T) {
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{{HandleID: "shellterm-1", Title: "portfolio"}}}
	svc := newTestService(t, newFakeShellRuntime(), st, &fakeProjectRootLocator{})

	_, err := svc.RenameShellTerminal(context.Background(), "shellterm-1", "   ")

	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Kind != apierr.KindInvalid {
		t.Fatalf("error = %v, want an invalid apierr", err)
	}
	if st.records[0].Title != "portfolio" {
		t.Errorf("title changed to %q on a rejected rename", st.records[0].Title)
	}
}

func TestRenameShellTerminalReturnsNotFoundForUnknownHandle(t *testing.T) {
	svc := newTestService(t, newFakeShellRuntime(), &fakeShellTerminalStore{}, &fakeProjectRootLocator{})

	_, err := svc.RenameShellTerminal(context.Background(), "shellterm-ghost", "whatever")

	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Kind != apierr.KindNotFound {
		t.Fatalf("error = %v, want a not-found apierr", err)
	}
}

// A row that names a PTY nobody spawned would be re-attached forever after a
// restart, so a failed insert must take the runtime down with it.
func TestOpenShellTerminalDestroysRuntimeWhenPersistFails(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{insertErr: errors.New("disk full")}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	if _, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{}); err == nil {
		t.Fatal("OpenShellTerminal succeeded despite a failed insert")
	}
	if len(rt.destroyed) != 1 {
		t.Fatalf("destroyed runtimes = %v, want the spawned PTY rolled back", rt.destroyed)
	}
	if rt.destroyed[0] != string(rt.created[0].SessionID) {
		t.Errorf("destroyed %q, want the handle that was just created", rt.destroyed[0])
	}
}

func TestCloseShellTerminalDestroysRuntimeAndDeletesRecord(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if err := svc.CloseShellTerminal(context.Background(), term.HandleID); err != nil {
		t.Fatalf("CloseShellTerminal: %v", err)
	}

	if len(st.records) != 0 {
		t.Errorf("records = %+v, want the row deleted", st.records)
	}
	if len(rt.destroyed) != 1 || rt.destroyed[0] != term.HandleID {
		t.Errorf("destroyed = %v, want %q", rt.destroyed, term.HandleID)
	}
}

func TestCloseShellTerminalReturnsNotFoundForUnknownHandle(t *testing.T) {
	svc := newTestService(t, newFakeShellRuntime(), &fakeShellTerminalStore{}, &fakeProjectRootLocator{})

	err := svc.CloseShellTerminal(context.Background(), "shellterm-missing")

	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Kind != apierr.KindNotFound {
		t.Fatalf("error = %v, want a not-found apierr", err)
	}
}

// TestCloseShellTerminalKeepsRowWhenRuntimeStaysAlive is the regression for
// the bug where CloseShellTerminal deleted the row BEFORE attempting Destroy,
// so a shell that survived (destroy failed and IsAlive confirms it) would
// vanish from tracking while still running. The row must now be kept, and the
// caller told the close didn't actually take.
func TestCloseShellTerminalKeepsRowWhenRuntimeStaysAlive(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	rt.destroyErr = errors.New("runtime: destroy refused")
	// aliveByHandle already has term.HandleID from the open above: still alive
	// despite the destroy error.

	err = svc.CloseShellTerminal(context.Background(), term.HandleID)

	var apiErr *apierr.Error
	if !errors.As(err, &apiErr) || apiErr.Kind != apierr.KindConflict {
		t.Fatalf("error = %v, want a conflict apierr", err)
	}
	if len(st.records) != 1 || st.records[0].HandleID != term.HandleID {
		t.Fatalf("records = %+v, want the still-alive shell's row kept", st.records)
	}
}

// The daemon may restart under a live app; the shells it left behind are still
// running and must come back as attachable tabs.
func TestListShellTerminalsForCurrentAppRunReturnsSurvivingTerminals(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})
	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}

	// A fresh Service over the SAME store and runtime stands in for the daemon
	// coming back up within one app run.
	restarted := NewService(rt, st, &fakeProjectRootLocator{}, nil, svc.dataDir, testAppRunID, testLogger())
	got, err := restarted.ListShellTerminalsForCurrentAppRun(context.Background())
	if err != nil {
		t.Fatalf("ListShellTerminalsForCurrentAppRun: %v", err)
	}
	if len(got) != 1 || got[0].HandleID != term.HandleID {
		t.Fatalf("terminals = %+v, want the surviving handle %q", got, term.HandleID)
	}
}

func TestListShellTerminalsForCurrentAppRunPrunesTerminalsWhoseShellExited(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})
	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	delete(rt.aliveByHandle, term.HandleID) // the user typed `exit`

	got, err := svc.ListShellTerminalsForCurrentAppRun(context.Background())
	if err != nil {
		t.Fatalf("ListShellTerminalsForCurrentAppRun: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("terminals = %+v, want the dead shell pruned", got)
	}
	if len(st.records) != 0 {
		t.Errorf("records = %+v, want the dead row deleted", st.records)
	}
}

// A probe ERROR is not proof of death — the same rule internal/terminal applies
// on attach. A transient runtime hiccup must not delete a working terminal.
func TestListShellTerminalsForCurrentAppRunKeepsTerminalWhenLivenessProbeErrors(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})
	if _, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{}); err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	rt.aliveErr = errors.New("runtime process unreachable")

	got, err := svc.ListShellTerminalsForCurrentAppRun(context.Background())
	if err != nil {
		t.Fatalf("ListShellTerminalsForCurrentAppRun: %v", err)
	}
	if len(got) != 1 {
		t.Errorf("terminals = %+v, want the row kept through a failed probe", got)
	}
	if len(st.records) != 1 {
		t.Errorf("records = %+v, want the row kept through a failed probe", st.records)
	}
}

// The app was force-killed, so nothing closed its shells. The next boot must
// sweep them rather than leak PTYs, while leaving the new run's shells alone.
func TestReapShellTerminalsFromPreviousAppRunsDestroysOrphansOnly(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{
		{HandleID: "shellterm-orphan1", AppRunID: "app-run-crashed", WorkingDir: "/a"},
		{HandleID: "shellterm-orphan2", AppRunID: "app-run-crashed", WorkingDir: "/b"},
		{HandleID: "shellterm-current", AppRunID: testAppRunID, WorkingDir: "/c"},
	}}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	cleared, err := svc.ReapShellTerminalsFromPreviousAppRuns(context.Background())
	if err != nil {
		t.Fatalf("ReapShellTerminalsFromPreviousAppRuns: %v", err)
	}
	if cleared != 2 {
		t.Errorf("cleared = %d, want 2", cleared)
	}
	if len(rt.destroyed) != 2 {
		t.Errorf("destroyed = %v, want both orphaned PTYs torn down", rt.destroyed)
	}
	if len(st.records) != 1 || st.records[0].HandleID != "shellterm-current" {
		t.Errorf("records = %+v, want only the current run's shell kept", st.records)
	}
}

// One un-destroyable PTY must not wedge the sweep: the rows are cleared anyway,
// or every future boot would retry the same failure forever.
func TestReapShellTerminalsFromPreviousAppRunsClearsRowsWhenDestroyFails(t *testing.T) {
	rt := newFakeShellRuntime()
	rt.destroyErr = errors.New("runtime: no such session")
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{
		{HandleID: "shellterm-orphan", AppRunID: "app-run-crashed", WorkingDir: "/a"},
	}}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	cleared, err := svc.ReapShellTerminalsFromPreviousAppRuns(context.Background())
	if err != nil {
		t.Fatalf("ReapShellTerminalsFromPreviousAppRuns: %v", err)
	}
	if cleared != 1 {
		t.Errorf("cleared = %d, want the row cleared despite the destroy failure", cleared)
	}
	if len(st.records) != 0 {
		t.Errorf("records = %+v, want cleared", st.records)
	}
}

// TestReapShellTerminalsFromPreviousAppRunsKeepsRowForConfirmedLiveOrphan is
// the boot-order regression: the old Reap bulk-deleted every orphan row after
// best-effort destroys, regardless of whether each one actually died. A shell
// that survived a crash independently of the daemon (its OS-level pty-host/conpty
// session outlives the process) would then have its row wiped anyway. Reap
// must keep that row instead.
func TestReapShellTerminalsFromPreviousAppRunsKeepsRowForConfirmedLiveOrphan(t *testing.T) {
	rt := newFakeShellRuntime()
	rt.destroyErr = errors.New("runtime: destroy refused")
	rt.aliveByHandle["shellterm-orphan-alive"] = true // survives the crash, still alive
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{
		{HandleID: "shellterm-orphan-alive", AppRunID: "app-run-crashed", WorkingDir: "/a"},
		{HandleID: "shellterm-orphan-dead", AppRunID: "app-run-crashed", WorkingDir: "/b"},
	}}
	svc := newTestService(t, rt, st, &fakeProjectRootLocator{})

	cleared, err := svc.ReapShellTerminalsFromPreviousAppRuns(context.Background())
	if err != nil {
		t.Fatalf("ReapShellTerminalsFromPreviousAppRuns: %v", err)
	}
	if cleared != 1 {
		t.Errorf("cleared = %d, want only the confirmed-dead orphan counted", cleared)
	}
	if len(st.records) != 1 || st.records[0].HandleID != "shellterm-orphan-alive" {
		t.Fatalf("records = %+v, want the still-alive orphan's row kept", st.records)
	}
}

func TestShellTerminalTitleFallsBackForRootlessPaths(t *testing.T) {
	if got := shellTerminalTitle(""); got != "Shell" {
		t.Errorf("title for empty path = %q, want %q", got, "Shell")
	}
	if got := shellTerminalTitle("/repos/portfolio"); got != "portfolio" {
		t.Errorf("title = %q, want %q", got, "portfolio")
	}
}

func indexOf(ss []string, want string) int {
	for i, s := range ss {
		if s == want {
			return i
		}
	}
	return -1
}

func TestOpenShellTerminalStartsCapture(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	capturer := &fakeCaptureLifecycle{log: &callLog{}}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if len(capturer.started) != 1 || capturer.started[0] != term.HandleID {
		t.Fatalf("capture Start calls = %v, want [%s]", capturer.started, term.HandleID)
	}
	if !term.DurableBlocks {
		t.Fatal("DurableBlocks = false, want true on a supported runtime")
	}
	if len(st.records) != 1 {
		t.Fatalf("records = %+v, want the row kept", st.records)
	}
}

func TestOpenShellTerminalUnsupportedCaptureStillOpens(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	capturer := &fakeCaptureLifecycle{log: &callLog{}, unsupported: true}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if term.DurableBlocks {
		t.Fatal("DurableBlocks = true, want false when the runtime cannot capture")
	}
	if len(rt.destroyed) != 0 {
		t.Fatalf("destroyed = %v, want no rollback for an unsupported runtime", rt.destroyed)
	}
	if len(st.records) != 1 {
		t.Fatalf("records = %+v, want the row kept", st.records)
	}
}

func TestOpenShellTerminalRollsBackWhenCaptureStartFails(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	capturer := &fakeCaptureLifecycle{log: &callLog{}, startErr: errors.New("pipe-pane: server not found")}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	if _, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{}); err == nil {
		t.Fatal("OpenShellTerminal succeeded despite a capture start failure on a supported runtime")
	}
	if len(rt.destroyed) != 1 {
		t.Fatalf("destroyed = %v, want the spawned PTY rolled back", rt.destroyed)
	}
	if len(st.records) != 0 {
		t.Fatalf("records = %+v, want the row deleted", st.records)
	}
}

func TestCloseShellTerminalStopsCaptureBeforeDestroy(t *testing.T) {
	rt := newFakeShellRuntime()
	log := &callLog{}
	rt.log = log
	st := &fakeShellTerminalStore{}
	capturer := &fakeCaptureLifecycle{log: log}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if err := svc.CloseShellTerminal(context.Background(), term.HandleID); err != nil {
		t.Fatalf("CloseShellTerminal: %v", err)
	}

	ev := log.snapshot()
	sd := indexOf(ev, "stopdrain:"+term.HandleID)
	de := indexOf(ev, "destroy:"+term.HandleID)
	if sd < 0 || de < 0 || sd > de {
		t.Fatalf("event order = %v, want stopdrain before destroy", ev)
	}
}

func TestCloseShellTerminalFailedDrainPreservesRow(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	capturer := &fakeCaptureLifecycle{log: &callLog{}, stopErr: errors.New("final drain: disk full")}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if err := svc.CloseShellTerminal(context.Background(), term.HandleID); err == nil {
		t.Fatal("CloseShellTerminal succeeded despite a capture drain failure")
	}
	if len(rt.destroyed) != 0 {
		t.Fatalf("destroyed = %v, want the PTY left running after a drain failure", rt.destroyed)
	}
	if len(st.records) != 1 {
		t.Fatalf("records = %+v, want the row preserved", st.records)
	}
}

func TestOpenShellTerminalNilCaptureReportsNoDurableBlocks(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, nil)

	term, err := svc.OpenShellTerminal(context.Background(), OpenShellTerminalInput{})
	if err != nil {
		t.Fatalf("OpenShellTerminal: %v", err)
	}
	if term.DurableBlocks {
		t.Fatal("DurableBlocks = true with no capture lifecycle wired; want false")
	}
}

func TestListAndRenameReflectLiveCaptureState(t *testing.T) {
	rt := newFakeShellRuntime()
	st := &fakeShellTerminalStore{records: []ShellTerminalRecord{
		{HandleID: "shellterm-captured", AppRunID: testAppRunID, WorkingDir: "/a", Title: "a"},
		{HandleID: "shellterm-uncaptured", AppRunID: testAppRunID, WorkingDir: "/b", Title: "b"},
	}}
	rt.aliveByHandle["shellterm-captured"] = true
	rt.aliveByHandle["shellterm-uncaptured"] = true
	capturer := &fakeCaptureLifecycle{log: &callLog{}, live: map[string]bool{"shellterm-captured": true}}
	svc := newTestServiceWithCapture(t, rt, st, &fakeProjectRootLocator{}, capturer)

	list, err := svc.ListShellTerminalsForCurrentAppRun(context.Background())
	if err != nil {
		t.Fatalf("ListShellTerminalsForCurrentAppRun: %v", err)
	}
	got := map[string]bool{}
	for _, term := range list {
		got[term.HandleID] = term.DurableBlocks
	}
	if !got["shellterm-captured"] {
		t.Error("list: captured handle reported DurableBlocks=false")
	}
	if got["shellterm-uncaptured"] {
		t.Error("list: uncaptured handle reported DurableBlocks=true")
	}

	renamed, err := svc.RenameShellTerminal(context.Background(), "shellterm-captured", "logs")
	if err != nil {
		t.Fatalf("RenameShellTerminal: %v", err)
	}
	if !renamed.DurableBlocks {
		t.Error("rename: captured handle reported DurableBlocks=false")
	}
}
