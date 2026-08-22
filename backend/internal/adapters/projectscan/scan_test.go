package projectscan

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestMain(m *testing.M) {
	switch os.Getenv("OPERATOR_PROJECTSCAN_HELPER") {
	case "slow-git":
		time.Sleep(500 * time.Millisecond)
		fmt.Println("slow-git")
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func runGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v in %s: %v (%s)", args, dir, err, out)
	}
	return string(out)
}

func commitAll(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o750); err != nil {
		t.Fatalf("mkdir %s: %v", dir, err)
	}
	runGit(t, dir, "init", "-b", "main")
	runGit(t, dir, "config", "user.email", "opr@example.com")
	runGit(t, dir, "config", "user.name", "Operator Tests")
	if err := os.WriteFile(filepath.Join(dir, "README.md"), []byte("hi\n"), 0o644); err != nil {
		t.Fatalf("write README: %v", err)
	}
	runGit(t, dir, "add", ".")
	runGit(t, dir, "commit", "-m", "initial")
}

func makeImportableRepo(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o750); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
	commitAll(t, path)
	runGit(t, path, "remote", "add", "origin", "https://example.com/"+filepath.Base(path)+".git")
}

func newRealScanner(homeDir string) *Scanner {
	return New(Options{HomeDir: homeDir})
}

func findRepo(repos []Repo, name string) (Repo, bool) {
	for _, repo := range repos {
		if repo.Name == name {
			return repo, true
		}
	}
	return Repo{}, false
}

func TestScanFolderWorkspaceFindsAndValidatesRepositories(t *testing.T) {
	root := t.TempDir()

	makeImportableRepo(t, filepath.Join(root, "alpha"))
	bare := filepath.Join(root, "bare-repo")
	if err := os.MkdirAll(bare, 0o750); err != nil {
		t.Fatal(err)
	}
	runGit(t, bare, "init", "--bare")

	noCommits := filepath.Join(root, "no-commits")
	if err := os.MkdirAll(noCommits, 0o750); err != nil {
		t.Fatal(err)
	}
	runGit(t, noCommits, "init", "-b", "main")

	noRemote := filepath.Join(root, "no-remote")
	commitAll(t, noRemote)

	worktree := filepath.Join(root, "linked-worktree")
	if err := os.MkdirAll(worktree, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(worktree, ".git"), []byte("gitdir: /elsewhere/.git/worktrees/x\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	detached := filepath.Join(root, "detached")
	commitAll(t, detached)
	runGit(t, detached, "checkout", "--detach", "HEAD")

	reserved := filepath.Join(root, "__root__")
	makeImportableRepo(t, reserved)

	if err := os.MkdirAll(filepath.Join(root, "plain-dir"), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "node_modules"), 0o750); err != nil {
		t.Fatal(err)
	}

	res, err := newRealScanner("").ScanFolder(context.Background(), root, ModeWorkspace)
	if err != nil {
		t.Fatalf("scan workspace: %v", err)
	}
	if res.Path != root {
		t.Errorf("path = %q, want %q", res.Path, root)
	}
	if res.SetupWarning != "" {
		t.Errorf("setupWarning = %q, want none", res.SetupWarning)
	}

	alpha, ok := findRepo(res.Repos, "alpha")
	if !ok {
		t.Fatalf("alpha missing from %+v", res.Repos)
	}
	if alpha.Status != StatusOK || alpha.Reason != "" {
		t.Errorf("alpha = %+v, want ok with no reason", alpha)
	}
	if alpha.Branch != "main" || !alpha.HasRemote || alpha.Remote != "https://example.com/alpha.git" {
		t.Errorf("alpha = %+v, want main branch and origin remote", alpha)
	}
	if alpha.RelativePath != "alpha" {
		t.Errorf("relativePath = %q, want alpha", alpha.RelativePath)
	}

	bareRepo, ok := findRepo(res.Repos, "bare-repo")
	if !ok || bareRepo.Status != StatusError || bareRepo.Reason != "Bare repositories cannot be imported." {
		t.Errorf("bare-repo = %+v, want bare import error", bareRepo)
	}
	noCommitRepo, ok := findRepo(res.Repos, "no-commits")
	if !ok || noCommitRepo.Reason != "Repository must have at least one commit." {
		t.Errorf("no-commits = %+v, want missing-commit reason", noCommitRepo)
	}
	noRemoteRepo, ok := findRepo(res.Repos, "no-remote")
	if !ok || noRemoteRepo.Status != StatusError || noRemoteRepo.Reason != "Origin remote is required." {
		t.Errorf("no-remote = %+v, want missing-origin reason", noRemoteRepo)
	}
	worktreeRepo, ok := findRepo(res.Repos, "linked-worktree")
	if !ok || worktreeRepo.Reason != "Linked worktree children cannot be imported." {
		t.Errorf("linked-worktree = %+v, want linked-worktree reason", worktreeRepo)
	}
	detachedRepo, ok := findRepo(res.Repos, "detached")
	if !ok || detachedRepo.Branch != "HEAD" || detachedRepo.Reason != "Repository must have a checked-out branch." {
		t.Errorf("detached = %+v, want detached-HEAD reason", detachedRepo)
	}
	reservedRepo, ok := findRepo(res.Repos, "__root__")
	if !ok || reservedRepo.Reason != "Repository name is reserved by Operator." {
		t.Errorf("__root__ = %+v, want reserved-name reason", reservedRepo)
	}

	if _, ok := findRepo(res.Repos, "plain-dir"); ok {
		t.Errorf("plain-dir scanned as a repository: %+v", res.Repos)
	}
	if _, ok := findRepo(res.Repos, "node_modules"); ok {
		t.Errorf("node_modules not skipped: %+v", res.Repos)
	}

	for i := 1; i < len(res.Repos); i++ {
		if res.Repos[i-1].Name > res.Repos[i].Name {
			t.Fatalf("repos not sorted by name: %+v", res.Repos)
		}
	}
}

func TestScanFolderProjectMode(t *testing.T) {
	root := t.TempDir()
	repoA := filepath.Join(root, "repo-a")
	makeImportableRepo(t, repoA)

	scanner := newRealScanner("")
	res, err := scanner.ScanFolder(context.Background(), repoA, ModeProject)
	if err != nil {
		t.Fatalf("scan project: %v", err)
	}
	if len(res.Repos) != 1 {
		t.Fatalf("repos = %+v, want exactly the root repository", res.Repos)
	}
	rootRepo := res.Repos[0]
	if rootRepo.Name != "repo-a" || rootRepo.RelativePath != "." || rootRepo.Status != StatusOK {
		t.Errorf("root repo = %+v, want ok repo-a at .", rootRepo)
	}
	if rootRepo.Path != repoA {
		t.Errorf("path = %q, want %q", rootRepo.Path, repoA)
	}

	nested := filepath.Join(repoA, "nested")
	if err := os.MkdirAll(nested, 0o750); err != nil {
		t.Fatal(err)
	}
	warning := scanner.AncestorRepository(context.Background(), nested)
	if !strings.Contains(warning, repoA) {
		t.Errorf("warning = %q, want it to mention %q", warning, repoA)
	}
	if warning := scanner.AncestorRepository(context.Background(), repoA); warning != "" {
		t.Errorf("warning = %q, want none for the repository root itself", warning)
	}
}

func TestAncestorRepositoryWarnsWhenParentIsRepository(t *testing.T) {
	parent := t.TempDir()
	makeImportableRepo(t, parent)
	inner := filepath.Join(parent, "inner")
	if err := os.MkdirAll(inner, 0o750); err != nil {
		t.Fatal(err)
	}

	scanner := newRealScanner("")
	warning := scanner.AncestorRepository(context.Background(), inner)
	if warning == "" {
		t.Fatal("warning = empty, want an ancestor-repository warning")
	}
	if !strings.Contains(warning, parent) {
		t.Errorf("warning = %q, want it to name the parent repository %q", warning, parent)
	}
	if !strings.Contains(warning, "Selected folder is inside an existing Git repository at ") {
		t.Errorf("warning = %q, want the desktop wording", warning)
	}
}

func TestScanFolderProjectModeFlagsOperatorStateDir(t *testing.T) {
	home := t.TempDir()
	inside := filepath.Join(home, ".operator", "inner")
	makeImportableRepo(t, inside)

	res, err := newRealScanner(home).ScanFolder(context.Background(), inside, ModeProject)
	if err != nil {
		t.Fatalf("scan project: %v", err)
	}
	if len(res.Repos) != 1 {
		t.Fatalf("repos = %+v, want the single safety-error result", res.Repos)
	}
	repo := res.Repos[0]
	if repo.Status != StatusError {
		t.Errorf("status = %q, want error", repo.Status)
	}
	want := "Selected folder is inside Operator's internal data directory. Select a project folder outside ~/.operator."
	if repo.Reason != want {
		t.Errorf("reason = %q, want %q", repo.Reason, want)
	}
}

func TestScanFolderSkipsSymlinksIncludingLoops(t *testing.T) {
	root := t.TempDir()
	repoA := filepath.Join(root, "repo-a")
	makeImportableRepo(t, repoA)
	if err := os.Symlink(root, filepath.Join(root, "loop")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(root, "missing-target"), filepath.Join(root, "dangling")); err != nil {
		t.Fatal(err)
	}

	done := make(chan struct{})
	var res Result
	var err error
	go func() {
		defer close(done)
		res, err = newRealScanner("").ScanFolder(context.Background(), root, ModeWorkspace)
	}()
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		t.Fatal("workspace scan hung on a symlink loop")
	}
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if len(res.Repos) != 1 || res.Repos[0].Name != "repo-a" {
		t.Fatalf("repos = %+v, want only repo-a (symlinks are not directories)", res.Repos)
	}
}

func TestScanFolderCanceledContext(t *testing.T) {
	root := t.TempDir()
	makeImportableRepo(t, filepath.Join(root, "repo-a"))

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := newRealScanner("").ScanFolder(ctx, root, ModeWorkspace); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
}

type fakeGit struct {
	mu           sync.Mutex
	activeDirs   map[string]int
	maxActive    int
	seenDirs     map[string]bool
	arrivals     int
	releaseAfter int
	release      chan struct{}
	once         sync.Once
}

func newFakeGit(releaseAfter int) *fakeGit {
	return &fakeGit{
		activeDirs:   map[string]int{},
		seenDirs:     map[string]bool{},
		releaseAfter: releaseAfter,
		release:      make(chan struct{}),
	}
}

func (f *fakeGit) gitOutput(_ context.Context, dir string, args []string) (string, error) {
	f.mu.Lock()
	f.seenDirs[dir] = true
	f.activeDirs[dir]++
	if active := len(f.activeDirs); active > f.maxActive {
		f.maxActive = active
	}
	gate := f.releaseAfter > 0 && len(args) >= 2 && args[0] == "rev-parse" && args[1] == "--is-bare-repository"
	if gate {
		f.arrivals++
		if f.arrivals >= f.releaseAfter {
			f.once.Do(func() { close(f.release) })
		}
	}
	f.mu.Unlock()
	if gate {
		select {
		case <-f.release:
		case <-time.After(10 * time.Second):
		}
	}

	var (
		out = ""
		err error
	)
	switch {
	case len(args) >= 2 && args[0] == "rev-parse" && args[1] == "--show-toplevel":
		out = dir
	case len(args) >= 2 && args[0] == "rev-parse" && args[1] == "--is-bare-repository":
		out = "false"
	case args[0] == "remote":
		out = "https://example.com/repo.git"
	case args[0] == "branch":
		out = "main"
	case args[0] == "symbolic-ref":
		err = errors.New("no origin/HEAD")
	}

	f.mu.Lock()
	f.activeDirs[dir]--
	if f.activeDirs[dir] == 0 {
		delete(f.activeDirs, dir)
	}
	f.mu.Unlock()
	return out, err
}

func TestScanFolderLimitsEntriesTo200(t *testing.T) {
	root := t.TempDir()
	const total = 210
	for i := 0; i < total; i++ {
		dir := filepath.Join(root, fmt.Sprintf("d%03d", i))
		if err := os.MkdirAll(filepath.Join(dir, ".git"), 0o750); err != nil {
			t.Fatal(err)
		}
	}

	s := New(Options{})
	s.runner = newFakeGit(0)
	res, err := s.ScanFolder(context.Background(), root, ModeWorkspace)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	scanned := 0
	for dir := range s.runner.(*fakeGit).seenDirs {
		if dir != root {
			scanned++
		}
	}
	if scanned > maxScanEntries {
		t.Fatalf("scanned %d entries, want at most %d", scanned, maxScanEntries)
	}
	if len(res.Repos) != maxScanEntries {
		t.Fatalf("repos = %d, want %d", len(res.Repos), maxScanEntries)
	}
	if _, ok := findRepo(res.Repos, "d209"); ok {
		t.Errorf("entry beyond the cap was scanned: %+v", res.Repos[len(res.Repos)-1])
	}
}

func TestScanFolderUsesEightWorkers(t *testing.T) {
	root := t.TempDir()
	const total = 16
	for i := 0; i < total; i++ {
		dir := filepath.Join(root, fmt.Sprintf("r%02d", i))
		if err := os.MkdirAll(filepath.Join(dir, ".git"), 0o750); err != nil {
			t.Fatal(err)
		}
	}

	s := New(Options{})
	s.runner = newFakeGit(scanConcurrency)
	if _, err := s.ScanFolder(context.Background(), root, ModeWorkspace); err != nil {
		t.Fatalf("scan: %v", err)
	}
	got := s.runner.(*fakeGit).maxActive
	if got != scanConcurrency {
		t.Fatalf("max concurrent repositories = %d, want %d", got, scanConcurrency)
	}
}

func TestGitCommandTimeout(t *testing.T) {
	if runtime.GOOS == "js" {
		t.Skip("helper process unavailable")
	}
	t.Setenv("OPERATOR_PROJECTSCAN_HELPER", "slow-git")
	root := t.TempDir()
	repo := filepath.Join(root, "slow-repo")
	if err := os.MkdirAll(filepath.Join(repo, ".git"), 0o750); err != nil {
		t.Fatal(err)
	}

	s := New(Options{GitBin: os.Args[0], Timeout: 50 * time.Millisecond})

	if _, err := s.gitOutput(context.Background(), repo, []string{"rev-parse", "--show-toplevel"}); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err = %v, want context.DeadlineExceeded from the five-second-timeout wiring", err)
	}

	res, err := s.ScanFolder(context.Background(), root, ModeWorkspace)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if len(res.Repos) != 0 {
		t.Fatalf("repos = %+v, want the timed-out candidate dropped", res.Repos)
	}
}
