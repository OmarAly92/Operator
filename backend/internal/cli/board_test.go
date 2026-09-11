package cli

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestBoardRendersLiveWorkersForProject(t *testing.T) {
	cfg := setConfigEnv(t)
	var gotQuery string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.RawQuery
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[
			{"id":"opr-1","projectId":"proj-1","kind":"worker","displayName":"resize fix","status":"ci_failed",
			 "activity":{"state":"idle"},"brief":"fix the flaky resize test",
			 "latestAssistantUpdate":"Pushed a fix; CI is still red.",
			 "prs":[{"url":"u","number":7,"state":"open","ci":"failing","review":"none"}]},
			{"id":"opr-2","projectId":"proj-1","kind":"orchestrator","status":"idle","activity":{"state":"idle"}}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(gotQuery, "project=proj-1") || !strings.Contains(gotQuery, "active=true") {
		t.Fatalf("query = %q, want project and active filters", gotQuery)
	}
	for _, want := range []string{"opr-1", "resize fix", "ci_failed", "fix the flaky resize test", "Pushed a fix; CI is still red.", "#7 open ci=failing"} {
		if !strings.Contains(out, want) {
			t.Fatalf("board output missing %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "opr-2") {
		t.Fatalf("board listed the orchestrator itself:\n%s", out)
	}
}

func TestBoardJSONIncludesBriefAndPRFields(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[
			{"id":"opr-1","projectId":"proj-1","kind":"worker","displayName":"resize fix","status":"ci_failed",
			 "activity":{"state":"idle"},"brief":"fix the flaky resize test",
			 "latestUserPrompt":"also check the codex path",
			 "latestAssistantUpdate":"Pushed a fix; CI is still red.",
			 "prs":[{"url":"u","number":7,"state":"open","ci":"failing","review":"none"}]}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "proj-1", "--json")
	if err != nil {
		t.Fatal(err)
	}

	var decoded boardOutput
	if err := json.Unmarshal([]byte(out), &decoded); err != nil {
		t.Fatalf("output is not valid JSON: %v\n%s", err, out)
	}
	if len(decoded.Data) != 1 {
		t.Fatalf("data length = %d, want 1", len(decoded.Data))
	}
	got := decoded.Data[0]
	if got.Brief != "fix the flaky resize test" {
		t.Fatalf("brief = %q", got.Brief)
	}
	if got.LatestUserPrompt != "also check the codex path" {
		t.Fatalf("latestUserPrompt = %q", got.LatestUserPrompt)
	}
	if got.LatestAssistantUpdate != "Pushed a fix; CI is still red." {
		t.Fatalf("latestAssistantUpdate = %q", got.LatestAssistantUpdate)
	}
	if len(got.PRs) != 1 || got.PRs[0].Number != 7 || got.PRs[0].State != "open" || got.PRs[0].CI != "failing" {
		t.Fatalf("prs = %+v", got.PRs)
	}
}

func TestBoardRequiresProjectWhenNotInASession(t *testing.T) {
	t.Setenv("OPERATOR_SESSION_ID", "")
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	_, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board")
	if err == nil {
		t.Fatal("expected a usage error when no project can be resolved")
	}
	if ExitCode(err) != 2 {
		t.Fatalf("exit code = %d, want 2", ExitCode(err))
	}
}

func TestBoardReportsAnEmptyProject(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "proj-1")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "(no live workers)") {
		t.Fatalf("output = %q", out)
	}
}

func TestBoardShowsLatestUserPromptWhenBriefIsEmpty(t *testing.T) {
	cfg := setConfigEnv(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"sessions":[
			{"id":"scratch-14","projectId":"scratch","kind":"worker","status":"working",
			 "activity":{"state":"idle"},
			 "latestUserPrompt":"search for new iphone 18",
			 "latestAssistantUpdate":"Here is what I found."}
		]}`)
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "board", "--project", "scratch")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "last prompt: search for new iphone 18") {
		t.Fatalf("board hid the latest user prompt, the only field that says what the work is:\n%s", out)
	}
	if !strings.Contains(out, "last update: Here is what I found.") {
		t.Fatalf("board dropped the assistant update:\n%s", out)
	}
}
