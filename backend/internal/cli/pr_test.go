package cli

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPRMergePostsToDaemon(t *testing.T) {
	cfg := setConfigEnv(t)
	srv, capture := reviewServer(t, http.StatusOK, `{"ok":true,"prNumber":42,"method":"squash"}`)
	writeRunFileFor(t, cfg, srv)

	out, errOut, err := executeCLI(t, aliveDeps(), "pr", "merge", "#42", "--url", "https://github.com/acme/widgets/pull/42", "--head-sha", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	if err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	if capture.method != http.MethodPost || capture.path != "/api/v1/prs/42/merge" {
		t.Fatalf("request = %s %s", capture.method, capture.path)
	}
	if want := `{"prUrl":"https://github.com/acme/widgets/pull/42","expectedHeadSha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`; strings.TrimSpace(capture.body) != want {
		t.Fatalf("body = %q, want %s", capture.body, want)
	}
	if !strings.Contains(out, "merged PR #42 using squash") {
		t.Fatalf("stdout = %q", out)
	}
}

func TestPRMergeOmitsMissingMethodFromOutput(t *testing.T) {
	cfg := setConfigEnv(t)
	srv, _ := reviewServer(t, http.StatusOK, `{"ok":true,"prNumber":42}`)
	writeRunFileFor(t, cfg, srv)

	out, errOut, err := executeCLI(t, aliveDeps(), "pr", "merge", "42", "--url", "u", "--head-sha", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	if err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	if out != "merged PR #42\n" {
		t.Fatalf("stdout = %q, want %q", out, "merged PR #42\n")
	}
}

func TestPRMergeRejectsInvalidNumber(t *testing.T) {
	setConfigEnv(t)

	for _, number := range []string{"0", "-1", "abc", "#"} {
		t.Run(number, func(t *testing.T) {
			_, _, err := executeCLI(t, aliveDeps(), "pr", "merge", number)
			if got := ExitCode(err); got != 2 {
				t.Fatalf("exit code = %d, want 2; err=%v", got, err)
			}
		})
	}
}

func TestPRMergeRequiresExactlyOneArgument(t *testing.T) {
	setConfigEnv(t)

	for _, args := range [][]string{
		{"pr", "merge"},
		{"pr", "merge", "42", "43"},
	} {
		_, _, err := executeCLI(t, aliveDeps(), args...)
		if got := ExitCode(err); got != 2 {
			t.Fatalf("args = %v, exit code = %d, want 2; err=%v", args, got, err)
		}
	}
}

func TestPRMergeSurfacesDaemonError(t *testing.T) {
	cfg := setConfigEnv(t)
	srv, _ := reviewServer(t, http.StatusConflict, `{"message":"PR is not mergeable","code":"PR_NOT_MERGEABLE","requestId":"req-1"}`)
	writeRunFileFor(t, cfg, srv)

	_, _, err := executeCLI(t, aliveDeps(), "pr", "merge", "42", "--url", "u", "--head-sha", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	if got := ExitCode(err); got != 1 {
		t.Fatalf("exit code = %d, want 1; err=%v", got, err)
	}
	for _, want := range []string{"PR is not mergeable", "PR_NOT_MERGEABLE", "req-1"} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("err = %q, want %q", err, want)
		}
	}
}

func TestPRResolveCommentsPostsIDs(t *testing.T) {
	cfg := setConfigEnv(t)
	srv, capture := reviewServer(t, http.StatusOK, `{"ok":true,"resolved":2}`)
	writeRunFileFor(t, cfg, srv)

	out, errOut, err := executeCLI(t, aliveDeps(), "pr", "resolve-comments", "42", "thread-1", "thread-2", "--url", "https://github.com/acme/widgets/pull/42")
	if err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	if capture.method != http.MethodPost || capture.path != "/api/v1/prs/42/resolve-comments" {
		t.Fatalf("request = %s %s", capture.method, capture.path)
	}
	var req resolveCommentsRequest
	if err := json.Unmarshal([]byte(capture.body), &req); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if req.PRURL != "https://github.com/acme/widgets/pull/42" {
		t.Fatalf("pr url = %q", req.PRURL)
	}
	if len(req.CommentIDs) != 2 || req.CommentIDs[0] != "thread-1" || req.CommentIDs[1] != "thread-2" {
		t.Fatalf("comment ids = %v", req.CommentIDs)
	}
	if !strings.Contains(out, "resolved 2 review thread(s) on PR #42") {
		t.Fatalf("stdout = %q", out)
	}
}

func TestPRResolveCommentsAllowsNoIDs(t *testing.T) {
	cfg := setConfigEnv(t)
	srv, capture := reviewServer(t, http.StatusOK, `{"ok":true,"resolved":3}`)
	writeRunFileFor(t, cfg, srv)

	if _, errOut, err := executeCLI(t, aliveDeps(), "pr", "resolve-comments", "42", "--url", "https://github.com/acme/widgets/pull/42"); err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	if want := `{"prUrl":"https://github.com/acme/widgets/pull/42"}`; strings.TrimSpace(capture.body) != want {
		t.Fatalf("body = %q, want %s", capture.body, want)
	}
}

func TestPRResolveCommentsNeedsURLOrSession(t *testing.T) {
	setConfigEnv(t)
	t.Setenv("OPERATOR_SESSION_ID", "")

	_, _, err := executeCLI(t, aliveDeps(), "pr", "resolve-comments", "42")
	if got := ExitCode(err); got != 2 {
		t.Fatalf("exit code = %d, want 2; err=%v", got, err)
	}
}

func TestPRResolveCommentsRequiresPRNumber(t *testing.T) {
	setConfigEnv(t)

	_, _, err := executeCLI(t, aliveDeps(), "pr", "resolve-comments")
	if got := ExitCode(err); got != 2 {
		t.Fatalf("exit code = %d, want 2; err=%v", got, err)
	}
}

// prSessionServer serves a session's PR list and records the action posted.
func prSessionServer(t *testing.T, prs string) (*httptest.Server, *map[string]string) {
	t.Helper()
	posted := map[string]string{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/api/v1/sessions/opr-7/pr":
			_, _ = io.WriteString(w, `{"sessionId":"opr-7","prs":`+prs+`}`)
		case r.URL.Path == "/api/v1/prs/42/merge":
			posted[r.URL.Path] = string(body)
			_, _ = io.WriteString(w, `{"ok":true,"prNumber":42,"method":"squash"}`)
		case r.URL.Path == "/api/v1/prs/42/resolve-comments":
			posted[r.URL.Path] = string(body)
			_, _ = io.WriteString(w, `{"ok":true,"resolved":1}`)
		default:
			w.WriteHeader(http.StatusAccepted)
		}
	}))
	t.Cleanup(srv.Close)
	return srv, &posted
}

const sessionPRs = `[{"url":"https://github.com/acme/widgets/pull/42","number":42,"headSha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},` +
	`{"url":"https://github.com/acme/other/pull/7","number":7,"headSha":"cccccccccccccccccccccccccccccccccccccccc"}]`

func TestPRMergeLooksUpURLAndHeadFromTheSession(t *testing.T) {
	cfg := setConfigEnv(t)
	t.Setenv("OPERATOR_SESSION_ID", "opr-7")
	srv, posted := prSessionServer(t, sessionPRs)
	writeRunFileFor(t, cfg, srv)

	if _, errOut, err := executeCLI(t, aliveDeps(), "pr", "merge", "42"); err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	want := `{"prUrl":"https://github.com/acme/widgets/pull/42","expectedHeadSha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}`
	if got := strings.TrimSpace((*posted)["/api/v1/prs/42/merge"]); got != want {
		t.Fatalf("merge body = %s, want %s", got, want)
	}
}

func TestPRResolveCommentsLooksUpURLFromSessionFlag(t *testing.T) {
	cfg := setConfigEnv(t)
	t.Setenv("OPERATOR_SESSION_ID", "")
	srv, posted := prSessionServer(t, sessionPRs)
	writeRunFileFor(t, cfg, srv)

	if _, errOut, err := executeCLI(t, aliveDeps(), "pr", "resolve-comments", "42", "--session", "opr-7"); err != nil {
		t.Fatalf("unexpected error: %v\nstderr=%s", err, errOut)
	}
	if got := strings.TrimSpace((*posted)["/api/v1/prs/42/resolve-comments"]); got != `{"prUrl":"https://github.com/acme/widgets/pull/42"}` {
		t.Fatalf("resolve body = %s", got)
	}
}

func TestPRMergeLookupRefusesUnknownOrAmbiguousPRs(t *testing.T) {
	for _, tc := range []struct {
		name string
		prs  string
		code int
	}{
		{"not the session's", `[]`, 1},
		{"number in two repos", `[{"url":"https://github.com/a/b/pull/42","number":42,"headSha":"x"},{"url":"https://github.com/c/d/pull/42","number":42,"headSha":"y"}]`, 2},
		{"head not observed", `[{"url":"https://github.com/a/b/pull/42","number":42}]`, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cfg := setConfigEnv(t)
			t.Setenv("OPERATOR_SESSION_ID", "opr-7")
			srv, posted := prSessionServer(t, tc.prs)
			writeRunFileFor(t, cfg, srv)

			_, _, err := executeCLI(t, aliveDeps(), "pr", "merge", "42")
			if got := ExitCode(err); got != tc.code {
				t.Fatalf("exit code = %d, want %d; err=%v", got, tc.code, err)
			}
			if len(*posted) != 0 {
				t.Fatalf("posted %v, want no merge", *posted)
			}
		})
	}
}

func TestPRMergeNeedsFlagsOrSession(t *testing.T) {
	setConfigEnv(t)
	t.Setenv("OPERATOR_SESSION_ID", "")

	_, _, err := executeCLI(t, aliveDeps(), "pr", "merge", "42", "--url", "https://github.com/acme/widgets/pull/42")
	if got := ExitCode(err); got != 2 {
		t.Fatalf("exit code = %d, want 2; err=%v", got, err)
	}
}
