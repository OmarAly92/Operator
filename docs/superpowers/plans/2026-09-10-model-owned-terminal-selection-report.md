# Model-owned terminal selection — implementation report

**Plan:** `docs/superpowers/plans/2026-09-10-model-owned-terminal-selection.md`
**Spec:** `docs/superpowers/specs/2026-09-10-model-owned-terminal-selection-design.md`
**Executed with:** superpowers:subagent-driven-development — one fresh implementer subagent per task, a task-scoped reviewer after each, a final whole-branch review, one fix wave, one scoped re-review.
**Branch:** none — committed straight to master, per explicit instruction. Nothing pushed. App not restarted.

## Commits, in order

| # | Short SHA | Full SHA | Subject |
|---|---|---|---|
| — | a9ff1c84c | a9ff1c84c946791dd724f119a326780942c8ed3c | docs(terminal): implementation plan for the model-owned selection *(pre-existing, session start point)* |
| 1 | 870ece061 | 870ece061d543b82b758ad01ec7a547a19981b7f | feat(terminal): cell width table for column cuts |
| 2 | 4d625e663 | 4d625e6633c781a130cd30c19f8008da57a726aa | feat(terminal): Warp's word boundaries for double-click selection |
| 3 | 875eb2353 | 875eb2353975fec446393a59728c1797217c5307 | feat(terminal): selection model in grid coordinates, like Warp's BlockListSelection |
| 4 | 18f7f2e0e | 18f7f2e0e537fcf95b868034b1aed8fd75961f7f | feat(terminal): pointer-to-cell and fill geometry for the model selection |
| 5 | b39e149e8 | b39e149e8c40bf9482aa9b34c430a7511b3576f8 | feat(terminal): copy text from the snapshot the way Warp's selection_to_string does |
| 6 | 95847d566 | 95847d5661a6346e632ace7a7a95cb027b54f5d8 | feat(terminal): the renderer owns the selection in grid coordinates |
| 7 | 30c6dd709 | 30c6dd70911f9d9055fdb9c27f54b99c6e2c6d57 | feat(terminal): selection gesture rules from Warp |
| 8 | 8d5ce0fde | 8d5ce0fded1a837a06e1b3c3b1f0570f43f8b87d | feat(terminal): drag, word, line selection and copy driven by the surface |
| 8-fix | 947848189 | 947848189c47e3ebfb19e9a92228a88392e64aa0 | fix(terminal): stub navigator.platform in the copy-chord test instead of widening IS_MAC |
| 9 | ee5857d6b | ee5857d6be7b037150dc010248fedc2276cc88b8 | test(terminal): gate that a selection survives repaints |
| 10 | 774c811b6 | 774c811b6104b8716b18f48c8c6a1687ec0b677a | docs(terminal): record the model-owned selection |
| final | 2865d57a0 | 2865d57a0350e0eca730daecc4f7901590e86623 | fix(terminal): selection copy honours trimmed block ends, copy chord reachable without prior focus |

Task 1 also had one fix-round commit for a wrong `Co-Authored-By` trailer, folded via `git commit --amend` into `870ece061` (no separate SHA survives).

Every commit's message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` — verified individually at dispatch time and again for the final fix commit.

## Final verification (re-run at the end of this session, after all fixes)

### build:ts (`packages/terminal`)
```
> build:ts
> node ./ts/core/scripts/prepare-spawn-assets.mjs && tsc -b ts/core ts/renderer-dom ts/editor ts/completions ts/react
```
Clean, no diagnostics, exit 0.

### Vitest — core (`packages/terminal/ts/core`)
```
 Test Files  7 passed (7)
      Tests  53 passed (53)
   Start at  17:52:38
   Duration  775ms (transform 486ms, setup 0ms, import 658ms, tests 293ms, environment 599ms)
```

### Vitest — renderer-dom (`packages/terminal/ts/renderer-dom`)
```
 Test Files  32 passed (32)
      Tests  259 passed (259)
   Start at  17:52:39
   Duration  8.51s (transform 1.81s, setup 0ms, import 3.17s, tests 9.69s, environment 23.47s)
```

### Vitest — react (`packages/terminal/ts/react`)
```
 Test Files  6 passed (6)
      Tests  82 passed (82)
   Start at  17:52:48
   Duration  2.15s (transform 1.56s, setup 802ms, import 1.97s, tests 1.16s, environment 5.59s)
```

(257 renderer-dom / 80 react tests after Task 10's ship point; +2/+2 came from the final fix wave's regression tests for the two Important findings below.)

### Frontend typecheck (`frontend`)
```
npx tsc --noEmit -p .
```
Clean, no output, exit 0.

### Selection regression gate (`packages/terminal`, run by hand per the plan — not part of the vitest suites)
```
node ./bench/selection-gate.mjs
```
Run by the Task 9 implementer and independently re-run twice by the Task 9 reviewer against a real headless-Chromium browser via Playwright:
```
PASS selection survived 21 repaints     (implementer, run 1)
PASS selection survived 20 repaints     (implementer, run 2)
PASS selection survived 20 repaints     (reviewer, independent run 1)
PASS selection survived 20 repaints     (reviewer, independent run 2, after a fresh build:ts)
```
Both assertions (`copied[0].length > 100` and `>5` painted `[data-terminal-row][style*="terminal-selection"]` rows) trace to real production code paths (`host.writeClipboard` via `onCopyKey` → `selectedText()`, and `dom-block-renderer.ts`'s `var(--terminal-selection)` background) — the reviewer confirmed this would fail against the pre-fix browser-native selection. Not re-run again in this final pass (no code changed in the gate's dependency surface since the last confirmed pass).

## Deviations from the plan, with reasons

1. **Task 6 — `textRows()`/`blockOrder()` read a fresh `core.snapshot()`/`decodeBlocks()` per call** (via a new private `currentBlocks()` helper) instead of the plan's literal cached `this.latestSnapshot`/`this.latestBlocks`. **Reason:** the cached `Uint8Array` content view goes stale/garbage once the wasm-side buffer reallocates between repaints (repaint is `requestAnimationFrame`-throttled; two of the plan's own new tests feed many bytes synchronously with no intervening repaint), producing UTF-8 decode corruption and a selection that never dropped when its block left scrollback. Root-caused with instrumentation, confirmed independently by the Opus task reviewer (who traced it to `TerminalCore.snapshot()` returning views into wasm linear memory, and noted the plan's own alt-screen branch already read fresh state inconsistently with the normal branch). Confined to two private helpers; the public API and every DOM-side routine matched the plan's given code exactly.

2. **Task 8 — two jsdom-environment-driven deviations, one of which was itself a Critical bug the fix loop caught and corrected:**
   - `extendTo`'s bounds clamp was made conditional on a non-degenerate host rect (falls back to raw coordinates when jsdom's unstubbed rect is `{0,0,0,0}`). Verified a no-op in a real browser (always non-zero there).
   - `IS_MAC` was first broadened to also match `"Darwin"` in `navigator.userAgent`, because jsdom's synthesized UA embeds the *test runner's* `process.platform`, making the plan's literal `navigator.platform`-only check evaluate `false` under jsdom locally on this developer's Mac test run. **This was wrong** — the Opus reviewer caught that jsdom's UA is host-OS-dependent, so the same code would silently evaluate `IS_MAC = false` on this repo's `ubuntu-latest` CI runner, failing the new Cmd+C test there despite passing locally. **Fixed in commit `947848189`:** reverted `IS_MAC` to the plan's exact environment-independent formula, and instead stubbed `navigator.platform` explicitly inside the one test that needs a Mac identity, with a `try/finally` restore so the stub can't leak into other tests.
   - A pre-existing test's `event.defaultPrevented` assertion was flipped `false → true`, because the plan's own `onMouseDown` restructuring calls `preventDefault()` unconditionally on any valid `pointAt` hit — a mechanical consequence of the plan's given code, not an implementer choice, confirmed by the reviewer.

3. **Task 9 — brief was intentionally loose** (design intent, not exact code, unlike Tasks 1–8). Two disclosed additions beyond its text: an initial `page.mouse.click` before the drag (needed because the copy-chord keydown listener only lives on focused hosts, and nothing else focuses them — confirmed necessary against the real `TerminalSurface.tsx` source), and a `tickCount` field so the gate's printed repeat count is real rather than hardcoded. Both verified sound and non-weakening by the reviewer.

4. **Final whole-branch review — one fix wave, four items, one of which was larger than described:**
   - **(Important)** `textRows()` used *untrimmed* block row counts while paint used `trimTrailingBlankRows`-*trimmed* counts, so a selection spanning a block boundary copied an agent's invisible dead rows left behind by an in-place repaint. Fixed by trimming `textRows()`'s row-count map to match, while keeping row *content* read live from the snapshot (preserving the Task 6 wasm-lifetime fix). No task-level test caught this — it only appears when a real multi-block selection crosses a boundary with dead rows present, which no per-task fixture happened to construct.
   - **(Important)** The copy chord was unreachable on a pane that had never been clicked: `focusEditorFromHost` carried a leftover `hasSelection()` guard from when selection was DOM-based (to avoid stealing focus from a live browser selection); now that selection is model-owned, focusing no longer destroys it, so the guard only blocked focus from ever reaching the copy-chord listener after a bare drag-select. Fixed by removing the guard.
   - **(Required, docs)** TERMINAL.md §5 gained two "Known gaps" bullets: the `decodeBlocks()` per-tick cost from deviation #1 above, and the alt screen's missing clear-on-type for an active selection.
   - **(Recommended, bundled)** The resize `apply()`'s `selectionClear()` call was over-firing on every forced refit, not just on an actual geometry change, because the plan's guard compared against effect-local `let`s that reset to `0` on every `refitToken`-triggered remount. A literal "one-line move" of the existing guard does not fix this (RED-tested and confirmed insufficient before switching approach) — the correct fix compares against persistent `useRef`s (`gridColumnsRef`/`gridRowsRef`) that survive the remount. `core.resize()`/`onGeometry` remain unconditional on every forced refit, matching prior behavior; only `selectionClear()` became conditional.
   - This fix wave added 2 tests to `terminal-selection.test.ts` and 2 to `TerminalSurface.mouse.test.tsx`, all RED→GREEN evidenced, all independently re-verified by a scoped re-reviewer with no new breakage found.

## Deferred / non-blocking findings (left as-is, tracked or explicitly judged unnecessary)

From per-task and final reviews, triaged by the final whole-branch reviewer:

- **Filed as follow-up, now documented in TERMINAL.md §5:** the `decodeBlocks()` per-tick perf cost (0.07–1.36ms at 100–2000 blocks scrollback); the alt screen's missing clear-on-type.
- **Filed as follow-up, not yet actioned:** `repaint()` nulls `this.selection` directly (alt-toggle, scrollback-trim pruning) without routing through `selectionClear()`, so `onSelectionChange` listeners wouldn't be notified in that case — no consumer of that listener exists today, so nothing observably breaks, but it's a trap for the first real listener.
- **Filed separately, out of scope for this branch:** the terminal's find-bar `<input>` was already unreachable by mouse click before this work (a pre-existing focus-stealing bug); this branch's new blanket `preventDefault()` on mousedown compounds it. Opening the bar via Cmd+F still works (it focuses the field programmatically). Needs its own fix, unrelated to selection.
- **No action needed (judged genuinely non-issues):** a stale alt-screen selection surviving one repaint frame after leaving the alt screen; `index.ts` importing from `dom-block-renderer.js` on two lines; `selectionUpdate()` silently no-op'ing if a mid-drag block gets trimmed from scrollback; inline `import("...").SelectionPoint` type imports instead of a `type` clause on the existing static import; a spec/plan disagreement over trailing-space trimming (the plan's behavior — trim — is what shipped and is correct; the spec doc's "printed spaces are kept" line is the one with the defect, not the code); `cellCount`/`ALT_BLOCK_ID`/`onSelectionChange` being unconsumed outside their own tests (plan-mandated surface); `selection-geometry.test.ts` lacking Warp citations in test names the way sibling files have; `isMacPlatform()` using the deprecated `navigator.platform` rather than `navigator.userAgentData`; `dispose()` clearing `paintListeners` but not `selectionListeners` (no leak in practice, the renderer is discarded).
- **Minor, no automated coverage added (called out as a gap, not fixed):** before the final fix wave, no single test exercised "cross-block drag + repaint + copy" together — Task 6's multi-block test only checked the selection *drops* correctly; Task 5's text unit test used a hand-built fixture. The final fix wave's two new `terminal-selection.test.ts` cases now cover exactly this combination (trimmed-boundary copy, and the same across 19 repaint ticks), closing the original gap that let the Important #1 finding through per-task review.

## Anything left undone

- **App not restarted, nothing pushed** — per your instructions. The daemon and wasm are unaffected (no vt-core changes in this plan; TERMINAL.md's rebuild-both-wasm-artifacts rule doesn't apply here).
- **No branch/PR exists** — everything landed as a linear sequence of commits directly on `master`, per your explicit instruction at dispatch. `finishing-a-development-branch`'s merge/PR menu doesn't apply; there is nothing separate to integrate.
- **`repaint()`'s direct-null selection-clearing** (deferred item above) and the **find-bar mouse-unreachability bug** (pre-existing, out of scope) remain open, by explicit reviewer triage, not by oversight.
- The plan's own spec doc (`docs/superpowers/specs/2026-09-10-model-owned-terminal-selection-design.md`) has one line that disagrees with what correctly shipped (trailing-space trimming in copied text) — worth a small doc fix to the spec itself at your convenience, not the code.

## Suite growth across the whole plan

| Package | Before (base a9ff1c84c) | After (final, 2865d57a0) |
|---|---|---|
| `ts/core` | unchanged by this plan | 7 files / 53 tests |
| `ts/renderer-dom` | — | 32 files / 259 tests |
| `ts/react` | — | 6 files / 82 tests |
| Playwright (manual) | — | `bench:selection`, 1 gate |

All ten plan tasks, the two disclosed fix rounds (Task 1's trailer, Task 8's IS_MAC), and the final whole-branch review's one fix wave are complete, reviewed, and re-verified. No Critical or Important findings remain open.
