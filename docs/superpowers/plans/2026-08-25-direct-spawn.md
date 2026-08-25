# Operator Direct Spawn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make normal `opr spawn` proceed directly to the daemon's real session-spawn operation without refreshing or probing the advisory agent catalog first.

**Architecture:** The CLI retains deterministic request, project, harness-selection, Scratch, and pull-request validation, then posts `POST /api/v1/sessions`. The daemon Session Manager remains the sole authority for requested-harness support, Chat compatibility/authentication, TUI runtime prerequisites, binary resolution, workspace/runtime creation, lifecycle state, and rollback. Agent catalog refresh and one-agent probes remain available only through explicit diagnostic surfaces.

**Tech Stack:** Go 1.25.7, Cobra/pflag, loopback HTTP daemon API, `httptest`, existing Session Manager and agent catalog services, Markdown/MDX documentation.

**Spec:** `docs/todo/operator-approach-3-direct-spawn-spec.md`

## Global Constraints

- Normal `opr spawn` must not call `POST /api/v1/agents/refresh` or `POST /api/v1/agents/{agent}/probe`.
- Keep deterministic CLI validation for command syntax, display name, mode, kind, project resolution, harness selection, Scratch restrictions, and pull-request references.
- Keep daemon validation for unknown harnesses, Chat driver capability/authentication, TUI runtime prerequisites, requested binary resolution, workspace/runtime creation, and launch failure.
- Do not modify `backend/internal/session_manager/`, `backend/internal/service/session/`, agent adapters, API DTOs, OpenAPI, or generated clients unless a failing preservation test proves the existing contract is broken.
- Keep `--skip-agent-check` accepted as a silent compatibility no-op for existing scripts. Do not require it and do not preserve catalog preflight behind another default-on flag.
- Keep `opr agent ls`, `opr agent ls --refresh`, `/agents/refresh`, and `/agents/{agent}/probe` unchanged as explicit diagnostic behavior.
- Preserve typed daemon error envelopes, request IDs, spawn telemetry, session lifecycle, worktree isolation, runtime cleanup, and rollback behavior.
- Do not claim that TUI spawn proves the agent is authenticated or ready for its first model request. This phase proves binary/runtime launch only; provider-specific TUI readiness is deferred.
- Do not parse terminal output or provider strings to infer authentication.
- Do not add live agent, network, timing-threshold, or provider-account dependencies to tests. Use `httptest` and existing fakes.
- Do not change desktop or Flutter spawn code: both already call `POST /api/v1/sessions` directly.
- Preserve all unrelated working-tree changes, especially the existing Tauri startup fixes. Stage only files named by the current task.

## Planned File Structure

| Path | Responsibility |
|---|---|
| `backend/internal/cli/spawn.go` | Validate CLI input, resolve project/harness, preserve compatibility flag, and post the authoritative session request without catalog preflight. |
| `backend/internal/cli/spawn_test.go` | Prove direct request order, compatibility behavior, daemon error propagation, and unchanged project/claim behavior. |
| `backend/internal/cli/agent_test.go` | Existing proof that cached and explicitly refreshed diagnostics remain available; no production behavior change. |
| `docs/cli/README.md` | Canonical CLI architecture and direct-spawn semantics. |
| `frontend/src/landing/content/docs/cli.mdx` | User-facing CLI command and compatibility-flag documentation. |
| `frontend/src/landing/content/docs/plugins/agents/codex.mdx` | Codex-specific explanation that diagnostics are explicit and spawn is authoritative. |

---

### Task 1: Remove Advisory Catalog Work from the CLI Spawn Critical Path

**Files:**
- Modify: `backend/internal/cli/spawn_test.go:75-790`
- Modify: `backend/internal/cli/spawn.go:1-445`
- Test: `backend/internal/cli/spawn_test.go`

**Interfaces:**
- Consumes: `commandContext.resolveSpawnProject`, `resolveSpawnHarness`, `commandContext.postJSON`, `spawnRequest`, and the existing daemon error envelope.
- Produces: normal and compatibility-flag CLI flows whose network sequence contains project-resolution requests followed by `POST /api/v1/sessions`, with no agent catalog endpoint.

- [ ] **Step 1: Add a failing direct-spawn request-order test**

Add this test near the existing basic spawn wiring tests:

```go
func TestSpawnDirectlyPostsSessionWithoutAgentCatalogPreflight(t *testing.T) {
	cfg := setConfigEnv(t)
	var requests []string
	var req spawnRequest
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		appendPrimaryRequest(&requests, r)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/api/v1/projects/demo":
			_, _ = io.WriteString(w, `{"status":"ok","project":{"id":"demo","name":"Demo","path":"/repo/demo","config":{"worker":{"agent":"codex"}}}}`)
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/sessions":
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Error(err)
			}
			_, _ = io.WriteString(w, `{"session":{"id":"demo-20","status":"idle"}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	writeRunFileFor(t, cfg, srv)

	out, errOut, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "spawn", "--project", "demo", "--name", "worker")
	if err != nil {
		t.Fatalf("spawn failed: %v stderr=%s", err, errOut)
	}
	if !strings.Contains(out, "spawned session demo-20") {
		t.Fatalf("output = %q", out)
	}
	if req.ProjectID != "demo" || req.Harness != "codex" || req.DisplayName != "worker" {
		t.Fatalf("spawn request = %#v", req)
	}
	want := []string{"GET /api/v1/projects/demo", "POST /api/v1/sessions"}
	if !reflect.DeepEqual(requests, want) {
		t.Fatalf("requests=%#v want %#v", requests, want)
	}
}
```

- [ ] **Step 2: Add a failing authoritative-error propagation test**

Add a table test proving the CLI reaches the daemon and preserves the real spawn error instead of failing in advisory preflight:

```go
func TestSpawnSurfacesAuthoritativeDaemonFailuresWithoutCatalogPreflight(t *testing.T) {
	tests := []struct {
		name    string
		agent   string
		status  int
		code    string
		message string
	}{
		{name: "unknown harness", agent: "bogus", status: http.StatusBadRequest, code: "UNKNOWN_HARNESS", message: `spawn: unknown agent harness: "bogus"`},
		{name: "missing binary", agent: "codex", status: http.StatusBadRequest, code: "AGENT_BINARY_NOT_FOUND", message: "agent binary was not found"},
		{name: "runtime prerequisite", agent: "codex", status: http.StatusBadRequest, code: "RUNTIME_PREREQUISITE_MISSING", message: "tmux is required"},
		{name: "chat auth", agent: "codex", status: http.StatusConflict, code: "CHAT_AUTH_REQUIRED", message: "The agent is installed but not authenticated"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := setConfigEnv(t)
			var requests []string
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				appendPrimaryRequest(&requests, r)
				w.Header().Set("Content-Type", "application/json")
				switch {
				case r.Method == http.MethodGet && r.URL.Path == "/api/v1/projects/demo":
					_, _ = io.WriteString(w, `{"status":"ok","project":{"id":"demo","name":"Demo","path":"/repo/demo"}}`)
				case r.Method == http.MethodPost && r.URL.Path == "/api/v1/sessions":
					w.WriteHeader(tc.status)
					_, _ = io.WriteString(w, `{"code":`+jsonQuote(tc.code)+`,"message":`+jsonQuote(tc.message)+`,"requestId":"req-spawn"}`)
				default:
					http.NotFound(w, r)
				}
			}))
			t.Cleanup(srv.Close)
			writeRunFileFor(t, cfg, srv)

			_, _, err := executeCLI(t, Deps{ProcessAlive: func(int) bool { return true }}, "spawn", "--project", "demo", "--agent", tc.agent, "--name", "worker")
			if err == nil || !strings.Contains(err.Error(), tc.message+" ("+tc.code+") [request req-spawn]") {
				t.Fatalf("err=%v, want authoritative daemon error", err)
			}
			want := []string{"GET /api/v1/projects/demo", "POST /api/v1/sessions"}
			if !reflect.DeepEqual(requests, want) {
				t.Fatalf("requests=%#v want %#v", requests, want)
			}
		})
	}
}
```

- [ ] **Step 3: Run the new tests and confirm the old preflight blocks them**

```bash
cd backend
go test ./internal/cli -run 'TestSpawn(DirectlyPostsSessionWithoutAgentCatalogPreflight|SurfacesAuthoritativeDaemonFailuresWithoutCatalogPreflight)$' -count=1
```

Expected: FAIL because current normal spawn calls `/api/v1/agents/refresh` before `/api/v1/sessions`.

- [ ] **Step 4: Implement the minimal direct-spawn path**

In `backend/internal/cli/spawn.go`:

1. Remove `skipAgentCheck bool` from `spawnOptions`.
2. Remove `agentProbeResult`.
3. Remove the `if !opts.skipAgentCheck { ... }` block before pull-request resolution.
4. Keep `fetchAgentInventory`; `opr agent ls` still uses it.
5. Remove `preflightSpawnAgentAuth`, `probeSpawnAgent`, `agentProbeUnavailable`, `agentCatalogState`, and `agentCatalogStateFor`.
6. Remove the now-unused `errors` and `net/http` imports. Keep `context` and `net/url`, which remain used.
7. Replace the bound compatibility flag with an accepted no-op:

```go
f.Bool("skip-agent-check", false, "Compatibility no-op; spawn already uses authoritative daemon validation")
```

The execution order after Scratch validation must be:

```go
claimRef := ""
if opts.claimPR != "" {
	claimRef, err = ctx.resolvePRRef(cmd.Context(), opts.claimPR, project)
	if err != nil {
		return err
	}
}
req := spawnRequest{
	ProjectID:   opts.project,
	IssueID:     opts.issue,
	Kind:        opts.kind,
	Harness:     opts.harness,
	Mode:        opts.mode,
	Branch:      opts.branch,
	Prompt:      opts.prompt,
	DisplayName: name,
}
var res spawnResult
if err := ctx.postJSON(cmd.Context(), "sessions", req, &res); err != nil {
	return err
}
```

- [ ] **Step 5: Replace obsolete preflight tests with direct-spawn expectations**

Delete these tests because the behavior they assert is intentionally removed:

```text
TestSpawnStaleUnauthorizedAgentRefreshesProbesThenAllows
TestSpawnFreshUnauthorizedWarnsAndAllows
TestSpawnUnavailableFreshProbeWarnsAndAllows
TestSpawnUnsupportedAgentRefreshesThenBlocks
TestSpawnNotInstalledAgentRefreshesThenBlocks
TestSpawnStaleNotInstalledFreshInstalledWarnsAndAllows
TestSpawnUnavailableFreshProbeForNotInstalledWarnsAndAllows
TestSpawnFreshProbeServerErrorBlocks
TestSpawnUnknownAuthRefreshesWarnsAndAllows
```

For these retained tests, delete the `/api/v1/agents/refresh` handler case and remove `POST /api/v1/agents/refresh` from the expected request slice:

```text
TestSpawnClaimPRWiring
TestSpawnClaimPRFailureRollsBackSession
TestSpawnResolvesProjectFromEnvAndDefaultAgent
TestSpawnResolvesProjectFromOperatorSessionID
TestSpawnResolvesProjectFromCWD
TestSpawnDefaultsToScratchWhenOnlyActiveProject
```

Rename `TestSpawnSkipAgentCheckBypassesOnlyPreflight` to `TestSpawnSkipAgentCheckRemainsAcceptedAsNoop`, use `codex` as the requested harness, keep the flag in the command, and retain this exact expected request sequence:

```go
want := []string{"GET /api/v1/projects/demo", "POST /api/v1/sessions"}
```

Keep `authorizedAgentsJSON` because `backend/internal/cli/agent_test.go` uses it to test explicit catalog refresh.

- [ ] **Step 6: Format and run the focused CLI tests**

```bash
cd backend
gofmt -w internal/cli/spawn.go internal/cli/spawn_test.go
go test ./internal/cli -run 'TestSpawn|TestAgentList' -count=1
```

Expected: PASS. The direct-spawn tests must record no agent catalog request, the compatibility flag must parse, claim rollback must remain intact, and agent list diagnostics must still pass.

- [ ] **Step 7: Run the authoritative daemon preservation tests**

```bash
cd backend
go test ./internal/service/session -run 'TestSpawn(EmitsTypedErrorCodeOnFailure|FailedEmitsDuration)$|TestToAPIErrorMapsWorkspaceBranchSentinels' -count=1
go test ./internal/session_manager -run 'TestSpawn_(RejectsMissingAgentBinary|RejectsMissingTmuxBeforeSessionRow|RejectsUnknownHarness)|TestChatSpawn(RejectedBeforeDurableStateWhenUnsupported|RollsBackWhenControllerFailsToStart)' -count=1
```

Expected: PASS. These tests prove typed errors, telemetry, requested-operation validation, and cleanup stayed in the daemon.

- [ ] **Step 8: Commit Task 1 without staging unrelated Tauri changes**

```bash
git add backend/internal/cli/spawn.go backend/internal/cli/spawn_test.go
git diff --cached --check
git commit -m "perf: remove agent catalog preflight from spawn"
```

### Task 2: Document Direct Spawn and Verify the Complete Boundary

**Files:**
- Modify: `docs/cli/README.md:109-116`
- Modify: `frontend/src/landing/content/docs/cli.mdx:104-126`
- Modify: `frontend/src/landing/content/docs/plugins/agents/codex.mdx:14-21`
- Test: `backend/internal/cli/agent_test.go`
- Test: `backend/internal/service/session/service_test.go`
- Test: `backend/internal/session_manager/manager_test.go`
- Test: `backend/internal/session_manager/chat_spawn_test.go`

**Interfaces:**
- Consumes: the direct CLI flow from Task 1 and unchanged explicit catalog commands.
- Produces: documentation that distinguishes advisory diagnostics from authoritative spawn and accurately describes the compatibility flag and TUI authentication limitation.

- [ ] **Step 1: Update the canonical CLI architecture documentation**

Replace the spawn-readiness paragraph in `docs/cli/README.md` with:

```markdown
If `--agent` / `--harness` is omitted, `opr spawn` uses the resolved project's
`worker.agent` config. After deterministic command, project, and harness-selection
validation, the CLI posts the session request directly. The daemon's real spawn
path is authoritative for harness support, Chat authentication, runtime
prerequisites, binary resolution, workspace creation, launch, and rollback.

Agent readiness remains advisory diagnostic information. Use `opr agent ls` for
the cached catalog or `opr agent ls --refresh` for fresh local install/auth probes.
The legacy `--skip-agent-check` flag is accepted as a compatibility no-op; normal
spawn already skips catalog preflight.
```

- [ ] **Step 2: Update the public CLI page**

Change the flag row in `frontend/src/landing/content/docs/cli.mdx` to:

```markdown
| `--skip-agent-check` | Compatibility no-op retained for existing scripts; normal spawn already skips advisory catalog checks. |
```

Replace the paragraph after the table with:

```markdown
Project resolution order is explicit `--project`, `OPERATOR_PROJECT_ID`, the project of `OPERATOR_SESSION_ID`, then the closest registered project containing the current directory. After deterministic request and project validation, Operator posts the session request directly. The daemon's real spawn path validates the requested harness, mode, runtime, binary, workspace, and launch. Use `opr agent ls --refresh` when you explicitly want install/auth diagnostics.
```

- [ ] **Step 3: Update the Codex agent page without overstating TUI readiness**

Replace the final paragraph in `frontend/src/landing/content/docs/plugins/agents/codex.mdx` with:

```markdown
`opr spawn` starts the real Codex session without first refreshing the advisory agent catalog. Chat mode reports structured driver and authentication failures from the daemon. Terminal UI mode validates the Codex binary and terminal runtime, but a successful terminal launch does not guarantee that a later provider request will authenticate. Use `opr agent ls --refresh` for explicit local diagnostics.
```

- [ ] **Step 4: Check documentation for stale default-preflight claims**

```bash
rg -n "refreshes the selected agent|probes before spawn|bypass only this CLI-side preflight|Before spawning, Operator refreshes" docs frontend/src/landing/content/docs
```

Expected: no matches.

Then confirm every remaining compatibility-flag mention describes a no-op:

```bash
rg -n "skip-agent-check" docs/cli/README.md frontend/src/landing/content/docs
```

Expected: only the updated compatibility descriptions.

- [ ] **Step 5: Run the complete backend verification suite**

```bash
cd backend
go test ./...
go test -race ./...
go vet ./...
```

Expected: all commands exit 0.

- [ ] **Step 6: Run repository-level lint and diff checks**

```bash
cd ..
npm run lint
git diff --check
git status --short
```

Expected: lint and diff checks exit 0. Status may still show the user's unrelated Tauri startup changes, but Task 2 may modify only the three documentation files listed above.

- [ ] **Step 7: Perform the final scope audit**

```bash
git diff HEAD~1 -- backend/internal/cli/spawn.go backend/internal/cli/spawn_test.go docs/cli/README.md frontend/src/landing/content/docs/cli.mdx frontend/src/landing/content/docs/plugins/agents/codex.mdx
git diff HEAD~1 -- backend/internal/session_manager backend/internal/service/session backend/internal/service/agent backend/internal/adapters/agent frontend/src/renderer packages/mobile
```

Expected: Task 1 is the current `HEAD` and Task 2 documentation is still unstaged, so the first command shows the complete direct-spawn CLI/tests/docs change from the parent of Task 1. The second command shows no changes. If the executor made additional commits, compare against the parent of the Task 1 commit instead of assuming it is `HEAD~1`.

- [ ] **Step 8: Commit Task 2 without staging unrelated files**

```bash
git add docs/cli/README.md frontend/src/landing/content/docs/cli.mdx frontend/src/landing/content/docs/plugins/agents/codex.mdx
git diff --cached --check
git commit -m "docs: explain authoritative direct spawn"
```

## Deferred Follow-Up Outside This Plan

- A provider-neutral TUI readiness handshake that distinguishes process launch, login/setup screens, immediate auth exit, first-request auth failure, and a genuinely task-ready worker.
- Moving requested-agent binary resolution ahead of workspace provisioning if measurements show missing-binary failure cleanup is too expensive.
- Additional spawn stage telemetry beyond the existing total success/failure duration.
- Removing the compatibility flag in a future breaking or normal deprecation cycle.
- Optimizing worktree creation, provisioning, runtime startup, or provider startup after catalog latency is removed.

## Completion Evidence

The implementation is complete only when the final reviewer can point to evidence for all of these statements:

- Default `opr spawn` reaches `POST /api/v1/sessions` without any agent catalog request.
- `--skip-agent-check` is still accepted and produces the same request sequence.
- Explicit agent listing and refresh continue to pass their existing tests.
- Missing binary, missing runtime prerequisite, unknown harness, Chat auth, workspace errors, telemetry, and rollback continue through the existing daemon contracts.
- No Session Manager, service, adapter, generated API, desktop renderer, or Flutter behavior changed.
- Documentation does not promise that a successful TUI process launch proves provider authentication or task readiness.
- Full backend tests, race tests, vet, repository lint, and diff checks pass.
