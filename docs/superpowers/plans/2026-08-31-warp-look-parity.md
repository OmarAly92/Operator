# Warp Look Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four look gaps found in the 2026-08-30 side-by-side against Warp, so a
pane reads as Warp's at a glance — in every pane, including agent panes.

**Architecture:** Three of the four are wrong values, not missing machinery, and their Warp
counterparts are already tabulated in spec §12.1. The fourth is an unexplained clipped row
that must be reproduced before it is touched. Two of the three "simple" fixes have a trap
that makes the naive version wrong; both are called out in the task that hits them.

**Tech Stack:** TypeScript, CSS, one bundled webfont.

**Spec:** [`docs/superpowers/specs/2026-08-29-warp-terminal-package-design.md`](../specs/2026-08-29-warp-terminal-package-design.md) — §9.2 (virtualization), §12.1 (theme, and the table of Warp's own values), §14 Phase 6.

---

## Warp's values, verified

Read in `/Users/omaraly/development/AI/warp` on 2026-08-30 and tabulated in spec §12.1.

| Property | Warp | Ours today | Source |
| --- | --- | --- | --- |
| Line-height ratio | `1.2` | `1.35` | `crates/warpui_core/src/elements/gui/text.rs:33`, wired at `app/src/settings/font.rs:50-58` |
| Monospace family | `Hack` | `ui-monospace, "SF Mono", Menlo, monospace` | `app/src/settings/font.rs:11` |
| Monospace size | `13.0` | host-supplied, package default `14` | `app/src/settings/font.rs:12` |
| Grid padding | `16` left, `8` vertical | none | `app/src/terminal/view.rs:744, 13098-13099` |

Warp also makes alt-screen padding separately configurable (`alt_screen_padding`,
`app/src/terminal/settings.rs:163`) with a carve-out set for apps that must match blocklist
padding — `k9s` and `lazygit` (`view.rs:603-609`). Task 2 copies the setting shape, not just
the number.

## Global Constraints

- **No comments in code.** The user's global rule.
- **No file over 600 lines** (`check-boundaries.mjs`).
- The package must not import from `frontend/`; `frontend/` imports by package name (§4.2).
- Bundled assets live inside `packages/terminal`; the package stays self-contained.
- Every task ends with `npm --prefix packages/terminal test`, `npm --prefix frontend test`
  and `npm --prefix packages/terminal run check:boundaries` green.
- Do **not** expect `bench:gate` to be green. `input-latency` is red from the paint throttle
  in `ac9236563`; spec §9.5 carries that as an open decision. Note if a number moves.

---

### Task 1: Line height 1.2, the value Warp actually uses

**Files:**
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx:383`
- Test: `frontend/src/renderer/components/BlockTerminal.test.tsx`

The package's own `defaultFont()` already uses `1.2`
(`ts/renderer-dom/src/dom-block-renderer.ts:475`). The `1.35` is a host override, so this is
a one-value change in `frontend`, not in the package.

- [ ] **Step 1: Write the failing test**

Assert the font config the host hands to `TerminalSurface`:

```tsx
it("uses Warp's line-height ratio", async () => {
	render(<BlockTerminal {...props} />);
	const font = await capturedFont();
	expect(font.lineHeight).toBe(1.2);
});
```

Read the neighbouring tests for how the surface props are captured rather than inventing a
harness.

- [ ] **Step 2: Run it and watch it fail**

```bash
npm --prefix frontend test -- BlockTerminal
```

Expected: FAIL, received `1.35`.

- [ ] **Step 3: Change the value**

In the `font` memo, `lineHeight: 1.35` becomes `lineHeight: 1.2`.

- [ ] **Step 4: Run it and watch it pass, then check nothing else pinned 1.35**

```bash
npm --prefix frontend test
npm --prefix packages/terminal test
```

Any test that asserted a pixel height derived from `1.35` describes the old look and must be
updated to the new ratio, not deleted.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer
git commit -m "feat(terminal): use Warp's 1.2 line-height ratio"
```

---

### Task 2: Grid padding, without breaking the geometry

**Files:**
- Modify: `packages/terminal/ts/react/src/TerminalSurface.tsx` — a padded wrapper
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css` and `styles.ts`
- Test: `packages/terminal/ts/react/src/TerminalSurface.test.tsx`

**The trap, and why the obvious version is wrong.** Geometry is computed as
`Math.floor(blockHost.clientWidth / cellWidth)` and the same for rows
(`TerminalSurface.tsx:117-118`). `clientWidth` and `clientHeight` **include** padding. Put
Warp's 16px/8px directly on the measured element and the grid will believe it has one to two
more columns and one more row than it can draw, and content will overflow the pane. Put the
padding on a **wrapper** and measure the inner element, whose client box is then the real
content box.

- [ ] **Step 1: Write the failing tests**

```ts
	it("pads the surface the way Warp does", () => {
		const { wrapper } = mountSurface();
		const style = getComputedStyle(wrapper);
		expect(style.paddingLeft).toBe("16px");
		expect(style.paddingTop).toBe("8px");
		expect(style.paddingBottom).toBe("8px");
	});

	it("measures the grid inside the padding, not through it", () => {
		const { host, onGeometry } = mountSurface({ width: 816, height: 408, cellWidth: 8, cellHeight: 16 });
		expect(host.clientWidth).toBe(784);
		expect(onGeometry).toHaveBeenCalledWith(98, 25);
	});
```

The second test is the one that matters: 816 minus 2×16 is 784, which is 98 columns at 8px,
not the 102 an unpadded measurement would report. Pick whatever numbers the harness can
actually produce in jsdom — if `clientWidth` cannot be driven there, assert on the value
passed to `core.resize` with a stubbed host instead, and say so in the test name.

- [ ] **Step 2: Run them and watch them fail**

```bash
npm --prefix packages/terminal/ts/react test
```

- [ ] **Step 3: Add the wrapper**

Wrap the block host in an element carrying the padding, and keep every measurement — the
`ResizeObserver`, `clientWidth`/`clientHeight`, and `pointerCell`'s
`getBoundingClientRect` — pointed at the **inner** host. `pointerCell` is easy to miss and
will silently offset mouse reporting by 16px if the wrapper's rect is used instead.

Padding values go in the stylesheet as custom properties so §12.1's follow-up can make them
configurable:

```css
	--terminal-padding-x: 16px;
	--terminal-padding-y: 8px;
```

Mirror every stylesheet change into `styles.ts`; `styles-parity.test.ts` fails if the two
drift.

- [ ] **Step 4: Run the suites**

```bash
npm --prefix packages/terminal test
npm --prefix frontend test
```

- [ ] **Step 5: Commit**

```bash
git add packages/terminal/ts
git commit -m "feat(terminal): pad the grid 16 by 8, the way Warp does"
```

---

### Task 3: Ship Hack, because naming it is not enough

**Files:**
- Create: `packages/terminal/ts/renderer-dom/src/fonts/` — the woff2 files
- Modify: `packages/terminal/ts/renderer-dom/src/styles.css` and `styles.ts` — `@font-face`
- Modify: `frontend/src/renderer/components/BlockTerminal.tsx` — the family stack
- Modify: `packages/terminal/ts/renderer-dom/package.json` — ship the files
- Test: `packages/terminal/ts/renderer-dom/src/styles-parity.test.ts`

**Hack is not installed on this machine** — `~/Library/Fonts` and `/Library/Fonts` have no
Hack. Setting `font-family: Hack` alone therefore changes nothing: it falls back to the
system stack and the pane looks exactly as it does today. Warp bundles the font; to match
it, so must we.

- [ ] **Step 1: Confirm the licence before adding the files**

Hack is distributed under a licence that permits redistribution and webfont embedding.
**Verify the current licence text from the upstream release you download**, and record its
name and version in the commit message. If it cannot be verified, stop and report — do not
add a font on an assumption.

- [ ] **Step 2: Write the failing test**

```ts
	it("declares the bundled family so it is not a silent fallback", () => {
		expect(terminalStyles).toContain("@font-face");
		expect(terminalStyles).toContain('font-family: "Hack"');
	});
```

Plus a `frontend` test that the font stack's first entry is `Hack`.

- [ ] **Step 3: Add regular, bold, italic and bold-italic as woff2**

Four faces, `font-display: swap`, referenced from `@font-face` in the package stylesheet.
Add the directory to `package.json`'s `files` so it survives packaging.

- [ ] **Step 4: Set the stack**

In `BlockTerminal.tsx`'s font memo:

```ts
			family: '"Hack", ui-monospace, "SF Mono", Menlo, monospace',
```

The fallbacks stay: a host that fails to load the bundled font must still render.

- [ ] **Step 5: Verify it actually loaded, not fell back**

In the running app, confirm `document.fonts.check('13px Hack')` is `true` and that the
rendered cell width changed from the SF Mono measurement. A green test that only asserts the
CSS string proves nothing about what the user sees.

- [ ] **Step 6: Commit**

```bash
git add packages/terminal frontend/src/renderer
git commit -m "feat(terminal): bundle Hack, the font Warp actually renders"
```

---

### Task 4: The clipped bottom row — reproduce before fixing

**Files:** unknown until Step 1. Do not guess.

Observed 2026-08-30 in a live agent pane: the bottom row rendered clipped and the TUI's
input composer was missing. This should be impossible — geometry floors
(`Math.floor(clientHeight / cellHeight)`), which under-fills and leaves a gap; it cannot
clip. Something disagrees between the measured cell height and the rendered row box.

Tasks 1–3 all change cell metrics, so **run this task last**: the symptom may move or
disappear, and either outcome is information.

- [ ] **Step 1: Reproduce it and capture the numbers**

Run the app, open an agent pane, and from the devtools console record: `blockHost.clientHeight`,
`renderer.measure().cellHeight`, the row count in the snapshot, the number of
`[data-terminal-row]` elements, and the `getBoundingClientRect().height` of one row.

- [ ] **Step 2: Name the disagreement**

`clientHeight / cellHeight` versus the rendered rows tells you which of three it is: the
measured cell height is smaller than the painted row box (rows overflow), the grid holds
more rows than were requested (a resize race), or the surface is taller than its container
(a layout problem outside the grid).

- [ ] **Step 3: Write the failing test, then fix**

Whichever it is, the test is at that seam and asserts the arithmetic, not the pixels.

**Reproduced 2026-08-31, in real Chromium via the smoke harness.** Measured on a 240px-tall
root with the surface padded 8px vertically:

| Measurement | Value |
| --- | --- |
| `.terminal-surface` content box | 224px |
| `.terminal-host` + `.terminal-editor-host` | 242px |
| **Overflow** | **18px, exactly the editor host's height** |
| `surfaceBottom` vs `rootBottom` | 920 = 920 (clipped, not scrolled) |

The cause is the layout: `.terminal-surface` is `height: 100%` with padding, and
`.terminal-host` inside it is *also* `height: 100%` — so the host consumes the entire
content box and `.terminal-editor-host` stacks below it, past the bottom edge. That is the
missing input composer.

**The fix is a flex column, and it is not landed.** Making `.terminal-surface`
`display: flex; flex-direction: column` with `.terminal-host { flex: 1 1 auto; min-height: 0 }`
removes the overflow, but it shrinks the host by ~35px and the pane then permanently stops
following its output: the smoke `follow` fixture ends 35px from the bottom
(`scrollTop 8216`, max `8251`, `clientHeight 166`) and does not converge after 600ms. A
`ResizeObserver` on the container that re-asserts stickiness across a shrink did **not** fix
it, and the cause was not identified — `applyStickiness` computes
`scrollHeight - clientHeight` at paint time and lands on a value 35px short, which means
either `stickToBottom` is already false by then or the geometry it reads is stale.

Whoever picks this up starts from those numbers rather than from scratch. Do not land the
flex change without resolving the follow regression: it trades a clipped composer for a
pane that stops following output, which is worse.

- [ ] **Step 4: If it does not reproduce, say so and stop**

Record what you tried and close it as not-reproducible. Do not fix a symptom you cannot see.

- [ ] **Step 5: Commit**

```bash
git commit -m "fix(terminal): <what the measurement showed>"
```

---

### Task 5: Record it

- [ ] **Step 1: Amend §12.1**

Replace the "values we currently get wrong" table with what landed: the ratio, the padding
custom properties, and the bundled font with its licence. Keep Warp's citations.

- [ ] **Step 2: Amend §14 Phase 6**

Mark the four deferred items resolved or, for Task 4 if it did not reproduce, re-deferred
with the reason — Phase 6's accept criteria require each to be fixed or explicitly
re-deferred.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers
git commit -m "spec: close the phase 6 look gaps"
```

---

## Self-Review

**Spec coverage.** All four §12.1 rows get a task, and Phase 6's "fixed or explicitly
re-deferred" criterion is Task 5.

**Warp fidelity.** Every value is cited to a file and line read on 2026-08-30 and already
tabulated in §12.1. Task 2 copies Warp's separately-configurable padding as custom
properties rather than hardcoding, because Warp has a setting there and a carve-out list.

**The two traps, both verified rather than assumed.** `clientWidth` includes padding, so
padding on the measured element inflates the grid — Task 2 uses a wrapper and pins the
arithmetic with a test. Hack is absent from this machine's font directories, so naming it in
CSS is a no-op — Task 3 bundles it and Step 5 checks it actually loaded rather than trusting
a CSS assertion.

**Ordering.** Tasks 1–3 are independent of each other but all change cell metrics, so Task 4
runs last on purpose. Task 4 may end in "not reproducible", which is a valid outcome and is
written as one.

**Out of scope.** The red `input-latency` gate (§9.5). Warp theme-file loading, splits, and
scrollback persistence — the rest of Phase 6, which this plan does not attempt.
