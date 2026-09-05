# Runtime fake remediation report

Date: 2026-09-05

Root cause: `backend/internal/integration/lifecycle_sqlite_test.go` defined `stubRuntime` without the new `SendInput` method required by `sessionmanager.runtimeController`.

Change made: added the missing no-op `SendInput` method to `stubRuntime` only.

Verification:
- `cd backend && go test ./internal/integration` passed on rerun.
- `cd backend && go test ./...` passed.

Note: the first `go test ./internal/integration` run surfaced a separate transient integration failure in `shell_blocks_tmux_test.go`; the package rerun was green and the full backend suite passed.
