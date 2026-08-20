# Operator Direct Spawn Specification
## Approach 3 — Spawn First, Let the Real Launch Decide

**Project:** Operator  
**Repository:** `OmarAly92/Operator`  
**Target behavior:** Direct agent spawning without advisory install/auth preflight  
**Document type:** Product + architecture implementation specification  
**Purpose:** Give a coding agent enough context to inspect the repository and produce an implementation plan before changing code.

---

# 1. Summary

Operator should stop performing agent readiness checks before every normal `opr spawn`.

When the Orchestrator asks Operator to spawn Claude Code, Codex, or another worker, Operator should begin the real session spawn immediately.

The real launch is the source of truth.

If the launch succeeds, the worker starts.

If the launch fails because the agent is not installed, is not authenticated, the runtime cannot start, the workspace cannot be created, or another real startup requirement fails, Operator should return a clear and meaningful failure.

The desired mental model is:

```text
Orchestrator requests worker
        |
        v
Validate request itself
        |
        v
Start real spawn immediately
        |
        +----------------------+
        |                      |
        v                      v
     SUCCESS                 FAILURE
        |                      |
        v                      v
 Worker is running     Return real failure reason
```

The spawn path must not refresh the complete agent inventory and must not probe unrelated agents.

---

# 2. Why This Change Exists

The current CLI spawn flow performs an advisory agent readiness preflight before sending the actual session creation request.

Current behavior is conceptually:

```text
opr spawn --agent claude-code
        |
        v
Resolve project
        |
        v
Resolve requested agent
        |
        v
Refresh agent inventory
        |
        v
Probe supported agents
        |
        v
Wait for readiness results
        |
        v
POST /sessions
        |
        v
Begin real spawn
```

The readiness refresh can include multiple agent harnesses even though only one agent is being requested.

This means Operator may spend time asking questions such as:

- Is Claude Code installed?
- Is Claude Code authenticated?
- Is Codex installed?
- Is Codex authenticated?
- Is Cursor available?
- Is Aider available?
- Are other registered harnesses available?

before the real Claude Code spawn begins.

That work is useful for diagnostics and UI readiness information, but it should not block an autonomous worker launch.

The important observation is:

> Even if a readiness preflight succeeds, the real spawn can still fail.

Therefore readiness information is advisory, while the real launch is authoritative.

---

# 3. Core Product Principle

## The real operation should determine whether the real operation works.

For spawning:

```text
Do not ask:
"Will Claude probably start?"

Then later ask:
"Start Claude."

Instead:

"Start Claude."
```

The actual launch either succeeds or returns the real failure.

This reduces duplicated validation, removes unrelated work from the critical path, and gives the Orchestrator the most accurate result.

---

# 4. Goals

The implementation should achieve all of the following.

## 4.1 Start real spawning immediately

After normal command/request validation and project/agent resolution, Operator should enter the real session-spawn path without first refreshing agent readiness.

For:

```text
opr spawn --agent claude-code ...
```

the next meaningful operation should be the session creation/spawn request, not a global agent inventory refresh.

---

## 4.2 Make actual spawn the authority

Installation, authentication, runtime readiness, and launch success should be determined by the actual spawn path.

The result of the actual operation is authoritative.

---

## 4.3 Return meaningful failures

A failed spawn should tell the caller what actually prevented the worker from starting.

Examples:

```text
Claude Code is not installed.
```

```text
Claude Code is not authenticated.
```

```text
Codex failed to start.
```

```text
The required runtime is not available.
```

```text
The worker workspace could not be created.
```

The caller should not receive only:

```text
spawn failed
```

when Operator can identify a more useful reason.

---

## 4.4 Avoid checking unrelated agents

Spawning Claude must not wait on:

- Codex
- Cursor
- Aider
- Kimi
- opencode
- any other unrelated harness

Spawning Codex must not wait on Claude or anything else.

---

## 4.5 Keep diagnostics available

The full agent inventory/readiness system should remain useful for:

- settings screens
- agent management
- troubleshooting
- diagnostics
- explicit user refresh
- displaying which agents appear installed/authenticated

Approach 3 does **not** mean removing the agent catalog.

It means removing the catalog from the critical spawn path.

---

# 5. Non-Goals

The first implementation of this change should not accidentally become a much larger spawn redesign.

Unless required by existing architecture, this work does **not** need to:

- make `POST /sessions` asynchronous
- add a job queue
- create a new scheduler
- redesign all session lifecycle states
- redesign agent model discovery
- remove the Agent Inventory feature
- remove authentication support
- automatically install missing agent CLIs
- automatically sign users into providers
- automatically fall back to another provider
- redesign TUI/Chat handoff
- redesign worktree management
- redesign the Orchestrator task model

The first objective is simple:

> Remove advisory readiness checks from normal spawn and rely on actual launch errors.

---

# 6. Current Operator Areas Relevant to This Change

The coding agent should inspect the current repository before producing the implementation plan.

At minimum inspect:

## CLI spawn path

`backend/internal/cli/spawn.go`

Current responsibilities include:

- validating CLI arguments
- resolving project
- resolving harness/agent
- optionally running agent preflight
- posting the session spawn request
- printing spawn success/failure

Important current concept:

`--skip-agent-check`

This proves Operator already supports bypassing the advisory readiness check.

Approach 3 changes the default philosophy so bypassing the readiness check is no longer exceptional behavior.

---

## Agent inventory/readiness service

`backend/internal/service/agent/service.go`

This service should continue to own diagnostic/readiness information.

It currently contains concepts such as:

- supported agents
- installed agents
- authorized agents
- full inventory refresh
- individual agent probe
- bounded install/auth probes
- cached inventory

This remains useful.

The change is about when it is used.

---

## Session service

`backend/internal/service/session/service.go`

The session service delegates actual spawn work to the session manager.

It already records:

- successful spawn telemetry
- failed spawn telemetry
- spawn duration

It also maps several real launch failures into meaningful API errors.

This is an important part of Approach 3.

---

## Session manager

`backend/internal/session_manager/`

Especially inspect the actual `Spawn` path and its TUI/Chat launch branches.

The implementation plan must identify where the real launch validates or discovers:

- unknown harness
- missing agent binary
- missing runtime prerequisite
- Chat driver availability
- authentication failure
- runtime creation failure
- workspace creation failure
- agent startup failure

The plan should also confirm cleanup behavior after partial startup failures.

---

## Agent adapters

`backend/internal/adapters/agent/...`

Especially:

- Claude Code adapter
- Codex adapter

The agent adapters build or resolve the actual executable launch.

The implementation plan should confirm how missing binaries and startup errors surface today.

---

# 7. Desired Spawn Flow

The desired normal flow is:

```text
Orchestrator / user
        |
        v
opr spawn
        |
        v
Validate CLI/request syntax
        |
        v
Resolve project
        |
        v
Resolve requested agent/harness
        |
        v
POST /sessions
        |
        v
Session service
        |
        v
Session manager
        |
        v
Prepare workspace
        |
        v
Resolve requested agent adapter
        |
        v
Try real runtime/agent launch
        |
        +-----------------------------+
        |                             |
        v                             v
     success                        failure
        |                             |
        v                             v
 session running              classify real reason
                                      |
                                      v
                              clean partial resources
                                      |
                                      v
                              return meaningful error
```

There must be no default branch like:

```text
refresh all agents
```

before `POST /sessions`.

---

# 8. What Validation Should Still Happen Before Real Spawn

Approach 3 does **not** mean "accept every invalid request and discover everything late."

Fast, deterministic request validation should remain.

Examples include:

- required worker name exists
- worker name length is valid
- session mode value is valid
- session kind value is valid
- requested project can be resolved
- scratch-project restrictions are respected
- requested agent/harness name can be resolved from the request/project configuration
- malformed request data is rejected

These checks are cheap and deterministic.

They are fundamentally different from external readiness probes.

The distinction is:

```text
REQUEST VALIDATION
"Is this request valid?"
        |
        | Keep
        v

READINESS PREFLIGHT
"Does the external agent appear ready?"
        |
        | Remove from normal spawn
        v

REAL LAUNCH
"Can the requested agent actually start?"
        |
        | Authoritative
        v
```

---

# 9. What Must Not Block Normal Spawn

Normal `opr spawn` must not block on:

- full agent inventory refresh
- install probe of unrelated agents
- auth probe of unrelated agents
- model catalog refresh
- agent list refresh
- diagnostic health checks
- provider readiness refresh that is not required by the real launch

A normal spawn request should not invoke the equivalent of:

```text
/agents/refresh
```

before creating the session.

It should also not require a separate single-agent readiness probe unless there is a strong correctness reason that cannot be handled by the actual launch.

Approach 3 intentionally prefers the real launch.

---

# 10. Success Behavior

Given:

```text
Claude Code is installed
Claude Code has valid authentication
runtime requirements are available
workspace creation succeeds
```

When the Orchestrator requests:

```text
spawn Claude worker
```

Operator should:

1. accept the valid request
2. immediately enter real spawn
3. create/prepare the worker session
4. prepare the isolated workspace
5. launch Claude Code
6. mark/return the worker as successfully started using the existing lifecycle semantics
7. return the session ID/status to the caller

No agent inventory refresh should happen first.

---

# 11. Failure Behavior

Failure handling is a central requirement of Approach 3.

The coding agent should preserve or improve typed failure behavior.

## 11.1 Agent binary missing

Scenario:

```text
opr spawn --agent claude-code
```

but the `claude` executable cannot be found.

Expected result:

```text
Spawn failed: Claude Code is not installed or its executable could not be found.
```

Machine-readable/API error should remain specific.

Operator already has a concept equivalent to:

`AGENT_BINARY_NOT_FOUND`

The implementation should use existing typed errors where possible instead of flattening everything into a generic failure.

---

## 11.2 Agent not authenticated

Scenario:

Claude Code or Codex is installed, but the actual startup cannot proceed because authentication is required.

Expected user-facing meaning:

```text
Spawn failed: Claude Code is not authenticated.
Authenticate Claude Code and try again.
```

The exact provider-specific wording may differ.

Important rule:

> Authentication failure should come from the authoritative launch/startup path, not from a global readiness refresh.

If TUI and Chat modes surface authentication differently, the implementation plan must explicitly describe both.

Do not assume that launching a CLI process automatically proves the agent is usable.

The coding agent should inspect the real provider/runtime startup signals and determine how Operator can distinguish:

- successfully started
- waiting for user authentication
- exited due to authentication
- startup unknown

Do not invent a fake readiness guarantee.

---

## 11.3 Runtime prerequisite missing

Examples might include a required terminal/runtime component being unavailable.

Expected behavior:

```text
Spawn failed: required runtime prerequisite is missing.
```

Use the existing typed runtime failure if available.

---

## 11.4 Workspace creation failure

If Operator cannot create the isolated worktree/workspace:

```text
Spawn failed: worker workspace could not be created.
```

The agent launch must not proceed against an invalid workspace.

Partial resources must be cleaned according to the existing session lifecycle guarantees.

---

## 11.5 Agent process fails to launch

If the binary exists but the actual process cannot start:

```text
Spawn failed: Claude Code could not be started.
```

The underlying reason should be preserved for logs/telemetry.

A useful user-facing reason should be returned where safe.

---

## 11.6 Unsupported/unknown agent

If the caller asks for an agent harness Operator does not support:

```text
Spawn failed: unknown agent "..."
```

This can remain an early deterministic validation error.

There is no value in building a workspace for an agent adapter that does not exist.

---

## 11.7 Invalid project

If the project does not exist or cannot be resolved:

fail before any agent launch.

This is request correctness, not agent readiness.

---

# 12. Authentication Semantics Need Special Attention

This is the most important edge case in Approach 3.

There are several possible real-world states:

```text
A. binary missing
B. binary installed + authenticated
C. binary installed + definitely unauthenticated
D. binary installed + auth state unknown
E. binary starts but opens a login/setup screen
F. binary starts then exits because credentials are invalid
G. binary starts successfully but first model request later fails
```

The implementation plan must inspect how each supported launch mode detects these today.

The rule should be:

## Definite failure

If actual startup conclusively says authentication is required:

```text
spawn = failed
reason = authentication required
```

## Unknown auth but process can start

Do not fail only because an advisory auth probe would have returned `unknown`.

Let the real launch continue.

## Login/setup screen

If Operator considers a worker unusable until the agent is ready for task execution, a login/setup state must not be reported as a healthy running coding worker.

The plan should identify how this can be represented with existing lifecycle/status concepts.

Prefer reusing existing `needs_input` or equivalent state if that matches Operator's current semantics.

If the existing architecture cannot reliably detect this in TUI mode, document that limitation instead of faking certainty.

---

# 13. CLI Behavior

## Desired normal command

The normal command remains simple:

```text
opr spawn --project <project> --agent claude-code --name "<name>" --prompt "<task>"
```

This command should directly begin actual spawn.

---

## `--skip-agent-check`

Approach 3 changes the default behavior to what this flag currently requests.

The implementation plan should choose a backwards-compatible migration strategy.

Preferred strategy:

### Initial release

- normal spawn skips readiness preflight by default
- keep `--skip-agent-check` accepted temporarily for compatibility
- make it a harmless/no-op compatibility flag if removing it immediately would break scripts
- update help text/documentation so users no longer need it

### Later cleanup

Remove the obsolete flag in a normal breaking/deprecation cycle if appropriate.

Do not require Orchestrator prompts to include `--skip-agent-check` forever.

---

# 14. Agent Inventory Behavior After This Change

The Agent Inventory should remain.

It should answer questions such as:

```text
Which agents does Operator support?
Which appear installed?
Which appear authenticated?
```

It should be refreshed when explicitly needed.

Examples:

```text
opr agent ls
```

and an explicit refresh operation.

A settings/diagnostics UI may also request refresh.

The important boundary becomes:

```text
Agent Inventory = information
Spawn = action
```

Information may become stale.

The actual action determines reality.

---

# 15. Orchestrator Behavior

This change is especially important for the Orchestrator.

Current mental model:

```text
Orchestrator decides worker is needed
        |
        v
opr spawn
        |
        v
Operator spends time checking readiness
        |
        v
real spawn starts
```

Desired:

```text
Orchestrator decides worker is needed
        |
        v
opr spawn
        |
        v
real spawn starts immediately
```

---

## Orchestrator success

Example:

```text
Orchestrator:
Spawn a Claude worker for backend auth.

Operator:
Spawn starts.

Claude:
Starts successfully.

Operator:
Returns worker session ID.

Orchestrator:
Continues coordinating.
```

---

## Orchestrator failure

Example:

```text
Orchestrator:
Spawn a Claude worker.

Operator:
Actual launch fails.

Result:
Claude Code is not authenticated.
```

The Orchestrator receives a clear failure and can reason about what to do next.

The base change should **not** automatically force fallback behavior unless Operator already has an explicit fallback policy.

Possible future behavior:

```text
Claude fails
    |
    v
Orchestrator decides whether Codex is acceptable
```

That is separate from this implementation.

---

# 16. UX Requirements

The user should understand that Operator is attempting the real spawn.

## Success

Example CLI result:

```text
spawned session <id> (<status>)
```

Existing success output can remain unless the implementation plan identifies a reason to change it.

---

## Failure

Failures should be concise but actionable.

Bad:

```text
spawn failed
```

Better:

```text
Spawn failed: Claude Code executable was not found.
```

Better:

```text
Spawn failed: Claude Code requires authentication.
Run Claude Code and sign in, then retry.
```

Better:

```text
Spawn failed: the worker runtime could not be started because a required prerequisite is missing.
```

The CLI and desktop UI should derive their message from typed failures, not fragile string matching whenever possible.

---

# 17. Session State Requirements

The implementation plan must explicitly verify what happens to the session record if spawn fails partway through.

A failed spawn must not leave an apparently healthy worker.

Acceptable outcomes depend on existing lifecycle semantics:

## Option A — rollback seed session completely

If failure occurs before meaningful durable session state exists:

```text
delete/rollback seed session
```

## Option B — preserve terminated/failed record

If Operator intentionally preserves partial sessions for lifecycle/audit reasons:

```text
session remains non-active
failure is observable
resources are cleaned
```

The implementation should follow the repository's existing lifecycle contract rather than inventing a second cleanup model.

Hard requirement:

> No ghost active worker may remain after a failed spawn.

---

# 18. Resource Cleanup Requirements

If real spawn fails after partial setup, Operator must not leak:

- worktrees
- temporary workspace directories
- runtime processes
- terminal/tmux sessions
- controller processes
- session ownership locks
- partial launch handles
- temporary prompt artifacts that should be removed
- other session-scoped resources

The implementation plan must inspect existing rollback/teardown functions and reuse them.

Do not add a second independent cleanup mechanism if the session manager already owns this lifecycle.

---

# 19. Telemetry and Observability

The change should make spawn performance measurable.

Operator already records spawn success/failure duration in the session service.

The implementation should preserve this.

Recommended additional timing visibility, if inexpensive and consistent with existing telemetry:

```text
spawn requested
session manager entered
workspace ready
runtime launch started
agent process started
spawn completed
```

This is useful because once the readiness preflight is removed, any remaining latency is real spawn latency.

The goal is to answer questions such as:

```text
Total spawn: 3.1s

Project/request resolution: 0.1s
Workspace creation:          0.4s
Runtime creation:            0.2s
Claude startup:              2.4s
```

Exact telemetry implementation is for the implementation plan.

Do not block the Approach 3 change on building a large telemetry system.

---

# 20. Performance Expectations

Approach 3 does not promise that a Claude or Codex worker is fully ready in zero milliseconds.

It promises:

> Operator begins the real spawn without spending time on advisory readiness checks first.

The meaningful comparison is:

## Before

```text
preflight/readiness delay
+
real spawn delay
=
time until worker
```

## After

```text
real spawn delay
=
time until worker
```

The implementation should remove preflight latency from the critical path.

---

# 21. Acceptance Criteria

The change is complete only when all relevant criteria below are satisfied.

## Critical-path criteria

- Normal `opr spawn` does not perform a full agent inventory refresh.
- Normal `opr spawn` does not wait on unrelated agent install/auth probes.
- Normal `opr spawn` proceeds to actual session creation after deterministic request/project/harness validation.
- The real session spawn remains authoritative for startup success.
- `opr agent ls` and explicit agent diagnostics continue to work independently.

---

## Success criteria

- Installed/authenticated Claude Code can be spawned normally.
- Installed/authenticated Codex can be spawned normally.
- The successful worker gets the same normal session/workspace isolation as before.
- The Orchestrator can spawn multiple workers without each worker first refreshing the entire agent inventory.

---

## Failure criteria

- Missing agent binary returns a meaningful typed/user-facing failure.
- Authentication-required startup returns a meaningful failure or existing needs-input state according to the actual launch mode.
- Missing runtime prerequisite returns a meaningful failure.
- Workspace failure returns a meaningful failure.
- Unknown harness remains a clear validation error.
- Invalid project remains a clear validation error.
- Partial spawn failure does not leave a ghost active session.
- Partial spawn failure does not leak runtime/workspace resources.

---

## Compatibility criteria

- Existing Agent Inventory/diagnostic behavior remains available.
- Existing session lifecycle behavior is preserved unless the implementation plan explicitly justifies a required change.
- Existing Orchestrator worker spawning continues to use ordinary `opr spawn`.
- Existing scripts using `--skip-agent-check` are handled with an intentional compatibility decision.

---

# 22. Test Specification

The coding agent should produce a test plan covering at least the following.

---

## Test 1 — Claude normal spawn

### Setup

- Claude Code installed
- authenticated
- project valid

### Action

Spawn Claude worker.

### Verify

- no full agent inventory refresh occurs
- no unrelated agent probe occurs
- real session spawn begins
- worker starts
- success result contains session ID/status
- normal workspace isolation exists

---

## Test 2 — Codex normal spawn

Same as Test 1 but for Codex.

Purpose:

prove the behavior is generic and not hard-coded to Claude.

---

## Test 3 — Missing Claude binary

### Setup

Claude adapter supported, but executable unavailable.

### Action

Spawn Claude.

### Verify

- no preflight inventory refresh
- real spawn attempts requested agent
- returns missing-agent-binary failure
- no healthy worker remains
- no leaked runtime/worktree remains

---

## Test 4 — Authentication required

### Setup

Agent installed but actual startup requires authentication.

### Action

Spawn worker.

### Verify

- no global readiness refresh
- actual startup determines authentication problem
- caller receives meaningful auth-related result
- worker is not falsely reported as healthy/running

Run separately for any launch modes that behave differently.

---

## Test 5 — Auth status unknown but launch works

### Setup

Advisory auth status would be unknown, but the agent can successfully launch.

### Action

Spawn worker.

### Verify

- spawn is allowed
- no advisory unknown-auth state blocks it
- successful real launch wins

This test captures the central philosophy of Approach 3.

---

## Test 6 — Unknown harness

### Action

Request an unsupported harness.

### Verify

- fail quickly
- do not create unnecessary workspace/runtime
- return clear validation error

---

## Test 7 — Workspace failure

### Setup

Force workspace/worktree creation failure.

### Verify

- agent process is not started against an invalid workspace
- failure reason is meaningful
- partial session state is cleaned according to lifecycle contract

---

## Test 8 — Runtime prerequisite missing

### Setup

Make required runtime unavailable.

### Verify

- return typed runtime prerequisite failure
- no global agent readiness refresh occurs
- cleanup is correct

---

## Test 9 — Agent process startup failure

### Setup

Binary resolves but process creation/start fails.

### Verify

- actual launch error reaches caller meaningfully
- session is not healthy
- cleanup succeeds

---

## Test 10 — Multiple Orchestrator spawns

### Setup

Orchestrator wants several independent workers.

### Action

Spawn multiple workers in normal orchestration flow.

### Verify

Each worker goes:

```text
spawn request
    ->
real spawn
```

not:

```text
spawn request
    ->
refresh all agents
    ->
real spawn
```

Confirm one slow unrelated agent cannot delay all requested workers.

---

## Test 11 — Agent diagnostics still work

### Action

Explicitly list/refresh agent readiness.

### Verify

- supported/installed/authenticated information still works
- this functionality is not removed
- it remains separate from spawn

---

## Test 12 — Compatibility flag

If `--skip-agent-check` is retained temporarily:

### Verify

- existing scripts do not fail simply because the flag still exists
- behavior is equivalent to normal direct spawn
- help/deprecation strategy matches the implementation plan

---

# 23. Performance Test

Before implementation, capture a baseline.

Example measurements:

```text
time from `opr spawn` start
to session POST

time from session POST
to workspace ready

time from workspace ready
to runtime start

time from runtime start
to agent ready / spawn return
```

After implementation, compare.

The key expected change is:

```text
agent inventory/preflight time = removed from normal spawn critical path
```

Do not claim a specific final spawn time without measurement.

Claude/Codex startup itself may still take seconds.

---

# 24. Important Architectural Boundary

The implementation should preserve this separation:

```text
+--------------------------+
| Agent Catalog            |
|                          |
| supported?               |
| appears installed?       |
| appears authenticated?   |
| models?                  |
| diagnostics?             |
+------------+-------------+
             |
             | informational
             |
             v

+--------------------------+
| Session Spawn            |
|                          |
| create real workspace    |
| launch real runtime      |
| start real agent         |
| report actual result     |
+--------------------------+
```

The Agent Catalog is informational.

Session Spawn performs actions.

The informational layer should not become a mandatory blocking dependency for every action.

---

# 25. Error Model Principles

The implementation plan should follow these rules.

## Prefer typed errors

Use stable error categories/codes rather than parsing human-readable process strings where Operator already has typed errors.

---

## Preserve cause internally

Logs and telemetry should keep the underlying technical cause.

User-facing output may be simpler.

---

## Give actionable messages

Examples:

```text
AGENT_BINARY_NOT_FOUND
Claude Code executable was not found.
```

```text
AGENT_AUTH_REQUIRED / existing auth equivalent
Claude Code requires authentication.
```

```text
RUNTIME_PREREQUISITE_MISSING
A required runtime dependency is unavailable.
```

---

## Do not misclassify

An unknown authentication status is not the same as unauthenticated.

A process existing is not necessarily the same as a usable coding worker.

A failed model request after a successfully established session may belong to runtime/session failure handling rather than spawn validation.

The implementation plan must identify the real boundary.

---

# 26. TUI vs Chat Considerations

Operator supports more than one interface mode.

The coding agent must explicitly inspect both.

## TUI

Typical flow:

```text
workspace
runtime/terminal
agent CLI process
interactive agent
```

Questions to answer in the implementation plan:

- What proves the process actually launched?
- What proves it did not immediately exit?
- Can Operator detect an authentication/login prompt?
- Does a login prompt map to `needs_input`, failure, or another existing state?
- When is spawn considered successful today?

---

## Chat

Typical flow uses the structured/native chat controller.

Questions to answer:

- Where does Chat authentication failure surface?
- Existing Operator code already has an auth-required error concept; can it be reused directly?
- When is the Chat session considered launched successfully?

Approach 3 should preserve mode-specific correctness while presenting a consistent product meaning.

---

# 27. Failure Cleanup Decision Table

The implementation plan should fill in a table like this after inspecting current code:

| Failure Point | Expected Session State | Workspace Cleanup | Runtime Cleanup | Returned Error |
|---|---|---|---|---|
| invalid project | no spawn | none | none | project error |
| unknown harness | no active worker | none/pre-workspace | none | unknown harness |
| workspace create failure | no active worker | rollback partial | none | workspace error |
| binary missing | no active worker | cleanup according to current lifecycle | none | agent binary missing |
| runtime prerequisite missing | no active worker | cleanup | cleanup partial runtime | runtime prerequisite |
| auth required | not falsely healthy | cleanup or needs-input based on real mode semantics | mode-dependent | auth error/state |
| agent launch error | no healthy worker | cleanup | cleanup | launch error |

The plan should not guess these rows.

It should verify current behavior in the Session Manager.

---

# 28. Rollout Strategy

Recommended rollout:

## Phase 1 — Change default critical path

- remove default advisory readiness preflight from normal spawn
- preserve real spawn error handling
- keep inventory diagnostics
- preserve compatibility for `--skip-agent-check`
- add/update tests

This delivers the primary performance win.

---

## Phase 2 — Improve error normalization if necessary

After direct spawn works, improve any weak real-launch failure messages discovered during testing.

Examples:

- TUI auth detection
- startup exit classification
- clearer provider names
- actionable remediation text

Do not block Phase 1 on broad perfection if existing errors are already adequate.

---

## Phase 3 — Measure real spawn bottlenecks

Once preflight delay is gone, inspect remaining latency.

Possible real bottlenecks:

- worktree creation
- runtime/tmux creation
- Claude startup
- Codex startup
- hook setup
- system prompt preparation
- environment preparation

Optimize these separately.

Do not confuse real spawn performance with readiness-preflight performance.

---

# 29. Implementation Plan Instructions for the Coding Agent

Before writing code, produce an implementation plan that answers all of these questions.

1. Where exactly does normal `opr spawn` invoke the readiness preflight?
2. Which CLI behavior should be removed or changed?
3. What should happen to `--skip-agent-check`?
4. Does any other spawn entry point perform the same readiness preflight?
5. Does desktop/mobile UI call a different spawn path that needs the same behavior?
6. Where does Session Manager resolve the requested agent adapter?
7. Where does actual agent binary resolution happen?
8. Where do runtime prerequisites fail?
9. How does Chat mode surface missing auth?
10. How does TUI mode behave when Claude/Codex is unauthenticated?
11. What proves a TUI agent has genuinely started?
12. What cleanup happens if the spawn fails after the session row is created?
13. What cleanup happens after workspace creation but before runtime launch?
14. What cleanup happens after runtime creation but before healthy startup?
15. Which existing typed errors already cover required failure cases?
16. Are any new error types actually necessary?
17. Which tests currently assert preflight behavior and must change?
18. Which tests prove agent diagnostics still work?
19. How will we verify no `/agents/refresh` call occurs in normal spawn?
20. How will we measure before/after spawn latency?
21. Is the Orchestrator system prompt currently telling workers to use `--skip-agent-check` anywhere?
22. Do docs/examples need to stop recommending `--skip-agent-check`?
23. Are there backwards-compatibility concerns for scripts using the flag?
24. Does the API response already carry enough structured error information for the Orchestrator to understand failure?
25. Are failure messages provider-neutral enough for Claude, Codex, and other harnesses?

The plan should reference exact repository files and tests.

Do not implement until this inspection is complete.

---

# 30. Definition of Done

Approach 3 is done when this is true:

```text
User/Orchestrator:
"Spawn Claude."

Operator:
Immediately attempts the real Claude worker spawn.

If Claude works:
Worker starts.

If Claude is missing:
Clear missing-agent error.

If Claude needs authentication:
Clear auth-required result/state based on actual startup behavior.

If runtime/workspace fails:
Clear real failure.

Operator does not first refresh/check every other agent.
```

And:

```text
opr agent ls / diagnostics
```

can still inspect readiness independently.

---

# 31. Final Design Principle

The long-term rule should be simple:

> Diagnostics describe what Operator believes may be ready.  
> Spawn tells Operator to actually try.  
> The actual spawn result is the source of truth.

For autonomous orchestration, the desired critical path is:

```text
reason
  ->
decide worker
  ->
spawn worker
  ->
observe real result
  ->
continue
```

not:

```text
reason
  ->
decide worker
  ->
refresh diagnostics
  ->
wait
  ->
spawn worker
  ->
observe real result
```

This keeps the Orchestrator responsive and makes failures more truthful.

---

# 32. Repository Facts This Specification Is Based On

At the time this specification was prepared, the current Operator `master` branch showed:

- `backend/internal/cli/spawn.go` contains a normal spawn preflight that can be skipped with `--skip-agent-check`.
- The CLI readiness preflight refreshes agent inventory before posting the actual session request.
- `backend/internal/service/agent/service.go` treats inventory/readiness as advisory and has separate full-refresh and individual-probe concepts.
- `backend/internal/service/session/service.go` delegates real spawning to Session Manager and records spawn success/failure duration.
- Session-service API error mapping already includes real launch failures such as:
  - unknown harness
  - missing agent binary
  - missing runtime prerequisite
  - Chat auth required
  - Chat driver availability/incompatibility
  - workspace/runtime conflicts
- The Session Manager is the lifecycle owner for actual session, workspace, runtime, and agent launch behavior.

The coding agent must re-check the current repository before implementation in case the branch has changed.
