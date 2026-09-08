# Components

Restyled/added core widgets (Phase 5 of the design-from-html-flutter skill), matching the
prototype's `Component` class style objects (`docs/design/Operator Mobile - standalone.html`,
decoded template's `const S = {...}` starting ~line 3515). Radii use the scale in
`lib/core/utils/app_constants.dart`, colors use `AppSkin` getters (`docs/design/colors.md`),
type uses `AppTextStyle` getters (`docs/design/typography.md`), motion uses `AppMotion`
(`docs/design/motion.md`).

## Radius/spacing scale (derived, with evidence)

Grepped every literal `borderRadius:` value actually consumed by the `Component` class (ignored
avatar `'50%'` circles and the dead `.sk-*` CSS boilerplate — see colors.md/motion.md for that
caveat). Real, repeated usage:

| `AppConstants` | px | Backed by |
|---|---|---|
| `radiusXs` | 4 | Spawn screen's agent-logo thumbnail |
| `radiusSm` | 6 | Shimmer skeleton text lines, small mono command chips |
| `radiusChip` | 7 | Theme/state toggle buttons, zoom group, terminal quick-tag borders |
| `radiusMd` | 8 | Icon buttons (connection more/cmd-trigger), small action buttons, command cards |
| `radiusLg` | 10 | Form inputs, medium icon wraps, permission card |
| `radiusButton` | 12 | Primary/secondary/sheet buttons, kill button |
| `radiusCard` | 14 | Cards, dialog, connection group, settings group |
| `radiusStepper` | 18 | Nav/PR-filter segmented stepper (one-off) |
| `radiusPill` | 999 | Status chips, sheet handle, skeleton pills, empty-state primary button, toggle thumbs |

## Restyled widgets

| Control | Spec | File |
|---|---|---|
| Primary button | height 50 (46 for sheet/dialog variants via `fixedSize`), `radiusButton`, `accent` bg, `onAccent` text, `style17Medium`, press scale `pressScaleDefault` + `spring` via `PressScale` | `main_widgets/primary_button.dart` |
| Card/tappable container | `radiusButton` default; opt-in `pressScale: true` applies `CARD_SURFACE`'s press feedback | `main_widgets/app_container.dart` |
| Filter chip | `agentChip` (default) and `pillStyle` (`dense: true`) are two distinct prototype specs sharing only the active `tintGreen` bg + brand-ink text (see judgment call below): `agentChip` is a bordered `bgSurface` chip, `style12p5SemiBold`, `textSecondary` when inactive; `pillStyle` is borderless `bgElevated`, `style12SemiBold`, `textTertiary` when inactive, tighter vertical padding. Sessions board uses the default; pull requests filter row passes `dense: true` | `main_widgets/app_pill.dart` |
| Text field | `radiusLg`, `borderSubtle` border, `bgElevated` fill | `main_widgets/app_text_field.dart` |
| Settings group/row/toggle | `radiusCard` group, `borderSubtle` row dividers; toggle-on now `accent` (was `blue`) | `main_widgets/settings_group.dart` |
| Confirm/remove dialog | `bgSurface`, `radiusCard`, padding 20, "Dialog" shadow recipe, `style16p5Bold` title, `style13p5Regular` body, full-width ghost/action button row (not trailing `TextButton`s) | `dialog/app_dialog.dart` |
| Empty state | Floating brand-green orb (`saOrbFloat`, bounded to 3 cycles — see Testing note below), `style21Bold` display title, `style13p5Regular` body; scroll-safe via `LayoutBuilder` so it never overflows a small host | `main_widgets/app_empty_state.dart` |
| Bottom sheets (theme/agent/project pickers) | Switched `showModalBottomSheet` → `showExpressiveSheet` (spring-driven, from the vendored `expressive_sheet` package) + new `AppSheetChrome` (the package supplies no background/radius/handle of its own); selection color `blue` → `accent` | `pickers/*_sheet.dart`, new `main_widgets/app_sheet_chrome.dart` |

## New primitives

| Widget | Spec | Notes |
|---|---|---|
| `PressScale` | Generic press-scale wrapper (`pressScaleDefault`/`Fab`/`Send` × `AppMotion.fast` + `spring`) | `main_widgets/press_scale.dart` |
| `AppExpressiveLoader` | The prototype's `loaderSvg` 7-shape morph (softBurst→cookie9→pentagon→pill→sunny→cookie4→oval) | Backed by the vendored `expressive_loading_indicator` package's `LoadingIndicator`, which already ports this exact Material 3 Expressive shape sequence and 650ms pop timing — no hand-rolled shape math needed. `loading_widget/app_loader.dart` |
| `ShimmerBlock` / `ShimmerBlock.pill` | `SHIMMER` helper: `shimmerBase`/`shimmerHi` sweep over `AppMotion.shimmer` | Backed by the `shimmer` pub package. `main_widgets/shimmer_block.dart` |
| `StatusDot` | `breatheDot`: opacity 1→0.35 pulse, `breatheActive`/`breatheIdle` period | `main_widgets/status_dot.dart` |
| `TypingDots` | `typingDotsEl`/`saDotBounce`: 3-dot bounce, staggered `dotBounceStagger` | `main_widgets/typing_dots.dart` |
| `AppToast` | `S.toast`/`saSlideUp` toast entrance | Backed by the vendored `expressive_snack` package's `showExpressiveSnack`, themed with `AppSkin` instead of the Material inverse-surface defaults. `main_widgets/app_toast.dart` |
| `AppSheetChrome` | Bottom-sheet visual container (see above) | `main_widgets/app_sheet_chrome.dart` |

Also discovered already vendored but not yet wired into any screen: `expressive_refresh_indicator`
(pull-to-refresh with the same shape-morph indicator) — a good fit for the sessions board's
refresh gesture in a later screen-implementation phase.

## Judgment calls

- **Chip active text color.** The prototype hardcodes `#117E3F` for active-chip text in light mode
  instead of `skin.accent` (too bright/low-contrast as foreground-on-tint there); dark mode uses
  `skin.accent` as-is. Implemented as a local `_activeTextColor` helper in `app_pill.dart`, not
  promoted to `AppSkin` since it's the only call site.
- **`Switch` thumb transition.** Flutter's own `Switch` doesn't accept a custom thumb-slide
  duration/curve, so it doesn't exactly reproduce the prototype's 180ms spring; colors are
  matched exactly (`accent` on, `bgSubtle` track off) but the built-in Material transition is used
  for the physical slide.
- **Empty-state icon param.** `AppEmptyState.icon` is now optional and unused in the body — every
  prototype empty state uses the brand orb, never a per-context icon. Kept the field so existing
  call sites (`icon: Icons.power_settings_new`, etc.) don't need a signature change; a future pass
  could remove it once all six call sites are confirmed migrated.
- **Loader implementation.** Full fidelity — no simplification needed. The vendored
  `expressive_loading_indicator` package already implements the exact same 7-polygon Material 3
  Expressive sequence the prototype's hand-rolled SVG `<animate>` uses, at the same 650ms pop
  timing. Wired via a themed `AppExpressiveLoader` wrapper rather than reimplementing the shape
  math.

## Testing note: perpetual animations vs. `pumpAndSettle`

Several of the above animate forever while mounted (`StatusDot` while breathing, `TypingDots`,
`ShimmerBlock`, `AppExpressiveLoader`) — this is intentional; they represent an ongoing state.
`AnimationController.repeat()` does **not** respect `SemanticsBinding.disableAnimations` in this
Flutter version (nor does the `shimmer` package or the vendored loading indicator), and Flutter's
test binding does **not** set `disableAnimations: true` by default — so if a screen renders one
of these and stays mounted in that state, `WidgetTester.pumpAndSettle()` will hang.

`AppEmptyState`'s orb hit exactly this (it's the empty state's persistent end-state, used across
6+ screens whose existing tests call `pumpAndSettle`), so it's implemented differently from the
others: it floats a **bounded** 3 cycles then rests, driven by chained `forward()`/`reverse()`
(not `repeat()`, whose `_RepeatingSimulation` never emits a `completed`/`dismissed` status to
count cycles from). `StatusDot`/`TypingDots`/`ShimmerBlock`/`AppExpressiveLoader` are not yet
wired into any feature screen, so they haven't hit this in practice — whoever wires them into a
screen that stays mounted in the animating state should either follow the same bounded-cycle
pattern, or have that screen's tests use bounded `tester.pump(duration)` calls instead of
`pumpAndSettle()`.
