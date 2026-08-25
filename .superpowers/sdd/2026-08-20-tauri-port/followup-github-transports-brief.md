# Follow-up task (spawned by Task 18): shell-side GitHub HTTPS transports

## Why spawned rather than wired in Task 18

Task 17 deliberately rejected adding reqwest "to avoid widening the pinned TLS
surface without a native-runner mandate" — an accepted ruling. Overturning it is
a dependency-surface decision that deserves its own review gate, not a rider on
packaging work. Additionally, honest verification of the new dependency tree
(cargo build + clippy + tests) on Windows and Linux runners cannot be produced
locally in the packaging task, so wiring it here would have shipped unverified
cross-platform build risk.

## Scope

- Add `reqwest` pinned EXACTLY (default-features off, rustls-tls) to
  `frontend/src-tauri/Cargo.toml`; justify the TLS-surface change against the
  prior ruling in the task report.
- Implement `updater/github.rs`: one transport type implementing BOTH seams
  already left behind:
  - `ReleasesSource` (`list_releases` -> GET /repos/{owner}/{repo}/releases?per_page=100
    deserialized into channel::GitHubRelease; `is_pr_open` -> GET /repos/../pulls/{n}
    state=="open", errors keep pins),
  - `EscalationFeeds` (`latest_stable_version` from latest.json;
    `nightly_important` from the nightly compat yml's important flag).
- Replace `StoppedReleasesSource` / `StoppedEscalationFeeds` in
  `open_shell_engine`; keep graceful degradation on fetch errors identical to
  Electron's unreachable-GitHub behavior.
- Tests against a loopback HTTP server speaking canned GitHub JSON; no live
  api.github.com dependency in CI.
- Native-runner cargo gates (fmt/clippy/test/build) on all three OSes recorded
  in the task report.

Gating status: NOT release-gating. Task 17's accepted design ships with the
transports unwired and degrade-safe (Electron unreachable-GitHub parity), so
interim releases are legitimate; this brief upgrades behavior, it does not
unblock shipping.

Until then: feature listing degrades to empty picker, reconcile keeps pins,
escalation probes degrade exactly like unreachable GitHub (latest still
escalates on its 48h rule).
