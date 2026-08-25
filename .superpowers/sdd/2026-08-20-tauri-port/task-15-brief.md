### Task 15: Implement the production standalone agent-browser adapter

**Files:**
- Create: `backend/internal/adapters/agentbrowser/install.go`
- Create: `backend/internal/adapters/agentbrowser/install_test.go`
- Create: `backend/internal/adapters/agentbrowser/runtime.go`
- Create: `backend/internal/adapters/agentbrowser/runtime_test.go`
- Create: `backend/internal/adapters/agentbrowser/policy.go`
- Create: `backend/internal/adapters/agentbrowser/policy_test.go`
- Create: `backend/internal/service/browser/runtime.go`
- Modify: `backend/internal/service/browser/service.go`
- Modify: `backend/internal/service/browser/service_test.go`
- Modify: `backend/internal/httpd/controllers/browser.go`
- Modify: `backend/internal/httpd/controllers/browser_test.go`
- Modify: `backend/internal/daemon/daemon.go`

**Interfaces:**
- Defines adapter-neutral `RuntimeStatus`, `RuntimeResult`, and `Runtime` contracts in the browser service, then implements `Runtime.Status(sessionID)`, `Runtime.Execute(ctx, sessionID, action, args)`, and `Runtime.DestroySession(ctx, sessionID)` in the standalone adapter. No public controller or service type may import the Electron broker package.
- Reports transport `agent-browser-standalone` and preserves existing capability authorization and public action names.

- [ ] **Step 1: Write failing install, policy, and runtime tests**

Port every applicable case from `frontend/src/main/agent-browser-runtime.test.ts`. Add serialized system-browser discovery/managed install, pinned version validation, partial-install cleanup, per-session roots, environment allowlisting, action-to-native-argument mapping, forbidden flags, count/size/output limits, timeout, cancellation, concurrent sessions, stale-owner scavenging, screenshot limits, and safe teardown.

- [ ] **Step 2: Run the failures**

```bash
cd backend
go test ./internal/adapters/agentbrowser ./internal/service/browser ./internal/httpd/controllers -run 'AgentBrowser|Browser'
```

Expected: FAIL because the adapter does not exist.

- [ ] **Step 3: Implement from Phase 0 evidence**

Use `~/.operator/browser-engine` only for shared managed engine files and `~/.operator/browser-runtime/<run>/<session>` for isolated writable state. Never set `AGENT_BROWSER_CDP`, auto-connect, the user's profile, or the user's home. Keep the Electron broker wired behind the Electron shell only until Task 16 proves API parity.

- [ ] **Step 4: Verify real actions and commit**

```bash
cd backend
go test ./internal/adapters/agentbrowser ./internal/service/browser ./internal/httpd/controllers ./internal/cli
git add internal/adapters/agentbrowser internal/service/browser internal/httpd/controllers/browser.go internal/httpd/controllers/browser_test.go internal/daemon/daemon.go
git commit -m "feat(browser): own standalone automation in daemon"
```

Run the Phase 0 fixture with `open`, `snapshot`, `click`, `console`, `errors`, `screenshot`, tabs, and teardown before committing.

