# Terminal: what is left that changes day-to-day use (2026-09-23)

Written after Plans A–F of `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`
landed and while the background-pane plan
(`docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`) awaits
execution. Items already dropped by the user are not repeated: mobile
conversation view, trying predictive echo, and Plan G (§4.2).

Order is the recommended order of work.

## 1. The visible pane's forced layout on every repaint (recommended next)

**What the user feels:** smoother streaming and less CPU, fan and battery while
Claude Code writes to the pane being watched.

**Evidence:**

- `docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md` measured repaint
  at 615 ms against parse 74 ms and line-editor snapshot 73 ms, and named a
  forced layout as the largest single cost.
- The site is `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:1055`:
  when `this.pinnedHeader` is set, every repaint calls
  `first.getBoundingClientRect()` and `container.getBoundingClientRect()` to
  decide `scrolledPastHeader`. Both reads come after `reconcileChildren` has
  mutated the DOM (`:1052`), so the browser lays out mid-frame.

**Direction:** derive `scrolledPastHeader` from state the renderer already owns
(block offsets from the windowing result, `rowHeight`, `BLOCK_PADDING_TOP_LINES`,
the scroll position it tracks) instead of reading geometry. The result must be
identical: `npm run bench:feel` zero pixel diff, `npm run bench:selection` and
`bench:agent:scroll` green, and a before/after layout count per 100 frames with
the same harness the measurement note used.

**Sequencing:** after Plan 4 lands; both change the repaint path in the same
file.

**Size:** one small plan.

## 2. Try the display flags that are built but default off

**What the user feels:** possibly better-looking Claude Code output (bold,
italic, dim and underline drawn properly; a cursor that stays readable).

**Evidence:** `packages/terminal/ts/renderer-dom/src/features.ts` defaults
`attributes: "plain"`, `cursorContrast: false`, `cursorHollowUnfocused: false`.
Plan D built all three; the feel gate already carries baselines for them
(`baselines/<fixture>/feature-attributes_warp`, `feature-cursorContrast`,
`feature-cursorHollowUnfocused`).

**Not known:** how much dim or italic text Claude Code emits in normal use. The
side-by-side answers that.

**Direction:** the same route as the graphemes/widthCache flip (7395b910c):
side-by-side screenshots on the real app with each flag, then flip only the
ones that look better, re-record the default baselines and keep a
`feature-<name>_false` baseline for the old look.

**Size:** no plan; one session like #2.

## 3. Claude Code's window title (lower priority)

**What the user feels:** a session card or tab that says what the agent is
doing right now, in Claude's own words.

**Evidence:**

- The `claude-long-50k` fixture carries 1,047 `OSC 0` title updates and
  `claude-spinner-10s` carries 16. The text is a spinner glyph (`◐`/`◑`)
  while working or `✳` when idle, then Claude's task summary, for example
  `◐ Number list 1 to 3000`.
- vt-core drops them: `packages/terminal/crates/vt-core/src/parser.rs:856`
  `osc_dispatch` handles only `OSC 8`.
- Operator already has working/idle state from its lifecycle code
  (`backend/internal/lifecycle/manager.go`), so the new value is the summary
  text, not the status.

**Direction:** vt-core records the latest `OSC 0`/`OSC 2` title and exports it;
the package exposes it through a host callback (keep it product-independent);
Operator decides where to show it. Survey entry §1.15 lists the title as not
done.

**Worth it only if** sessions are hard to tell apart at a glance.

**Size:** one small plan.

## Before the next push (housekeeping, not a plan)

- **AGPL commits in published history: left as is (user decision 2026-09-23).**
  `ad0d322e0` (Warp-derived path detection) and its revert `7bfe5cdec` are
  already on `origin/development` of the public repo `OmarAly92/Operator`, and
  the local branches `split-view` and `terminal-hover-file-paths` contain them.
  The shipped tree carries only the clean-room replacement `b17acd63c`.
  Removing them means rewriting published history and force-pushing
  `development`; GitHub keeps orphaned commits reachable by SHA until support
  purges them, so a rewrite alone does not unpublish them.
  The user chose to keep the history unchanged; do not rewrite it.
- **Duplicate survey: done 2026-09-23.** The `docs/superpowers/specs/` copy was
  deleted; `docs/terminal/2026-09-19-terminal-reference-survey.md` was a
  strict superset (it adds the implementation status table). Every reference
  in the plans and specs now points at `docs/terminal/`, and Plan F's cited
  line ranges were remapped to the kept copy.
- **Manual Japanese-IME check** from Plan D (§3.10) is still pending, only if
  IME input is used.

## Checked and already covered

- **Find in scrollback:** `packages/terminal/ts/renderer-dom/src/find-bar.ts`.
- **Connection heartbeat:** `backend/internal/terminal/manager.go:727`
  (`heartbeatLoop`).

## Order

1. Execute Plan 4 (background-pane cost).
2. Plan for #1 (visible-pane forced layout).
3. #2 side-by-side session.
4. #3 only if wanted.
