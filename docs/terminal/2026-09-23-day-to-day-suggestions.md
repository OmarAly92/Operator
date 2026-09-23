# Terminal: what is left that changes day-to-day use (2026-09-23)

Written after Plans A–F of `docs/superpowers/specs/2026-09-19-agent-tui-experience-design.md`
landed and while the background-pane plan
(`docs/superpowers/plans/2026-09-23-terminal-background-pane-cost.md`) awaits
execution. Items already dropped by the user are not repeated: mobile
conversation view, trying predictive echo, and Plan G (§4.2).

Order is the recommended order of work.

## 1. Cheaper layout for visible panes (only if several panes are visible at once)

**Status: measured 2026-09-23, no gain, nothing changed.**
`.terminal-row { contain: layout }` was inside noise in Chromium and WebKit;
the scroller already carries `contain: strict`
(`packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:161`, set inline,
which this item missed by reading only `styles.css`), and each layout has the
same 142 dirty objects with or without row containment. See
`docs/superpowers/specs/2026-09-23-layout-containment-measurement.md` and
TERMINAL.md §4.26. The section below is kept as the original proposal.

**What the user feels:** less CPU while several visible panes stream at once
(split view). With one visible pane there is nothing to feel.

**Evidence** (`docs/superpowers/specs/2026-09-23-background-pane-cost-measurement.md`):

- One visible pane alone costs 0.23–0.39 s of main thread per 10 s (2–4 % of a
  core), of which layout is 0.06–0.10 s. Ten visible panes cost 0.86–1.13 s
  per 10 s, layout 0.25–0.30 s.
- The 615 ms `repaint` figure is from the profile of the 1 visible + 9 parked
  row, so most of it is parked panes, which Plan 4 removes.
- Each pane pays about one layout per output frame (122 per 100 frames). It is
  forced at the pinned-header test,
  `packages/terminal/ts/renderer-dom/src/dom-block-renderer.ts:1055`
  (`getBoundingClientRect` after `reconcileChildren` at `:1052`). The note
  records that removing that read only moves the layout to
  `applyStickiness`'s `scrollHeight` at `:1128`; the browser would lay out
  before painting anyway. Moving or removing reads does not remove the cost.
- `styles.css` sets no `contain` or `content-visibility` on blocks or rows.

**Direction:** make each layout cheaper rather than avoid it: CSS containment
on block and row elements so a changed row does not re-lay-out the whole list,
and derive the pinned-header test from the windowing result so the frame has
one layout instead of a forced one plus the render-step one (measure whether
there are two first). Gate: `npm run bench:feel` zero pixel diff,
`bench:selection` and `bench:agent:scroll` green, and the pane-cost harness's
10-visible row before and after.

**Sequencing:** after Plan 4, and only if split view (several visible panes)
is used day to day.

**Size:** one small plan, measurement first.

## 2. Try the display flags that are built but default off

**Status: done 2026-09-23. `attributes` flipped to `"warp"` (`534ef20fe`);
`cursorContrast` and `cursorHollowUnfocused` left off.** A new fixture,
`bench/agent-session/fixtures/claude-markdown-reply` (`a405a9917`: markdown
reply, diff, Bash call, idle prompt), emits bold 18, dim 6, italic 5 and no
underline, strike, inverse, blink, hidden, overline or SGR 58 (byte count
and vt-core export agree on which attributes appear). Side-by-sides:
`attributes=warp` changed only the two italic words on the Claude Code
recordings; `cursorContrast` changed 0 px on all three, because the input
cursor sits on the default background, so it was not flipped;
`cursorHollowUnfocused` outlined the `❯` input cursor on all three, and the
user did not choose it. The section below is kept as the original proposal.

**What each flag does:**

- `attributes: "warp"` (`features.ts`, default `"plain"`): `"plain"` already
  paints bold (`fontWeight 700`) and dim (`opacity 0.55`)
  (`row-builder.ts:75-80`). `"warp"` adds italic, five underline styles,
  underline colour (SGR 58), strike, overline, blink and hidden
  (`attributes.ts`, `row-builder.ts:82`; TERMINAL.md §5).
- `cursorContrast`: when the cursor colour sits on a background too close to
  it, the cursor cell is drawn inverted with the character on top
  (`cursor.ts:63`, `cursor-contrast.ts:51`).
- `cursorHollowUnfocused`: the cursor becomes an outline when the pane is not
  focused (`cursor.ts:62`), which shows which pane has the keyboard.

**Evidence of use:** in the `claude-long-50k` fixture Claude Code emits bold
5,630 times, dim once, and no italic, underline or inverse. It hides and shows
the terminal cursor 5,837/5,838 times, so Operator's cursor is the one drawn in
Claude's input box. The fixture is a plain number list, so it does not show
what markdown replies, diffs or links emit.

**Not known:** whether Claude Code uses italic or underline in normal replies.
A recording of a markdown-heavy reply answers it before anything is flipped.

**Direction:** record one real session with a markdown reply and a diff,
count its SGR attributes, then the same route as the graphemes/widthCache flip
(7395b910c): side-by-side screenshots on the real app per flag, flip only what
looks better, re-record the default baselines and keep a
`feature-<name>_false` baseline for the old look. `cursorHollowUnfocused` is
the most likely keeper if split view is used.

**Size:** no plan; one session.

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

1. Plan 4 (background-pane cost): merged (`f4d93ba68`).
2. #2 recording and side-by-side session: done, `attributes` flipped (see its status).
3. #1: done, no gain (see its status).
4. #3 only if wanted.
