# AppSkin theming for the renderer — design

**Date:** 2026-08-16
**Status:** draft design, pending review
**Scope:** replace the CSS-cascade theming in `frontend/src/styles/tokens.css` with an
`AppSkin` contract, ported from `sahla_assistant/lib/core/app_themes`

## Context

Theming in the renderer is 445 design tokens declared across `styles/tokens.css` (1,290
lines) and consumed through `styles.css` (3,454 lines) via Tailwind v4's `@theme inline`.
230 of those are colour-valued; the remaining 215 are size, type, radius, spacing and z-index.

Eight named style themes ship today — GitHub, Catppuccin, Dracula, Tokyo Night, Rosé Pine,
Nord, Gruvbox, Solarized — each implemented as a CSS override block keyed on
`:root[data-style-theme="…"]`, plus a light variant keyed on `[data-theme="light"]`.

### The problem, measured

Each style theme overrides **24 tokens**. The app defines **230 colour tokens**.

```
:root[data-style-theme="github"] {
  --background --foreground --card --card-foreground --popover --popover-foreground
  --primary --primary-foreground --secondary --secondary-foreground --muted
  --muted-foreground --accent --accent-foreground --border --input --ring
  --sidebar --sidebar-foreground --sidebar-primary --sidebar-primary-foreground
  --sidebar-accent --sidebar-accent-foreground --sidebar-ring
}
```

Everything else keeps the default palette. Concretely, `--color-status-working`,
`--color-status-needs-you`, `--color-status-in-review` and `--color-status-ready` — the
colours that carry the Kanban board's entire meaning — are declared once for dark
(`tokens.css:114-121`) and once for light (`tokens.css:710-717`), and are overridden by
**zero** of the eight themes. Selecting Dracula leaves the board's dots at Tailwind's
generic blue/orange/yellow/green. The same holds for the 21 `--term-*` tokens, the 15
`--border-*`, the 13 `--preview-*`, and the rest.

So "create a new theme" currently means: hand-write 24 declarations, inherit 206 that
belong to a different palette, and discover the mismatches by looking at the app. Nothing
enforces completeness, because a CSS cascade has no notion of a missing value — only of an
inherited one.

### Goal

Adding a skin is one file. The type system names every colour the skin must supply, defaults
the ones that can be derived, and a test fails when a consumer reads a colour no skin
produces.

### Decisions taken

| Decision | Choice |
|---|---|
| Pattern source | `sahla_assistant/lib/core/app_themes/colors` |
| Contract shape | Required slots + derived slots with overridable defaults |
| Slot documentation | Every slot carries a doc comment naming a real place in the Operator UI |
| Consumers | React (`useSkin()`), Tailwind/shadcn (generated CSS vars), xterm (`skinToXtermTheme`) |
| Migration | Byte-identical CSS vars first, then port themes, then delete the cascade |
| Existing themes | All eight ported to skins; none dropped |
| Scope | Colour only. Type, motion and shape get parallel systems later |

### Non-goals

- **No redesign.** Phase 1 must produce the same pixels. Any colour that changes is a bug
  until a design decision says otherwise.
- **No new themes** as part of this work.
- **No type/motion/shape systems yet.** `sahla` has `AppTextStyle`, `AppMotion` and
  `AppShapes` alongside the skin; Operator already has tokens for all three
  (132 `size-*`, 22 `font-*`, 19 `radius-*`, 12 `tracking-*`). They follow the same pattern
  and are tracked in "Follow-ups", not built here.
- **No dependency on the Tauri port.** This is pure renderer work and survives a shell swap
  untouched. See `2026-08-16-tauri-port-design.md`.

## Architecture

### One source of truth, three consumers

```
        skins/dark.ts, light.ts, github.ts, dracula.ts, …
                          │
                    defineSkin()          ← fills derived slots
                          │
                     AppSkin (resolved)   ← ~230 slots, all present
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 ▼                  ▼
   useSkin()      skinToCssVars()     skinToXtermTheme()
   React code     :root custom props   xterm ITheme object
                          │
                   @theme inline
                          │
                 Tailwind utilities
                 shadcn components
```

`sahla`'s structure has two consumers: its own widgets read `context.skin`, and Material's
widgets read `Theme.of(context).colorScheme`, bridged by `AppThemes.fromSkin`. Operator has
the same split with three consumers. CSS custom properties play the `ColorScheme` role
exactly — the interface a framework that has never heard of `AppSkin` reads from. The rule
that governs `sahla`'s bridge governs ours: **every value the second consumer can read must
be produced by the skin.** A token left out silently falls back, and falling back silently is
the bug we are removing.

### File layout

```
frontend/src/renderer/theme/
├── app-skin.ts          # the AppSkin contract + SkinInput + defineSkin()
├── skins/
│   ├── dark.ts          # the current default
│   ├── light.ts
│   ├── github.ts        # ported from the cascade
│   ├── catppuccin.ts
│   ├── dracula.ts
│   ├── tokyo-night.ts
│   ├── rose-pine.ts
│   ├── nord.ts
│   ├── gruvbox.ts
│   ├── solarized.ts
│   └── index.ts         # the registry: id → skin, used by Settings
├── bridge/
│   ├── css-vars.ts      # skinToCssVars(skin): Record<string, string>
│   └── xterm-theme.ts   # skinToXtermTheme(skin): ITheme
├── skin-context.tsx     # SkinProvider + useSkin()
└── README.md            # the one rule, the recipes (mirrors sahla's colors/README.md)
```

### The contract

TypeScript has no abstract getters with defaults, so the Dart pattern splits in two: an input
type carrying what a skin author writes, and a resolved type carrying what consumers read.

```ts
/** What a skin author supplies: required slots, plus any derived slot they disagree with. */
export type SkinInput = SkinRequired & Partial<SkinDerived>;

/** What consumers read: every slot present, nothing optional. */
export type AppSkin = SkinRequired & SkinDerived;

export function defineSkin(input: SkinInput): AppSkin;
```

`SkinRequired` is the irreducible palette — colours that cannot be computed from other
colours and genuinely differ per skin. `SkinDerived` is everything expressible from it, each
with a default in `defineSkin`, each overridable by a skin that disagrees. This is the split
that makes the pattern scale: a new component colour costs one line with a sensible default,
and only the skins that need something different say so.

The required set is drawn from the eight existing themes plus the semantic groups no theme
currently reaches:

| Group | Slots | Why required |
|---|---|---|
| Base surfaces | `background` `surface` `card` `surfaceElevated` `popover` | The page ladder; every theme redefines these |
| Text | `textPrimary` `textSecondary` `textMuted` `textPassive` | Emphasis ramp, not derivable across light/dark |
| Brand | `primary` `primaryForeground` `ring` | The accent identity of the theme |
| Borders | `border` `borderStrong` `borderSubtle` `input` | Operator's hairlines are load-bearing (see `DESIGN.md`) |
| Status | `statusWorking` `statusNeedsYou` `statusInReview` `statusReady` `statusTerminated` | The board's meaning. **The gap this design closes** |
| Feedback | `success` `error` `warning` `info` | Semantic, hue-specific per palette |
| Terminal | `termBackground` `termForeground` `termCursor` `termSelection` + 16 ANSI | The terminal keeps its own palette per `CLAUDE.md`, but it is still the skin's job to say so |

Everything else derives. Illustrative:

```ts
// The fill behind a selected sidebar row. Example: the highlighted "Scratch"
// project in the projects rail.
sidebarAccent: mix(surface, primary, 0.08),

// The glow behind a working session's dot. Example: the pulsing blue dot on
// the IDLE / WORKING column header.
statusWorkingGlow: alpha(statusWorking, 0.6),
```

Each slot's doc comment names a real place in the UI. That is the highest-leverage part of
the pattern and it is not decoration: it makes "which colour goes here?" answerable without
opening the design file or guessing, and it is what keeps a 230-slot contract usable.

### Runtime

`SkinCubit` becomes a Zustand store — the renderer already uses Zustand (`stores/ui-store.ts`)
and already persists a theme choice. On change it writes the resolved skin into
`SkinProvider` and applies `skinToCssVars(skin)` to `document.documentElement`. Both
consumers move together, so they can never disagree about which skin is active.

`lib/apply-initial-theme.ts` runs before React mounts to prevent a flash of the wrong theme.
It must keep doing so: it reads the persisted skin id and applies that skin's CSS vars
synchronously on first paint. **This is a hard constraint** — a theming refactor that
introduces a white flash on launch has failed regardless of its internal elegance.

## Migration

The risk in this work is not the contract; it is that 4,700 lines of CSS quietly change
colour. The sequencing exists to make that impossible to do by accident.

**Phase 1 — bridge, no visual change.** Build `AppSkin`, `defineSkin`, and `dark`/`light`
skins whose output is *byte-identical* to the current `:root` and `:root[data-theme="light"]`
blocks. Apply them at runtime. A test asserts the generated var set equals the values
currently in `tokens.css`, token for token. Nothing in the UI changes; the source of the
values moves.

**Phase 2 — port the eight themes.** Each becomes a skin supplying its required slots. This
is where they gain the ~206 tokens they never had, so this phase *does* change pixels — by
design, and only inside a non-default theme. Each ported theme gets a screenshot reviewed
against its upstream palette.

**Phase 3 — delete the cascade.** Remove the `[data-style-theme]` override blocks and the
duplicated light block from `tokens.css`. What remains is the non-colour tokens (size, type,
radius, spacing), which the skin does not own.

**Phase 4 — close the leaks.** Replace remaining hardcoded colour in components with skin
slots. `SessionsBoard.tsx:526` composing `box-shadow` from `col.dot` inline is the
representative case: it should read a `statusWorkingGlow`-style slot.

Each phase is independently revertable and independently shippable.

## Testing

The guardrail is the point of the pattern; without it this is just a refactor with extra
files.

| Test | Asserts |
|---|---|
| `skin-completeness.test.ts` | Every skin in the registry resolves to a full `AppSkin` — no `undefined` slots |
| `css-var-coverage.test.ts` | Every `--color-*` referenced by `styles.css`'s `@theme inline` is produced by `skinToCssVars` |
| `skin-parity.test.ts` | Phase 1 only: generated vars equal the current `tokens.css` values |
| `xterm-theme.test.ts` | Every `ITheme` field xterm reads is produced for every skin |
| `no-raw-color.test.ts` | No raw hex/`oklch()` in `renderer/components/**` (lint-style scan, allowlist for the skin files themselves) |

`css-var-coverage` is the analogue of `sahla`'s `color_scheme_mapping_test.dart` and the most
important of the five: it is what makes a dropped token loud instead of invisible.

## Risks

| Risk | Mitigation |
|---|---|
| Silent colour drift across 4,700 lines of CSS | Phase 1 parity test; phases are separately revertable |
| Flash of unstyled/wrong theme on launch | `apply-initial-theme` keeps synchronous first paint; explicit test |
| Runtime var application slower than static CSS | ~230 `setProperty` calls on one element, once per skin change. Measure; fall back to a generated stylesheet per skin if it registers |
| The 8 ported themes look wrong once they control 100% of tokens | Phase 2 reviews each against its upstream palette; this is a design review, not a code review |
| Contract grows unbounded | Derived-by-default is the discipline: a new slot is required only when it genuinely cannot be computed |

## Follow-ups

- `AppTextStyle` for the 22 `font-*` / 12 `tracking-*` / 4 `leading-*` tokens.
- `AppShapes` for the 19 `radius-*` tokens.
- `AppMotion` for durations and easing.
- A skin editor in Settings — once skins are data, a UI that writes one is tractable.
