You are implementing a written plan in the Operator repository.

## Your task

Execute, task by task:

`docs/superpowers/plans/2026-09-12-mobile-public-tunnel.md`

Read it in full before starting — all 20 tasks. It already contains the verified
evidence, the exact test code, the named traps and the commands that prove each
step. **Do not re-derive what it establishes, and do not re-measure what the
evidence file already measured.**

REQUIRED SUB-SKILL: invoke `superpowers:subagent-driven-development` before
doing anything else. One fresh subagent per task, with review between tasks.

## Workspace

Baseline is `master` at `885773834` (clean). Create an isolated worktree via
`superpowers:using-git-worktrees` on branch `mobile-public-tunnel`, as an
**external sibling** — `/Users/omaraly/development/AI/Operator-mobile-tunnel`.

Do not nest it inside the main checkout: `CLAUDE.md` records that worktrees
under `.worktrees/` or `.claude/worktrees/` poison repo-wide `grep`/`find` by
matching stale duplicate copies of tracked files. Scope searches to real source
directories regardless.

Do not merge to `master`. Stop at a green branch and report.

## The three documents, and which is the authority

| Document | Role |
| --- | --- |
| `docs/superpowers/plans/2026-09-12-mobile-public-tunnel.md` | What to do, step by step. Follow it. |
| `docs/superpowers/specs/2026-09-12-mobile-public-tunnel-design.md` | **Why.** The authority on intent. Read §3–§11 before Task 1. |
| `docs/superpowers/evidence/mobile-public-tunnel-probes.md` | Measured facts: real API responses, timings, headers, auth requirements, distribution limits. Every fixture in the plan comes from here. |

If the plan and the spec disagree, the spec wins and you report the conflict. If
either contradicts something you observe in the code, **stop and report** — do
not quietly pick one. One false claim has already been caught and corrected in
this spec (it asserted a pinned checksum for both providers; ngrok's endpoint
cannot be pinned), so treat these documents as good but not infallible.

## What this feature is

Operator's desktop app pairs a Flutter mobile client over a second HTTP listener
bound to the LAN ("Connect Mobile", port 3011), authenticated by a rotating
password carried in a QR code. Off the LAN the QR is useless, because
`AutopickLANIP` can only ever return a private address.

This adds one switch to that dialog which starts a public HTTPS tunnel to the
same port and rewrites the QR to the tunnel URL — so a phone on cellular scans
once and connects. Two providers sit behind it: **ngrok** when an authtoken is
saved (stable address, so pair-once), **cloudflared quick tunnel** otherwise
(needs no account at all, so the very first press always works, but its address
rotates on every restart).

## Traps, stated up front

**1. ngrok cannot be checksum-pinned. Do not "fix" this.**
Its download URL is a rolling channel whose version component the server
ignores — `ngrok-v3-0.0.0-nonsense-darwin-arm64.zip` returns byte-identical
bytes to `stable` (evidence §13). Verification for ngrok is TLS to the official
host plus an executed `--version` floor check. cloudflared *is* versioned and
*does* get a pinned SHA-256. If you find yourself adding an ngrok checksum
constant, you are about to break the build on ngrok's next release.

**2. Never touch the user's own ngrok config.**
`~/Library/Application Support/ngrok/ngrok.yml` holds a real authtoken and must
be left byte-identical. Operator writes only
`<dataDir>/mobile/ngrok.yml`. In particular **never run
`ngrok config add-authtoken` without `--config`** pointing at Operator's file —
the default target is the user's config. The plan's Task 11 tests drive a fake
binary, so no test should invoke the real `ngrok` at all.

**3. No test may start a real tunnel or touch the network.**
Every test uses `httptest`, a fake shell-script binary, or an injected clock.
The one networked step in the whole plan is Task 2 Step 6, which fetches the
cloudflared releases to compute checksums — that is a one-off `curl | shasum`
you run by hand, not a test.

**4. `agent.web_addr` is the verified config key.**
For moving ngrok's agent API off its default `127.0.0.1:4040`. `ngrok http` has
no flag for it. `web_addr` at top level, `api.addr`, and `agent.api_addr` are all
rejected by `ngrok config check` (evidence §11). Do not guess a different key.

**5. cloudflared's `/ready` returns 503 while still connecting.**
That is a normal pre-ready state, not a failure. Treating it as an error makes
the tunnel look broken for its first ~6 seconds.

**6. The fallback is classified by failure *shape*, not by an error-code list.**
Only `ERR_NGROK_4018` is measured. The codes for quota and session limits are
**not known**, and an invented list would silently fail to match the real quota
error — which is precisely the case the user asked to handle. Classify on: exited
before publishing a URL → refused; errored after serving → refused (the quota
shape); session established then lost → network, so reconnect. Carry the
provider's own `err` string verbatim. Do not add guessed code constants.

**7. Do not "optimize" two mobile behaviors that look like inefficiencies.**
`CLAUDE.md` documents both: the 12-second Dio `connectTimeout`/`receiveTimeout`
(a sleeping host otherwise hangs for the OS TCP timeout), and the sequential auth
probing in `sessions_remote_data_source.dart` (parallel requests burn the
daemon's 5-failure lockout). Task 18 edits the same `dio_consumer.dart` block as
the timeouts — change the headers map only.

**8. Locales before UI.**
Task 12 must land before Tasks 13–15. `frontend/src/renderer/i18n/instance.test.ts:149`
fails if any English key is missing from all seven other catalogs, and `:162`
fails on mismatched `{{variables}}`. Out of order, three UI tasks sit red for a
reason that has nothing to do with their own code.

## Hard rules, non-negotiable

1. **No comments in code.** The user's global `~/.claude/CLAUDE.md` rule: "don't
   make comments". This **overrides** the surrounding Go files' dense comment
   style — and do not "fix" the resulting inconsistency. It applies to tests,
   fakes and scaffolding too. Explain in commit messages. (Doc comments are not
   lint-required here: `backend/.golangci.yml` enables no `exported` revive rule.)
   One exception already in the plan: a single `catch {}` comment in
   `TunnelConfirmDialog.tsx` marking a deliberately silent branch — the plan says
   delete it if applying the rule strictly. Delete it.
2. **Conventional commits** (`feat:`, `fix:`, `test:`, `docs:`, `chore:`), one per
   task, per `AGENTS.md`. End every commit message with:
   `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
3. **API contract changes go through the generator.** After any DTO or route
   change run `npm run api` and commit `openapi.yaml` + `frontend/src/api/schema.ts`
   with the Go change. Add a `schemaNames` entry for every new named type. CI
   regenerates both and fails if they are stale. Never hand-edit them.
4. **Do not touch `packages/terminal`, the pty-host, or any terminal rendering,
   resize, attach, replay or selection code.** Nothing in this plan needs it. If
   you think it does, you have misread a task — stop and report.
5. **Follow the existing design system.** The renderer clones the
   `agent-orchestrator` web app verbatim (`DESIGN.md`, and read its top banner).
   Build from `components/ui/*` primitives. The new dialogs reuse `Dialog`,
   `Button`, `Switch` — do not introduce new primitives or new visual idioms.
6. **Build nothing from the spec's §12 "Deliberately not built" list**: no custom
   domains or reserved-domain provisioning, no auto-expiry or periodic
   re-confirmation, no embedded ngrok Go SDK, no IP pinning. And do not remove the
   Tailscale tab.
7. **Never log, echo, or telemeter the ngrok authtoken** — not in status
   responses, not in errors, not into the stdout line buffer that diagnostics
   surface. Task 11 has a test for the error path; keep it honest.

## The one thing the plan leaves open

Spec §10 asks for a tunnel-live indicator discoverable **outside** the Connect
Mobile dialog, so a live tunnel cannot be forgotten. Task 13 states the
requirement but deliberately leaves placement to you, because the surrounding
chrome (`Sidebar.tsx`, `WindowTitlebar.tsx`) was never surveyed and guessing
would have been worse than naming the gap.

Decide it during Task 13: either implement it where it genuinely fits, or leave
it out and say so explicitly in your report. Do not silently skip it.

## Gates — all must pass before you report done

```bash
npm run lint                 # backend go test ./... + golangci-lint v2.12.2
npm run typecheck
npm run frontend:lint
npm run api                  # must leave the tree CLEAN; a diff means stale artifacts
cd frontend && npx vitest run src/renderer/
cd packages/mobile && flutter analyze   # must print "No issues found!"
cd packages/mobile && flutter test
cd backend && go test -race ./internal/tunnel/ ./internal/httpd/... ./internal/daemon/ ./internal/mobilebridge/
```

Also run, and report the output of:

```bash
pgrep -fl "ngrok|cloudflared"   # must be empty — a surviving child is an orphan-reaping bug
git diff --stat master
git -C . status --short          # must be clean
```

And confirm the user's config is untouched:

```bash
shasum -a 256 "$HOME/Library/Application Support/ngrok/ngrok.yml"
```

Record that hash at the START of your run and again at the end. **If it changed,
that is a serious bug — say so loudly.**

## What you can and cannot verify

**You can** run the desktop app (`cd frontend && npm run tauri:dev`;
`RUN_APP_COMMANDS.md` is the truth, and the `opr-desktop-dev` skill is marked
stale for describing the old Electron shell). You can flip the switch, watch the
state reach `live`, and `curl` the public URL expecting **401** — a `200` there
would mean auth is not enforced, which is a stop-and-fix bug, not a pass.

**You cannot** verify the phone half. The mobile client needs a new TestFlight
build to parse the `v:2` QR, and you cannot ship one. Do not claim end-to-end
verification. State plainly in your report that the phone path is unverified and
why.

Starting a real tunnel during manual verification briefly exposes this machine to
the internet. Keep it short, turn the switch off afterwards, and confirm with
`pgrep` that nothing survives.

## Report back

When the branch is green, report:

1. **Per-task status** — landed / landed with deviation / not done. For every
   deviation: what the plan said, what you did, and why.
2. **Verbatim gate output** for each command above. Not "tests pass" — the actual
   summary lines. If something fails and you could not fix it, say so with the
   output; a known failure reported is worth more than a green claim that is
   wrong.
3. **The two ngrok config hashes** (start and end).
4. **The §10 indicator decision** — implemented where, or deliberately left out.
5. **Anything in the spec, plan, or evidence you found to be wrong**, with
   `file:line`. This is wanted, not a criticism of the plan.
6. **What a human still has to check**, concretely — at minimum the phone scan on
   cellular after a TestFlight build.

Do not merge, do not push, do not open a PR. The dispatching session reviews the
branch afterwards.
