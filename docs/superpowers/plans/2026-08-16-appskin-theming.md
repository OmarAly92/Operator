# AppSkin Theming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CSS-cascade theming in `frontend/src/styles/tokens.css` with a typed `AppSkin` contract, so adding a theme is one file that the type system checks for completeness.

**Architecture:** A skin is a flat, typed record of colour slots keyed by slot name and mapped to CSS custom properties by a generated token map. `defineSkin()` resolves an author's input (required slots + any derived slot they override) into a complete `AppSkin`. Three bridges consume it: `skinToCssVars()` for Tailwind/shadcn, `useSkin()` for React, `skinToXtermTheme()` for the terminal. Values are extracted from the existing CSS mechanically rather than transcribed by hand, and a parity test pins the generated output to the current stylesheet so the first phases are provably invisible.

**Tech Stack:** TypeScript, React 19, Tailwind v4 (`@theme inline`), Zustand, Vitest + jsdom, `@xterm/xterm` 5.5.

**Spec:** `docs/superpowers/specs/2026-08-16-appskin-theming-design.md`

## Global Constraints

- **Phase 1–2 must be visually invisible.** Any generated CSS var that differs from the current stylesheet is a bug, not a design choice. The parity test is the arbiter.
- **The `data-theme` and `data-style-theme` attributes must keep being set.** 21 rules in `renderer/styles.css` are keyed on them (e.g. `:root[data-theme="light"] .cursor-chat-surface`). Removing the attributes breaks those rules even though skins now supply the vars.
- **No new runtime dependencies.** Derived slots emit CSS `color-mix(...)` / `oklch(... / n%)` strings, which the existing tokens already use — no colour-manipulation library.
- **Doc comments on skin slots are required**, as an explicit exception to the repo's no-comments rule. They are the feature: they make "which colour goes here?" answerable. Comments elsewhere still follow the normal rule.
- **Never a raw hex in feature code.** Reaching for one means a slot is missing.
- Design system: `DESIGN.md` — the renderer clones agent-orchestrator verbatim. This work changes no design.
- Commands, from `frontend/`: `npm run test` (Vitest), `npm run typecheck`. From the repo root: `npm run lint`.
- Test conventions: Vitest with jsdom, tab indentation, `import { describe, expect, it } from "vitest"`.
- Token counts to expect: **230** colour tokens in the base `:root` block, **146** in the `[data-theme="light"]` block, **24** per style theme, **8** style themes.

---

## File Structure

| File | Responsibility |
|---|---|
| `frontend/scripts/extract-skin-tokens.mjs` | Build-time-only: parses `tokens.css`, emits `token-map.generated.ts` and the skin value files. Not shipped |
| `frontend/src/renderer/theme/token-map.generated.ts` | `SKIN_TOKENS`: slot name → CSS var name. Generated, checked in |
| `frontend/src/renderer/theme/app-skin.ts` | `AppSkin`, `SkinInput`, `RequiredSlot`, `DerivedSlot`, `defineSkin()` |
| `frontend/src/renderer/theme/skins/dark.ts` … `solarized.ts` | One file per skin |
| `frontend/src/renderer/theme/skins/index.ts` | `skinFor(style, theme)` registry |
| `frontend/src/renderer/theme/bridge/css-vars.ts` | `skinToCssVars()`, `applySkinVars()` |
| `frontend/src/renderer/theme/bridge/xterm-theme.ts` | `skinToXtermTheme()` |
| `frontend/src/renderer/theme/skin-context.tsx` | `SkinProvider`, `useSkin()` |
| `frontend/src/renderer/theme/README.md` | The one rule and the recipes |

Skins keep the existing **two-axis** model — `ThemeStyle` (9 values) × `Theme` (light/dark) — because the UI has two separate controls and a `system` preference. A skin is the resolved pair.

---

### Task 1: Extract the token inventory

Hand-transcribing 230 values × 18 blocks would introduce errors that the parity test would then faithfully enshrine. Extraction makes the values mechanical and reviewable.

**Files:**
- Create: `frontend/scripts/extract-skin-tokens.mjs`
- Create: `frontend/src/renderer/theme/token-map.generated.ts` (script output)
- Test: `frontend/src/renderer/theme/token-map.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces: `SKIN_TOKENS: Record<string, string>` (slot name → CSS var name), `SlotName = keyof typeof SKIN_TOKENS`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { SKIN_TOKENS } from "./token-map.generated";

describe("token map", () => {
	it("covers every colour token in the base block", () => {
		expect(Object.keys(SKIN_TOKENS).length).toBe(230);
	});

	it("maps camelCase slot names to their CSS variable", () => {
		expect(SKIN_TOKENS.statusWorking).toBe("--color-status-working");
		expect(SKIN_TOKENS.background).toBe("--background");
		expect(SKIN_TOKENS.sidebarAccent).toBe("--sidebar-accent");
	});

	it("has no duplicate CSS variable targets", () => {
		const vars = Object.values(SKIN_TOKENS);
		expect(new Set(vars).size).toBe(vars.length);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/token-map.test.ts`
Expected: FAIL — `Cannot find module './token-map.generated'`

- [ ] **Step 3: Write the extraction script**

```js
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const TOKENS = path.resolve("src/styles/tokens.css");
const NON_COLOUR = /^--(size|space|radius|font|tracking|leading|z|duration|ease|breakpoint)/;

// `--color-` is a namespace prefix, not part of the name: --color-status-working
// and --background must both yield a usable slot name.
function camel(cssVar) {
	return cssVar
		.replace(/^--(color-)?/, "")
		.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

function assertNoCollisions(cssVars) {
	const seen = new Map();
	for (const cssVar of cssVars) {
		const slot = camel(cssVar);
		if (seen.has(slot)) {
			throw new Error(`slot name collision: ${slot} <- ${seen.get(slot)} and ${cssVar}`);
		}
		seen.set(slot, cssVar);
	}
}

export function parseBlock(css, selector) {
	const start = css.indexOf(selector);
	if (start === -1) throw new Error(`selector not found: ${selector}`);
	const open = css.indexOf("{", start);
	const close = css.indexOf("\n}", open);
	const body = css.slice(open + 1, close);
	const out = {};
	for (const line of body.split("\n")) {
		const match = line.match(/^\s*(--[a-z0-9-]+)\s*:\s*(.+?);/);
		if (!match) continue;
		const [, name, value] = match;
		if (NON_COLOUR.test(name)) continue;
		out[name] = value.trim();
	}
	return out;
}

const css = await readFile(TOKENS, "utf8");
const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
assertNoCollisions(Object.keys(base));
const entries = Object.keys(base).sort().map((v) => `\t${camel(v)}: "${v}",`);

await writeFile(
	path.resolve("src/renderer/theme/token-map.generated.ts"),
	`// Generated by scripts/extract-skin-tokens.mjs. Do not edit.\n` +
		`export const SKIN_TOKENS = {\n${entries.join("\n")}\n} as const;\n\n` +
		`export type SlotName = keyof typeof SKIN_TOKENS;\n`,
);

console.log(`wrote ${Object.keys(base).length} tokens`);
```

- [ ] **Step 4: Run the script and the test**

Run: `cd frontend && node scripts/extract-skin-tokens.mjs && npx vitest run --config vite.renderer.config.ts src/renderer/theme/token-map.test.ts`
Expected: script prints `wrote 230 tokens`; test PASSES.

If the count is not 230, the block selector or the `NON_COLOUR` filter is wrong — fix the script, not the test. The test's number comes from the spec's measurement.

If `assertNoCollisions` throws, two tokens collapse to one slot name — most likely a
`--accent` / `--color-accent-*` pair, since stripping the `--color-` namespace can make them
identical. Resolve it by keeping the namespace for the colliding token only: add an explicit
override map in the script (`const SLOT_OVERRIDES = { "--color-accent-foo": "colorAccentFoo" }`)
and consult it before calling `camel`. Do not silence the guard.

- [ ] **Step 5: Commit**

```bash
git add frontend/scripts/extract-skin-tokens.mjs frontend/src/renderer/theme/
git commit -m "feat(theme): extract the colour token inventory into a typed map"
```

---

### Task 2: The AppSkin contract

Every slot starts **required**. Derivation is introduced later (Task 6) with the parity test proving each move is safe. Starting flat means Phase 1 cannot drift.

**Files:**
- Create: `frontend/src/renderer/theme/app-skin.ts`
- Test: `frontend/src/renderer/theme/app-skin.test.ts`

**Interfaces:**
- Consumes: `SKIN_TOKENS`, `SlotName` from Task 1
- Produces: `AppSkin = Record<SlotName, string>`, `type SkinInput`, `defineSkin(input: SkinInput): AppSkin`, `DERIVED_DEFAULTS: Partial<Record<SlotName, (s: Record<SlotName, string>) => string>>`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { defineSkin } from "./app-skin";
import { SKIN_TOKENS } from "./token-map.generated";

const everySlot = Object.fromEntries(Object.keys(SKIN_TOKENS).map((k) => [k, "#000000"]));

describe("defineSkin", () => {
	it("resolves a fully specified skin unchanged", () => {
		const skin = defineSkin(everySlot as never);
		expect(Object.keys(skin).length).toBe(Object.keys(SKIN_TOKENS).length);
		expect(skin.statusWorking).toBe("#000000");
	});

	it("leaves no slot undefined", () => {
		const skin = defineSkin(everySlot as never);
		for (const slot of Object.keys(SKIN_TOKENS)) {
			expect(skin[slot as keyof typeof skin], `slot ${slot}`).toBeDefined();
		}
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/app-skin.test.ts`
Expected: FAIL — `Cannot find module './app-skin'`

- [ ] **Step 3: Write the contract**

```ts
import { SKIN_TOKENS, type SlotName } from "./token-map.generated";

export type AppSkin = Record<SlotName, string>;

export type DerivedSlot = never;
export type RequiredSlot = Exclude<SlotName, DerivedSlot>;

export type SkinInput = Pick<AppSkin, RequiredSlot> & Partial<Pick<AppSkin, DerivedSlot>>;

export const DERIVED_DEFAULTS: Partial<Record<SlotName, (skin: Partial<AppSkin>) => string>> = {};

export function defineSkin(input: SkinInput): AppSkin {
	const resolved = { ...input } as AppSkin;
	for (const slot of Object.keys(SKIN_TOKENS) as SlotName[]) {
		if (resolved[slot] !== undefined) continue;
		const derive = DERIVED_DEFAULTS[slot];
		if (!derive) throw new Error(`skin is missing required slot: ${slot}`);
		resolved[slot] = derive(resolved);
	}
	return resolved;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/app-skin.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/theme/app-skin.ts frontend/src/renderer/theme/app-skin.test.ts
git commit -m "feat(theme): add the AppSkin contract and defineSkin"
```

---

### Task 3: The dark and light skins, pinned by a parity test

This is the task that makes Phase 1 provable. The parity test reads `tokens.css` at test time and asserts the skins reproduce it exactly.

**Files:**
- Modify: `frontend/scripts/extract-skin-tokens.mjs` (emit skin value files)
- Create: `frontend/src/renderer/theme/skins/dark.ts`, `frontend/src/renderer/theme/skins/light.ts`
- Test: `frontend/src/renderer/theme/skin-parity.test.ts`

**Interfaces:**
- Consumes: `defineSkin` from Task 2, `parseBlock` from Task 1
- Produces: `darkSkin: AppSkin`, `lightSkin: AppSkin`

- [ ] **Step 1: Write the failing test**

The light block overrides only 146 of the 230 slots, so `lightSkin` inherits the remaining 84 from the dark values — exactly what the cascade does today.

```ts
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseBlock } from "../../../scripts/extract-skin-tokens.mjs";
import { SKIN_TOKENS, type SlotName } from "./token-map.generated";
import { darkSkin } from "./skins/dark";
import { lightSkin } from "./skins/light";

const css = readFileSync(path.resolve(__dirname, "../../styles/tokens.css"), "utf8");

describe("skin parity with tokens.css", () => {
	it("dark skin reproduces the base block", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			expect(darkSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(base[cssVar]);
		}
	});

	it("light skin reproduces the light block, inheriting the rest from dark", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		const light = parseBlock(css, ':root[data-theme="light"]');
		expect(Object.keys(light).length).toBe(146);
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			const expected = light[cssVar] ?? base[cssVar];
			expect(lightSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(expected);
		}
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/skin-parity.test.ts`
Expected: FAIL — `Cannot find module './skins/dark'`

- [ ] **Step 3: Extend the script to emit the skin files**

Append to `scripts/extract-skin-tokens.mjs`:

```js
function emitSkin(name, values, importPath = "../app-skin") {
	const body = Object.entries(values)
		.sort(([a], [b]) => a.localeCompare(b))
		.map(([cssVar, value]) => `\t${camel(cssVar)}: "${value}",`)
		.join("\n");
	return (
		`// Generated by scripts/extract-skin-tokens.mjs. Do not edit.\n` +
		`import { defineSkin } from "${importPath}";\n\n` +
		`export const ${name} = defineSkin({\n${body}\n});\n`
	);
}

const light = parseBlock(css, ':root[data-theme="light"]');
await writeFile(path.resolve("src/renderer/theme/skins/dark.ts"), emitSkin("darkSkin", base));
await writeFile(
	path.resolve("src/renderer/theme/skins/light.ts"),
	emitSkin("lightSkin", { ...base, ...light }),
);
console.log(`wrote dark (${Object.keys(base).length}) and light (${Object.keys(light).length} overrides)`);
```

- [ ] **Step 4: Run the script and the test**

Run: `cd frontend && mkdir -p src/renderer/theme/skins && node scripts/extract-skin-tokens.mjs && npx vitest run --config vite.renderer.config.ts src/renderer/theme/skin-parity.test.ts`
Expected: PASS (2 tests). Both skins now reproduce `tokens.css` slot for slot.

- [ ] **Step 5: Commit**

```bash
git add frontend/scripts/extract-skin-tokens.mjs frontend/src/renderer/theme/skins/ frontend/src/renderer/theme/skin-parity.test.ts
git commit -m "feat(theme): generate the dark and light skins, pinned to tokens.css"
```

---

### Task 4: The CSS variable bridge

**Files:**
- Create: `frontend/src/renderer/theme/bridge/css-vars.ts`
- Test: `frontend/src/renderer/theme/bridge/css-vars.test.ts`

**Interfaces:**
- Consumes: `AppSkin`, `SKIN_TOKENS`
- Produces: `skinToCssVars(skin: AppSkin): Record<string, string>`, `applySkinVars(skin: AppSkin, root?: HTMLElement): void`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { applySkinVars, skinToCssVars } from "./css-vars";
import { darkSkin } from "../skins/dark";

describe("skinToCssVars", () => {
	it("emits one entry per slot, keyed by CSS variable name", () => {
		const vars = skinToCssVars(darkSkin);
		expect(Object.keys(vars).length).toBe(230);
		expect(vars["--color-status-working"]).toBe(darkSkin.statusWorking);
	});

	it("applies every variable to the element", () => {
		const root = document.createElement("div");
		applySkinVars(darkSkin, root);
		expect(root.style.getPropertyValue("--color-status-working")).toBe(darkSkin.statusWorking);
		expect(root.style.getPropertyValue("--background")).toBe(darkSkin.background);
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/bridge/css-vars.test.ts`
Expected: FAIL — `Cannot find module './css-vars'`

- [ ] **Step 3: Write the bridge**

```ts
import type { AppSkin } from "../app-skin";
import { SKIN_TOKENS, type SlotName } from "../token-map.generated";

export function skinToCssVars(skin: AppSkin): Record<string, string> {
	const vars: Record<string, string> = {};
	for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
		vars[cssVar] = skin[slot as SlotName];
	}
	return vars;
}

export function applySkinVars(skin: AppSkin, root: HTMLElement = document.documentElement): void {
	for (const [cssVar, value] of Object.entries(skinToCssVars(skin))) {
		root.style.setProperty(cssVar, value);
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/bridge/css-vars.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/theme/bridge/
git commit -m "feat(theme): bridge a skin onto CSS custom properties"
```

---

### Task 5: The skin registry and React access

**Files:**
- Create: `frontend/src/renderer/theme/skins/index.ts`, `frontend/src/renderer/theme/skin-context.tsx`
- Test: `frontend/src/renderer/theme/skins/index.test.ts`

**Interfaces:**
- Consumes: `darkSkin`, `lightSkin`, `Theme` and `ThemeStyle` from `renderer/lib/theme.ts`
- Produces: `skinFor(style: ThemeStyle, theme: Theme): AppSkin`, `SkinProvider`, `useSkin(): AppSkin`

- [ ] **Step 1: Write the failing test**

Until Task 7 ports them, every style resolves to the base skins — which is exactly today's behaviour, since no style theme overrides anything outside the 24 base tokens.

```ts
import { describe, expect, it } from "vitest";
import { skinFor } from "./index";
import { darkSkin } from "./dark";
import { lightSkin } from "./light";

describe("skinFor", () => {
	it("resolves the default style to the base skins", () => {
		expect(skinFor("orchestrate", "dark")).toBe(darkSkin);
		expect(skinFor("orchestrate", "light")).toBe(lightSkin);
	});

	it("resolves every known style for both appearances", () => {
		const styles = [
			"orchestrate", "github", "catppuccin", "dracula",
			"tokyo-night", "rose-pine", "nord", "gruvbox", "solarized",
		] as const;
		for (const style of styles) {
			expect(skinFor(style, "dark"), style).toBeDefined();
			expect(skinFor(style, "light"), style).toBeDefined();
		}
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/skins/index.test.ts`
Expected: FAIL — `Cannot find module './index'`

- [ ] **Step 3: Write the registry and the context**

`skins/index.ts`:

```ts
import type { Theme, ThemeStyle } from "../../lib/theme";
import type { AppSkin } from "../app-skin";
import { darkSkin } from "./dark";
import { lightSkin } from "./light";

const REGISTRY: Partial<Record<ThemeStyle, { dark: AppSkin; light: AppSkin }>> = {};

export function skinFor(style: ThemeStyle, theme: Theme): AppSkin {
	const pair = REGISTRY[style];
	if (pair) return theme === "light" ? pair.light : pair.dark;
	return theme === "light" ? lightSkin : darkSkin;
}
```

`skin-context.tsx`:

```tsx
import { createContext, useContext, type ReactNode } from "react";
import type { AppSkin } from "./app-skin";
import { darkSkin } from "./skins/dark";

const SkinContext = createContext<AppSkin>(darkSkin);

export function SkinProvider({ skin, children }: { skin: AppSkin; children: ReactNode }) {
	return <SkinContext.Provider value={skin}>{children}</SkinContext.Provider>;
}

export function useSkin(): AppSkin {
	return useContext(SkinContext);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/skins/index.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add frontend/src/renderer/theme/skins/index.ts frontend/src/renderer/theme/skins/index.test.ts frontend/src/renderer/theme/skin-context.tsx
git commit -m "feat(theme): add the skin registry and React access"
```

---

### Task 6: Apply skins at runtime without a flash

The attributes must still be set: 21 rules in `styles.css` are keyed on them.

`stores/ui-store.ts` already holds `themePreference`, `resolvedTheme` and `themeStyle` in
Zustand and applies them at three call sites (`:157`, `:165`, `:178`) inside
`runThemeTransition`. Skins hook in there, so React reactivity comes free from the existing
store rather than from a second source of truth.

**Files:**
- Modify: `frontend/src/renderer/lib/theme.ts` (add `applyDocumentSkin`)
- Modify: `frontend/src/renderer/lib/apply-initial-theme.ts`
- Modify: `frontend/src/renderer/stores/ui-store.ts:154-181` (three call sites)
- Modify: `frontend/src/renderer/theme/skin-context.tsx` (derive the skin from the store)
- Modify: `frontend/src/renderer/main.tsx` (mount the provider)
- Test: `frontend/src/renderer/lib/apply-initial-theme.test.ts`

**Interfaces:**
- Consumes: `skinFor`, `applySkinVars`, `resolveTheme`, `readStoredThemeStyle`, `useUiStore`
- Produces: `applyDocumentSkin(style: ThemeStyle, theme: Theme): void`, a `SkinProvider` that needs no props

- [ ] **Step 1: Write the failing test**

```ts
import { beforeEach, describe, expect, it } from "vitest";
import { applyDocumentSkin } from "./theme";
import { darkSkin } from "../theme/skins/dark";
import { lightSkin } from "../theme/skins/light";

describe("applyDocumentSkin", () => {
	beforeEach(() => {
		document.documentElement.removeAttribute("style");
		document.documentElement.removeAttribute("data-theme");
		document.documentElement.removeAttribute("data-style-theme");
	});

	it("sets the vars and keeps the attributes the stylesheet depends on", () => {
		applyDocumentSkin("orchestrate", "dark");
		const root = document.documentElement;
		expect(root.style.getPropertyValue("--background")).toBe(darkSkin.background);
		expect(root.dataset.theme).toBe("dark");
		expect(root.dataset.styleTheme).toBeUndefined();
	});

	it("switches every var when the appearance changes", () => {
		applyDocumentSkin("orchestrate", "dark");
		applyDocumentSkin("orchestrate", "light");
		const root = document.documentElement;
		expect(root.style.getPropertyValue("--background")).toBe(lightSkin.background);
		expect(root.dataset.theme).toBe("light");
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/apply-initial-theme.test.ts`
Expected: FAIL — `applyDocumentSkin is not a function`

- [ ] **Step 3: Add the applier and call it on boot**

Append to `renderer/lib/theme.ts`:

```ts
import { applySkinVars } from "../theme/bridge/css-vars";
import { skinFor } from "../theme/skins";

export function applyDocumentSkin(style: ThemeStyle, theme: Theme): void {
	if (typeof document === "undefined") return;
	applyDocumentTheme(theme);
	applyDocumentThemeStyle(style);
	applySkinVars(skinFor(style, theme));
}
```

Replace the body of `renderer/lib/apply-initial-theme.ts`:

```ts
import { applyDocumentSkin, readStoredThemeStyle, resolveTheme } from "./theme";

applyDocumentSkin(readStoredThemeStyle(), resolveTheme());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/lib/apply-initial-theme.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Route the store's three call sites through the skin**

In `stores/ui-store.ts`, replace the `applyDocumentTheme` / `applyDocumentThemeStyle` calls
with `applyDocumentSkin`, reading whichever axis is not changing from `get()`:

```ts
// setThemePreference (was applyDocumentTheme at :157)
applyDocumentSkin(get().themeStyle, resolvedTheme);

// setThemeStyle (was applyDocumentThemeStyle at :165)
applyDocumentSkin(themeStyle, get().resolvedTheme);

// syncSystemTheme (was applyDocumentTheme at :178)
applyDocumentSkin(get().themeStyle, next);
```

- [ ] **Step 6: Make the provider read the store, and mount it**

`SkinProvider` takes no props — a second source of truth for "which skin is active" is exactly
the disagreement this design exists to prevent:

```tsx
import { useUiStore } from "../stores/ui-store";
import { skinFor } from "./skins";

export function SkinProvider({ children }: { children: ReactNode }) {
	const themeStyle = useUiStore((state) => state.themeStyle);
	const resolvedTheme = useUiStore((state) => state.resolvedTheme);
	const skin = skinFor(themeStyle, resolvedTheme);
	return <SkinContext.Provider value={skin}>{children}</SkinContext.Provider>;
}
```

Then wrap the tree in `main.tsx`, inside `TelemetryBoundary` and outside `RouterProvider`, so
every route and dialog can call `useSkin()`.

- [ ] **Step 7: Verify no flash in the real app**

Run the desktop app (`opr-desktop-dev` skill, isolated mode), toggle light/dark in Settings, and restart with a light theme stored. Expected: no flash of dark on launch, no colour change anywhere versus before the task.

- [ ] **Step 8: Commit**

```bash
git add frontend/src/renderer/lib/theme.ts frontend/src/renderer/lib/apply-initial-theme.ts frontend/src/renderer/lib/apply-initial-theme.test.ts frontend/src/renderer/stores/ui-store.ts frontend/src/renderer/theme/skin-context.tsx frontend/src/renderer/main.tsx
git commit -m "feat(theme): drive document theming from skins"
```

---

### Task 7: The xterm bridge

Pulls the terminal into the system instead of leaving it with its own palette.

**Files:**
- Create: `frontend/src/renderer/theme/bridge/xterm-theme.ts`
- Modify: `frontend/src/renderer/components/XtermTerminal.tsx:341-350` (the `new Terminal({...})` call)
- Test: `frontend/src/renderer/theme/bridge/xterm-theme.test.ts`

**Interfaces:**
- Consumes: `AppSkin`
- Produces: `skinToXtermTheme(skin: AppSkin): ITheme`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from "vitest";
import { skinToXtermTheme } from "./xterm-theme";
import { darkSkin } from "../skins/dark";
import { lightSkin } from "../skins/light";

describe("skinToXtermTheme", () => {
	it("maps the terminal slots onto xterm's ITheme", () => {
		const theme = skinToXtermTheme(darkSkin);
		expect(theme.background).toBe(darkSkin.bgTerminalOpaque);
		expect(theme.foreground).toBe(darkSkin.textTerminal);
	});

	it("produces every field xterm reads, for both skins", () => {
		const fields = [
			"background", "foreground", "cursor", "selectionBackground",
			"black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
			"brightBlack", "brightRed", "brightGreen", "brightYellow",
			"brightBlue", "brightMagenta", "brightCyan", "brightWhite",
		] as const;
		for (const skin of [darkSkin, lightSkin]) {
			const theme = skinToXtermTheme(skin) as Record<string, unknown>;
			for (const field of fields) {
				expect(theme[field], field).toBeTruthy();
			}
		}
	});
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/bridge/xterm-theme.test.ts`
Expected: FAIL — `Cannot find module './xterm-theme'`

- [ ] **Step 3: Write the bridge**

Slot names come from the generated map — confirm the exact `term*` slot names with `grep -n "term" src/renderer/theme/token-map.generated.ts` and use those. The 21 `--term-*` tokens supply the ANSI palette.

```ts
import type { ITheme } from "@xterm/xterm";
import type { AppSkin } from "../app-skin";

export function skinToXtermTheme(skin: AppSkin): ITheme {
	return {
		background: skin.bgTerminalOpaque,
		foreground: skin.textTerminal,
		cursor: skin.termCursor,
		selectionBackground: skin.termSelection,
		black: skin.termBlack,
		red: skin.termRed,
		green: skin.termGreen,
		yellow: skin.termYellow,
		blue: skin.termBlue,
		magenta: skin.termMagenta,
		cyan: skin.termCyan,
		white: skin.termWhite,
		brightBlack: skin.termBrightBlack,
		brightRed: skin.termBrightRed,
		brightGreen: skin.termBrightGreen,
		brightYellow: skin.termBrightYellow,
		brightBlue: skin.termBrightBlue,
		brightMagenta: skin.termBrightMagenta,
		brightCyan: skin.termBrightCyan,
		brightWhite: skin.termBrightWhite,
	};
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/bridge/xterm-theme.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Wire it into the terminal and verify visually**

Pass `theme: skinToXtermTheme(useSkin())` in the `new Terminal({...})` options at `XtermTerminal.tsx:341`. Run the app, open a session terminal, and confirm colours are unchanged from before the task.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/theme/bridge/xterm-theme.ts frontend/src/renderer/theme/bridge/xterm-theme.test.ts frontend/src/renderer/components/XtermTerminal.tsx
git commit -m "feat(theme): drive the terminal palette from the active skin"
```

---

### Task 8: Introduce derived slots

The parity test from Task 3 is now a refactoring safety net: a slot moved from required to derived must produce a byte-identical value, or the test fails.

**Files:**
- Modify: `frontend/src/renderer/theme/app-skin.ts`
- Modify: `frontend/scripts/extract-skin-tokens.mjs` (omit derived slots from emitted skins)
- Test: `frontend/src/renderer/theme/app-skin.test.ts` (extend)

**Interfaces:**
- Consumes: everything from Tasks 2–3
- Produces: a populated `DerivedSlot` union and `DERIVED_DEFAULTS`

- [ ] **Step 1: Find genuinely derivable slots**

Run: `cd frontend && grep -nE "var\(--" src/styles/tokens.css | sed -n '1,60p'`

Slots whose value is already `var(--other-token)` are derivable by definition — the CSS says so. Example from the spec: `--color-status-terminated: var(--chart-3)`. Collect that list; it is the safe starting set.

- [ ] **Step 2: Write the failing test**

```ts
it("derives slots the author omits", () => {
	const required = Object.fromEntries(
		Object.keys(SKIN_TOKENS)
			.filter((k) => k !== "statusTerminated")
			.map((k) => [k, "#000000"]),
	);
	const skin = defineSkin({ ...required, chart3: "#123456" } as never);
	expect(skin.statusTerminated).toBe("#123456");
});

it("throws when a required slot is missing", () => {
	expect(() => defineSkin({} as never)).toThrow(/missing required slot/);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/app-skin.test.ts`
Expected: FAIL — `statusTerminated` is `"#000000"`, not `"#123456"`

- [ ] **Step 4: Populate the derived set**

```ts
export type DerivedSlot = "statusTerminated";

export const DERIVED_DEFAULTS: Partial<Record<SlotName, (skin: Partial<AppSkin>) => string>> = {
	statusTerminated: (skin) => skin.chart3!,
};
```

Then make the script omit derived slots from the emitted skin files, and re-run it.

- [ ] **Step 5: Run the full suite**

Run: `cd frontend && node scripts/extract-skin-tokens.mjs && npm run test && npm run typecheck`
Expected: all PASS — including `skin-parity`, which proves the derivation reproduces the original value exactly.

Repeat steps 1–5 for each further derivable slot. Stop when only genuinely independent colours remain required. **Do not invent derivations** — if a slot's value is not expressible from another slot, it stays required.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/theme/ frontend/scripts/extract-skin-tokens.mjs
git commit -m "refactor(theme): express derivable slots as defaults"
```

---

### Task 9: Port the eight style themes

This is the phase that **changes pixels**, by design: each theme gains the ~206 tokens it never had. Review each against its upstream palette.

**Files:**
- Modify: `frontend/scripts/extract-skin-tokens.mjs`
- Create: `frontend/src/renderer/theme/skins/{github,catppuccin,dracula,tokyo-night,rose-pine,nord,gruvbox,solarized}.ts`
- Modify: `frontend/src/renderer/theme/skins/index.ts` (populate `REGISTRY`)
- Test: `frontend/src/renderer/theme/skins/index.test.ts` (extend)

**Interfaces:**
- Consumes: `defineSkin`, `darkSkin`, `lightSkin`
- Produces: eight `{ dark, light }` skin pairs registered in `REGISTRY`

- [ ] **Step 1: Write the failing test**

```ts
it("gives every style its own status colours", () => {
	const base = skinFor("orchestrate", "dark");
	for (const style of ["github", "dracula", "nord", "gruvbox"] as const) {
		const skin = skinFor(style, "dark");
		expect(skin.background, style).not.toBe(base.background);
		expect(skin.statusWorking, style).not.toBe(base.statusWorking);
	}
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/skins/index.test.ts`
Expected: FAIL — `statusWorking` is still the base value for every style.

- [ ] **Step 3: Generate the skins from the existing blocks**

The layering must reproduce today's cascade exactly: the dark skin is base → style-dark, and
the light skin is base → light → style-dark → style-light, because
`:root[data-style-theme="github"]` and `:root[data-theme="light"]` both match a light GitHub
document and the more specific block wins per token.

```js
const STYLES = [
	"github", "catppuccin", "dracula", "tokyo-night",
	"rose-pine", "nord", "gruvbox", "solarized",
];

for (const style of STYLES) {
	const styleDark = parseBlock(css, `:root[data-style-theme="${style}"]`);
	const styleLight = parseBlock(css, `:root[data-style-theme="${style}"][data-theme="light"]`);
	const name = style.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
	await writeFile(
		path.resolve(`src/renderer/theme/skins/${style}.ts`),
		emitSkin(`${name}Dark`, { ...base, ...styleDark }) +
			"\n" +
			emitSkin(`${name}Light`, { ...base, ...light, ...styleDark, ...styleLight }).replace(
				/^\/\/.*\n|^import .*\n\n/gm,
				"",
			),
	);
	console.log(`wrote ${style} (${Object.keys(styleDark).length} dark overrides)`);
}
```

Then populate the registry in `skins/index.ts`:

```ts
import { githubDark, githubLight } from "./github";
import { catppuccinDark, catppuccinLight } from "./catppuccin";
import { draculaDark, draculaLight } from "./dracula";
import { tokyoNightDark, tokyoNightLight } from "./tokyo-night";
import { rosePineDark, rosePineLight } from "./rose-pine";
import { nordDark, nordLight } from "./nord";
import { gruvboxDark, gruvboxLight } from "./gruvbox";
import { solarizedDark, solarizedLight } from "./solarized";

const REGISTRY: Partial<Record<ThemeStyle, { dark: AppSkin; light: AppSkin }>> = {
	github: { dark: githubDark, light: githubLight },
	catppuccin: { dark: catppuccinDark, light: catppuccinLight },
	dracula: { dark: draculaDark, light: draculaLight },
	"tokyo-night": { dark: tokyoNightDark, light: tokyoNightLight },
	"rose-pine": { dark: rosePineDark, light: rosePineLight },
	nord: { dark: nordDark, light: nordLight },
	gruvbox: { dark: gruvboxDark, light: gruvboxLight },
	solarized: { dark: solarizedDark, light: solarizedLight },
};
```

- [ ] **Step 4: Choose each theme's semantic colours**

The generated skins still carry base status/terminal colours, because the CSS never defined per-theme ones. For each of the eight, set the status and ANSI slots from that palette's own colours — Dracula's green for `statusReady`, Nord's `nord11` for `error`, and so on. This is a design decision per theme, not a mechanical transform.

- [ ] **Step 5: Run the suite and review each theme visually**

Run: `cd frontend && npm run test && npm run typecheck`
Then run the app and switch through all eight themes in Settings, in both light and dark, checking the board, the terminal, and the inspector.
Expected: tests PASS; each theme reads as its palette rather than as the default with a different background.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/renderer/theme/skins/ frontend/scripts/extract-skin-tokens.mjs
git commit -m "feat(theme): port the eight style themes to skins"
```

---

### Task 10: Delete the cascade and add the guardrails

**Files:**
- Modify: `frontend/src/styles/tokens.css` (remove colour blocks, keep non-colour tokens)
- Delete: `frontend/src/renderer/theme/skin-parity.test.ts` (its source of truth is gone)
- Create: `frontend/src/renderer/theme/css-var-coverage.test.ts`, `frontend/src/renderer/theme/no-raw-color.test.ts`
- Create: `frontend/src/renderer/theme/README.md`

**Interfaces:**
- Consumes: everything above
- Produces: the permanent guardrail suite

- [ ] **Step 1: Write the failing tests**

```ts
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { skinToCssVars } from "./bridge/css-vars";
import { darkSkin } from "./skins/dark";

const styles = readFileSync(path.resolve(__dirname, "../styles.css"), "utf8");

describe("css var coverage", () => {
	it("every colour var the stylesheet consumes is produced by a skin", () => {
		const produced = new Set(Object.keys(skinToCssVars(darkSkin)));
		const consumed = [...styles.matchAll(/var\((--[a-z0-9-]+)\)/g)].map((m) => m[1]);
		const colourish = consumed.filter((v) => /(color|bg|text|border|term|status|sidebar|accent)/.test(v));
		const missing = [...new Set(colourish)].filter((v) => !produced.has(v));
		expect(missing, `unproduced colour vars: ${missing.join(", ")}`).toEqual([]);
	});
});
```

```ts
import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

function walk(dir: string): string[] {
	return readdirSync(dir).flatMap((entry) => {
		const full = path.join(dir, entry);
		if (statSync(full).isDirectory()) return walk(full);
		return /\.tsx?$/.test(entry) && !/\.test\./.test(entry) ? [full] : [];
	});
}

describe("no raw colour in components", () => {
	it("components use skin slots, not literal colours", () => {
		const offenders: string[] = [];
		for (const file of walk(path.resolve(__dirname, "../components"))) {
			const source = readFileSync(file, "utf8");
			for (const match of source.matchAll(/#[0-9a-fA-F]{6}\b|oklch\(/g)) {
				offenders.push(`${path.basename(file)}: ${match[0]}`);
			}
		}
		expect(offenders, offenders.join("\n")).toEqual([]);
	});
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx vitest run --config vite.renderer.config.ts src/renderer/theme/css-var-coverage.test.ts src/renderer/theme/no-raw-color.test.ts`
Expected: both FAIL, listing unproduced vars and raw-colour offenders.

- [ ] **Step 3: Close the gaps**

For each unproduced var, add the missing slot to the token map and skins. For each raw colour in a component, replace it with `useSkin()` — the `box-shadow` composed from `col.dot` at `SessionsBoard.tsx:526` is the representative case and should read a dedicated glow slot.

- [ ] **Step 4: Strip the cascade from tokens.css**

Delete the `[data-style-theme]` blocks and the colour half of the `[data-theme="light"]` block. Keep every non-colour token — size, space, radius, font, tracking, leading, z. Delete `skin-parity.test.ts`, whose source of truth no longer exists.

- [ ] **Step 5: Run the full suite and the app**

Run: `cd frontend && npm run test && npm run typecheck` and from the root `npm run lint`
Then run the desktop app and check every theme in both appearances.
Expected: all PASS; no visual change from Task 9's reviewed state.

- [ ] **Step 6: Write the README**

`frontend/src/renderer/theme/README.md`, mirroring `sahla_assistant/lib/core/app_themes/colors/README.md`: the one rule (feature code uses `useSkin()`, never a literal), how a colour reaches a component, the required/derived split, and the three recipes — use a colour, add a colour, add a skin.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/styles/tokens.css frontend/src/renderer/theme/ frontend/src/renderer/components/
git rm frontend/src/renderer/theme/skin-parity.test.ts
git commit -m "feat(theme): retire the CSS cascade in favour of skins"
```

---

## Definition of done

- Adding a theme is one file in `theme/skins/`, and omitting a required slot is a **type error**.
- All eight existing themes render their own palette across the whole app, including board status colours and the terminal.
- `npm run test`, `npm run typecheck` and `npm run lint` pass.
- No visual change to the default theme at any point in the plan.
- No flash of the wrong theme on launch.
