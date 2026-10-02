# 2A spike: light/dark flip and frame cost

Date: 2026-09-28. Simulator: iPhone 17 Pro (iOS 27). Spec: `02a-looks/spec.md` §B8, Done items 7 and 8.

## Question

Does native small glass flip between light and dark with the content behind it, and can the package match it cheaply?

## Method

- Native `material.flip` scrolls the `scroll` backdrop (text, photo, white, black) under three glass blocks: small at the top, large, and small at the bottom.
- `flip.py` reads the backdrop in a band around each block and the glass in the block's centre half. It takes the median glass value in frames where the band is uniformly white (5th percentile ≥ 245) or black (95th percentile ≤ 10).
- It compares that value with the same-size block of `material.regular` over `white` or `black`, in the same appearance ("no flip") and in the other appearance ("flips").

## Result

| Appearance | Glass | Over | Observed | Same appearance | Other appearance | Verdict |
|---|---|---|---|---|---|---|
| light | small_top | white | 250 | 252 | 184 | no flip |
| light | small_top | black | — | 132 | 32 | not seen |
| light | large | white | — | 254 | 121 | not seen |
| light | large | black | 134 | 136 | 32 | no flip |
| light | small_bottom | white | 250 | 252 | 184 | no flip |
| light | small_bottom | black | 130 | 132 | 32 | no flip |
| dark | small_top | white | 182 | 184 | 252 | no flip |
| dark | small_top | black | — | 32 | 132 | not seen |
| dark | large | white | — | 121 | 254 | not seen |
| dark | large | black | 33 | 32 | 136 | no flip |
| dark | small_bottom | white | 182 | 184 | 252 | no flip |
| dark | small_bottom | black | 30 | 32 | 132 | no flip |

## Decision

Native `.glassEffect()` glass does not flip on iOS 27, at 44 pt or at 200 pt, in either appearance. The package already draws the same-appearance material, so B8 needs no implementation in 2A. Bars and tab bars are measured again in project 3 with the `tabbar.*` and `navbar.*` scenes.

## Frame cost (Done item 8)

| Renderer | perf.none raster median | perf.glass raster median | perf.glass p90 |
|---|---|---|---|
| old (development) | 0.577 | 12.096 | 12.793 |
| new (this branch) | 0.621 | 12.479 | 13.209 |
| new (second take) | 0.588 | 12.238 | 12.901 |

`perf.glass` is 13 own-layer glasses (12 of 110 × 44, one of 360 × 200) over a backdrop that moves every frame, in a debug build on the simulator, each drawn with `const LiquidGlassSettings()` (default blur, identity tone curve, no hairline or specular) — not the tuned iOS 27 material rows. The new renderer's mean of two takes' raster medians (12.36 ms) is 2.2% slower than the old one (12.10 ms), well under the 20% budget. The cost of the tuned materials (frost as high as 72 under Reduce Transparency) is not yet measured; that needs a `perf.material` scene built from `GlassEffect`. The real-device check is project 5.

Native `material.flip` filmstrip: `packages/mobile/build/glass_lab/runs/20260928-000844/material.flip/dark-scroll/native/`. Flutter flip scene does not exist because 2A builds no flip scene.
