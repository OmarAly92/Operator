# Motion

Extracted from the prototype's live `Component` class (`docs/design/Operator Mobile -
standalone.html`, decoded template ~lines 2898-3960). Wired in
`lib/core/app_themes/app_motion.dart` (`AppMotion`).

**Note on source noise:** the standalone export also carries dead CSS boilerplate from an
unrelated base template — `--dur-fast/base/slow`, `--ease-*` custom properties, and
`@keyframes tg-spin` / `sk-obs-pulse` / `sk-toast-in` (prefixed `.sk-*`/`.tg-*`). None of
these are referenced by the actual mobile screens (the `Component` class's inline `S.*`
style objects) and are excluded below.

## Durations

| Token (`AppMotion`) | Value | Used for |
|---|---|---|
| `fast` | 120ms | Press feedback, toggle thumb slide, chat bubble transform/background transition |
| `base` | 180ms | Scrim fade-in, screen-swap transform/background transitions, toast slide |
| `slow` | 260ms | Entrance stagger (fade-up/pop/slide-up), sheet/dialog/command-menu pop-in |
| `shimmer` | 1400ms | Loading skeleton shimmer sweep (`linear infinite`) |
| `loaderSpin` | 1730ms | Expressive SVG loader container spin (`linear infinite`) |
| `loaderPop` | 650ms | Expressive SVG loader per-shape pop (`easeOut infinite`) |
| `dotBounce` | 1200ms | Typing/status dot bounce (`easeInOut infinite`) |
| `dotBounceStagger` | 150ms | Per-dot delay offset (dot `i` delays `i × 150ms`) |
| `breatheActive` | 1600ms | Status dot breathing pulse — busy/working session |
| `breatheIdle` | 2200ms | Status dot breathing pulse — stopped/idle session |
| `orbFloat` | 2500ms | Empty-state green orb float bob (`easeInOut infinite`) |
| `spin` | 1000ms | Plain busy/"sending" icon spinner (`linear infinite`) |
| `staggerBase` | 120ms | Delay before the first item in a staggered list |
| `staggerStep` | 40ms | Additional delay per subsequent staggered item |

`AppMotion.staggerDelay(i) = staggerBase + i × staggerStep` — matches the prototype's
`enter(i, kind)` helper exactly.

## Curves

| Token | cubic-bezier | Notes |
|---|---|---|
| `easeOut` | `(.22, .61, .36, 1)` | Default one-shot deceleration — entrances, scrims |
| `easeInOut` | `(.65, 0, .35, 1)` | Symmetric ease for infinite loops (dot bounce, orb float) |
| `spring` | `(.34, 1.4, .64, 1)` | Overshoot spring — the `1.4` second control point produces the overshoot. Used for press feedback, sheet/dialog/command-menu pop-in, slide-up, toggle thumb |

Flutter's `Cubic(x1, y1, x2, y2)` constructor takes the same 4 control-point values as CSS
`cubic-bezier()` — direct 1:1 mapping, confirmed and used as-is in `AppMotion`.

## Keyframe recipes

| Keyframe | Effect | Duration + curve | Used by |
|---|---|---|---|
| `saFadeUp` | opacity 0→1, translateY 10px→0 | `slow` (260ms) `easeOut`, `both` fill | Default staggered-list entrance (e.g. board sections/cards) |
| `saPop` | opacity 0→1, scale 0.94→1 | `slow` (260ms) `spring`, `both` fill | Alternate staggered entrance kind; dialog, command-menu pop-in |
| `saSlideUp` | opacity 0→1, translateY 60px→0 | Sheets: `slow` (260ms) `spring`; toast: `base` (180ms) `easeOut` | Bottom sheet open; toast entrance |
| `saFade` | opacity 0→1 | Scrim: `base` (180ms) `easeOut`; command-menu scrim: `fast`×1 (120ms) `easeOut` | Scrim/backdrop fade-in |
| `saShimmer` | background-position 180%→-80% | `shimmer` (1400ms) linear, infinite | Loading skeleton rows |
| `saLoaderPop` | scale holds 1.0 (0-46%), peaks `loaderPopPeakScale` 1.125 (77%), back to 1.0 (100%) | `loaderPop` (650ms) `easeOut`, infinite | Expressive SVG loader, per morphing shape |
| `saLoaderSpin` | rotate 0→360° | `loaderSpin` (1730ms) linear, infinite | Expressive SVG loader container |
| `saDotBounce` | translateY 0→`dotBounceOffset` -4px (30%)→0 | `dotBounce` (1200ms) `easeInOut`, infinite, staggered `i × dotBounceStagger` | Typing dots (3 dots) |
| `saOrbFloat` | translateY 0→`orbFloatOffset` -10px (50%)→0 | `orbFloat` (2500ms) `easeInOut`, infinite | Empty-state green orb ("No agents running") |
| `breatheDot` | opacity 1→0.35 (50%)→1 | `breatheActive` 1600ms *or* `breatheIdle` 2200ms `ease-in-out`, infinite | Session status dot — 1600ms while busy/working, 2200ms while stopped/idle |
| `spin` (plain) | rotate 0→360° | `spin` (1000ms) linear, infinite | Busy/"sending" icon (e.g. composer send icon while a message is sending) |

## Screen transitions

The prototype swaps screens **instantly** — there is no screen-to-screen transition style
in the source (`sc-if` branches toggle visibility with no animated container swap). Only
sheets, dialogs, command-menus, toasts, and scrims animate in/out per the recipes above.
Do not invent a screen-transition curve/duration; if the Flutter app wants one, treat it as
a new addition beyond the prototype and flag it separately.

## Micro-interactions (press scales)

All are `transform: scale(x)` applied on press-down (`style-active` in the prototype),
released back to 1.0 — no explicit release duration is set beyond the element's own
`transition: transform 120ms spring` (`AppMotion.fast` + `AppMotion.spring`).

| Scale | `AppMotion` token | Controls |
|---|---|---|
| 0.97 | `pressScaleDefault` | Primary/secondary buttons ("Pair Desktop", sheet save, spawn submit/cancel-adjacent primary), session cards (active + muted/archived) |
| 0.94 | `pressScaleFab` | Floating "spawn agent" FAB |
| 0.92 | `pressScaleSend` | Chat composer send button |
