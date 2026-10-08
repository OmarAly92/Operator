# navbar.inline still-check regression: diagnosis

Scope: diagnosis only. No source file changed, no simulator used. Runs compared: 2B.1 `glass-lab-runs/2b1/runs/20261006-175623` (archive, read-only) against `build/glass_lab/runs/20261008-093137`, at HEAD 27d5e9b9d. Probes (scratch, not in the repo): `/private/tmp/claude-501/-Users-omaraly-development-AI-Operator/6a4bdb3c-1809-4f2a-b131-dabdffec7f0a/scratchpad/probe/*.dart` (import `test/geometry/scene_sdf_mirror.dart` by path) and `.../scratchpad/n7/` (copies of `blend_model.py` and `blend_at_spacing.py` with one extra model).

## 1. What the scene really draws

`_InlineNavScene` (`lib/core/widgets/glass/lab/scenes/lab_navigation_scenes.dart:58-71`) passes two `GlassButton.icon` actions to `GlobalAppbar.sub`. `GlobalAppbar` wraps every trailing action in `GlassBarItem` (`global_appbar.dart:125`), and `GlassBarItem` is itself glass (`GlassSurface(kind: capsule, size: 44)`, `glass_bar_item.dart:15`). `GlassButton.icon` is glass too (`GlassSurface(kind: circle, size: 44)`, `glass_button.dart:85`). `GlassEffect` has no nesting rule (`glass_effect.dart:230-246`): both register with the container's blend group.

So each action is **two coincident glass members**: a `LiquidRoundedRectangle(999)` on a 44 x 44 rect (shader type 3, radius clamped to 22, a circle) and a `LiquidOval` on the same rect (type 2). The container's shape list is 5 shapes: back button (single glass, `global_appbar.dart:57`), cap1, circ1, cap2, circ2. The order (outer first or inner first) gives identical fields (checked).

The app's own screens pass non-glass actions (`notifications_screen.dart:26` TextButton, `preview_screen.dart:20` Semantics), so the double glass is a lab-scene artefact; the real app's navbar has one glass per action.

## 2. Measured geometry (frames, 3 px per pt, glass mask = luma > 25 on black)

| | 2B.1 Flutter | now Flutter | native |
|---|---|---|---|
| trailing button diameter (vertical, through centre) | 162 px = **54 pt** | 132 px = **44 pt** | capsule 132 px = 44 pt |
| trailing group width | 318 px = 106 pt (855-1172) | 288 px = 96 pt (870-1157) | 304 px = 102 pt (854-1157) |
| button centres | 936 / 1092 px = 312 / 364 pt | same | one capsule |
| centre distance, gap | 156 px = 52 pt, gap 8 pt (`toolbarItemGap`) | same | n/a |
| neck (column height), min | 36.0 pt at x 336-337 | 20.7 pt at x 337, **16.0 pt at x 338-339** (step at the bisector x = 338) | 44 pt everywhere |
| column at x = 335 pt (the rim_rms column: centre of native box 284 + 102/2) | 36.0 pt | 22.0 pt | 44 pt |
| back button (same container, single glass) | 132 px = 44 pt | 132 px = 44 pt | 44 pt |

Every changed pixel between the two runs lies in x 284-391, y 56-111 pt (the trailing pair) in all six cases; the back button region has max difference **0** in all six cases. The result.json boxes: 2B.1 `[285, 57, 106, 54]`, now `[290, 62, 96, 44]`, native `[284, 62, 102, 44]`.

## 3. Model against frames (Dart mirror, k = spacing = 20 pt; the shader works in px with k = 60 px and shapes x 3, the field scales linearly)

Column heights (pt) across the neck, model / frame (dark-black; light-black agrees within 0.7 pt):

| x (pt) | 2B.1 quadratic, 5 shapes | 2B.1 frame | angle, 5 shapes (now) | now frame | angle, deduplicated 3 shapes |
|---|---|---|---|---|---|
| 330 | 40.67 | 40.00 | 27.38 | 26.67 | 26.43 |
| 335 | 36.11 | 36.00 | 21.87 | 22.00 | 15.82 |
| 337 | 35.90 | 36.00 | 20.63 | 20.67 | 13.03 |
| 338 | 36.16 | 36.67 | 16.41 | 16.00 | 12.41 |
| 339 | 36.64 | 37.33 | 15.69 | 16.00 | 13.03 |
| 341 | 38.10 | 38.67 | 16.79 | 18.00 | 15.82 |
| 346 | 43.11 | 44.00 | 26.48 | 28.00 | 26.43 |
| button radius | 27.00 | 27.0 (162 px) | 22.00 | 22.0 (132 px) | 22.00 |

Both frames are reproduced from the shader formulas alone, on static geometry at the laid-out positions, to about 1 pt.

Field values at key points (pt / px):

| point | plain min | 2B.1 quadratic, 5 shapes | quadratic, dedup | angle, 5 shapes (now) | angle, dedup |
|---|---|---|---|---|---|
| outer edge of button 1 (290, 84) | 0 / 0 | **-5.00 / -15.0** | 0 / 0 | 0 / 0 | 0 / 0 |
| top of button 1 (312, 62) | 0 / 0 | **-5.00 / -15.0** | 0 / 0 | 0 / 0 | 0 / 0 |
| neck centre, left of bisector (337.99, 84.5) | 3.99 / 12.0 | -5.66 / -17.0 | -1.00 / -3.0 | **-2.47 / -7.4** | -0.99 / -3.0 |
| neck centre, right of bisector (338.01, 84.5) | 3.99 / 12.0 | -5.67 / -17.0 | -1.00 / -3.0 | **-2.27 / -6.8** | -0.99 / -3.0 |
| neck 6 pt up, left (337.99, 78) | 4.67 / 14.0 | -4.98 / -15.0 | -0.32 / -1.0 | **-1.51 / -4.5** | -0.06 / -0.2 |
| neck 6 pt up, right (338.01, 78) | 4.67 / 14.0 | -4.99 / -15.0 | -0.32 / -1.0 | **-0.89 / -2.7** | -0.06 / -0.2 |

Largest one-pixel field step across the bisector inside the refracting band (field in [-10, 0] pt), pixel centres: angle 5 shapes **7.69 px** (elsewhere max 1.48 px); angle dedup **0.000 px**. The step peaks on the centre row (y 83-86 pt: 3.9-7.7 px) and is 2.0-2.8 px along the rest of the bisector.

## 4. Cause (confidence: high)

**Two effects, both from the duplicate glass meeting the shader change of 27f8613ef.**

**(a) The size and the neck: 2B.1's look was a bug that the angle union removed.** The quadratic `smoothUnion(d, d, k) = d - k/4`: two coincident shapes grow by k/4 = 5 pt (15 px). In 2B.1 each action's two coincident members made 54 pt circles (outer edge and top both at -5.00 pt, matching the 162 px frame exactly), and the bloated circles overlapped into a 36 pt neck. The angle weight `w = (1 - n_a.n_b)/2` is 0 for coincident shapes (parallel normals), so the pair adds nothing: now the circles are the correct 44 pt (the back button, native and the frame agree) and the neck is a real 8 pt-gap neck. rim_rms samples the column x = 335 pt, which passes through the neck: native 44 pt of glass, 2B.1 36 pt, now 22 pt, so rim_rms rises. bbox_pt 5 -> 6 is the same story: 2B.1's error was the 5 pt bloat on top and bottom (its left edge 285 was 1 pt off only because of the bloat); now height is exact and the left edge shows a 6 pt layout difference (native's group is 102 pt wide, Flutter's two circles span 96).

**(b) The seam: the fold's normal output is discontinuous, and the duplicate re-blends on one side only.** `angleSmoothUnion` returns `mix(near.n, far.n, h*w/2)` as the normal for the next fold step. With w < 1 that weight is below 1/2, so at the bisector (where `near` switches from button 1's field to button 2's) the returned normal jumps from mostly n1 to mostly n2. The 5th shape (circ2, identical to cap2) is then blended against that normal: right of the bisector the normal is about n2, w = 0, nothing happens; left of it the normal is about n1, w is about 0.9, and the pair's blend is applied a second time. The field steps (table above: -1.51 against -0.89 pt at 6 pt up), the neck is 19.8 pt left of the bisector and 16.2 pt right (frame 20.7 / 16.0), and on the centre row, where the mixed normal of two anti-parallel normals nearly cancels, the step reaches 7.7 px. The geometry shader takes the normal from `dFdx(sd)`/`dFdy(sd)`, constant per 2 x 2 quad, so quads straddling the step draw the blocky column just left of the seam.

**What rules the other hypotheses out:**
- (1) units: `blend * devicePixelRatio` and the shape data `* devicePixelRatio` are unchanged since 2B.1 (`liquid_glass_blend_group.dart:262-297`); the model at k = 60 px reproduces both frames.
- (2) angle union at far gaps shrinking circles: it never shrinks (the correction is never positive); the outer edges and tops are exactly 0 in every model except 2B.1's duplicate bloat. The "10 % smaller" is 2B.1 being 23 % too big (54 / 44).
- (3) outline band (ruling 11) and (4) container material row (ruling 30, Task 20): the back button is in the same container, layer and blend group, and is byte-identical in all six cases; the side is pinned to 44 in both runs.
- (5) generic loop against the unrolled path: 2B.1 had 5 shapes, so it already took the loop (`numShapes > 4`); the two paths are the same arithmetic. The seam needs a third shape near the neck: the deduplicated 3-shape field is continuous (0.000 px step), with only a slope kink of 0.049 per pt at the neck edge (the w < 1 off-axis term; the quadratic was C1 there).
- Tasks 8, 17, 18, 24b: no `GlassEffectUnion` in the scene (`unionOutline` null); the scene is static and the button centres are at the same pixels in both runs; the static model explains both frames without any geometry change.

## 5. Proposed fix

### Fix 1 (required for the seam; changes no N7 number): coincident glass never enters the fold twice

- **1a, the scene** (`lab_navigation_scenes.dart:66-69`): pass the actions the way Operator's screens do, as non-glass icon widgets, so `GlassBarItem` is the only glass per action. This makes the scene represent the app.
- **1b, a package guard** in `RenderLiquidGlassBlendGroup.gatherShapeData` (`lib/src/liquid_glass_blend_group.dart`, the candidate loop at about L316-369): skip a candidate whose blend-group rect equals an earlier candidate's rect (to 1e-3 logical px) and whose outline is the same, comparing canonical outlines: a `LiquidRoundedRectangle` whose radius is at least half the side of a square rect is the `LiquidOval` of that rect; otherwise same shader type and same effective radius. (A superellipse on a square is not a circle at exponent 3.5, so it is not merged with an oval.) The skipped member's content still paints; only the SDF list loses the duplicate.

Effect on navbar.inline with either: the field becomes the deduplicated one exactly. Seam gone (step 0.000 px), circles 44 pt, neck 12.41 pt at the bisector, **15.82 pt at the rim column x = 335 (now 22.0, 2B.1 36.0, native 44)**. rim_rms will be worse than in this run, not better; bbox_pt stays 6.

Tests that would pin it:
- render object: a `GlassEffectContainer` holding a capsule `GlassEffect` that wraps a circle `GlassEffect` on the same 44 pt rect, beside a second such pair: `gatherShapeData` returns 2 shapes, not 4; a rounded rectangle with a radius below half the side on the same rect is not merged.
- mirror (`test/geometry/`): the navbar geometry `[back, circ1, circ2]` at k = 20 is continuous across x = 338 (largest one-pixel step 0 px in the band) and has the column heights 12.41 pt at 338 and 15.82 pt at 335; and, as a recorded hazard, the same geometry with the duplicates (`[back, cap1, circ1, cap2, circ2]`) differs from it by up to 2.8 pt (-3.81 against -1.00 pt on the centre row just left of the bisector) and steps 7.69 px across the bisector, which is why the guard exists. Today's mirror tests only cover two shapes.
- the scene: a widget test that the navbar.inline scene builds 3 grouped glass members, not 5.

N7 / ruling 9: **no change.** Every N7 scene is two distinct circles; nothing is deduplicated. `R/blend-at-spacing-light-photo.json` stays S4 0.165, S6 0.47, S8 0.374, S10 0.502, S12 0.502, S16 0.334, S20 0.421, S40 0.427, S80 0.413. The join at spacing / 2, k = spacing, the default 8 and the angle weighting are untouched.

### Alternatives considered (not recommended for this regression)

- **C1 form, k_eff = k*w** in `angleSmoothUnion` (`sdf.glsl`): `kw = k*w; if (kw <= 1e-4) return near; h = max(kw - |a.x - b.x|, 0)/kw; value = near.x - kw/4*h*h; normal = normalize(mix(near.n, far.n, h/2))`. Identical to the current field on the bisector and on the centre line (the join at spacing / 2 and the tips unchanged), removes the 0.049 slope kink (to 0.0001), makes the returned normal continuous at a = b. **It does not remove the duplicate seam**: with the 5 shapes the centre-row step is still 7.77 px (the anti-parallel normals cancel there) and the neck is still re-blended (18.2 pt at x 335, 14.9 at x 341). It moves 5 N7 neck rows by one pixel pair (-0.67 pt): light photo RMS S4 0.165 -> 0.372, S10 0.500 -> 0.601, S40 0.426 -> 0.453, the rest identical; light black S4 0.334 -> 0.667, S10 0.499 -> 0.763, S40 0.640 -> 0.692, S80 0.798 -> 0.882. That breaks ruling 9's "all its RMS at or below 0.5 pt" at S10. (My rerun of the stored angle model gives 0.5 / 0.426 / 0.412 where the plan records 0.502 / 0.427 / 0.413: rounding only.)
- **Pairwise max against the nearest member** in `sceneSDF` (find the member with the smallest raw distance, then `value = nearest.d - max_j(k/4 * h_j^2 * w_j)` with h and w taken against that member's own normal): order-independent and idempotent for duplicates; equals the current field for any two shapes to 5e-15 pt (N7 identical) and equals the deduplicated navbar field to 1e-14 pt (step 0 px). But it changes every cluster of three or more distinct shapes within k: up to 2.5 pt on a row of three 44 pt circles at gap 8, and a triangle of three at gap 4 gets a hole at its centre that the fold fills. There is no native 3-shape reference, so this is a guess about native behaviour; keep it for when one is recorded.

## 6. LOUD: navbar.inline cannot be made "no worse than 2B.1" by any correct union

**2B.1's navbar numbers came from a defect: the quadratic union bloated each duplicated action by k/4 = 5 pt, giving 54 pt circles where native and the back button are 44 pt.** Every correct model draws a much thinner neck at the rim column x = 335: quadratic deduplicated 17.2 pt, angle deduplicated 15.8 pt, angle with the k*w form 14.9 pt, against 2B.1's 36 pt and native's 44 pt.

- Getting 36 pt at that column from two 44 pt circles 8 pt apart under the angle model needs **spacing 52.3 pt** (44 pt needs **76.8 pt**). That means changing `GlassScope`'s spacing far beyond native semantics.
- Getting it back from the shader means **restoring the coincident-shape bloat, that is w = 1 for parallel normals, which is abandoning the angle weighting**. Ruling 9 rejects that: the quadratic is 1.4 to 11.5 pt off at S16 to S80.
- None of the join at spacing / 2, k = spacing, the default 8 or the angle weighting needs to change for Fix 1. Matching native needs a different structure.

**Native draws the trailing group as one 102 x 44 capsule** (every column across it is 44 pt). The Flutter structure that matches it is one capsule for the trailing group: `GlobalAppbar` wraps the trailing `Row` of non-glass items in one `GlassBarItem`-style capsule, or draws the items as one `GlassEffectUnion` (Task 8). Predicted: 44 pt at the rim column. bbox stays 6 pt off: native's group is 102 pt wide against Flutter's 96. That is a layout difference whose cause is not known here, and it was hidden in 2B.1 by the bloat. This is an Operator design change (DESIGN.md, the clone rule) and needs the user's approval.

Recommendation: record navbar.inline's 2A comparison as 2B.1's duplicate bloat disappearing (the real app's navbar never had it, since its screens pass non-glass actions), take Fix 1 (scene and guard) for the seam, and ask the user whether the trailing group should become one capsule like native's.
