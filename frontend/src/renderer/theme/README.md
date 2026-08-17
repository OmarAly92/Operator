# Theming — the skin system

## The one rule

**A colour is a slot on the skin. Feature code never writes a colour literal.**

No `#rrggbb`, no `oklch(...)`, no `rgb(...)` in `renderer/components/**`. Two
tests enforce it and both run in `npm run test`:

- `no-raw-color.test.ts` — walks every non-test `.ts`/`.tsx` under
  `renderer/components/` and fails on a hex literal or an `oklch(` call.
- `css-var-coverage.test.ts` — every colour variable `renderer/styles.css`
  consumes but does not itself declare must be produced by a skin.

`styles/tokens.css` no longer carries colour for the light theme or for any
named style. It holds the **non-colour** scale only — size, space, radius,
font, tracking, leading, z, duration, ease, breakpoint — plus the base block
and `color-scheme`. Colour lives in `theme/skins/`.

## How a colour reaches a component

```
theme/skins/<skin>.ts          one object, one value per slot
  → defineSkin()               fills in every defaulted slot, throws on a missing required one
    → skinFor(style, theme)    picks the skin for the active style + appearance
      → applySkinVars()        writes every slot onto <html> as its CSS variable
        → --color-status-working, --background, …
          → styles.css / Tailwind utilities → the component
```

Two entry points drive that chain:

- `lib/apply-initial-theme.ts` runs as `main.tsx`'s first import, **before**
  `styles.css` loads, so the variables are on `<html>` before first paint. That
  is why there is no flash of the wrong theme.
- `SkinProvider` (`skin-context.tsx`) re-resolves the skin whenever the store's
  style or appearance changes; `useSkin()` reads it.

In a component, prefer the CSS variable — `className="text-[var(--color-…)]"`
or an existing Tailwind utility. Reach for `useSkin()` when the value must be a
**string in TypeScript**: the xterm palette (`XtermTerminal.tsx`) and the
Windows native window-controls overlay (`WindowTitlebar.tsx`) are the two real
cases, because neither consumer can read CSS.

## Required vs. defaulted slots

`SlotName` (in `token-map.generated.ts`) is the full list of slots. `app-skin.ts`
splits it:

- **`DerivedSlot`** — slots with an entry in `DERIVED_DEFAULTS`. A skin may omit
  them; `defineSkin` fills each one in, usually from another slot of the *same*
  skin (`bgPrimary` ← `background`, `warning` ← `statusNeedsYou`), occasionally
  from a constant (`windowOverlayBg`). Overriding one in a skin is always
  allowed and wins over the default.
- **`RequiredSlot`** — everything else. `SkinInput` types them as required, so
  omitting one is a **type error**; `defineSkin` also throws at runtime.

Never copy a derived value into a skin by hand — that is exactly the stale-copy
bug the defaults exist to prevent.

## Recipes

### Use a colour

Find the slot in `token-map.generated.ts`, use its CSS variable:

```tsx
<span className="text-[var(--color-status-working)]" />
```

If you need it as a value:

```tsx
const skin = useSkin();
void window.operator?.window?.setOverlay({ color: skin.windowOverlayBg });
```

### Add a colour

1. Add the slot to `SKIN_TOKENS` in `token-map.generated.ts`, in the
   hand-maintained section at the end, with a doc comment saying why it exists.
   (Doc comments on slots are deliberate: a slot name alone rarely explains
   itself.)
2. Decide whether it is required or defaulted. Defaulted → add a
   `DERIVED_DEFAULTS` entry and the name to `DerivedSlot` in `app-skin.ts`, and
   you are done. Required → give it a value in **every** skin: `skins/dark.ts`,
   `skins/light.ts` and both objects in each of the eight `skins/<style>.ts`
   files, or `defineSkin` will not compile.
3. Bump the slot count in `token-map.test.ts` and `bridge/css-vars.test.ts`.

### Add a skin

One file in `skins/`:

```ts
import { defineSkin } from "../app-skin";

export const midnightDark = defineSkin({
	background: "#0b0f19",
	foreground: "#dbe2f0",
	// … every required slot; the compiler lists the ones you missed
});
```

Then register the pair in `skins/index.ts` and add the style to `ThemeStyle` in
`lib/theme.ts` so the settings UI can select it. Nothing else — no CSS, no
`[data-style-theme]` block. The existing eight styles keep a
`<style>.generated.ts` neighbour only because they were ported out of the old
CSS cascade; a new skin does not need one.
