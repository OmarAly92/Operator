# ios_liquid_glass 2A.1: the 2A review's fix round — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Close the gaps the 2A review found, then re-tune and re-measure, on the 2A branch:
- a rim measure that sees all four sides of every glass at its exact edge;
- an edge model that can draw what native draws (crisp silhouette, dark outer outline at the curved ends, a bright line and sheen at the top and bottom, nothing at the ends);
- a shadow that reaches native's long soft tail, a clear glass with none, and a tuner that can see both;
- a scroll edge made of real Gaussians instead of a sparse 7 × 7 kernel;
- the code review's bugs (stale builds, clear tint under accessibility, clamped starts, `--a11y`/`--row` mismatches, Operator's bottom edges) and its stale document facts;
- a re-tune over all five backdrops, and verification of spec Done items 3–6 and 8 in `results-2a1.md`.

**Architecture.**
- Nothing in the renderer's structure changes. The geometry pass now encodes the signed distance to the silhouette (not the bevel height) and covers a thin band outside the shape, so the final render can draw a crisp silhouette pixel, an outline outside it and exponential line and sheen terms inside it. The adaptive inner hairline is removed.
- The scroll edge becomes stacked `BackdropFilter`s, each an `ImageFilter.compose` of a real Gaussian and a small mask shader, plus a painted tint gradient and divider line.
- The harness scores the rim on the manifest's pinned regions, pads shadow steps, refuses stale builds, scopes candidates to the tuned anchor and closes other lab apps before each capture.
- Table numbers still come from `lab.py tune --write`, starting from seed rows this plan gives verbatim (the prototype's measured and tuned values).

**Tech stack.** Flutter 3.44.5 / Dart with Impeller runtime-effect shaders (GLSL 460), Python 3 (stdlib, Pillow, numpy) for the harness, Xcode 27 and the iOS 27 simulator.

**Spec.** `docs/liquid_glass/02a-looks/spec.md` (approved 2026-09-27) and its Done items; the 2A plan `plan.md` and its 15 rulings still hold except where a ruling below replaces one. Read `docs/liquid_glass/ROADMAP.md` §3–§5 first, then `results.md` (what failed in 2A) and `rulings.md`.

**Where the code comes from.** Every code block below ran in a throwaway prototype, `/Users/omaraly/development/AI/Operator-2a1-proto` (branch `proto/2a1` from `370b02ada`, uncommitted), on the "iPhone 17 Pro (iOS 27)" simulator. Its gates at the end: harness 104 tests OK (2A: 84), package 63 (2A: 51), example 8 (2A: 6), app 2,146, `flutter analyze` clean in app, package and example. `PROTOTYPE-2A1.md` at its root lists every measurement with its folder. Transcribe the code exactly, then run the verification steps. If a step fails, fix the cause and say what changed in the task report.

**Rulings the prototype forced, with evidence.** They refine the spec and the 2A plan; where they differ, these win. They replace 2A's ruling 3 ("the geometry pass needs no change": it now encodes the signed distance and covers the outline band, rulings 2 and 18) and extend 2A's ruling 15 (the shadow stays static, now fitted to native's whole tail, ruling 4). Folders are under the prototype's `packages/mobile/build/glass_lab/` (`tune/` or `runs/`); `2a-<run>` folders are copies of the 2A branch's runs.

1. **The rim is measured on all four sides of every pinned glass, at its exact edge, and never looser than 2A's measure** (finding 1). `rim_rms` is the maximum of 2A's centre-column measure on the detected box and every pinned region's four-sided RMS (±12 pt around the top, bottom, left end and right end). Re-analysing 2A's run `20260930-082046` with it: `material.regular dark-white` 8.10 → 19.77 (the ends read 26: native's dark outline, which the centre column never crossed), `dark-black` 8.26 unchanged, `light-white` 5.68 → 8.39, `material.tinted dark-black` 49.08 unchanged. No case scored better.
2. **The edge is a new model, not a retune** (finding 2). Native 200 pt glass, luma minus bare, one pixel per step (2A run `20260930-082046`):
   - on black, dark: the top row is 95, 76, 62, then a sheen 45, 43 … 32 over about 10 pt; the bottom the same (90, 73, 59); the curved ends 31 flat, no line at all. 2A's first row was 26 (its AA faded the last two pixels) and it lit the ends like the top;
   - on white, dark: the ends have a dark line **outside** the silhouette, 40 and 129 luma against 234 around it; the top has none. Light appearance: a weaker outline all round, strongest at the ends (−97, −56 at the ends, −35, −24 at the top);
   - Reduce Transparency and Increase Contrast show the same structure (the outline reads 3–7 luma on white in dark), so the adaptive inner hairline is removed, not kept for them.

   The model: one-pixel coverage, an outline band outside the shape weighted `mix(outlineTop, outline, |n.x|)`, and exponential line and sheen terms on the two light lobes with the light straight down the normal of the top edge. Seeded, then tuned on black and white at 200 pt: dark rim 1.48 on black and 2.33 on white, every side under 2.4 (`tune/20260930-173453`); light 1.27 and 3.17 (`tune/20260930-202218`). The same cases scored 7.1 and 19.2 (dark), 15.7 and 8.4 (light) with 2A's table under ruling 1's measure.
3. **Two seed scripts write the tables once, outside `tune --write`** (Tasks 4 and 5), as 2A's seed did. The field set changes, and the prototype's measured and tuned values are a better start than 2A's for a coordinate descent that only moves one field at a time (the soft scroll edge from 2A's row got stuck at MAD 12.84, `tune/20260930-181637`; from a fitted seed it reached 4.04, `tune/20260930-184134`). Run on a copy of 2A's committed tables, the two scripts produce the prototype's measured tables byte for byte.
4. **Native's shadow is one Gaussian, offset down, and the tuner now sees its whole tail** (finding 3). Fitted to native's darkening on `white`, `text` and `photo` (2A run `20260930-082046`, error 0.2–0.6 luma): 200 pt sigma 17, offset 8, opacity 0.18 dark, 0.12 light; 88 pt sigma 7 and 6, opacity 0.054 and 0.039; 44 pt sigma about 2.5, opacity 0.012. `BoxShadow.blurRadius = (sigma − 0.5) / 0.57735`. Tuned with `--pad 60` on `white` and `text`: dark 0.16 / 29 / 8 and light 0.12 / 29.6 / 8, box and centre 0.0 on both backdrops in both appearances (`tune/20260930-210741`, `tune/20260930-212328`; 2A's Done run read box 12, centre 6). Below the dark glass on white, every 3 pt, native reads −30, −27, −23, −20, −17, −14, −11, −9, −7, −5, −4, −3, −2, −1, −1, 0 and the prototype, with Task 6's clipped cut-out, −26, −24, −21, −18, −15, −13, −10, −8, −6, −5, −4, −3, −2, −1, −1, −1, 0 (`tune/20260930-231917`; 2A: −48, −35, −24, −14, −8, 0). One layer is enough; no second shadow.
5. **Clear glass casts no shadow** (finding 6): the fitted opacity under native clear glass is 0.000 on white in both appearances. The seed sets 0 and the clear shadow step's grid starts at 0.
6. **Tone points come from native first** (finding 4). `lab.py tonefit` fits the shader's three-point curve to native's glass-interior luma against its bare backdrop over the five backdrops. Frost preserves the mean and the curve acts on luma alone, so the fit gives the points directly: it reproduces 2A's dark rows within 0.01 and shows 2A's light rows were wrong where 2A never looked (`toneMid 0.725`, `toneWhite 1.19` against native's 0.797 and 0.997 at 200 pt). With the fitted points, light 200 pt glass over `photo` went from luminance 15.32 to 0.05 and MAD 17.12 to 6.88; over `text` from 7.47 / 6.95 to 2.60 / 1.23 (`tune/20260930-213724` against `tune/20260930-215155`, five backdrops).
7. **The lens is tuned on `stripes` and `photo`, where it shows.** 2A's light 200 pt `thickness 48` (the top of its grid) pulled bright stripes from far inside into the curved ends; the left end read 212–226 where native reads 180. At `thickness 4`, `refractiveIndex 1.075`: `stripes` rim 16.3 → 3.95 and MAD 7.3 → 3.8, `photo` rim 6.9 → 3.85 and MAD 6.9 → 3.3 (`tune/20260930-215835`). Every measure of light 200 pt glass on `stripes`, `photo` and `white` then passes.
8. **Which backdrops each step uses** (finding 4): tone on all five; shadow on `white` and `text` (the fit is the same on every light backdrop, and black hides it); edge light on `black` and `white` (they isolate the line, sheen and outline); lens on `stripes`, `photo` and `white`; accessibility tone on all five.
9. **The scroll edge is stacked real Gaussians** (finding 7). A `ShaderMask` over a `BackdropFilter` draws no blur at all under Impeller (text stays sharp, MAD 27.37, `tune/20260930-181321`); `ImageFilter.compose(outer: shader(mask), inner: blur)` does, and the backdrop filter's source-over draw cross-fades it. Soft is 8 levels whose combined sigma follows its own ramp (`blurKnee`, `blurReach`); the tint, cap and line are painted. Measured with the seeded rows: soft dark MAD 3.98 / luminance 0.13 (`tune/20260930-193014`), soft light 4.21 / 0.05 (`tune/20260930-193453`), hard dark 3.48 / 0.06 (`tune/20260930-193656`), hard light 2.08 / 0.05 (`tune/20260930-195957`); 2A: 21.27, 5.67, 4.56, 1.91. A zoomed crop of the soft band shows no grid and no doubled text.
10. **`blur` and `capBlur` are a Gaussian sigma in points.** 2A's 7 × 7 kernel at spacing r/3 with weights `exp(−(i² + j²)/8)` was a sigma of 2r/3.
11. **Operator's bottom scroll edges use `soft`** (finding 8e, Task 7): no native bottom edge is measured, the top-tuned `automatic` row draws a divider 37 pt above the tab bar, and soft is the pre-2A Operator look, measured on the top edge.
12. **Rebuild before every `tune` step.** The build is 15 s when only Dart changed (prototype), `tune` refuses a stale build (Task 2), and a stale build is how 2A's Group F scored a seed-look "Edit" button (code review bug 1).
13. **A candidate reaches only its own size anchor** (`materialSide`, Tasks 2 and 6). Without it, a 200 pt candidate repaints the 44 and 88 pt glass, which `--pad 60` brings into the region.
14. **Every capture closes the other lab apps first.** A native reference taken while the example app still ran showed iOS's "◀ Ios Liquid Glass E…" back link under the clock; soft light scored MAD 5.49 against 4.21 on a clean reference (`tune/20260930-193136`, `tune/20260930-193453`).
15. **The tinted "Run" button is native's 78 × 37 pt, and lab scenes centre on whole points** (finding 5). The 86 × 40 pt button lifted the column so the 88 pt block sat 2 pt high; with 78 × 37 the column is 173 pt tall, plain centring put it at 364.5 pt, and SwiftUI puts native's at 365. With both fixes the block's box and centre match exactly and its rim is 2.5 on `dark-black` (run `20260930-230435`; 2A: 36.7 under ruling 1's measure).
16. **Frame cost is measured on the tuned material, and the shadow is cut out with a clip** (finding 9). `perf.material` draws the `perf.glass` layout through `GlassEffect`. With the old `saveLayer` + `dstOut` cut-out it measured 14.72 ms raster median, 21.6% over the old renderer's 12.10 ms; turning shadows off gave 12.62 ms, and frost and the outline band cost nothing measurable. With a difference clip instead: 13.04 ms, +7.8% (`perf-2a1b.json`, 3 alternating takes; `perf.glass` 12.65 ms in the same takes). A soft scroll edge (`perf.edge`, 8 levels) costs 4.98 ms over the bare backdrop; the spec sets no budget for it, and the ROADMAP records it for project 5's device check.
17. **Not fixed: native's capsule has continuous corners.** At 200 pt its flat top starts about 19 pt later than a circle-ended capsule (first lit pixel on the top row at x 139.7 pt against the package's 112) and its edge sits up to 1.3 pt lower near the arc's start; the package's capsule is `LiquidRoundedRectangle(999)`. It changes pixels only in the corners, not at the four sides the rim measure samples. It needs a new SDF, which 2A.1 does not build; the ROADMAP records it.
18. **Geometry images are sized by rounding, not `ceil`.** Upstream sizes the geometry picture and images with `ceil()` of pixel-snapped extents. The outline band's 1.55 pt inflation makes those extents thirds of a point, and floating point turns 760 px into 760.0000000000001, so the image became 761 × 275 px against a 760 × 274 px matte: the geometry was sampled 1 px off at the right and bottom, and the 88 and 44 pt glass lost their last lit column and row (lit x 228–977 against native's 228–978 on `light-black`, run `20260930-221352`) while the 200 pt glass, whose extents happened to be exact, did not. Any glass at a fractional position hits the same bug.

## Global Constraints

- **Paths and git**
  - Work only in the worktree `/Users/omaraly/development/AI/Operator-ios-liquid-glass`, on branch `feat/ios-liquid-glass-2a`, on top of `370b02ada` and this plan's docs commit. 2A.1 continues the 2A branch; there is no new branch.
  - Never touch `/Users/omaraly/development/AI/Operator` (the shared checkout, other sessions' uncommitted work), `/Users/omaraly/development/AI/Operator-2a-proto` or `/Users/omaraly/development/AI/Operator-2a1-proto` (the prototypes; reference only).
  - Paths are relative to `packages/mobile/` unless they start with `docs/`, which is relative to the repository root.
  - Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. Never `git stash`. Never push, never merge.
- **Code**
  - No code comments in any new or changed code: Dart, Swift, Python, GLSL or shell. Keep upstream comments that already exist, including dartdoc in the vendored renderer files and the copyright line of each shader.
  - Never run `dart format` on whole files; match the surrounding style.
  - Material numbers in `lib/src/material/ios27.dart` and `ios27_scroll_edge.dart` change only through `lab.py tune --write` and the two seed scripts this plan gives verbatim (Task 4 Step 8 and Task 5 Step 6).
- **Simulator and tools**
  - Simulator: "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`. The harness finds it by name. Never touch the iOS 26.5 simulator (`94D0C207-A90B-4806-BBAB-8AF9B3F16329`) or its Operator data.
  - `flutter build ios` alone fails under Xcode 27. Build lab apps only with `python3 tool/glass_lab/harness/lab.py build <native|example|operator|all>`.
  - Only one lab command at a time: `build`, `prepare`, `run`, `tune`, `perf`, `a11y` and `flip` all drive the same simulator. Run long ones with the Bash tool's `run_in_background` (never a trailing `&`) and wait for the completion notice; never poll with short sleeps.
  - After any interrupted lab command, `xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled` must print `0`; if it does not, run `python3 -c "import sys; sys.path.insert(0, 'tool/glass_lab/harness'); import sim; sim.accessibility(sim.device(), 'none')"`.
  - From Task 2 on, `tune`, `run` and `perf` refuse to start when the example app was built from other sources than the ones on disk. The answer is always `lab.py build example` (about 15 s when only Dart changed), never working around the check.
  - Python may use the standard library, Pillow and numpy only. No `pip install`, and no downloads of any kind.
- **Gates**, for every task that touches their code:
  - App, from `packages/mobile`: `flutter analyze` prints "No issues found!" and `flutter test` is green.
  - Package, from `packages/mobile/packages/ios_liquid_glass`: `flutter analyze` and `flutter test`.
  - Example, from `packages/mobile/packages/ios_liquid_glass/example`: `flutter analyze` and `flutter test`.
  - Harness, from `packages/mobile`: `python3 -m unittest discover tool/glass_lab/harness/tests` prints OK.
  - `flutter test` prints a long SkSL error about `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"). It is known and harmless; tests still pass.
- **Operator and the simulator.** Operator is used only through its debug glass lab. Never pair it, never enter a password, never touch real sessions or desktops. System prompts get only "Don't Allow" or "Not Now".
- **Judging glass.** Judge only by lab measurements, never by eye. When a number looks wrong, open the screenshots. Record every number you quote with its run or tune folder.

## Review Focus

1. **A tune step whose committed value lies outside its grid or outside the old clamp.** Expected: the first candidate is the committed row exactly, so `start_score` describes the table and `--write` never rewrites a value nobody searched. Pinned by `test_the_start_is_evaluated_as_committed_even_outside_the_range` (Task 2).
2. **A lab command run on a build older than the sources**, after a Dart change or the previous step's `--write`. Expected: `tune`, `run` and `perf` exit before touching the simulator and name `lab.py build <target>`. Pinned by `FreshBuildTests` and `RunFreshnessTests` (Task 2).
3. **A tune candidate for one size repainting another size** inside a region padded to 60 pt. Expected: only glass at the tuned anchor takes the candidate. Pinned by `test_material_candidates_reach_only_the_tuned_anchor_and_edge_candidates_every_glass` (Task 2) and `side-scoped overrides reach only the glass at that anchor` (Task 6).
4. **A changed `outlineWidth` on a glass whose geometry is cached.** Expected: the geometry is rebuilt, so the outline band and the bounds follow the new width; a changed outline strength alone does not rebuild. Pinned by `a new outline width rebuilds the cached geometry, a new outline strength does not` (Task 4).
5. **A capture polluted by the previous app**: a back link under the clock, or a lab app left in front. Expected: every capture starts with the other lab apps closed. Pinned by `test_every_other_lab_app_is_closed_so_no_back_link_shows_in_the_status_bar` (Task 2). 2A's `AccessibilityTests` still pin that no accessibility mode is left on.

## What this plan expects to reach

Measured in the prototype with the seeded tables and no campaign (runs `20260930-232714` regular, `-233849` tinted, `-234542` clear, `-225554` edges, `20260930-235058`, `20261001-000014`, `-000307` Operator; `perf-2a1b.json`). The rim numbers use ruling 1's stricter measure.

| Done item | 2A | Prototype | Expected after Task 8 |
|---|---|---|---|
| 3 Material scenes, strict | 0 of 20 | 5 of 20: `material.regular` 5 of 10, `material.tinted` 0 of 6, `material.clear` 0 of 4 | **`material.regular`: likely 10 of 10.** The 200 pt glass's rim is 5.2 or less on every backdrop in both appearances; the failures are the untuned dark 44 pt row's curved ends (sides 9–18) and `light-photo`'s box (3 pt). **`material.tinted`: the block passes (box and centre 0, rim 2.5–2.6); the Run button is not proven** (rim 12.7–27.8 untuned, and its top and bottom sample lines cross the label, whose glyphs are Flutter's). **`material.clear`: not proven** (box ≤ 1 and centre ≤ 0.5 now, but rim 9–18 and dark MAD 7.9–9.3 until Group C). |
| 4 Scroll edge | 2 of 6 | 5 of 6 (soft light MAD 4.12) | Likely 6 of 6. |
| 5 Reduce Transparency, Increase Contrast | 0 of 20 | not measured | Not proven. The seed gives each size native's own tone points and the stronger dark outline; Group E tunes the rest. |
| 6 Operator components halve rim and luminance | 18 of 32 | 20 of 32 | **Not expected to reach 32.** The tab bar's rims all halve now (dark-black 25.57 → 1.33), but 12 measures do not: `button.press` rim (13.08, worse than 2A's 9.33) and most of `navbar.inline`, where labels and icons take Operator's accent colour and the trailing group fuses into one shape, plus `tabbar.rest` light-photo and light-stripes luminance (4.56, 5.34). That is Operator component code, which project 3 replaces; 2A.1 does not touch it. |
| 8 Frame cost within 20% | +2.2% at default settings | +7.8% with the tuned material (13.04 ms against 12.10 ms) | Pass. |

---

## File map

| Path (under `packages/mobile/`) | Responsibility | Task |
|---|---|---|
| `tool/glass_lab/harness/{metrics,analyze}.py` | Four-sided rim at pinned regions | 1 |
| `tool/glass_lab/harness/{build,tune,lab,record,report,probe,tonefit}.py` | Stamps and freshness, ranges and start, `--pad`, anchor scope, row from `--a11y`, closing other apps, run metadata, tone fit | 2 |
| `packages/ios_liquid_glass/lib/src/material/glass_material.dart`, `lib/src/api/glass_foreground.dart` | Clear glass untinted under accessibility | 3 |
| `packages/ios_liquid_glass/lib/assets/shaders/{displacement_encoding.glsl,liquid_glass_geometry_blended.frag,liquid_glass_final_render.frag}` | Signed-distance geometry, outline band, line and sheen | 4 |
| `packages/ios_liquid_glass/lib/src/{liquid_glass_settings,liquid_glass_blend_group}.dart`, `lib/src/rendering/liquid_glass_render_object.dart`, `lib/src/internal/{render_liquid_glass_geometry,snap_rect_to_pixels}.dart` | New fields, uniforms, bounds, rebuild, image sizes rounded | 4 |
| `packages/ios_liquid_glass/lib/src/material/{glass_material,ios27}.dart` | Defaults, `toSettings`, seeded table | 4 |
| `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart`, `lib/src/material/{scroll_edge_material,ios27_scroll_edge}.dart`, `lib/assets/shaders/scroll_edge_mask.frag` | Gaussian scroll edge | 5 |
| `packages/ios_liquid_glass/lib/src/material/glass_material_override.dart`, `lib/src/api/glass_material_context.dart`, `lib/src/glass_shadow.dart`, `example/lib/lab/**` | Anchor-scoped overrides, whole-point centring, Run geometry, clipped shadow cut-out, `perf.material`, `perf.edge` | 6 |
| `lib/core/app_routes/home_shell.dart`, `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart` | Soft bottom edges | 7 |
| `docs/liquid_glass/02a-looks/{tuning-log-2a1,results-2a1,summary-material-2a1}.md` | Campaign log and results | 8, 9 |
| `packages/ios_liquid_glass/{README,FORK,CHANGELOG}.md`, `tool/glass_lab/README.md`, `docs/liquid_glass/ROADMAP.md`, `docs/liquid_glass/02a-looks/{results,flip-spike}.md` | Documents | 10 |

**Task order and why.**
1. The rim measure, so everything after it is scored the new way.
2. The tuning tool, which Tasks 4–6 already use to prove themselves.
3. The clear tint fix, before Task 4 rewrites `glass_material.dart` around it.
4. The edge model and the seeded material table.
5. The scroll edge renderer and its seeded rows.
6. The example app, which must scope candidates before any campaign step pads its region.
7. Operator's bottom edges, which need Task 5's soft style.
8. The campaign.
9. Verification.
10. Documents.

---

### Task 1: The rim is measured on all four sides of every pinned glass (finding 1)

**Files:**
- Modify: `tool/glass_lab/harness/metrics.py`, `tool/glass_lab/harness/analyze.py`
- Test: `tool/glass_lab/harness/tests/test_metrics.py`

**Interfaces:**
- Produces:
  - `metrics.RIM_SIDES = ("top", "bottom", "left", "right")`;
  - `metrics.rim_sides(frame, box, reach=12)`: luma samples across each side of `box`, at its exact edge, ±`reach` pt: the vertical centre column through the top and the bottom edge, the horizontal centre row through the left and the right end;
  - `metrics.element_rim(native, flutter, box)` → `{"rms": float, "sides": {side: float}}`;
  - `metrics.static_compare(native, flutter, native_bare, flutter_bare, region, elements=None)`: with `elements` (`{name: (x, y, w, h)}`), the result gains `rim_legacy` (the old centre-column measure on the detected box) and `rim_elements`, and `rim_rms` becomes `max(rim_legacy, every element's rms)`;
  - `analyze.elements_for(scene)`: every manifest region of the scene except its `track`.
- Why the maximum: the Done measure may only get stricter. The old measure stays inside the maximum, so no case can pass that failed before on rim. Re-analysing run `20260930-082046` with this code (prototype) moved `material.regular dark-white` from rim 8.10 to 19.77 (the ends: left 26, right 26, from native's dark outline that the old column never saw) and `light-white` from 5.68 to 8.39. No case got better.

- [ ] **Step 1: Write the failing tests.** Replace `tool/glass_lab/harness/tests/test_metrics.py` with:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
import analyze
import metrics
import springfit


def canvas(width=402, height=874, value=40.0):
    return np.full((height * 3, width * 3, 3), value, dtype=np.float32)


def draw_box(image, box, value=200.0):
    x, y, w, h = (v * 3 for v in box)
    image[y : y + h, x : x + w] = value
    return image


class GlassBoxTests(unittest.TestCase):
    def test_finds_drawn_box_within_one_point(self):
        bare = canvas()
        frame = draw_box(canvas(), (100, 300, 150, 44))
        boxes = metrics.glass_boxes(frame, bare)
        self.assertEqual(len(boxes), 1)
        for got, want in zip(boxes[0], (100, 300, 150, 44)):
            self.assertLessEqual(abs(got - want), 1)

    def test_orders_components_by_area(self):
        bare = canvas()
        frame = draw_box(draw_box(canvas(), (20, 20, 30, 30)), (100, 400, 200, 100))
        boxes = metrics.glass_boxes(frame, bare)
        self.assertEqual(boxes[0][:2], (100, 400))
        self.assertEqual(len(boxes), 2)

    def test_ignores_differences_below_threshold(self):
        bare = canvas()
        frame = canvas(value=44.0)
        self.assertEqual(metrics.glass_boxes(frame, bare), [])

    def test_union_pads_and_clips(self):
        self.assertEqual(metrics.union([(5, 5, 10, 10), (380, 800, 20, 70)], pad=12), (0, 0, 402, 874))
        self.assertIsNone(metrics.union([]))


class RimProfileTests(unittest.TestCase):
    def test_returns_the_drawn_gradient(self):
        frame = canvas(value=0.0)
        ramp = np.linspace(0, 255, 874 * 3, dtype=np.float32)
        frame[:, :, :] = ramp[:, None, None]
        profile = metrics.rim_profile(frame, (100, 300, 100, 50), reach=4)
        top = ramp[(300 - 4) * 3 : (300 + 4) * 3]
        np.testing.assert_allclose(profile[: len(top)], top, atol=1e-3)


class ElementRimTests(unittest.TestCase):
    def test_samples_all_four_sides_at_the_exact_edge(self):
        frame = draw_box(canvas(value=0.0), (100, 300, 150, 44), 100.0)
        sides = metrics.rim_sides(frame, (100, 300, 150, 44))
        for side in metrics.RIM_SIDES:
            self.assertEqual(len(sides[side]), 72)
            self.assertEqual(float(sides[side].min()), 0.0)
            self.assertAlmostEqual(float(sides[side].max()), 100.0, places=3)
        self.assertEqual(float(sides["top"][35]), 0.0)
        self.assertAlmostEqual(float(sides["top"][36]), 100.0, places=3)
        self.assertAlmostEqual(float(sides["right"][35]), 100.0, places=3)
        self.assertEqual(float(sides["right"][36]), 0.0)

    def test_an_end_cap_difference_is_seen_that_the_centre_column_misses(self):
        box = (100, 300, 150, 44)
        native = draw_box(canvas(value=0.0), box, 100.0)
        flutter = draw_box(native.copy(), (100, 300, 1, 44), 160.0)
        rim = metrics.element_rim(native, flutter, box)
        self.assertEqual(rim["sides"]["top"], 0.0)
        self.assertEqual(rim["sides"]["bottom"], 0.0)
        self.assertEqual(rim["sides"]["right"], 0.0)
        self.assertGreater(rim["sides"]["left"], 10.0)
        self.assertGreater(rim["rms"], 5.0)

    def test_the_element_rim_only_makes_the_rim_measure_stricter(self):
        box = (100, 300, 150, 44)
        bare = canvas(value=0.0)
        native = draw_box(canvas(value=0.0), box, 100.0)
        flutter = draw_box(native.copy(), (100, 300, 1, 44), 160.0)
        region = (88, 288, 174, 68)
        legacy = metrics.static_compare(native, flutter, bare, bare, region)
        pinned = metrics.static_compare(native, flutter, bare, bare, region, {"pill": box})
        self.assertEqual(pinned["rim_legacy"], legacy["rim_rms"])
        self.assertGreater(pinned["rim_rms"], legacy["rim_rms"])
        self.assertEqual(pinned["rim_rms"], pinned["rim_elements"]["pill"]["rms"])

    def test_analysis_scores_every_pinned_region_except_the_track(self):
        import manifest
        scenes = {s.id: s for s in manifest.load()}
        self.assertEqual(sorted(analyze.elements_for(scenes["material.regular"])), ["s200", "s44", "s88"])
        self.assertEqual(sorted(analyze.elements_for(scenes["material.tinted"])), ["block", "run"])
        self.assertEqual(analyze.elements_for(scenes["material.edge.soft"]), {})


class StaticCompareTests(unittest.TestCase):
    def test_identical_frames_pass(self):
        bare = canvas()
        frame = draw_box(canvas(), (100, 300, 150, 44))
        result = metrics.static_compare(frame, frame, bare, bare, (80, 280, 190, 84))
        self.assertTrue(all(result["pass"].values()))
        self.assertEqual(result["mad"], 0.0)

    def test_centre_ignores_symmetric_growth(self):
        bare = canvas()
        native = draw_box(canvas(), (100, 300, 150, 44))
        flutter = draw_box(canvas(), (96, 296, 158, 52))
        result = metrics.static_compare(native, flutter, bare, bare, (80, 280, 200, 90))
        self.assertTrue(result["pass"]["centre_pt"])
        self.assertFalse(result["pass"]["bbox_pt"])

    def test_matches_flutter_parts_that_overlap_the_native_element(self):
        bare = canvas()
        native = draw_box(canvas(), (20, 791, 360, 62))
        flutter = canvas()
        for box in ((24, 795, 93, 54), (150, 800, 30, 30), (300, 800, 30, 30), (20, 100, 120, 120)):
            draw_box(flutter, box)
        result = metrics.static_compare(native, flutter, bare, bare, (0, 80, 402, 794))
        self.assertEqual(result["flutter_box"], (24, 795, 306, 54))

    def test_a_faint_native_element_is_measured_by_its_parts(self):
        bare = canvas()
        native = canvas()
        for box in ((25, 795, 98, 54), (170, 800, 30, 30), (330, 800, 30, 30)):
            draw_box(native, box)
        flutter = draw_box(canvas(), (16, 788, 370, 74))
        result = metrics.static_compare(native, flutter, bare, bare, (0, 700, 402, 174))
        self.assertEqual(result["native_box"], (25, 795, 335, 54))
        self.assertEqual(result["flutter_box"], (16, 788, 370, 74))

    def test_a_full_screen_flutter_layer_does_not_widen_the_native_element(self):
        bare = canvas()
        native = draw_box(draw_box(canvas(), (0, 710, 402, 164)), (300, 18, 60, 20))
        flutter = draw_box(canvas(), (0, 0, 402, 874))
        result = metrics.static_compare(native, flutter, bare, bare, (0, 0, 402, 874))
        self.assertEqual(result["native_box"], (0, 710, 402, 164))
        self.assertGreater(result["centre_pt"], 300)

    def test_flutter_glass_missing_at_the_native_element_is_unmatched(self):
        bare = canvas()
        native = draw_box(canvas(), (284, 62, 102, 44))
        flutter = draw_box(canvas(), (17, 62, 42, 44))
        result = metrics.static_compare(native, flutter, bare, bare, (4, 50, 394, 68))
        self.assertIsNone(result["flutter_box"])
        self.assertFalse(result["pass"]["centre_pt"])

    def test_shifted_box_fails_bbox(self):
        bare = canvas()
        native = draw_box(canvas(), (100, 300, 150, 44))
        flutter = draw_box(canvas(), (104, 300, 150, 44))
        result = metrics.static_compare(native, flutter, bare, bare, (80, 280, 200, 84))
        self.assertFalse(result["pass"]["bbox_pt"])
        self.assertAlmostEqual(result["bbox_pt"], 4, delta=1)


class EventTests(unittest.TestCase):
    def test_splits_bursts_separated_by_quiet_time(self):
        times = [i / 120 for i in range(10)] + [1.0 + i / 120 for i in range(10)]
        diffs = [0.0] + [2.0] * 9 + [2.0] + [2.0] * 9
        self.assertEqual(align.events(diffs, times), [(0, 9), (9, 19)])

    def test_ignores_small_differences(self):
        times = [i / 120 for i in range(6)]
        self.assertEqual(align.events([0.0, 0.2, 0.3, 0.1, 0.0, 0.2], times), [])

    def test_reports_gaps_inside_motion_only(self):
        times = [0.0, 0.008, 0.016, 0.06, 0.068, 2.0, 2.008]
        diffs = [0.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0]
        self.assertEqual([round(g) for g in align.stalls(diffs, times)], [44])

    def test_resample_interpolates_on_grid(self):
        rows = [{key: 0.0 for key in align.KEYS}, {key: 12.0 for key in align.KEYS}]
        series = align.resample([0.0, 0.1], rows, hz=120)
        self.assertEqual(len(series["width"]), 13)
        self.assertAlmostEqual(series["width"][6], 6.0)

    def test_significant_needs_real_travel(self):
        flat = {key: [1.0, 1.0, 1.2] for key in align.KEYS}
        moving = dict(flat, width=[10.0, 30.0, 40.0])
        self.assertFalse(align.significant(flat))
        self.assertTrue(align.significant(moving))

    def test_extent_bounds_changed_tiles_below_the_status_area(self):
        first = np.zeros((874, 402, 3), dtype=np.float32)
        moved = first.copy()
        moved[400:480, 100:200] = 200
        moved[10:30, 10:30] = 200
        self.assertEqual(align.extent([first, moved]), [(96, 400, 104, 80)])


class SpringFitTests(unittest.TestCase):
    def test_recovers_response_and_damping(self):
        times = np.arange(0, 1.5, 1 / 60)
        for response, damping in ((0.35, 0.7), (0.5, 0.86), (0.25, 1.0), (0.8, 0.45)):
            values = 10 + 90 * springfit.step_response(times, response, damping)
            got = springfit.fit(times, values)
            self.assertLessEqual(abs(got["response"] - response) / response, 0.05)
            self.assertLessEqual(abs(got["damping"] - damping), 0.05)

    def test_features_of_underdamped_curve(self):
        times = np.arange(0, 2.0, 1 / 60)
        values = springfit.step_response(times, 0.5, 0.5)
        result = springfit.features(times, values)
        self.assertGreater(result["overshoot_pct"], 10)
        self.assertGreater(result["settle_ms"], result["peak_ms"])

    def test_flat_series_has_no_fit(self):
        self.assertIsNone(springfit.fit([0, 1, 2], [5, 5, 5]))


class ThresholdTests(unittest.TestCase):
    def test_thresholds_classify_known_inputs(self):
        self.assertLessEqual(3.9, metrics.THRESHOLDS["mad"])
        self.assertGreater(4.1, metrics.THRESHOLDS["mad"])
        self.assertEqual(metrics.THRESHOLDS["time_ms"], 17.0)


class OnsetAlignmentTests(unittest.TestCase):
    def _series(self, shift, count=60):
        native = {key: [10.0] * count for key in align.KEYS}
        native["width"] = [float(i) for i in range(count)]
        flutter = {key: [10.0] * count for key in align.KEYS}
        flutter["width"] = [float(i + shift) for i in range(count)]
        return native, flutter

    def test_recovers_a_positive_offset_within_one_frame(self):
        native, flutter = self._series(5)
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - 5), 1)

    def test_recovers_a_negative_offset_within_one_frame(self):
        native, flutter = self._series(-7)
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - -7), 1)


class JointAlignmentTests(unittest.TestCase):
    def test_aligns_all_moving_series_together(self):
        count = 80
        native = {key: [10.0] * count for key in align.KEYS}
        flutter = {key: [10.0] * count for key in align.KEYS}
        native["width"] = [float(i * 2) for i in range(count)]
        flutter["width"] = [float((i + 6) * 2) for i in range(count)]
        native["height"] = [float(i * 5) for i in range(count)]
        flutter["height"] = [float((i + 6) * 5) for i in range(count)]
        self.assertLessEqual(abs(analyze.best_lag(native, flutter) - 6), 1)

    def test_no_moving_series_means_no_lag(self):
        flat = {key: [10.0] * 30 for key in align.KEYS}
        self.assertEqual(analyze.best_lag(flat, flat), 0)


class SpringOnFullEventTests(unittest.TestCase):
    def test_springs_are_fitted_on_each_full_event_not_the_aligned_overlap(self):
        times = np.arange(0, 1.2, 1 / 120)
        curve = [10.0] + list(10 + 90 * springfit.step_response(times, 0.4, 0.7))
        native = {key: [10.0] * len(curve) for key in align.KEYS}
        flutter = {key: [10.0] * len(curve) for key in align.KEYS}
        native["width"], flutter["width"] = list(curve), list(curve)
        native["height"] = [float(i) for i in range(len(curve))]
        flutter["height"] = [float(i + 16) for i in range(len(curve))]
        result = analyze.compare_motion({"events": [{"series": native}]}, {"events": [{"series": flutter}]})
        event = result["events"][0]
        self.assertNotEqual(event["lag_ms"], 0)
        self.assertEqual(event["width"]["response_pct"], 0.0)
        self.assertEqual(event["width"]["damping"], 0.0)


class MotionCheckTests(unittest.TestCase):
    def test_no_native_motion_fails_even_when_counts_match(self):
        checks = analyze.motion_checks({"event_count": [0, 0], "events": []})
        self.assertTrue(checks["events.count"])
        self.assertFalse(checks["events.native_motion"])

    def test_native_motion_passes_when_present(self):
        checks = analyze.motion_checks({"event_count": [2, 2], "events": []})
        self.assertTrue(checks["events.native_motion"])
        self.assertTrue(checks["events.count"])


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_metrics.py`
Expected: errors, `AttributeError: module 'metrics' has no attribute 'rim_sides'`.

- [ ] **Step 2: Replace** `tool/glass_lab/harness/metrics.py` with:

```python
from collections import deque

import numpy as np
from PIL import Image

SCALE = 3
SCREEN = (402, 874)
LAYER_FRACTION = 0.5
THRESHOLDS = {
    "mad": 4.0,
    "luminance": 3.0,
    "rim_rms": 6.0,
    "bbox_pt": 1.0,
    "centre_pt": 1.0,
    "time_ms": 17.0,
    "overshoot_pct": 2.0,
    "response_pct": 5.0,
    "damping": 0.05,
}


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)


def luma(image):
    return image[..., 0] * 0.2126 + image[..., 1] * 0.7152 + image[..., 2] * 0.0722


def crop(image, rect):
    x, y, w, h = (int(round(v * SCALE)) for v in rect)
    return image[y : y + h, x : x + w]


def mad(a, b):
    return float(np.mean(np.abs(a - b)))


def _components(mask):
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        seen[y, x] = True
        queue = deque([(y, x)])
        top, left, bottom, right, area = y, x, y, x, 0
        while queue:
            cy, cx = queue.popleft()
            area += 1
            top, bottom, left, right = min(top, cy), max(bottom, cy), min(left, cx), max(right, cx)
            for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        found.append((area, (int(left), int(top), int(right - left + 1), int(bottom - top + 1))))
    found.sort(key=lambda item: -item[0])
    return found


def glass_boxes(frame, bare, threshold=6.0, min_area=40, scale=SCALE):
    difference = np.abs(frame - bare).max(axis=2)
    height, width = difference.shape
    grid = difference[: height // scale * scale, : width // scale * scale]
    grid = grid.reshape(height // scale, scale, width // scale, scale).mean(axis=(1, 3))
    return [box for area, box in _components(grid > threshold) if area >= min_area]


def union(boxes, pad=0, bounds=SCREEN):
    if not boxes:
        return None
    left = max(0, min(b[0] for b in boxes) - pad)
    top = max(0, min(b[1] for b in boxes) - pad)
    right = min(bounds[0], max(b[0] + b[2] for b in boxes) + pad)
    bottom = min(bounds[1], max(b[1] + b[3] for b in boxes) + pad)
    return (left, top, right - left, bottom - top)


def rim_profile(frame, box, reach=12):
    x, y, w, h = box
    column = int(round((x + w / 2) * SCALE))
    lum = luma(frame)[:, column]
    limit = lum.shape[0]
    top = int(round(y * SCALE))
    bottom = int(round((y + h) * SCALE))
    span = reach * SCALE
    pieces = [lum[max(0, top - span) : min(limit, top + span)], lum[max(0, bottom - span) : min(limit, bottom + span)]]
    return np.concatenate(pieces)


RIM_SIDES = ("top", "bottom", "left", "right")


def rim_sides(frame, box, reach=12):
    x, y, w, h = box
    lum = luma(frame)
    height, width = lum.shape
    span = reach * SCALE
    column = min(width - 1, int(round((x + w / 2) * SCALE)))
    row = min(height - 1, int(round((y + h / 2) * SCALE)))
    top, bottom = int(round(y * SCALE)), int(round((y + h) * SCALE))
    left, right = int(round(x * SCALE)), int(round((x + w) * SCALE))
    return {
        "top": lum[max(0, top - span) : min(height, top + span), column],
        "bottom": lum[max(0, bottom - span) : min(height, bottom + span), column],
        "left": lum[row, max(0, left - span) : min(width, left + span)],
        "right": lum[row, max(0, right - span) : min(width, right + span)],
    }


def element_rim(native, flutter, box):
    a, b = rim_sides(native, box), rim_sides(flutter, box)
    sides = {side: float(np.sqrt(np.mean((a[side] - b[side]) ** 2))) for side in RIM_SIDES}
    joined = np.concatenate([a[side] - b[side] for side in RIM_SIDES])
    return {"rms": float(np.sqrt(np.mean(joined**2))), "sides": sides}


def box_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[0] + a[2] - b[0] - b[2]), abs(a[1] + a[3] - b[1] - b[3])))


def overlaps(a, b, slack=4):
    return not (
        a[0] + a[2] + slack <= b[0]
        or b[0] + b[2] + slack <= a[0]
        or a[1] + a[3] + slack <= b[1]
        or b[1] + b[3] + slack <= a[1]
    )


def matching(boxes, target):
    hits = [box for box in boxes if overlaps(box, target)]
    if not hits:
        return None
    left, top = min(b[0] for b in hits), min(b[1] for b in hits)
    right, bottom = max(b[0] + b[2] for b in hits), max(b[1] + b[3] for b in hits)
    return (left, top, right - left, bottom - top)


def centre_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] + a[2] / 2 - b[0] - b[2] / 2), abs(a[1] + a[3] / 2 - b[1] - b[3] / 2)))


def static_compare(native, flutter, native_bare, flutter_bare, region, elements=None):
    native_region, flutter_region = crop(native, region), crop(flutter, region)
    native_boxes = glass_boxes(native_region, crop(native_bare, region))
    flutter_boxes = glass_boxes(flutter_region, crop(flutter_bare, region))
    offset = lambda boxes: [(b[0] + region[0], b[1] + region[1], b[2], b[3]) for b in boxes]
    native_all, flutter_all = offset(native_boxes), offset(flutter_boxes)
    native_main = native_all[0] if native_all else None
    if native_main is None:
        flutter_main = flutter_all[0] if flutter_all else None
    else:
        flutter_main = matching(flutter_all, native_main)
        if flutter_main is not None and flutter_main[2] * flutter_main[3] < LAYER_FRACTION * SCREEN[0] * SCREEN[1]:
            native_main = matching(native_all, flutter_main)
    result = {
        "mad": mad(native_region, flutter_region),
        "luminance": abs(float(luma(native_region).mean() - luma(flutter_region).mean())),
        "native_box": native_main,
        "flutter_box": flutter_main,
        "bbox_pt": box_delta(native_main, flutter_main),
        "centre_pt": centre_delta(native_main, flutter_main),
    }
    if native_main is not None:
        a = rim_profile(native, native_main)
        b = rim_profile(flutter, native_main)
        size = min(len(a), len(b))
        result["rim_native"] = a[:size].tolist()
        result["rim_flutter"] = b[:size].tolist()
        result["rim_rms"] = float(np.sqrt(np.mean((a[:size] - b[:size]) ** 2)))
    else:
        result["rim_rms"] = float("inf")
    if elements:
        result["rim_legacy"] = result["rim_rms"]
        result["rim_elements"] = {name: element_rim(native, flutter, box) for name, box in elements.items()}
        worst = max(entry["rms"] for entry in result["rim_elements"].values())
        result["rim_rms"] = max(result["rim_rms"], worst)
    result["pass"] = {key: result[key] <= THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")}
    return result
```

- [ ] **Step 3: Replace** `tool/glass_lab/harness/analyze.py` with:

```python
import json
import re
import subprocess
from pathlib import Path

import numpy as np

import align
import metrics
import springfit

OVERVIEW_FPS = 20
MATCH_MARGIN = 6.0
TILE = 24
SKIP_TOP_TILES = 3
LEAD_SECONDS = 0.2
MAX_LAG_MS = 150
MIN_TRAVEL = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 3.0}
PTS = re.compile(r"pts_time:([0-9.]+)")


def _crop_filter(region, downscale):
    x, y, w, h = (int(round(v * metrics.SCALE)) for v in region)
    size = f",scale={max(1, w // metrics.SCALE)}:{max(1, h // metrics.SCALE)}" if downscale else ""
    return f"crop={w}:{h}:{x}:{y}{size}"


def _clean(dest):
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob("*.png"):
        old.unlink()
    return dest


def overview(video, dest):
    dest = _clean(dest)
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", str(video), "-vf", f"fps={OVERVIEW_FPS},{_crop_filter((0, 0, *metrics.SCREEN), True)}", str(dest / "%06d.png")],
        check=True,
    )
    paths = sorted(dest.glob("*.png"))
    return align.Frames(paths, [i / OVERVIEW_FPS for i in range(len(paths))])


def frames(video, start, end, region, dest):
    dest = _clean(dest)
    process = subprocess.run(
        [
            "ffmpeg", "-loglevel", "info", "-y", "-copyts",
            "-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", str(video),
            "-fps_mode", "passthrough",
            "-vf", f"{_crop_filter(region, True)},showinfo",
            str(dest / "%06d.png"),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    times = [float(t) for t in PTS.findall(process.stderr)]
    paths = sorted(dest.glob("*.png"))
    count = min(len(paths), len(times))
    return align.Frames(paths[:count], times[:count])


def shrink(image):
    height, width = image.shape[0] // metrics.SCALE, image.shape[1] // metrics.SCALE
    trimmed = image[: height * metrics.SCALE, : width * metrics.SCALE]
    return trimmed.reshape(height, metrics.SCALE, width, metrics.SCALE, 3).mean(axis=(1, 3))


def tile_difference(a, b):
    difference = np.abs(a - b).mean(axis=2)
    height, width = difference.shape[0] // TILE * TILE, difference.shape[1] // TILE * TILE
    tiles = difference[:height, :width].reshape(height // TILE, TILE, width // TILE, TILE).mean(axis=(1, 3))
    return float(tiles[SKIP_TOP_TILES:].max())


def window(case_dir):
    view = overview(case_dir / "video.mp4", case_dir / "overview")
    ready = shrink(metrics.load(case_dir / "ready.png"))
    settled = shrink(metrics.load(case_dir / "settled.png"))
    to_ready = [tile_difference(frame, ready) for frame in view]
    to_settled = [tile_difference(frame, settled) for frame in view]
    if not to_ready:
        return None
    ready_limit = min(to_ready) + MATCH_MARGIN
    settled_limit = min(to_settled) + MATCH_MARGIN
    first = next((i for i, d in enumerate(to_ready) if d <= ready_limit), 0)
    leave = next((i for i in range(first, len(to_ready)) if to_ready[i] > ready_limit), None)
    last = max((i for i, d in enumerate(to_settled) if d <= settled_limit), default=len(view) - 1)
    if leave is None or last <= leave:
        return None
    start = max(0, leave - 4)
    chosen = align.Frames(view.paths[start : last + 1], view.times[start : last + 1])
    return start / OVERVIEW_FPS, (last + 1) / OVERVIEW_FPS, chosen


def region_for(scene, case_dir):
    if scene.track:
        return tuple(scene.regions[scene.track])
    bare = metrics.load(case_dir / "bare" / "ready.png")
    boxes = metrics.glass_boxes(metrics.load(case_dir / "ready.png"), bare)
    boxes += metrics.glass_boxes(metrics.load(case_dir / "settled.png"), bare)
    if not scene.rest and (case_dir / "video.mp4").exists():
        found = window(case_dir)
        if found:
            boxes += align.extent(found[2])
    boxes = [box for box in boxes if box[1] + box[3] > align.SKIP_TOP_POINTS]
    return metrics.union(boxes, pad=12) or (0, 0, *metrics.SCREEN)


def elements_for(scene):
    return {name: tuple(rect) for name, rect in scene.regions.items() if name != scene.track}


def motion(case_dir, region):
    found = window(case_dir)
    if found is None:
        return {"events": [], "stalls": []}
    start, end, _ = found
    crops = frames(case_dir / "video.mp4", max(0.0, start - LEAD_SECONDS), end, region, case_dir / "frames")
    if len(crops) < 2:
        return {"events": [], "stalls": []}
    bare_path = case_dir / "bare" / "ready.png"
    bare = shrink(metrics.crop(metrics.load(bare_path), region)) if bare_path.exists() else crops[0]
    diffs = align.differences(crops)
    found_events = []
    for first, last in align.events(diffs, crops.times):
        series = align.event_series(crops, first, last, bare)
        if align.significant(series):
            found_events.append({"start": crops.times[first], "series": series})
    return {"events": found_events, "stalls": align.stalls(diffs, crops.times), "first_time": crops.times[0]}


def compare_series(key, a, b, a_full, b_full):
    entry = {"rms": float(np.sqrt(np.mean((a - b) ** 2))), "native": a.tolist(), "flutter": b.tolist()}
    if abs(a_full[-1] - a_full[0]) < MIN_TRAVEL[key] or abs(b_full[-1] - b_full[0]) < MIN_TRAVEL[key]:
        return entry
    a_times = np.arange(len(a_full)) / align.GRID_HZ
    b_times = np.arange(len(b_full)) / align.GRID_HZ
    fa, fb = springfit.features(a_times, a_full), springfit.features(b_times, b_full)
    if fa and fb:
        entry["peak_ms"] = abs(fa["peak_ms"] - fb["peak_ms"])
        entry["settle_ms"] = abs(fa["settle_ms"] - fb["settle_ms"])
        entry["overshoot_pct"] = abs(fa["overshoot_pct"] - fb["overshoot_pct"])
    sa, sb = springfit.fit(a_times, a_full), springfit.fit(b_times, b_full)
    if sa and sb and sa["rms"] < 0.15 and sb["rms"] < 0.15:
        entry["native_spring"], entry["flutter_spring"] = sa, sb
        entry["response_pct"] = abs(sa["response"] - sb["response"]) / sa["response"] * 100
        entry["damping"] = abs(sa["damping"] - sb["damping"])
    return entry


def best_lag(a_series, b_series):
    limit = int(MAX_LAG_MS / 1000 * align.GRID_HZ)
    moving = [key for key in align.KEYS if np.ptp(np.array(a_series[key])) >= MIN_TRAVEL[key]]
    if not moving:
        return 0
    series = [(np.array(a_series[key]) / np.ptp(a_series[key]), np.array(b_series[key]) / np.ptp(a_series[key])) for key in moving]
    best, chosen = float("inf"), 0
    for lag in range(-limit, limit + 1):
        error = 0.0
        for a, b in series:
            x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
            count = min(len(x), len(y))
            if count < 3:
                break
            error += float(np.mean((x[:count] - y[:count]) ** 2))
        else:
            if error < best:
                best, chosen = error, lag
    return chosen


def compare_motion(native, flutter):
    result = {"event_count": [len(native["events"]), len(flutter["events"])], "events": []}
    for native_event, flutter_event in zip(native["events"], flutter["events"]):
        a_series, b_series = native_event["series"], flutter_event["series"]
        lag = best_lag(a_series, b_series)
        event = {"lag_ms": lag * 1000 / align.GRID_HZ}
        for key in align.KEYS:
            a_full, b_full = np.array(a_series[key]), np.array(b_series[key])
            a, b = (a_full[lag:], b_full) if lag >= 0 else (a_full, b_full[-lag:])
            count = min(len(a), len(b))
            if count < 3:
                continue
            event[key] = compare_series(key, a[:count], b[:count], a_full, b_full)
        result["events"].append(event)
    return result


NOISE_FACTOR = 1.5
LIMITS = (("peak_ms", "time_ms"), ("settle_ms", "time_ms"), ("overshoot_pct", "overshoot_pct"), ("response_pct", "response_pct"), ("damping", "damping"))


def motion_measures(result):
    measures = {}
    for number, event in enumerate(result["events"]):
        for key in align.KEYS:
            for measure, limit in LIMITS:
                if key in event and measure in event[key]:
                    measures[f"event{number}.{key}.{measure}"] = (event[key][measure], limit)
    return measures


def motion_limits(result, noise=None):
    noise = noise or {}
    native, flutter = result["event_count"]
    limits = {"events.count": (abs(native - flutter), 0, "max"), "events.native_motion": (native, 1, "min")}
    for name, (value, limit) in motion_measures(result).items():
        limits[name] = (value, max(metrics.THRESHOLDS[limit], NOISE_FACTOR * noise.get(name, 0.0)), "max")
    return limits


def within(value, limit, bound):
    return value >= limit if bound == "min" else value <= limit


def motion_checks(result, noise=None):
    return {name: within(*entry) for name, entry in motion_limits(result, noise).items()}


def analyze(scene, case_dir, noise=None):
    case_dir = Path(case_dir)
    native_dir, flutter_dir = case_dir / "native", case_dir / "flutter"
    result = {"scene": scene.id, "case": case_dir.name}
    if scene.native_only:
        native = motion(native_dir, (0, 0, *metrics.SCREEN)) if not scene.rest else {"events": []}
        result.update(kind="reference", native_events=[{"start": e["start"], "series": e["series"]} for e in native["events"]])
        return result
    region = region_for(scene, native_dir)
    result["region"] = region
    flutter_timing = json.loads((flutter_dir / "timing.json").read_text()) if (flutter_dir / "timing.json").exists() else None
    if flutter_timing is None or flutter_timing.get("missing"):
        result["kind"] = "missing"
        return result
    result["kind"] = "compared"
    result["static"] = {}
    for name in ("ready", "settled"):
        result["static"][name] = metrics.static_compare(
            metrics.load(native_dir / f"{name}.png"),
            metrics.load(flutter_dir / f"{name}.png"),
            metrics.load(native_dir / "bare" / "ready.png"),
            metrics.load(flutter_dir / "bare" / "ready.png"),
            region,
            elements_for(scene),
        )
    checks = {f"{name}.{key}": value for name, stat in result["static"].items() for key, value in stat["pass"].items() if key in scene.measures}
    measures = {f"{name}.{key}": (stat[key], metrics.THRESHOLDS[key], "max") for name, stat in result["static"].items() for key in stat["pass"] if key in scene.measures}
    if not scene.rest:
        native, flutter = motion(native_dir, region), motion(flutter_dir, region)
        result["motion"] = compare_motion(native, flutter)
        result["native_stalls"] = native["stalls"]
        result["flutter_stalls"] = flutter["stalls"]
        limits = motion_limits(result["motion"], noise)
        measures.update({f"motion.{k}": v for k, v in limits.items()})
        checks.update({f"motion.{k}": within(*v) for k, v in limits.items()})
    result["checks"] = checks
    result["measures"] = measures
    result["pass"] = bool(checks) and all(checks.values())
    return result
```

The only changes are `elements_for` and the `elements_for(scene)` argument in `analyze`.

- [ ] **Step 4: Run the tests**

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_metrics.py`
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tool/glass_lab/harness/metrics.py tool/glass_lab/harness/analyze.py tool/glass_lab/harness/tests/test_metrics.py
git commit -m "feat(mobile): glass lab measures the rim on all four sides of every pinned glass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `tune` can see the shadow tail, cannot run on a stale build, and cannot rewrite what it did not search (findings 3, 8a, 8c, 8d, 8f)

**Files:**
- Create: `tool/glass_lab/harness/tonefit.py`, `tool/glass_lab/harness/tests/test_tonefit.py`
- Modify: `tool/glass_lab/harness/build.py`, `tool/glass_lab/harness/tune.py`, `tool/glass_lab/harness/lab.py`, `tool/glass_lab/harness/record.py`, `tool/glass_lab/harness/report.py`, `tool/glass_lab/harness/probe.py`
- Test: `tool/glass_lab/harness/tests/test_tune.py`, `tool/glass_lab/harness/tests/test_lab.py`, `tool/glass_lab/harness/tests/test_record.py`, `tool/glass_lab/harness/tests/test_report.py`, `tool/glass_lab/harness/tests/test_probe.py`

**Interfaces:**
- Produces:
  - **Build stamps.** `build.SOURCES` (`example`: the package `lib/` and `example/lib/`; `operator`: the package `lib/` and the app `lib/`), `build.STAMPS` (`build/glass_lab/example/sources.sha256`, `build/glass_lab/flutter/sources.sha256`), `build.sources_hash(roots)`, `build.stamp(target, digest, stamps=None)` and `build.require_fresh(target, sources=None, stamps=None)`, which raises `SystemExit` naming `lab.py build <target>` when the app on the simulator was built from other sources. `build.example` and `build.flutter` hash the sources before building and stamp them after.
  - **Guards.** `tune.run` and `lab.py run` (when a Flutter app is captured) and `lab.py perf` call `require_fresh` before touching the simulator.
  - **Ranges.** `tune.RANGES` now covers the shader's whole domain: tone points −0.5–2.0, `specular` and `sheen` from −1, alphas (`tintAmount`, `shadowOpacity`, `outline`, `outlineTop`, and the edge `dim`, `knee`, `cap`, `line`, `lineShade`) 0–1, widths and blurs from 0, `refractiveIndex` from 1, `shadowOffsetY` unbounded. `coordinate_descent` evaluates the start exactly as given, so the first candidate is always the committed row; only grid and refinement candidates are clamped.
  - **Padding.** `tune.named_region(scene, names, pad=PAD)`, `Evaluator(..., pad=PAD)`, `tune.run(..., pad=PAD)` and `lab.py tune --pad N` (default 12). Shadow steps use `--pad 60`, which reaches native's tail (0 by about 48 pt below the 200 pt glass).
  - **Elements.** The evaluator scores the rim on the named regions' exact edges (`Evaluator.elements()`, Task 1's `elements`), and `log.jsonl` records each backdrop's `rim_sides`.
  - **Anchor scope.** `record.write_launch_file(..., material=None, material_side=None)` and `record.drive(..., material_side=None)` write `"materialSide"` next to `"material"`; the evaluator sends its `--size` for material tables and nothing for the scroll edge table. Task 6 makes the example app apply the overrides only to glass at that anchor, so a 200 pt candidate no longer repaints the 44 and 88 pt glass inside a padded region.
  - **Rows.** `lab.tune_row(a11y, row)`: `--a11y reduce-transparency` means `--row reduceTransparency`, `--a11y increase-contrast` means `--row increaseContrast`, no `--a11y` means `regular` unless `--row` says otherwise; any other pairing exits with an error. `--row` has no default any more.
  - `lab.py perf` gains `--scenes a,b` (default: every scene in `probe.PERF_SCENES`, now `perf.none`, `perf.glass`, `perf.material` and `perf.edge`) and `--a11y MODE`; `probe.perf(udid, bundle, takes=3, scenes=PERF_SCENES)` and `perf_summary` reports `<scene>_cost_ms` over `perf.none` for every scene. The two new scenes arrive in Task 6, so `lab.py perf` first runs in Task 6 Step 8.
  - **No back link.** `record.close_other_apps(udid, target)` terminates every other lab app before each capture. In the prototype, a native reference captured while the example app was still running showed iOS's "◀ Ios Liquid Glass E…" back link under the clock, and scored soft light MAD 5.49 instead of 4.21 (`20260930-193136` against `20260930-193453`).
  - **Tone fit.** `tonefit.run_fit(run_dir, scene, a11y="none")` and `lab.py tonefit <run> [--scene material.regular] [--a11y MODE]`: for each appearance and pinned region, the mean luma of native's glass interior against its bare backdrop on every backdrop the run has, fitted to the shader's three-point curve (`toneBlack`, `toneMid`, `toneWhite`) by least squares, with the worst residual in luma. It reads only native captures. Frost preserves the mean and the tone curve acts on luma alone (the chroma term has zero luma), so the fit gives the tone points directly; on 2A's run it reproduces 2A's tuned dark rows within 0.01 and shows why light glass over `photo` was dark: 2A's light rows (`toneMid 0.725`, `toneWhite 1.19`, tuned on three backdrops) against native's `0.797` and `0.997` at 200 pt.
  - **Run metadata.** `lab.py run` writes `run.json` (`{"flutter": ..., "a11y": ...}`) into the run folder, and `report.markdown` names the Flutter target from it ("against the ios_liquid_glass example app"); 2A's summaries said "Operator's Flutter glass" for example-app runs (code review, docs item 10).
- Why the stamp covers all of `lib/` and not only the two tables: the edge scenes' "Edit" button, the other sizes in `material.regular`, and every shader change all come from the build, not from the launch file. A stale build was the cause of code review bug 1.

- [ ] **Step 1: Write the failing tests.** Replace `tool/glass_lab/harness/tests/test_tune.py`, `test_lab.py`, `test_record.py`, `test_report.py` and `test_probe.py`, and create `test_tonefit.py`, all in `tool/glass_lab/harness/tests/`:

```python
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import material_table
import tune


def scene(scene_id, **extra):
    entry = {
        "id": scene_id,
        "group": "material",
        "title": "t",
        "inventory": "2.1",
        "app": "lab",
        "backdrops": ["stripes"],
        "appearances": ["dark"],
        "steps": [],
        **extra,
    }
    return manifest.parse([entry])[0]


class ScoreTests(unittest.TestCase):
    def test_perfect_match_scores_zero(self):
        self.assertEqual(tune.score({"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}), 0)

    def test_each_measure_is_capped(self):
        worst = {"mad": 1e9, "luminance": 1e9, "rim_rms": 1e9, "centre_pt": float("inf"), "bbox_pt": 1e9}
        self.assertEqual(tune.score(worst), 5 * tune.CAP)

    def test_threshold_values_score_one_each(self):
        self.assertAlmostEqual(tune.score({"mad": 4, "luminance": 3, "rim_rms": 6, "centre_pt": 1, "bbox_pt": 1}), 5)

    def test_scores_only_the_scene_measures(self):
        stat = {"mad": 8, "luminance": 3, "rim_rms": 1e9, "centre_pt": 1e9, "bbox_pt": 1e9}
        self.assertAlmostEqual(tune.score(stat, ("mad", "luminance")), 3)


class ParamTests(unittest.TestCase):
    def test_parses_ranges(self):
        grid = tune.parse_params("toneBlack=0:0.4:5,toneWhite=0.5:1:2")
        self.assertEqual(grid["toneBlack"], [0.0, 0.1, 0.2, 0.3, 0.4])
        self.assertEqual(grid["toneWhite"], [0.5, 1.0])

    def test_parses_scroll_edge_names(self):
        self.assertEqual(tune.parse_params("edge.blur=2:6:3"), {"edge.blur": [2.0, 4.0, 6.0]})
        self.assertEqual(tune.field("edge.blur"), "blur")
        self.assertEqual(tune.field("toneBlack"), "toneBlack")


class DescentTests(unittest.TestCase):
    def test_finds_the_optimum_of_a_separable_bowl(self):
        target = {"toneBlack": 0.2, "toneWhite": 0.7}
        evaluate = lambda m: (m["toneBlack"] - target["toneBlack"]) ** 2 + (m["toneWhite"] - target["toneWhite"]) ** 2
        grid = tune.parse_params("toneBlack=0:0.4:5,toneWhite=0.5:1:6")
        best, value, log = tune.coordinate_descent(evaluate, grid, {"toneBlack": 0.0, "toneWhite": 1.0})
        self.assertAlmostEqual(best["toneBlack"], 0.2)
        self.assertAlmostEqual(best["toneWhite"], 0.7)
        self.assertLess(value, 1e-9)
        self.assertGreater(len(log), 1)

    def test_start_is_kept_when_nothing_is_better(self):
        best, value, _ = tune.coordinate_descent(lambda m: abs(m["toneBlack"] - 0.1), {"toneBlack": [0.0, 0.1, 0.2]}, {"toneBlack": 0.1})
        self.assertEqual(best, {"toneBlack": 0.1})
        self.assertEqual(value, 0)


class ClampTests(unittest.TestCase):
    def test_refinement_never_evaluates_below_the_floor_when_the_optimum_sits_there(self):
        seen = []

        def evaluate(material):
            seen.append(material["outline"])
            return abs(material["outline"])

        grid = tune.parse_params("outline=0:0.4:5")
        tune.coordinate_descent(evaluate, grid, {"outline": 0.2})
        self.assertTrue(all(value >= 0.0 for value in seen))

    def test_the_start_is_evaluated_as_committed_even_outside_the_range(self):
        seen = []

        def evaluate(material):
            seen.append(dict(material))
            return abs(material["outline"] - 1.05)

        grid = tune.parse_params("outline=0.6:1.4:5")
        best, _, _ = tune.coordinate_descent(evaluate, grid, {"outline": 1.05})
        self.assertEqual(seen[0], {"outline": 1.05})
        self.assertEqual(best, {"outline": 1.05})
        self.assertTrue(all(entry["outline"] <= 1.0 for entry in seen[1:]))

    def test_the_ranges_cover_the_shader_domain(self):
        self.assertEqual(tune.clamp("specular", -0.1), -0.1)
        self.assertEqual(tune.clamp("toneBlack", -0.0688), -0.0688)
        self.assertEqual(tune.clamp("toneWhite", 1.4084), 1.4084)
        self.assertEqual(tune.clamp("shadowOffsetY", -3.0), -3.0)

    def test_an_edge_prefixed_field_is_clamped_by_its_field_range(self):
        self.assertEqual(tune.clamp("edge.dim", 1.2833), 1.0)
        self.assertEqual(tune.clamp("outline", -0.5), 0.0)


class ElementTests(unittest.TestCase):
    def test_picks_the_box_whose_shorter_side_is_closest(self):
        boxes = [(4, 455, 395, 236), (75, 329, 252, 97), (125, 237, 152, 44)]
        self.assertEqual(tune.element_box(boxes, 44), (125, 237, 152, 44))
        self.assertEqual(tune.element_box(boxes, 88), (75, 329, 252, 97))
        self.assertEqual(tune.element_box(boxes, 200), (4, 455, 395, 236))

    def test_named_regions_are_unioned_and_padded(self):
        tinted = scene("material.tinted", regions={"block": [76, 365, 250, 88], "run": [162, 501, 78, 37]})
        self.assertEqual(tune.named_region(tinted, ["block"]), (64, 353, 274, 112))
        self.assertEqual(tune.named_region(tinted, ["block", "run"]), (64, 353, 274, 197))

    def test_a_wider_pad_reaches_the_shadow_tail_and_stops_at_the_screen(self):
        regular = scene("material.regular", regions={"s200": [21, 465, 360, 200]})
        self.assertEqual(tune.named_region(regular, ["s200"], pad=60), (0, 405, 402, 320))

    def test_keys_material_rows_by_row_and_size_and_edges_by_style(self):
        self.assertEqual(tune.table_key(scene("material.regular"), "dark", "regular", 88), "dark.regular.88")
        edge = scene("material.edge.hard", regions={"edge": [0, 0, 402, 240]}, track="edge")
        self.assertEqual(tune.table_key(edge, "light", "regular", 88), "light.hard")


class FilmstripTests(unittest.TestCase):
    def test_writes_native_candidate_and_difference_side_by_side(self):
        native = np.zeros((30, 30, 3), dtype=np.float32)
        flutter = np.full((30, 30, 3), 10, dtype=np.float32)
        with tempfile.TemporaryDirectory() as temp:
            dest = Path(temp) / "best.png"
            tune.filmstrip(native, flutter, (0, 0, 10, 10), dest)
            image = np.asarray(Image.open(dest))
        self.assertEqual(image.shape, (30, 90, 3))
        self.assertEqual(int(image[0, 75, 0]), 40)


class EvaluatorTests(unittest.TestCase):
    def _evaluator(self, scene_obj, row_overrides):
        with tempfile.TemporaryDirectory() as out:
            evaluate = tune.Evaluator("udid", scene_obj, ["stripes"], 88, "example", out, row_overrides=row_overrides)
            image = np.zeros((3, 3, 3), dtype=np.float32)
            evaluate.references = lambda backdrop: (image, image, image, (0, 0, 3, 3))
            yield evaluate

    def test_sends_the_whole_material_row_merged_with_the_candidate(self):
        row = {"toneBlack": 0.1, "toneWhite": 0.8}
        for evaluate in self._evaluator(scene("material.regular"), row):
            sent = []
            with mock.patch.object(tune.record, "drive", side_effect=lambda *a, **k: sent.append(k.get("material"))), \
                 mock.patch.object(tune.metrics, "load", return_value=np.zeros((3, 3, 3), dtype=np.float32)), \
                 mock.patch.object(tune.metrics, "static_compare", return_value={"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}):
                evaluate({"toneBlack": 0.3})
            self.assertEqual(sent, [{"toneBlack": 0.3, "toneWhite": 0.8}])
            self.assertEqual(evaluate.records[-1]["material"], {"toneBlack": 0.3})

    def test_material_candidates_reach_only_the_tuned_anchor_and_edge_candidates_every_glass(self):
        for scene_obj, expected in ((scene("material.regular"), 88), (scene("material.edge.hard", regions={"edge": [0, 0, 402, 240]}, track="edge"), None)):
            for evaluate in self._evaluator(scene_obj, {}):
                sides = []
                with mock.patch.object(tune.record, "drive", side_effect=lambda *a, **k: sides.append(k.get("material_side"))), \
                     mock.patch.object(tune.metrics, "load", return_value=np.zeros((3, 3, 3), dtype=np.float32)), \
                     mock.patch.object(tune.metrics, "static_compare", return_value={"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}):
                    evaluate({"toneBlack": 0.3})
                self.assertEqual(sides, [expected])

    def test_sends_the_whole_scroll_edge_row_merged_with_the_candidate(self):
        edge = scene("material.edge.hard", regions={"edge": [0, 0, 402, 240]}, track="edge")
        row_overrides = {material_table.EDGE_PREFIX + "blur": 4.0, material_table.EDGE_PREFIX + "dim": 0.6}
        for evaluate in self._evaluator(edge, row_overrides):
            sent = []
            with mock.patch.object(tune.record, "drive", side_effect=lambda *a, **k: sent.append(k.get("material"))), \
                 mock.patch.object(tune.metrics, "load", return_value=np.zeros((3, 3, 3), dtype=np.float32)), \
                 mock.patch.object(tune.metrics, "static_compare", return_value={"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}):
                evaluate({material_table.EDGE_PREFIX + "blur": 5.0})
            self.assertEqual(sent, [{material_table.EDGE_PREFIX + "blur": 5.0, material_table.EDGE_PREFIX + "dim": 0.6}])
            self.assertEqual(evaluate.records[-1]["material"], {material_table.EDGE_PREFIX + "blur": 5.0})


class EvaluatorElementTests(unittest.TestCase):
    def test_scores_the_rim_at_the_named_elements_exact_edges(self):
        regular = scene("material.regular", regions={"s88": [76, 329, 250, 88]})
        with tempfile.TemporaryDirectory() as out:
            evaluate = tune.Evaluator("udid", regular, ["black"], 88, "example", out, regions=["s88"], pad=60)
            image = np.zeros((3, 3, 3), dtype=np.float32)
            evaluate.references = lambda backdrop: (image, image, image, (16, 269, 370, 208))
            calls = []
            stat = {"mad": 0, "luminance": 0, "rim_rms": 0, "centre_pt": 0, "bbox_pt": 0}
            with mock.patch.object(tune.record, "drive"), \
                 mock.patch.object(tune.metrics, "load", return_value=image), \
                 mock.patch.object(tune.metrics, "static_compare", side_effect=lambda *a: calls.append(a) or stat):
                evaluate({"toneBlack": 0.1})
        self.assertEqual(calls[0][5], {"s88": (76, 329, 250, 88)})


class FreshBuildTests(unittest.TestCase):
    def test_refuses_a_build_older_than_its_sources_and_accepts_a_fresh_one(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "lib"
            root.mkdir()
            (root / "ios27.dart").write_text("a")
            sources = {"example": (root,)}
            stamps = {"example": Path(temp) / "out" / "sources.sha256"}
            with self.assertRaises(SystemExit):
                tune.build.require_fresh("example", sources, stamps)
            tune.build.stamp("example", tune.build.sources_hash(sources["example"]), stamps)
            tune.build.require_fresh("example", sources, stamps)
            (root / "ios27.dart").write_text("b")
            with self.assertRaises(SystemExit):
                tune.build.require_fresh("example", sources, stamps)


class TableTests(unittest.TestCase):
    def test_round_trip_and_update(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ios27.dart"
            table = {"dark.regular.44": {"toneBlack": 0.1, "toneWhite": 0.75}, "light.clear.200": {"frost": 1.5}}
            material_table.write(table, path)
            self.assertEqual(material_table.read(path), table)
            material_table.update("dark.regular.44", {"toneBlack": 0.25}, path)
            self.assertEqual(material_table.read(path)["dark.regular.44"], {"toneBlack": 0.25, "toneWhite": 0.75})

    def test_rows_are_ordered_by_appearance_row_and_numeric_anchor(self):
        table = {"light.regular.44": {}, "dark.regular.200": {}, "dark.regular.44": {}, "dark.clear.88": {}}
        keys = [line.split("'")[1] for line in material_table.format_table(table).splitlines()[1:-1]]
        self.assertEqual(keys, ["dark.regular.44", "dark.regular.200", "dark.clear.88", "light.regular.44"])

    def test_scroll_edge_table_round_trips_in_style_order(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "edge.dart"
            rows = {"light.soft": {"blur": 4.0}, "dark.automatic": {"dim": 0.6}, "dark.soft": {"knee": 0.45}}
            material_table.write(rows, path, material_table.SCROLL_EDGE)
            text = path.read_text()
            self.assertTrue(text.startswith("const Map<String, Map<String, double>> ios27ScrollEdgeTable = {"))
            self.assertEqual(material_table.read(path, material_table.SCROLL_EDGE), rows)
            keys = [line.split("'")[1] for line in text.splitlines()[1:-1]]
            self.assertEqual(keys, ["dark.soft", "dark.automatic", "light.soft"])

    def test_scenes_pick_their_table(self):
        self.assertIs(material_table.for_scene("material.edge.soft"), material_table.SCROLL_EDGE)
        self.assertIs(material_table.for_scene("material.regular"), material_table.MATERIAL)

    def test_the_committed_tables_parse_with_every_row(self):
        table = material_table.read()
        self.assertEqual(len(table), 30)
        for appearance in material_table.APPEARANCES:
            for row in material_table.ROWS:
                for anchor in material_table.ANCHORS:
                    self.assertIn(f"{appearance}.{row}.{anchor}", table)
        edges = material_table.read(table=material_table.SCROLL_EDGE)
        self.assertEqual(sorted(edges), sorted(f"{a}.{s}" for a in material_table.APPEARANCES for s in material_table.STYLES))

    def test_the_committed_tables_are_in_writer_format(self):
        for table in (material_table.MATERIAL, material_table.SCROLL_EDGE):
            text = table.path.read_text()
            self.assertEqual(material_table.format_table(material_table.parse(text, table), table), text)


if __name__ == "__main__":
    unittest.main()
```

```python
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import lab


def _tune_args(**overrides):
    args = [
        "tune",
        "--scene", "material.regular",
        "--appearance", "dark",
        "--backdrops", "white",
        "--params", "frost",
    ]
    for key, value in overrides.items():
        args += [f"--{key}", value]
    return args


class TuneRejectsOperatorTests(unittest.TestCase):
    def test_tune_rejects_the_operator_target(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                lab.parser().parse_args(_tune_args(flutter="operator"))

    def test_tune_still_accepts_the_example_target(self):
        args = lab.parser().parse_args(_tune_args(flutter="example"))
        self.assertEqual(args.flutter, "example")


class TuneRowTests(unittest.TestCase):
    def test_the_accessibility_mode_picks_its_row(self):
        self.assertEqual(lab.tune_row("reduce-transparency", None), "reduceTransparency")
        self.assertEqual(lab.tune_row("increase-contrast", None), "increaseContrast")
        self.assertEqual(lab.tune_row("none", None), "regular")
        self.assertEqual(lab.tune_row("none", "tinted"), "tinted")
        self.assertEqual(lab.tune_row("increase-contrast", "increaseContrast"), "increaseContrast")

    def test_a_row_that_the_accessibility_mode_would_not_render_is_rejected(self):
        for a11y, row in (("reduce-transparency", "regular"), ("increase-contrast", "reduceTransparency"), ("none", "increaseContrast")):
            with self.assertRaises(SystemExit):
                lab.tune_row(a11y, row)


class RunFreshnessTests(unittest.TestCase):
    def test_run_refuses_a_stale_flutter_build_before_touching_the_simulator(self):
        args = lab.parser().parse_args(["run", "material.regular", "--app", "both"])
        with mock.patch.object(lab.build, "require_fresh", side_effect=SystemExit("stale")) as fresh, \
             mock.patch.object(lab.sim, "device") as device:
            with self.assertRaises(SystemExit):
                lab.cmd_run(args)
        fresh.assert_called_once_with("example")
        device.assert_not_called()

    def test_a_native_only_run_needs_no_flutter_build_and_records_its_target(self):
        args = lab.parser().parse_args(["run", "material.regular", "--app", "native"])
        with tempfile.TemporaryDirectory() as temp, \
             mock.patch.object(lab.build, "require_fresh") as fresh, \
             mock.patch.object(lab.sim, "device", return_value="udid"), \
             mock.patch.object(lab, "run_cases"), \
             mock.patch.object(lab, "new_run_dir", return_value=Path(temp)):
            lab.cmd_run(args)
            self.assertEqual(json.loads((Path(temp) / "run.json").read_text()), {"flutter": "example", "a11y": "none"})
        fresh.assert_not_called()


class AccessibilityRestoredOnFailureTests(unittest.TestCase):
    def test_cmd_tune_restores_none_even_when_accessibility_set_fails(self):
        args = mock.Mock(
            scene="material.regular", appearance="dark", backdrops="white", params="frost",
            row="increaseContrast", size=88, flutter="example", passes=4, write=False, region=None, pad=12, a11y="increase-contrast",
        )
        calls = []

        def fake_accessibility(udid, mode):
            calls.append(mode)
            if mode == "increase-contrast":
                raise RuntimeError("boom")

        with mock.patch.object(lab.sim, "device", return_value="udid"), \
             mock.patch.object(lab.sim, "accessibility", side_effect=fake_accessibility), \
             mock.patch.object(lab, "manifest") as fake_manifest, \
             mock.patch.object(lab, "tune") as fake_tune:
            fake_manifest.select.return_value = [mock.Mock()]
            fake_manifest.load.return_value = []
            with self.assertRaises(RuntimeError):
                lab.cmd_tune(args)

        self.assertEqual(calls, ["increase-contrast", "none"])

    def test_run_cases_restores_none_even_when_accessibility_set_fails(self):
        calls = []

        def fake_accessibility(udid, mode):
            calls.append(mode)
            if mode == "increaseContrast":
                raise RuntimeError("boom")

        with mock.patch.object(lab.sim, "accessibility", side_effect=fake_accessibility):
            with self.assertRaises(RuntimeError):
                lab.run_cases("udid", [], [], [], None, "increaseContrast", Path("/tmp"))

        self.assertEqual(calls, ["increaseContrast", "none"])


if __name__ == "__main__":
    unittest.main()
```

```python
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import build
import manifest
import record


class LaunchFileTests(unittest.TestCase):
    def test_write_then_clear(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "Documents" / "glass_lab"
            record.write_launch_file(folder, "menu.bar", "photo", True)
            written = json.loads((folder / record.LAUNCH_FILE).read_text())
            self.assertEqual(written, {"scene": "menu.bar", "backdrop": "photo", "bare": True})
            record.clear_launch_file(folder)
            self.assertFalse((folder / record.LAUNCH_FILE).exists())
            record.clear_launch_file(folder)

    def test_material_overrides_travel_in_the_launch_file(self):
        with tempfile.TemporaryDirectory() as temp:
            record.write_launch_file(temp, "material.regular", "white", False, {"frost": 24.0, "edge.blur": 6.0})
            written = json.loads((Path(temp) / record.LAUNCH_FILE).read_text())
            self.assertEqual(written["material"], {"frost": 24.0, "edge.blur": 6.0})
            record.write_launch_file(temp, "material.regular", "white", False)
            self.assertNotIn("material", json.loads((Path(temp) / record.LAUNCH_FILE).read_text()))

    def test_the_tuned_anchor_travels_with_the_overrides(self):
        with tempfile.TemporaryDirectory() as temp:
            record.write_launch_file(temp, "material.regular", "white", False, {"frost": 24.0}, 200)
            self.assertEqual(json.loads((Path(temp) / record.LAUNCH_FILE).read_text())["materialSide"], 200)
            record.write_launch_file(temp, "material.regular", "white", False, None, 200)
            self.assertNotIn("materialSide", json.loads((Path(temp) / record.LAUNCH_FILE).read_text()))


class OtherAppsTests(unittest.TestCase):
    def test_every_other_lab_app_is_closed_so_no_back_link_shows_in_the_status_bar(self):
        with mock.patch.object(record.subprocess, "run") as run:
            record.close_other_apps("udid", record.build.NATIVE_BUNDLE)
        closed = [call.args[0][-1] for call in run.call_args_list]
        self.assertEqual(sorted(closed), sorted(record.build.FLUTTER_TARGETS.values()))
        self.assertTrue(all(call.args[0][:3] == ["xcrun", "simctl", "terminate"] for call in run.call_args_list))


class TargetTests(unittest.TestCase):
    def test_flutter_means_the_example_unless_operator_is_asked_for(self):
        base = {"group": "material", "title": "t", "inventory": "2.1", "backdrops": ["stripes"], "appearances": ["dark"], "steps": []}
        lab, apple = manifest.parse([
            {**base, "id": "material.regular", "app": "lab"},
            {**base, "id": "apple.maps.sheet", "group": "apple", "app": "com.apple.Maps"},
        ])
        self.assertEqual(record.target_for(lab, "native"), build.NATIVE_BUNDLE)
        self.assertEqual(record.target_for(lab, "flutter"), build.EXAMPLE_BUNDLE)
        self.assertEqual(record.target_for(lab, "flutter", "operator"), build.FLUTTER_BUNDLE)
        self.assertEqual(record.target_for(apple, "flutter"), "com.apple.Maps")


if __name__ == "__main__":
    unittest.main()
```

```python
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import report


def compared(scene, case, measures):
    checks = {name: False for name in measures}
    return {"scene": scene, "case": case, "kind": "compared", "pass": False, "checks": checks, "measures": measures}


class WorstMeasureTests(unittest.TestCase):
    def test_ranks_failing_measures_by_how_far_they_exceed_the_limit(self):
        result = compared("x", "c", {
            "ready.mad": [8.0, 4.0, "max"],
            "ready.bbox_pt": [30.0, 1.0, "max"],
            "motion.events.native_motion": [0, 1, "min"],
            "ready.luminance": [3.3, 3.0, "max"],
        })
        result["checks"]["ready.ok"] = True
        self.assertEqual(
            report.worst(result),
            "motion.events.native_motion 0 < 1, ready.bbox_pt 30.00 > 1.00, ready.mad 8.00 > 4.00",
        )

    def test_an_event_count_mismatch_ranks_by_its_size(self):
        result = compared("x", "c", {
            "motion.events.count": [1, 0, "max"],
            "ready.bbox_pt": [30.0, 1.0, "max"],
        })
        self.assertEqual(report.worst(result), "ready.bbox_pt 30.00 > 1.00, motion.events.count 1 > 0")

    def test_passing_case_has_no_measures(self):
        self.assertEqual(report.worst({"checks": {"ready.mad": True}, "measures": {"ready.mad": [1.0, 4.0, "max"]}}), "—")


class BacklogOrderTests(unittest.TestCase):
    def test_orders_priority_scenes_then_failures_by_ratio_then_missing_then_reference(self):
        results = [
            {"scene": "apple.maps.sheet", "case": "dark-none", "kind": "reference"},
            {"scene": "menu.bar", "case": "light-stripes", "kind": "missing"},
            compared("glass.small", "light-stripes", {"ready.mad": [5.0, 4.0, "max"]}),
            compared("glass.large", "light-stripes", {"ready.mad": [40.0, 4.0, "max"]}),
            compared("material.regular", "light-stripes", {"ready.mad": [4.5, 4.0, "max"]}),
            {"scene": "tabbar.drag", "case": "dark-stripes", "kind": "missing"},
            compared("tabbar.rest", "light-stripes", {"ready.mad": [4.5, 4.0, "max"]}),
        ]
        lines = report.markdown("runs/x", {"fail": 4}, [(None, r) for r in results], []).splitlines()
        self.assertEqual(lines[0], "# Glass lab baseline")
        rows = [line.split(" | ")[0].lstrip("| ") for line in lines if line.startswith("| ") and " | " in line and not line.startswith("| Status") and not line.startswith("| Scene") and not line.startswith("| fail")]
        self.assertEqual(rows, ["tabbar.rest", "tabbar.drag", "material.regular", "glass.large", "glass.small", "menu.bar", "apple.maps.sheet"])


class SummaryTargetTests(unittest.TestCase):
    def test_the_summary_names_the_flutter_target_the_run_captured(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertIn("against the Flutter lab app.", report.markdown(temp, {}, [], []))
            (Path(temp) / "run.json").write_text(json.dumps({"flutter": "example", "a11y": "none"}))
            self.assertIn("against the ios_liquid_glass example app.", report.markdown(temp, {}, [], []))
            (Path(temp) / "run.json").write_text(json.dumps({"flutter": "operator", "a11y": "none"}))
            self.assertIn("against Operator's debug glass lab.", report.markdown(temp, {}, [], []))


if __name__ == "__main__":
    unittest.main()
```

```python
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import probe


def take(scene, median, p90=0.0, frames=100):
    return {"scene": scene, "frames": frames, "raster_ms": {"median": median, "p90": p90}, "build_ms": {"median": 1.0}}


class PerfTests(unittest.TestCase):
    def test_takes_alternate_order(self):
        self.assertEqual(
            probe.perf_order(("a", "b"), 3),
            ["a", "b", "b", "a", "a", "b"],
        )

    def test_summary_uses_medians_across_takes_and_reports_glass_cost(self):
        summary = probe.perf_summary({
            "perf.none": [take("perf.none", 2.0), take("perf.none", 3.0), take("perf.none", 2.5)],
            "perf.glass": [take("perf.glass", 5.0), take("perf.glass", 4.0), take("perf.glass", 9.0)],
        })
        self.assertEqual(summary["perf.none"]["raster_median_ms"], 2.5)
        self.assertEqual(summary["perf.glass"]["raster_median_ms"], 5.0)
        self.assertEqual(summary["perf.glass"]["frames"], 300)
        self.assertEqual(summary["glass_cost_ms"], 2.5)

    def test_every_glass_scene_reports_its_cost_over_the_bare_scene(self):
        summary = probe.perf_summary({
            "perf.none": [take("perf.none", 2.0)],
            "perf.glass": [take("perf.glass", 5.0)],
            "perf.material": [take("perf.material", 6.5)],
        })
        self.assertEqual(summary["material_cost_ms"], 4.5)
        self.assertEqual(summary["glass_cost_ms"], 3.0)
        self.assertIn("perf.material", probe.PERF_SCENES)
        self.assertIn("perf.edge", probe.PERF_SCENES)


class WaitTests(unittest.TestCase):
    def test_returns_the_first_accepted_value(self):
        values = iter([None, {"x": 1}, {"x": 2}])
        self.assertEqual(probe.wait_for(lambda: next(values), lambda v: v["x"] == 2, timeout=5, interval=0), {"x": 2})

    def test_times_out(self):
        with self.assertRaises(TimeoutError):
            probe.wait_for(lambda: None, lambda v: True, timeout=0.05, interval=0.01)


class AccessibilityTests(unittest.TestCase):
    def test_every_mode_is_switched_off_even_when_the_launch_fails(self):
        modes = []
        with tempfile.TemporaryDirectory() as temp, \
                mock.patch.object(probe.record, "launch_folder", return_value=Path(temp)), \
                mock.patch.object(probe.sim, "accessibility", side_effect=lambda udid, mode: modes.append(mode)), \
                mock.patch.object(probe, "launch", side_effect=RuntimeError("launch failed")), \
                mock.patch.object(probe, "terminate") as terminate:
            with self.assertRaises(RuntimeError):
                probe.accessibility_check("udid", "bundle")
        self.assertEqual(modes[-1], "none")
        terminate.assert_called_once_with("udid", "bundle")


if __name__ == "__main__":
    unittest.main()
```

```python
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest
import tonefit


def curve(x, black, mid, white):
    return black * (1 - x) * (1 - 2 * x) + 4 * mid * x * (1 - x) + white * x * (2 * x - 1)


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.full((2622, 1206, 3), value, dtype=np.uint8)).save(path)


class ToneFitTests(unittest.TestCase):
    def test_recovers_the_three_tone_points_from_backdrop_and_glass_brightness(self):
        points = [(x, curve(x, 0.12, 0.47, 0.58)) for x in (0.0, 0.36, 0.67, 0.9, 1.0)]
        result = tonefit.fit(points)
        self.assertAlmostEqual(result["toneBlack"], 0.12, places=3)
        self.assertAlmostEqual(result["toneMid"], 0.47, places=3)
        self.assertAlmostEqual(result["toneWhite"], 0.58, places=3)
        self.assertLess(result["max_error_luma"], 0.01)

    def test_samples_the_interior_away_from_the_rim(self):
        self.assertEqual(tonefit.interior((21, 465, 360, 200)), (121, 525, 160, 80))

    def test_fits_every_pinned_region_of_a_native_run(self):
        scene = manifest.parse([{
            "id": "material.regular", "group": "material", "title": "t", "inventory": "2.1", "app": "lab",
            "backdrops": list(tonefit.BACKDROPS), "appearances": ["dark"], "steps": [],
            "regions": {"s88": [76, 329, 250, 88]},
        }])[0]
        with tempfile.TemporaryDirectory() as temp:
            for backdrop, bare in zip(tonefit.BACKDROPS, (0, 110, 170, 230, 255)):
                native = Path(temp) / "material.regular" / f"dark-{backdrop}" / "native"
                save(native / "bare" / "ready.png", bare)
                save(native / "ready.png", round(255 * curve(bare / 255, 0.125, 0.478, 0.577)))
            fits = tonefit.run_fit(temp, scene)
        self.assertEqual(list(fits), ["dark.s88"])
        self.assertAlmostEqual(fits["dark.s88"]["toneMid"], 0.478, places=2)


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_tune.py tool/glass_lab/harness/tests/test_lab.py tool/glass_lab/harness/tests/test_record.py tool/glass_lab/harness/tests/test_report.py tool/glass_lab/harness/tests/test_probe.py tool/glass_lab/harness/tests/test_tonefit.py`
Expected: failures and errors naming `require_fresh`, `tune_row`, `pad`, `material_side`, `elements`, `close_other_apps`, `run.json`, `material_cost_ms` and `No module named 'tonefit'`.

- [ ] **Step 2: Replace** `tool/glass_lab/harness/build.py` with:

```python
import hashlib
import subprocess
import sys
from pathlib import Path

import sim
from manifest import LAB

MOBILE = LAB.parents[1]
OUT = MOBILE / "build" / "glass_lab"
NATIVE = LAB / "native"
PROJECT = NATIVE / "GlassLab.xcodeproj"
NATIVE_DATA = OUT / "native"
FLUTTER_DATA = OUT / "flutter"
BACKDROPS = OUT / "backdrops"
NATIVE_APP = NATIVE_DATA / "Build/Products/Debug-iphonesimulator/GlassLab.app"
FLUTTER_APP = FLUTTER_DATA / "Build/Products/Debug-iphonesimulator/Runner.app"
EXAMPLE = MOBILE / "packages" / "ios_liquid_glass" / "example"
EXAMPLE_DATA = OUT / "example"
EXAMPLE_APP = EXAMPLE_DATA / "Build/Products/Debug-iphonesimulator/Runner.app"
NATIVE_BUNDLE = "dev.operator.glasslab"
FLUTTER_BUNDLE = "dev.operator.operatorMobile"
EXAMPLE_BUNDLE = "dev.operator.iosliquidglass.example"
FLUTTER_TARGETS = {"example": EXAMPLE_BUNDLE, "operator": FLUTTER_BUNDLE}
PACKAGE_LIB = MOBILE / "packages" / "ios_liquid_glass" / "lib"
SOURCES = {"example": (PACKAGE_LIB, EXAMPLE / "lib"), "operator": (PACKAGE_LIB, MOBILE / "lib")}
STAMPS = {"example": EXAMPLE_DATA / "sources.sha256", "operator": FLUTTER_DATA / "sources.sha256"}


def stream(args, cwd=None):
    process = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if process.returncode != 0:
        sys.stderr.write(process.stdout[-6000:] + process.stderr[-6000:])
        raise SystemExit(f"command failed: {' '.join(str(a) for a in args[:4])}")
    return process.stdout


def destination(udid):
    return f"platform=iOS Simulator,id={udid}"


def native(udid):
    stream([sys.executable, str(NATIVE / "gen_project.py")])
    stream([
        "xcodebuild", "build-for-testing",
        "-project", str(PROJECT),
        "-scheme", "GlassLab",
        "-destination", destination(udid),
        "-derivedDataPath", str(NATIVE_DATA),
    ])
    sim.install(udid, NATIVE_APP)


def flutter_app(udid, root, data_path, app_path):
    stream(["flutter", "build", "ios", "--simulator", "--debug", "--config-only"], cwd=root)
    stream([
        "xcodebuild", "build",
        "-workspace", str(root / "ios/Runner.xcworkspace"),
        "-scheme", "Runner",
        "-configuration", "Debug",
        "-sdk", "iphonesimulator",
        "-destination", destination(udid),
        "-derivedDataPath", str(data_path),
        "IPHONEOS_DEPLOYMENT_TARGET=15.0",
    ])
    sim.install(udid, app_path)


def sources_hash(roots):
    digest = hashlib.sha256()
    for root in roots:
        for path in sorted(p for p in Path(root).rglob("*") if p.is_file()):
            digest.update(str(path.relative_to(root)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def stamp(target, digest, stamps=None):
    stamps = stamps or STAMPS
    stamps[target].parent.mkdir(parents=True, exist_ok=True)
    stamps[target].write_text(digest + "\n")


def require_fresh(target, sources=None, stamps=None):
    sources, stamps = sources or SOURCES, stamps or STAMPS
    built = stamps[target].read_text().strip() if stamps[target].exists() else None
    if built != sources_hash(sources[target]):
        raise SystemExit(f"the {target} app build is older than its sources; run lab.py build {target} first")


def flutter(udid):
    digest = sources_hash(SOURCES["operator"])
    flutter_app(udid, MOBILE, FLUTTER_DATA, FLUTTER_APP)
    stamp("operator", digest)


def example(udid):
    digest = sources_hash(SOURCES["example"])
    flutter_app(udid, EXAMPLE, EXAMPLE_DATA, EXAMPLE_APP)
    stamp("example", digest)


def backdrops():
    stream([sys.executable, str(LAB / "backdrops" / "generate.py"), str(BACKDROPS)])
    return BACKDROPS
```

- [ ] **Step 3: Replace** `tool/glass_lab/harness/record.py` with:

```python
import json
import os
import signal
import subprocess
import time
from pathlib import Path

import build
import sim


class Recording:
    def __init__(self, udid, path):
        self.udid = udid
        self.path = Path(path)
        self.started = None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.process = subprocess.Popen(
            ["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force", str(self.path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        deadline = time.time() + 15
        while time.time() < deadline:
            line = self.process.stdout.readline()
            if "Recording started" in line:
                self.started = time.time()
                return self
            if not line and self.process.poll() is not None:
                break
        self.process.kill()
        raise RuntimeError("recordVideo did not start")

    def __exit__(self, *exc):
        self.process.send_signal(signal.SIGINT)
        self.process.communicate(timeout=60)
        return False


LAUNCH_FILE = "launch.json"


def launch_folder(udid, target):
    return sim.container(udid, target) / "Documents" / "glass_lab"


def write_launch_file(folder, scene_id, backdrop, bare, material=None, material_side=None):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    payload = {"scene": scene_id, "backdrop": backdrop, "bare": bare}
    if material:
        payload["material"] = material
    if material and material_side:
        payload["materialSide"] = material_side
    (folder / LAUNCH_FILE).write_text(json.dumps(payload))


def clear_launch_file(folder):
    (Path(folder) / LAUNCH_FILE).unlink(missing_ok=True)


def close_other_apps(udid, target):
    for bundle in (build.NATIVE_BUNDLE, *build.FLUTTER_TARGETS.values()):
        if bundle != target:
            subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)


def drive(udid, target, scene_id, steps, backdrop, bare, out_dir, settle=1.5, material=None, material_side=None):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    close_other_apps(udid, target)
    folder = launch_folder(udid, target) if target in build.FLUTTER_TARGETS.values() and scene_id else None
    if folder:
        write_launch_file(folder, scene_id, backdrop, bare, material, material_side)
    env = dict(
        os.environ,
        TEST_RUNNER_GLASS_TARGET=target,
        TEST_RUNNER_GLASS_SCENE=scene_id,
        TEST_RUNNER_GLASS_STEPS=json.dumps(list(steps)),
        TEST_RUNNER_GLASS_BACKDROP=backdrop,
        TEST_RUNNER_GLASS_BARE="1" if bare else "0",
        TEST_RUNNER_GLASS_SETTLE=str(settle),
        TEST_RUNNER_GLASS_OUT=str(out_dir),
    )
    try:
        result = _run_driver(udid, env)
    finally:
        if folder:
            clear_launch_file(folder)
    (out_dir / "driver.log").write_text(result.stdout[-20000:] + result.stderr[-5000:])
    if result.returncode != 0:
        raise RuntimeError(f"driver failed, see {out_dir / 'driver.log'}")
    return json.loads((out_dir / "timing.json").read_text())


def _run_driver(udid, env):
    return subprocess.run(
        [
            "xcodebuild", "test-without-building",
            "-project", str(build.PROJECT),
            "-scheme", "GlassLab",
            "-destination", build.destination(udid),
            "-derivedDataPath", str(build.NATIVE_DATA),
            "-only-testing:GlassLabDriver/DriverTests/testScene",
            "-collect-test-diagnostics", "never",
        ],
        env=env,
        capture_output=True,
        text=True,
    )


def target_for(scene, app, flutter_target="example"):
    if scene.native_only:
        return scene.app
    return build.NATIVE_BUNDLE if app == "native" else build.FLUTTER_TARGETS[flutter_target]


def capture(udid, scene, app, backdrop, out_dir, flutter_target="example"):
    out_dir = Path(out_dir)
    target = target_for(scene, app, flutter_target)
    scene_id = "" if scene.native_only else scene.id
    if not scene.native_only:
        drive(udid, target, scene_id, [], backdrop, True, out_dir / "bare", settle=1.0)
    with Recording(udid, out_dir / "video.mp4") as recording:
        timing = drive(udid, target, scene_id, scene.steps, backdrop, False, out_dir)
    timing["video_start"] = recording.started
    (out_dir / "timing.json").write_text(json.dumps(timing))
    return timing


def prepare_apple(udid, scene, out_dir):
    return drive(udid, scene.app, "", scene.prepare, "none", False, Path(out_dir) / "prepare", settle=2.0)
```

- [ ] **Step 4: Replace** `tool/glass_lab/harness/tune.py` with:

```python
import json
import math
import time
from pathlib import Path

import numpy as np
from PIL import Image

import build
import material_table
import metrics
import record
import sim

CAP = 10.0
WEIGHTS = {key: metrics.THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "centre_pt", "bbox_pt")}
PAD = 12

RANGES = {
    "toneBlack": (-0.5, 2.0),
    "toneMid": (-0.5, 2.0),
    "toneWhite": (-0.5, 2.0),
    "tintAmount": (0.0, 1.0),
    "shadowOpacity": (0.0, 1.0),
    "outline": (0.0, 1.0),
    "outlineTop": (0.0, 1.0),
    "saturation": (0.0, math.inf),
    "frost": (0.0, math.inf),
    "thickness": (0.001, math.inf),
    "dispersion": (0.0, math.inf),
    "outlineWidth": (0.0, math.inf),
    "specular": (-1.0, math.inf),
    "sheen": (-1.0, math.inf),
    "specularWidth": (0.001, math.inf),
    "sheenWidth": (0.001, math.inf),
    "specularPower": (0.0, math.inf),
    "specularFill": (0.0, math.inf),
    "shadowBlur": (0.0, math.inf),
    "tintBlack": (0.0, math.inf),
    "tintWhite": (0.0, math.inf),
    "refractiveIndex": (1.0, math.inf),
    "extent": (0.0, math.inf),
    "blur": (0.0, math.inf),
    "capBlur": (0.0, math.inf),
    "dim": (0.0, 1.0),
    "knee": (0.0, 1.0),
    "blurKnee": (0.0, 1.0),
    "blurReach": (0.0, 1.0),
    "cap": (0.0, 1.0),
    "line": (0.0, 1.0),
    "lineShade": (0.0, 1.0),
}


def clamp(name, value):
    low, high = RANGES.get(field(name), (-math.inf, math.inf))
    return min(max(value, low), high)


def score(stat, measures=tuple(WEIGHTS)):
    return sum(min(stat[key] / WEIGHTS[key], CAP) for key in measures)


def parse_params(text):
    grid = {}
    for item in text.split(","):
        name, spec = item.split("=")
        low, high, count = spec.split(":")
        values = np.linspace(float(low), float(high), int(count))
        grid[name.strip()] = [round(float(v), 4) for v in values]
    return grid


def coordinate_descent(evaluate, grid, start, min_gain=0.01, max_passes=4):
    best = dict(start)
    best_score = evaluate(best)
    log = [(dict(best), best_score)]
    seen = {tuple(sorted(best.items()))}
    for _ in range(max_passes):
        before = best_score
        for name, values in grid.items():
            for raw_value in values:
                value = clamp(name, raw_value)
                if value == best.get(name):
                    continue
                candidate = {**best, name: value}
                key = tuple(sorted(candidate.items()))
                if key in seen:
                    continue
                seen.add(key)
                result = evaluate(candidate)
                log.append((candidate, result))
                if result < best_score:
                    best, best_score = candidate, result
        if before - best_score < min_gain * before:
            break
    for name, values in grid.items():
        if len(values) < 2:
            continue
        step = (values[1] - values[0]) / 2
        for raw_value in (best[name] - step, best[name] + step):
            value = clamp(name, round(raw_value, 4))
            candidate = {**best, name: value}
            key = tuple(sorted(candidate.items()))
            if key in seen:
                continue
            seen.add(key)
            result = evaluate(candidate)
            log.append((candidate, result))
            if result < best_score:
                best, best_score = candidate, result
    return best, best_score, log


def element_box(boxes, size):
    if not boxes:
        return None
    return min(boxes, key=lambda box: abs(min(box[2], box[3]) - size))


def named_region(scene, names, pad=PAD):
    boxes = [tuple(scene.regions[name]) for name in names]
    return metrics.union(boxes, pad=pad)


def table_key(scene, appearance, row, size):
    if material_table.for_scene(scene.id) is material_table.SCROLL_EDGE:
        return f"{appearance}.{scene.id.rsplit('.', 1)[1]}"
    return f"{appearance}.{row}.{size}"


def field(name):
    return name.removeprefix(material_table.EDGE_PREFIX)


def filmstrip(native, flutter, region, dest):
    a, b = metrics.crop(native, region), metrics.crop(flutter, region)
    difference = np.clip(np.abs(a - b) * 4, 0, 255)
    strip = np.concatenate([a, b, difference], axis=1).astype(np.uint8)
    Image.fromarray(strip).save(dest)


class Evaluator:
    def __init__(self, udid, scene, backdrops, size, flutter_target, out, regions=(), row_overrides=None, pad=PAD):
        self.udid = udid
        self.pad = pad
        self.scene = scene
        self.backdrops = backdrops
        self.size = size
        self.regions = tuple(regions)
        self.target = build.FLUTTER_TARGETS[flutter_target]
        self.out = Path(out)
        self.count = 0
        self.cache = {}
        self.records = []
        self.row_overrides = dict(row_overrides or {})

    def _drive(self, target, backdrop, bare, folder, material=None):
        side = None if material_table.for_scene(self.scene.id) is material_table.SCROLL_EDGE else self.size
        record.drive(self.udid, target, self.scene.id, [], backdrop, bare, folder, settle=1.0, material=material, material_side=side)
        return metrics.load(Path(folder) / "ready.png")

    def region(self, native, native_bare):
        if self.scene.track:
            return tuple(self.scene.regions[self.scene.track])
        if self.regions:
            return named_region(self.scene, self.regions, self.pad)
        box = element_box(metrics.glass_boxes(native, native_bare), self.size)
        return metrics.union([box], pad=self.pad) if box else (0, 0, *metrics.SCREEN)

    def elements(self):
        return {name: tuple(self.scene.regions[name]) for name in self.regions}

    def references(self, backdrop):
        if backdrop not in self.cache:
            base = self.out / "reference" / backdrop
            native = self._drive(build.NATIVE_BUNDLE, backdrop, False, base / "native")
            native_bare = self._drive(build.NATIVE_BUNDLE, backdrop, True, base / "native_bare")
            flutter_bare = self._drive(self.target, backdrop, True, base / "flutter_bare")
            self.cache[backdrop] = (native, native_bare, flutter_bare, self.region(native, native_bare))
        return self.cache[backdrop]

    def __call__(self, material):
        self.count += 1
        total, stats = 0.0, {}
        sent = {**self.row_overrides, **material}
        for backdrop in self.backdrops:
            native, native_bare, flutter_bare, region = self.references(backdrop)
            folder = self.out / "candidates" / f"{self.count:04d}" / backdrop
            flutter = self._drive(self.target, backdrop, False, folder, sent)
            stat = metrics.static_compare(native, flutter, native_bare, flutter_bare, region, self.elements())
            stats[backdrop] = {key: stat[key] for key in self.scene.measures}
            if "rim_elements" in stat:
                stats[backdrop]["rim_sides"] = {name: entry["sides"] for name, entry in stat["rim_elements"].items()}
            total += score(stat, self.scene.measures)
        result = total / len(self.backdrops)
        entry = {"n": self.count, "material": material, "score": result, "stats": stats, "time": time.time()}
        self.records.append(entry)
        with open(self.out / "log.jsonl", "a") as handle:
            handle.write(json.dumps(entry) + "\n")
        print(f"  #{self.count} score {result:.3f} {json.dumps(material)}", flush=True)
        return result

    def filmstrips(self):
        best = min(self.records, key=lambda entry: entry["score"])
        for backdrop in self.backdrops:
            native, _, _, region = self.references(backdrop)
            flutter = metrics.load(self.out / "candidates" / f"{best['n']:04d}" / backdrop / "ready.png")
            filmstrip(native, flutter, region, self.out / f"best-{backdrop}.png")


def run(udid, scene, appearance, backdrops, grid, row, size, flutter_target, out, write=False, max_passes=4, regions=(), pad=PAD):
    build.require_fresh(flutter_target)
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    sim.appearance(udid, appearance)
    table = material_table.for_scene(scene.id)
    key = table_key(scene, appearance, row, size)
    current = material_table.read(table=table).get(key, {})
    start = {name: current.get(field(name), grid[name][len(grid[name]) // 2]) for name in grid}
    if table is material_table.SCROLL_EDGE:
        row_overrides = {material_table.EDGE_PREFIX + name: value for name, value in current.items()}
    else:
        row_overrides = dict(current)
    evaluate = Evaluator(udid, scene, backdrops, size, flutter_target, out, regions, row_overrides, pad)
    best, best_score, _ = coordinate_descent(evaluate, grid, start, max_passes=max_passes)
    evaluate.filmstrips()
    summary = {"key": key, "scene": scene.id, "backdrops": backdrops, "pad": pad, "start": start, "start_score": evaluate.records[0]["score"], "best": best, "best_score": best_score}
    (out / "best.json").write_text(json.dumps(summary, indent=2))
    if write:
        material_table.update(key, {field(name): value for name, value in best.items()}, table=table)
    return summary
```

- [ ] **Step 5: Replace** `tool/glass_lab/harness/lab.py`, `tool/glass_lab/harness/report.py` and `tool/glass_lab/harness/probe.py` with:

```python
import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze
import build
import flip
import manifest
import metrics
import probe
import record
import report
import sim
import tonefit
import tune

RUNS = build.OUT / "runs"
RUN_NAME = re.compile(r"\d{8}-\d{6}")
NOISE = manifest.LAB / "noise.json"
REPEAT_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar")
BASELINE_A11Y_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar", "sheet.detents")


def cmd_build(args):
    udid = sim.device()
    if args.target in ("native", "all"):
        build.native(udid)
    if args.target in ("example", "all"):
        build.example(udid)
    if args.target in ("operator", "all"):
        build.flutter(udid)
    print(f"built for {udid}")


def cmd_prepare(args):
    udid = sim.device()
    sim.status_bar(udid)
    source = build.backdrops()
    for bundle in (build.NATIVE_BUNDLE, *build.FLUTTER_TARGETS.values()):
        sim.install_backdrops(udid, bundle, source)
    for scene in manifest.load():
        if scene.native_only:
            sim.revoke_location(udid, scene.app)
            if scene.prepare:
                record.prepare_apple(udid, scene, build.OUT / "prepare" / scene.id)
    print(f"prepared {udid}")


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_cases(udid, scenes, apps, appearances, backdrop, a11y, run_dir, flutter_target="example"):
    try:
        sim.accessibility(udid, a11y)
        for scene in scenes:
            backdrops = [backdrop] if backdrop else list(scene.backdrops)
            for appearance in [a for a in scene.appearances if a in appearances]:
                sim.appearance(udid, appearance)
                for chosen in backdrops:
                    case_dir = run_dir / scene.id / case_name(appearance, chosen, a11y)
                    for app in ["native"] if scene.native_only else apps:
                        print(f"{scene.id} {case_dir.name} {app}", flush=True)
                        try:
                            record.capture(udid, scene, app, chosen, case_dir / app, flutter_target)
                        except Exception as error:
                            (case_dir / app).mkdir(parents=True, exist_ok=True)
                            (case_dir / app / "error.txt").write_text(str(error))
                            print(f"  failed: {error}", flush=True)
    finally:
        sim.accessibility(udid, "none")


def new_run_dir():
    run_dir = RUNS / time.strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def apps_for(value):
    return ["native", "flutter"] if value == "both" else [value]


def appearances_for(value):
    return ["light", "dark"] if value == "both" else [value]


def cmd_run(args):
    scenes = manifest.select(manifest.load(), args.scene)
    if "flutter" in apps_for(args.app) and any(not scene.native_only for scene in scenes):
        build.require_fresh(args.flutter)
    udid = sim.device()
    run_dir = new_run_dir()
    (run_dir / "run.json").write_text(json.dumps({"flutter": args.flutter, "a11y": args.a11y}))
    run_cases(udid, scenes, apps_for(args.app), appearances_for(args.appearance), args.backdrop, args.a11y, run_dir, args.flutter)
    print(run_dir)


def load_noise():
    return json.loads(NOISE.read_text()) if NOISE.exists() else {}


def analyze_run(run_dir):
    scenes = {s.id: s for s in manifest.load()}
    noise = load_noise()
    for case_dir in sorted(Path(run_dir).glob("*/*")):
        scene = scenes.get(case_dir.parent.name)
        if scene is None or not case_dir.is_dir():
            continue
        if any((case_dir / app / "error.txt").exists() for app in ("native", "flutter")):
            (case_dir / "result.json").write_text(json.dumps({"scene": scene.id, "case": case_dir.name, "kind": "error"}))
            continue
        result = analyze.analyze(scene, case_dir, noise.get(scene.id))
        (case_dir / "result.json").write_text(json.dumps(result))


def latest_run():
    runs = sorted(p for p in RUNS.glob("*") if p.is_dir() and RUN_NAME.fullmatch(p.name))
    if not runs:
        raise SystemExit("no runs yet")
    return runs[-1]


def cmd_report(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    analyze_run(run_dir)
    page, counts, _ = report.build(run_dir, manifest.load())
    print(page)
    print(json.dumps(counts))


def cmd_summary(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    _, counts, results = report.build(run_dir, manifest.load())
    Path(args.out).write_text(report.markdown(run_dir, counts, results, manifest.load()))
    print(args.out)


def cmd_baseline(args):
    cmd_prepare(args)
    udid = sim.device()
    run_dir = new_run_dir()
    scenes = manifest.load()
    run_cases(udid, scenes, ["native", "flutter"], ["light", "dark"], None, "none", run_dir, args.flutter)
    chosen = [s for s in scenes if s.id in BASELINE_A11Y_SCENES]
    for mode in ("reduce-transparency", "increase-contrast", "reduce-motion"):
        run_cases(udid, chosen, ["native", "flutter"], ["dark"], None, mode, run_dir, args.flutter)
    analyze_run(run_dir)
    page, counts, _ = report.build(run_dir, scenes)
    print(page)
    print(json.dumps(counts))


def cmd_repeat(args):
    udid = sim.device()
    names = REPEAT_SCENES if args.scene == "default" else [args.scene]
    scenes = [manifest.select(manifest.load(), name)[0] for name in names]
    run_dir = new_run_dir()
    noise = load_noise()
    failed = []
    for scene in scenes:
        appearance, backdrop = scene.appearances[0], scene.backdrops[0]
        sim.appearance(udid, appearance)
        takes = []
        for number in range(args.times):
            take = run_dir / "takes" / scene.id / str(number)
            print(f"{scene.id} take {number}", flush=True)
            record.capture(udid, scene, "native", backdrop, take)
            takes.append(take)
        worst, static_worst = {}, 0.0
        for i in range(len(takes)):
            for j in range(i + 1, len(takes)):
                case = run_dir / scene.id / f"pair-{i}{j}"
                case.mkdir(parents=True, exist_ok=True)
                for name, source in (("native", takes[i]), ("flutter", takes[j])):
                    link = case / name
                    if not link.exists():
                        link.symlink_to(source)
                result = analyze.analyze(scene, case)
                (case / "result.json").write_text(json.dumps(result))
                for stat in result.get("static", {}).values():
                    static_worst = max(static_worst, stat["mad"])
                if "motion" in result:
                    for name, (value, _) in analyze.motion_measures(result["motion"]).items():
                        worst[name] = max(worst.get(name, 0.0), value)
        noise[scene.id] = worst
        print(f"{scene.id}: static mad {static_worst:.2f}, motion noise {json.dumps({k: round(v, 1) for k, v in worst.items()})}")
        if static_worst > 1.0:
            print(f"{scene.id}: static repeatability FAILED (mad {static_worst:.2f} > 1.0)")
            failed.append(scene.id)
    NOISE.write_text(json.dumps(noise, indent=2, sort_keys=True) + "\n")
    print(NOISE)
    if failed:
        raise SystemExit(f"static repeatability failed for {', '.join(failed)}")


A11Y_ROWS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast"}


def tune_row(a11y, row):
    expected = A11Y_ROWS.get(a11y)
    if row is None:
        return expected or "regular"
    if expected != row and (expected or row in A11Y_ROWS.values()):
        raise SystemExit(f"--a11y {a11y} renders the {expected or 'plain'} row, not --row {row}")
    return row


def cmd_tune(args):
    row = tune_row(args.a11y, args.row)
    udid = sim.device()
    scene = manifest.select(manifest.load(), args.scene)[0]
    out = build.OUT / "tune" / time.strftime("%Y%m%d-%H%M%S")
    try:
        sim.accessibility(udid, args.a11y)
        summary = tune.run(
            udid, scene, args.appearance, args.backdrops.split(","), tune.parse_params(args.params),
            row, args.size, args.flutter, out, write=args.write, max_passes=args.passes,
            regions=args.region.split(",") if args.region else (), pad=args.pad,
        )
    finally:
        sim.accessibility(udid, "none")
    print(json.dumps(summary, indent=2))
    print(out)


def cmd_tonefit(args):
    scene = manifest.select(manifest.load(), args.scene)[0]
    print(json.dumps(tonefit.run_fit(args.run_dir, scene, args.a11y), indent=2))


def cmd_flip(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    text = flip.report(run_dir, args.regular)
    print(text)
    if args.out:
        Path(args.out).write_text(text)


def cmd_perf(args):
    build.require_fresh(args.flutter)
    udid = sim.device()
    sim.appearance(udid, args.appearance)
    try:
        sim.accessibility(udid, args.a11y)
        summary = probe.perf(udid, build.FLUTTER_TARGETS[args.flutter], args.takes, tuple(args.scenes.split(",")))
    finally:
        sim.accessibility(udid, "none")
    text = json.dumps(summary, indent=2)
    print(text)
    if args.out:
        Path(args.out).write_text(text + "\n")


def cmd_a11y(args):
    udid = sim.device()
    results = probe.accessibility_check(udid, build.FLUTTER_TARGETS[args.flutter])
    print(json.dumps(results, indent=2))
    failed = [mode for mode, result in results.items() if not result["live"]]
    if failed:
        raise SystemExit(f"not delivered live: {', '.join(failed)}")


def cmd_geometry(args):
    udid = sim.device()
    scene = manifest.select(manifest.load(), args.scene)[0]
    out = build.OUT / "geometry" / scene.id
    sim.appearance(udid, args.appearance)
    backdrop = args.backdrop or scene.backdrops[0]
    record.drive(udid, build.NATIVE_BUNDLE, scene.id, [], backdrop, True, out / "bare", settle=1.0)
    record.drive(udid, build.NATIVE_BUNDLE, scene.id, [], backdrop, False, out / "scene", settle=1.5)
    boxes = metrics.glass_boxes(metrics.load(out / "scene" / "ready.png"), metrics.load(out / "bare" / "ready.png"))
    for box in boxes:
        print(json.dumps({"x": box[0], "y": box[1], "width": box[2], "height": box[3]}))


def parser():
    root = argparse.ArgumentParser(prog="lab.py")
    commands = root.add_subparsers(dest="command", required=True)
    b = commands.add_parser("build")
    b.add_argument("target", nargs="?", default="all", choices=("native", "example", "operator", "all"))
    b.set_defaults(func=cmd_build)
    commands.add_parser("prepare").set_defaults(func=cmd_prepare)
    r = commands.add_parser("run")
    r.add_argument("scene")
    r.add_argument("--app", default="both", choices=("native", "flutter", "both"))
    r.add_argument("--appearance", default="both", choices=("light", "dark", "both"))
    r.add_argument("--backdrop", choices=manifest.BACKDROPS)
    r.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    r.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    r.set_defaults(func=cmd_run)
    p = commands.add_parser("report")
    p.add_argument("run_dir", nargs="?")
    p.set_defaults(func=cmd_report)
    bl = commands.add_parser("baseline")
    bl.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    bl.set_defaults(func=cmd_baseline)
    m = commands.add_parser("summary")
    m.add_argument("out")
    m.add_argument("run_dir", nargs="?")
    m.set_defaults(func=cmd_summary)
    t = commands.add_parser("repeat")
    t.add_argument("scene", nargs="?", default="default")
    t.add_argument("--times", type=int, default=3)
    t.set_defaults(func=cmd_repeat)
    u = commands.add_parser("tune")
    u.add_argument("--scene", required=True)
    u.add_argument("--appearance", required=True, choices=("light", "dark"))
    u.add_argument("--backdrops", required=True)
    u.add_argument("--params", required=True)
    u.add_argument("--row", choices=("regular", "clear", "tinted", "reduceTransparency", "increaseContrast"))
    u.add_argument("--size", type=int, default=88, choices=(44, 88, 200))
    u.add_argument("--region")
    u.add_argument("--pad", type=int, default=tune.PAD)
    u.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    u.add_argument("--flutter", default="example", choices=("example",))
    u.add_argument("--passes", type=int, default=4)
    u.add_argument("--write", action="store_true")
    u.set_defaults(func=cmd_tune)
    o = commands.add_parser("tonefit")
    o.add_argument("run_dir")
    o.add_argument("--scene", default="material.regular")
    o.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    o.set_defaults(func=cmd_tonefit)
    l = commands.add_parser("flip")
    l.add_argument("run_dir", nargs="?")
    l.add_argument("--regular")
    l.add_argument("--out")
    l.set_defaults(func=cmd_flip)
    f = commands.add_parser("perf")
    f.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    f.add_argument("--appearance", default="dark", choices=("light", "dark"))
    f.add_argument("--takes", type=int, default=3)
    f.add_argument("--scenes", default=",".join(probe.PERF_SCENES))
    f.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    f.add_argument("--out")
    f.set_defaults(func=cmd_perf)
    y = commands.add_parser("a11y")
    y.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    y.set_defaults(func=cmd_a11y)
    g = commands.add_parser("geometry")
    g.add_argument("scene")
    g.add_argument("--appearance", default="dark", choices=("light", "dark"))
    g.add_argument("--backdrop", choices=manifest.BACKDROPS)
    g.set_defaults(func=cmd_geometry)
    return root


def main(argv=None):
    args = parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
```

```python
import html
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops

STRIP_STEP = 6
STRIP_FRAMES = 24


def svg_lines(series, width=520, height=160, colors=("#1f77b4", "#d62728")):
    values = [v for line in series.values() for v in line]
    if not values:
        return ""
    low, high = min(values), max(values)
    span = high - low or 1.0
    count = max(len(line) for line in series.values())
    paths = []
    for (name, line), color in zip(series.items(), colors):
        points = " ".join(
            f"{i / max(1, count - 1) * width:.1f},{height - (v - low) / span * height:.1f}" for i, v in enumerate(line)
        )
        paths.append(f'<polyline fill="none" stroke="{color}" stroke-width="1.5" points="{points}"><title>{html.escape(name)}</title></polyline>')
    legend = " ".join(f'<span style="color:{c}">{html.escape(n)}</span>' for n, c in zip(series, colors))
    return f'<div class="chart"><svg viewBox="0 0 {width} {height}" width="{width}" height="{height}">{"".join(paths)}</svg><div>{legend}</div></div>'


def diff_image(native, flutter, out):
    a = Image.open(native).convert("RGB")
    b = Image.open(flutter).convert("RGB").resize(a.size)
    ImageChops.difference(a, b).point(lambda v: min(255, v * 4)).save(out)


def thumb(source, out, width=201):
    image = Image.open(source).convert("RGB")
    image.resize((width, round(image.height * width / image.width))).save(out)


def strip(frames_dir, out):
    if not Path(frames_dir).exists():
        return False
    paths = sorted(Path(frames_dir).glob("*.png"))[::STRIP_STEP][:STRIP_FRAMES]
    if not paths:
        return False
    images = [Image.open(p).convert("RGB") for p in paths]
    width, height = images[0].size
    scale = min(1.0, 120 / width)
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    sheet = Image.new("RGB", (size[0] * len(images), size[1]), (128, 128, 128))
    for index, image in enumerate(images):
        sheet.paste(image.resize(size), (index * size[0], 0))
    sheet.save(out)
    return True


def fmt(value):
    if isinstance(value, float):
        return "∞" if value == float("inf") else f"{value:.2f}"
    return html.escape(str(value))


def case_section(scene_id, case_dir, result, assets):
    rel = lambda p: html.escape(str(Path(p).relative_to(assets.parent)))
    parts = [f'<h3 id="{html.escape(scene_id)}-{html.escape(result["case"])}">{html.escape(scene_id)} · {html.escape(result["case"])}</h3>']
    native_dir, flutter_dir = case_dir / "native", case_dir / "flutter"
    images = []
    for app_dir in (native_dir, flutter_dir):
        for name in ("ready", "settled"):
            source = app_dir / f"{name}.png"
            if source.exists():
                target = assets / f"{scene_id}-{result['case']}-{app_dir.name}-{name}.png"
                thumb(source, target)
                images.append(f'<figure><img src="{rel(target)}"><figcaption>{app_dir.name} {name}</figcaption></figure>')
    if result.get("kind") == "compared":
        for name in ("ready", "settled"):
            target = assets / f"{scene_id}-{result['case']}-diff-{name}.png"
            diff_image(native_dir / f"{name}.png", flutter_dir / f"{name}.png", target)
            thumb(target, target)
            images.append(f'<figure><img src="{rel(target)}"><figcaption>diff ×4 {name}</figcaption></figure>')
    parts.append(f'<div class="row">{"".join(images)}</div>')
    motion = result.get("motion") or {}
    for app_dir in (native_dir, flutter_dir):
        target = assets / f"{scene_id}-{result['case']}-{app_dir.name}-strip.png"
        if strip(app_dir / "frames", target):
            parts.append(f'<div><div class="label">{app_dir.name} filmstrip (about 50 ms per frame)</div><img class="strip" src="{rel(target)}"></div>')
    if motion:
        parts.append(f'<div class="small">motion events native/flutter: {motion["event_count"][0]}/{motion["event_count"][1]}</div>')
    for number, event in enumerate(result.get("native_events", [])):
        parts.append(f'<div class="label">native event {number}</div>' + svg_lines({key: event["series"][key] for key in ("width", "height")}))
    for number, event in enumerate(motion.get("events", [])):
        for key in ("width", "height", "cx", "cy", "luma"):
            if key not in event:
                continue
            entry = event[key]
            parts.append(f'<div class="label">event {number} · {key}</div>' + svg_lines({"native": entry["native"], "flutter": entry["flutter"]}))
            springs = ""
            if "native_spring" in entry:
                springs = f' · spring native {fmt(entry["native_spring"]["response"])}s/{fmt(entry["native_spring"]["damping"])}, flutter {fmt(entry["flutter_spring"]["response"])}s/{fmt(entry["flutter_spring"]["damping"])}'
            parts.append(f'<div class="small">rms {fmt(entry["rms"])}{springs}</div>')
    for name, stat in (result.get("static") or {}).items():
        if "rim_native" in stat:
            parts.append(f'<div class="label">rim profile ({name})</div>' + svg_lines({"native": stat["rim_native"], "flutter": stat["rim_flutter"]}))
        rows = "".join(
            f'<tr><td>{key}</td><td>{fmt(stat[key])}</td><td class="{"ok" if ok else "bad"}">{"pass" if ok else "fail"}</td></tr>'
            for key, ok in stat["pass"].items()
        )
        parts.append(f"<table><tr><th>{name}</th><th>value</th><th></th></tr>{rows}</table>")
    if result.get("flutter_stalls"):
        parts.append(f'<div class="small bad">Flutter frame gaps over 25 ms: {", ".join(fmt(g) for g in result["flutter_stalls"])}</div>')
    return "".join(parts)


BACKLOG_FIRST = (
    "tabbar.rest", "tabbar.press", "tabbar.drag", "button.press", "sheet.detents",
    "navbar.inline", "material.regular", "material.tinted", "material.clear", "material.interactive",
)
STATUS_ORDER = ("fail", "pass", "missing", "reference", "error")


def ratio(value, limit, bound):
    if bound == "max" and limit == 0:
        return 1.0 + value
    low, high = (value, limit) if bound == "min" else (limit, value)
    return high / low if low > 0 else float("inf")


def ranked(result):
    checks = result.get("checks") or {}
    measures = result.get("measures") or {}
    failing = [(name, *measures[name]) for name, ok in checks.items() if not ok and name in measures]
    return sorted(failing, key=lambda entry: -ratio(*entry[1:]))


def worst(result):
    checks = result.get("checks") or {}
    measures = result.get("measures") or {}
    entries = [f"{name} {fmt(value)} {'<' if bound == 'min' else '>'} {fmt(limit)}" for name, value, limit, bound in ranked(result)]
    entries += [name for name, ok in checks.items() if not ok and name not in measures]
    return ", ".join(entries[:3]) if entries else "—"


def status_of(result):
    kind = result.get("kind")
    return ("pass" if result.get("pass") else "fail") if kind == "compared" else kind


def backlog_key(result):
    scene, case, status = result["scene"], result["case"], status_of(result)
    if scene in BACKLOG_FIRST:
        return (0, BACKLOG_FIRST.index(scene), (), case)
    ratios = tuple(-ratio(*entry[1:]) for entry in ranked(result))
    group = 1 + (STATUS_ORDER.index(status) if status in STATUS_ORDER else len(STATUS_ORDER))
    return (group, 0, ratios, scene, case)


def build(run_dir, scenes):
    run_dir = Path(run_dir)
    assets = run_dir / "report_assets"
    assets.mkdir(exist_ok=True)
    results = []
    for result_path in sorted(run_dir.glob("*/*/result.json")):
        results.append((result_path.parent, json.loads(result_path.read_text())))
    by_scene = {s.id: s for s in scenes}
    counts = {"pass": 0, "fail": 0, "missing": 0, "reference": 0, "error": 0}
    rows, sections = [], []
    for case_dir, result in results:
        kind = result.get("kind")
        if kind == "compared":
            status = "pass" if result.get("pass") else "fail"
        else:
            status = kind
        counts[status] = counts.get(status, 0) + 1
        scene = by_scene.get(result["scene"])
        title = scene.title if scene else ""
        anchor = f'{result["scene"]}-{result["case"]}'
        rows.append(
            f'<tr><td><a href="#{html.escape(anchor)}">{html.escape(result["scene"])}</a></td><td>{html.escape(result["case"])}</td>'
            f'<td>{html.escape(title)}</td><td class="{status}">{status}</td><td>{html.escape(worst(result))}</td></tr>'
        )
        sections.append(case_section(result["scene"], case_dir, result, assets))
    summary = " · ".join(f"{k}: {v}" for k, v in counts.items())
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Glass lab report</title>
<style>
body{{font:14px -apple-system,system-ui,sans-serif;margin:24px;background:#fafafa;color:#111}}
table{{border-collapse:collapse;margin:8px 0}}td,th{{border:1px solid #ddd;padding:4px 8px;text-align:left}}
.pass,.ok{{color:#0a7d32}}.fail,.bad{{color:#c0262d}}.missing{{color:#8a6d00}}.reference,.error{{color:#555}}
.row{{display:flex;gap:8px;flex-wrap:wrap}}figure{{margin:0}}figcaption,.label,.small{{font-size:12px;color:#555}}
img.strip{{max-width:100%}}.chart svg{{background:#fff;border:1px solid #eee}}h3{{margin-top:40px}}
</style></head><body>
<h1>Glass lab report</h1><p>{summary}</p>
<table><tr><th>scene</th><th>case</th><th>title</th><th>status</th><th>failing measures</th></tr>{"".join(rows)}</table>
{"".join(sections)}
</body></html>"""
    (run_dir / "report.html").write_text(page)
    return run_dir / "report.html", counts, results


TARGETS = {"example": "the ios_liquid_glass example app", "operator": "Operator's debug glass lab"}


def target_of(run_dir):
    meta = Path(run_dir) / "run.json"
    flutter = json.loads(meta.read_text()).get("flutter") if meta.exists() else None
    return TARGETS.get(flutter, "the Flutter lab app")


def markdown(run_dir, counts, results, scenes):
    by_scene = {s.id: s for s in scenes}
    lines = [
        "# Glass lab baseline",
        "",
        f"Run: `{Path(run_dir).name}`. Native iOS 27 (iPhone 17 Pro simulator) against {target_of(run_dir)}.",
        "",
        "| Status | Count |",
        "|---|---|",
    ]
    lines += [f"| {key} | {value} |" for key, value in counts.items()]
    lines += ["", "| Scene | Case | Title | Status | Failing measures |", "|---|---|---|---|---|"]
    for result in sorted((r for _, r in results), key=backlog_key):
        status = status_of(result)
        scene = by_scene.get(result["scene"])
        title = scene.title if scene else ""
        lines.append(f"| {result['scene']} | {result['case']} | {title} | {status} | {worst(result)} |")
    return "\n".join(lines) + "\n"
```

```python
import json
import statistics
import subprocess
import time
from pathlib import Path

import record
import sim

PERF_FILE = "perf.json"
ACCESSIBILITY_FILE = "accessibility.json"
PERF_SCENES = ("perf.none", "perf.glass", "perf.material", "perf.edge")
FLAGS = {"reduce-transparency": "reduceTransparency", "increase-contrast": "increaseContrast", "reduce-motion": "reduceMotion"}


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def wait_for(read, accept, timeout, interval=0.25):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = read()
        if value is not None and accept(value):
            return value
        time.sleep(interval)
    raise TimeoutError("the app never reported the expected value")


def launch(udid, bundle, scene_id, backdrop="stripes"):
    folder = record.launch_folder(udid, bundle)
    record.write_launch_file(folder, scene_id, backdrop, False)
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle], check=True, capture_output=True)
    return folder


def terminate(udid, bundle):
    subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True)


def perf_order(scenes, takes):
    return [scene for take in range(takes) for scene in (scenes if take % 2 == 0 else tuple(reversed(scenes)))]


def perf_take(udid, bundle, scene_id, timeout=40):
    folder = record.launch_folder(udid, bundle)
    (folder / PERF_FILE).unlink(missing_ok=True)
    try:
        launch(udid, bundle, scene_id)
        return wait_for(lambda: read_json(folder / PERF_FILE), lambda value: value.get("scene") == scene_id, timeout)
    finally:
        terminate(udid, bundle)
        record.clear_launch_file(folder)


def perf_summary(takes):
    summary = {}
    for scene_id, results in takes.items():
        summary[scene_id] = {
            "takes": len(results),
            "frames": sum(r["frames"] for r in results),
            "raster_median_ms": statistics.median(r["raster_ms"]["median"] for r in results),
            "raster_p90_ms": statistics.median(r["raster_ms"]["p90"] for r in results),
            "build_median_ms": statistics.median(r["build_ms"]["median"] for r in results),
        }
    if "perf.none" in summary:
        for scene_id in summary.copy():
            if scene_id != "perf.none":
                summary[f"{scene_id.removeprefix('perf.')}_cost_ms"] = summary[scene_id]["raster_median_ms"] - summary["perf.none"]["raster_median_ms"]
    return summary


def perf(udid, bundle, takes=3, scenes=PERF_SCENES):
    results = {scene: [] for scene in scenes}
    for scene_id in perf_order(scenes, takes):
        results[scene_id].append(perf_take(udid, bundle, scene_id))
    return perf_summary(results)


def accessibility_check(udid, bundle, modes=tuple(FLAGS), timeout=10):
    folder = record.launch_folder(udid, bundle)
    (folder / ACCESSIBILITY_FILE).unlink(missing_ok=True)
    results = {}
    sim.accessibility(udid, "none")
    try:
        launch(udid, bundle, "material.regular")
        read = lambda: read_json(folder / ACCESSIBILITY_FILE)
        wait_for(read, lambda value: not any(value.values()), timeout)
        for mode in modes:
            sim.accessibility(udid, mode)
            try:
                seen = wait_for(read, lambda value: value.get(FLAGS[mode]) is True, timeout)
                results[mode] = {"live": True, "seen": seen}
            except TimeoutError:
                results[mode] = {"live": False, "seen": read()}
            sim.accessibility(udid, "none")
            try:
                wait_for(read, lambda value: not any(value.values()), timeout)
            except TimeoutError:
                results[mode]["reset"] = False
    finally:
        sim.accessibility(udid, "none")
        terminate(udid, bundle)
        record.clear_launch_file(folder)
    return results
```

and create `tool/glass_lab/harness/tonefit.py`:

```python
from pathlib import Path

import numpy as np

import metrics

BACKDROPS = ("black", "photo", "stripes", "text", "white")


def interior(box):
    x, y, w, h = box
    return (x + h * 0.5, y + h * 0.3, w - h, h * 0.4)


def point(native, bare, box):
    region = interior(box)
    return float(metrics.luma(metrics.crop(bare, region)).mean() / 255), float(metrics.luma(metrics.crop(native, region)).mean() / 255)


def fit(points):
    xs = np.array([p[0] for p in points])
    ys = np.array([p[1] for p in points])
    basis = np.stack([(1 - xs) * (1 - 2 * xs), 4 * xs * (1 - xs), xs * (2 * xs - 1)], axis=1)
    solution, *_ = np.linalg.lstsq(basis, ys, rcond=None)
    worst = float(np.abs(basis @ solution - ys).max() * 255)
    black, mid, white = (round(float(v), 4) for v in solution)
    return {"toneBlack": black, "toneMid": mid, "toneWhite": white, "max_error_luma": round(worst, 2)}


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_fit(run_dir, scene, a11y="none"):
    fits = {}
    for appearance in scene.appearances:
        for name, box in scene.regions.items():
            if name == scene.track:
                continue
            points = []
            for backdrop in BACKDROPS:
                native = Path(run_dir) / scene.id / case_name(appearance, backdrop, a11y) / "native"
                if (native / "ready.png").exists():
                    points.append(point(metrics.load(native / "ready.png"), metrics.load(native / "bare" / "ready.png"), box))
            if len(points) >= 3:
                fits[f"{appearance}.{name}"] = fit(points)
    return fits
```

- [ ] **Step 6: Run every harness test**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: `OK`.

- [ ] **Step 7: Check the tone fit on 2A's native captures.** `python3 tool/glass_lab/harness/lab.py tonefit build/glass_lab/runs/20260930-082046`, then the same with `20260930-094506 --a11y reduce-transparency` and `20260930-095626 --a11y increase-contrast`. Expected: the numbers in Task 4's seed script (`TONE`), each with its `max_error_luma` (0.45–1.42 except the 44 pt light rows, 8.7 plain and 4.85 under Increase Contrast, where the interior is small).

- [ ] **Step 8: Commit**

```bash
git add tool/glass_lab/harness
git commit -m "fix(mobile): tune pads shadow steps, refuses stale builds, keeps the committed start and matches rows to accessibility

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Clear glass stays untinted under Reduce Transparency and Increase Contrast (finding 8b)

**Files:**
- Modify: `packages/ios_liquid_glass/lib/src/material/glass_material.dart`, `packages/ios_liquid_glass/lib/src/api/glass_foreground.dart`
- Test: `packages/ios_liquid_glass/test/glass_material_test.dart`, `packages/ios_liquid_glass/test/glass_effect_test.dart`

**Interfaces:**
- Produces: `GlassMaterial.resolve` keeps the tint under RT/IC only for `Glass.regular.tint(c)` (the plain-mode `tinted` row), never for `Glass.clear.tint(c)`, which the README promises is untinted. `GlassForeground.colorOf` returns the tinted (white) foreground only for regular glass with a tint.

- [ ] **Step 1: Write the failing tests.** In `packages/ios_liquid_glass/test/glass_material_test.dart`, insert before the test `untinted glass under reduce transparency keeps the RT row's own tintAmount`:

```dart
  test('clear glass stays untinted under reduce transparency and increase contrast', () {
    for (final accessibility in const [GlassAccessibilityData(reduceTransparency: true), GlassAccessibilityData(increaseContrast: true)]) {
      expect(resolve(glass: Glass.clear.tint(accent), accessibility: accessibility)['tintAmount'], GlassMaterial.defaults['tintAmount']);
    }
  });

```

In `packages/ios_liquid_glass/test/glass_effect_test.dart`, at the end of the test `foreground is white in dark, black in light and white on tinted glass`, after `expect(seen, GlassForeground.tinted);`, add:

```dart
    await tester.pumpWidget(_host(GlassEffect(glass: Glass.clear.tint(_accent), child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.light);
```

Run, from `packages/ios_liquid_glass`: `flutter test test/glass_material_test.dart test/glass_effect_test.dart`
Expected: 2 failures (`tintAmount` is 1.0 or 0.9, and the foreground is white).

- [ ] **Step 2: Fix the resolve condition.** In `glass_material.dart`, change

```dart
    if ((row == 'reduceTransparency' || row == 'increaseContrast') && glass.tintColor != null) {
```

to

```dart
    if ((row == 'reduceTransparency' || row == 'increaseContrast') && glass.kind == GlassKind.regular && glass.tintColor != null) {
```

- [ ] **Step 3: Fix the foreground.** Replace `packages/ios_liquid_glass/lib/src/api/glass_foreground.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';

class GlassForeground extends StatelessWidget {
  const GlassForeground({super.key, required this.child});

  static const Color dark = Color(0xFFFFFFFF);
  static const Color light = Color(0xFF000000);
  static const Color tinted = Color(0xFFFFFFFF);

  final Widget child;

  static Color colorOf(BuildContext context) {
    final glass = GlassEffectScope.maybeOf(context);
    if (glass != null && glass.kind == GlassKind.regular && glass.tintColor != null) return tinted;
    return GlassTheme.brightnessOf(context) == Brightness.dark ? dark : light;
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(context);
    return DefaultTextStyle.merge(
      style: TextStyle(color: color),
      child: IconTheme.merge(data: IconThemeData(color: color), child: child),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the package gates.** `flutter test test/glass_material_test.dart test/glass_effect_test.dart` passes; `flutter analyze` prints "No issues found!".

- [ ] **Step 5: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "fix(mobile): clear glass stays untinted under reduce transparency and increase contrast

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The iOS 27 edge: crisp silhouette, outer outline, top and bottom line and sheen (finding 2)

**Files:**
- Modify:
  - `packages/ios_liquid_glass/lib/assets/shaders/displacement_encoding.glsl`, `liquid_glass_geometry_blended.frag`, `liquid_glass_final_render.frag`
  - `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart`
  - `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart` (uniform packing)
  - `packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart` (geometry uniforms, bounds)
  - `packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart` (`requiresGeometryRebuild`, image sizes)
  - `packages/ios_liquid_glass/lib/src/internal/snap_rect_to_pixels.dart` (`toPixelCount`)
  - `packages/ios_liquid_glass/lib/src/material/glass_material.dart` (defaults, `toSettings`)
  - `packages/ios_liquid_glass/lib/src/material/ios27.dart`, only through the seed script in Step 8
- Test: `packages/ios_liquid_glass/test/liquid_glass_settings_test.dart`, `packages/ios_liquid_glass/test/glass_material_test.dart`, `packages/ios_liquid_glass/test/pixel_count_test.dart`

**Interfaces:**
- Produces:
  - `LiquidGlassSettings` loses `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight` and `effectiveHairline`, and gains `outline`, `outlineTop`, `outlineWidth` (pt), `sheen`, `sheenWidth` (pt), `effectiveOutline`, `effectiveOutlineTop` and `effectiveSheen`. `specularWidth` is now the decay length of the line in pt.
  - `GlassMaterial.defaults` and `toSettings` follow: `outline 0`, `outlineTop 0`, `outlineWidth 0.5`, `specular 0`, `specularWidth 0.65`, `specularPower 2`, `specularFill 0.9`, `sheen 0`, `sheenWidth 2.5`, `lightAngle 1.5708`.
  - The geometry texture now encodes the signed distance to the silhouette in its blue channel (`0.5 − 0.5 · sd / thickness`, so a band `outlineWidth` + 1 px outside the shape is inside the texture too) and uses alpha as an "inside the shape or its outline band" flag. `encodeGeometry` and `decodeSignedDistance` live in `displacement_encoding.glsl`.
  - Pixel-snapped image sizes are rounded, not ceiled (`double.toPixelCount()` in `snap_rect_to_pixels.dart`), in the geometry picture, the rendered geometry cache and the render object's geometry image (ruling 18).
  - The geometry uniforms' second float (`uOpticalProps.y`) carries the outline band in physical px; it was the unused dispersion. The geometry bounds grow by `outlineWidth + 1` pt, and a change of `outlineWidth` rebuilds the geometry.
  - Final render uniforms: `uTintSheen = (tintBlack, tintWhite, sheen, sheenWidth·dpr)`, `uOutline = (outline, outlineTop, outlineWidth·dpr, 0)`, `uLight = (specular, specularWidth·dpr, specularPower, specularFill)`.
- The model, per pixel, measured against native (prototype evidence in the header):
  1. coverage is `clamp(0.5 − sd, 0, 1)` in physical px, so the silhouette pixel is fully lit (native's first row on black reads 95; the 2A AA `1 − smoothstep(−2, 0, sd)` gave 26);
  2. outside the silhouette, a band of `outlineWidth` darkens the backdrop by `mix(outlineTop, outline, |n.x|)`: native draws a dark line at the curved ends (white backdrop, dark: two pixels at 40 and 129 luma against 234) and none at the top in dark appearance;
  3. inside, the line `specular · exp(−d / specularWidth)` and the sheen `sheen · exp(−d / sheenWidth)`, both weighted by the key and fill lobes of `lightAngle` (now straight down the inward normal of the top edge, 1.5708) and faded out over the last 30% of the bevel, so the ends (horizontal normal) get none: native's top on black reads 95, 76, 62 then 45 … 32, the ends read 31 flat;
  4. the adaptive inner hairline is gone: native shows no inner line on any backdrop, in either appearance, with or without accessibility modes (`increase-contrast` and `reduce-transparency` runs `20260930-095626`, `20260930-094506`).

- [ ] **Step 1: Write the failing tests.** Replace `packages/ios_liquid_glass/test/liquid_glass_settings_test.dart` and `packages/ios_liquid_glass/test/glass_material_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/internal/render_liquid_glass_geometry.dart';

void main() {
  test('fillRatio defaults to upstream symmetric look', () {
    expect(const LiquidGlassSettings().fillRatio, 0.8);
  });

  test('copyWith changes and preserves fillRatio', () {
    const base = LiquidGlassSettings(fillRatio: 0.25);
    expect(base.copyWith(thickness: 3).fillRatio, 0.25);
    expect(base.copyWith(fillRatio: 0.5).fillRatio, 0.5);
  });

  test('fillRatio takes part in equality', () {
    expect(const LiquidGlassSettings(fillRatio: 0.2), isNot(const LiquidGlassSettings(fillRatio: 0.3)));
  });

  test('the iOS look defaults leave the backdrop untouched', () {
    const settings = LiquidGlassSettings();
    expect([settings.toneBlack, settings.toneMid, settings.toneWhite], [0, 0.5, 1]);
    expect([settings.tintBlack, settings.tintWhite], [1, 1]);
    expect([settings.outline, settings.outlineTop, settings.specular, settings.sheen], [0, 0, 0, 0]);
  });

  test('visibility fades the tone curve and edge light towards no effect', () {
    const settings = LiquidGlassSettings(
      visibility: 0.5,
      toneBlack: 0.2,
      toneMid: 0.7,
      toneWhite: 0.6,
      outline: 0.4,
      outlineTop: 0.2,
      specular: 0.8,
      sheen: 0.1,
    );
    expect(settings.effectiveToneBlack, closeTo(0.1, 1e-9));
    expect(settings.effectiveToneMid, closeTo(0.6, 1e-9));
    expect(settings.effectiveToneWhite, closeTo(0.8, 1e-9));
    expect(settings.effectiveOutline, closeTo(0.2, 1e-9));
    expect(settings.effectiveOutlineTop, closeTo(0.1, 1e-9));
    expect(settings.effectiveSpecular, closeTo(0.4, 1e-9));
    expect(settings.effectiveSheen, closeTo(0.05, 1e-9));
  });

  test('copyWith and equality cover every iOS look field', () {
    const base = LiquidGlassSettings();
    final changed = [
      base.copyWith(toneBlack: 0.1),
      base.copyWith(toneMid: 0.4),
      base.copyWith(toneWhite: 0.9),
      base.copyWith(tintBlack: 0.8),
      base.copyWith(tintWhite: 1.1),
      base.copyWith(outline: 0.3),
      base.copyWith(outlineTop: 0.2),
      base.copyWith(outlineWidth: 2),
      base.copyWith(specular: 0.5),
      base.copyWith(specularWidth: 3),
      base.copyWith(specularPower: 4),
      base.copyWith(specularFill: 0.1),
      base.copyWith(sheen: 0.2),
      base.copyWith(sheenWidth: 5),
    ];
    for (final settings in changed) {
      expect(settings, isNot(base));
    }
    expect(base.copyWith(toneMid: 0.4).copyWith(outline: 0.3).toneMid, 0.4);
  });

  test('a new outline width rebuilds the cached geometry, a new outline strength does not', () {
    const base = LiquidGlassSettings(outlineWidth: 0.5);
    expect(base.copyWith(outlineWidth: 0.8).requiresGeometryRebuild(base), isTrue);
    expect(base.copyWith(outline: 0.9).requiresGeometryRebuild(base), isFalse);
  });
}
```

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  const accent = Color(0xFF1ACB64);
  const table = {
    'dark.regular.44': {'frost': 2.0, 'toneBlack': 0.1},
    'dark.regular.88': {'frost': 4.0, 'toneBlack': 0.2},
    'dark.regular.200': {'frost': 8.0, 'toneBlack': 0.3},
    'dark.tinted.88': {'tintAmount': 0.9, 'tintBlack': 1.3, 'tintWhite': 0.7},
    'dark.clear.88': {'frost': 1.0},
    'dark.reduceTransparency.88': {'toneBlack': 0.16, 'toneWhite': 0.16},
    'dark.increaseContrast.88': {'outline': 0.9},
    'light.regular.88': {'frost': 5.0},
  };

  GlassMaterial resolve({
    Glass glass = Glass.regular,
    double side = 88,
    Brightness brightness = Brightness.dark,
    GlassAccessibilityData accessibility = const GlassAccessibilityData(),
  }) => GlassMaterial.resolve(glass: glass, shorterSide: side, brightness: brightness, accessibility: accessibility, table: table);

  test('reads the row for the appearance at an anchor', () {
    expect(resolve()['frost'], 4);
    expect(resolve(brightness: Brightness.light)['frost'], 5);
  });

  test('interpolates on log size between anchors', () {
    final side = math.sqrt(44 * 88);
    expect(resolve(side: side)['frost'], closeTo(3, 1e-9));
    expect(resolve(side: side)['toneBlack'], closeTo(0.15, 1e-9));
  });

  test('clamps outside the anchors', () {
    expect(resolve(side: 10)['frost'], 2);
    expect(resolve(side: 900)['frost'], 8);
  });

  test('missing fields fall back to defaults', () {
    expect(resolve()['saturation'], GlassMaterial.defaults['saturation']);
  });

  test('picks the row from the glass and accessibility, accessibility first', () {
    expect(GlassMaterial.rowFor(Glass.regular, const GlassAccessibilityData()), 'regular');
    expect(GlassMaterial.rowFor(Glass.clear, const GlassAccessibilityData()), 'clear');
    expect(GlassMaterial.rowFor(Glass.regular.tint(accent), const GlassAccessibilityData()), 'tinted');
    expect(GlassMaterial.rowFor(Glass.clear, const GlassAccessibilityData(increaseContrast: true)), 'increaseContrast');
    expect(
      GlassMaterial.rowFor(Glass.regular, const GlassAccessibilityData(reduceTransparency: true, increaseContrast: true)),
      'reduceTransparency',
    );
    expect(resolve(glass: Glass.regular.tint(accent))['tintAmount'], 0.9);
    expect(resolve(accessibility: const GlassAccessibilityData(reduceTransparency: true))['toneWhite'], 0.16);
  });

  test('overrides replace fields by name', () {
    final material = resolve().withOverrides({'frost': 12, 'toneMid': 0.4});
    expect(material['frost'], 12);
    expect(material['toneMid'], 0.4);
    expect(material['toneBlack'], 0.2);
  });

  test('settings carry every rendered field and the tint', () {
    final material = GlassMaterial(const {
      'thickness': 20,
      'dispersion': 0.03,
      'frost': 9,
      'saturation': 1.4,
      'toneBlack': 0.1,
      'toneMid': 0.4,
      'toneWhite': 0.8,
      'tintAmount': 0.9,
      'tintBlack': 0.8,
      'tintWhite': 1.1,
      'outline': 0.3,
      'outlineTop': 0.1,
      'outlineWidth': 0.6,
      'specular': 0.5,
      'sheen': 0.07,
      'sheenWidth': 2.4,
    });
    final settings = material.toSettings(tint: accent);
    expect(settings.thickness, 20);
    expect(settings.chromaticAberration, 0.03);
    expect(settings.blur, 9);
    expect(settings.saturation, 1.4);
    expect([settings.toneBlack, settings.toneMid, settings.toneWhite], [0.1, 0.4, 0.8]);
    expect([settings.tintBlack, settings.tintWhite], [0.8, 1.1]);
    expect(settings.glassColor, accent.withValues(alpha: 0.9));
    expect([settings.outline, settings.outlineTop, settings.outlineWidth], [0.3, 0.1, 0.6]);
    expect(settings.specular, 0.5);
    expect([settings.sheen, settings.sheenWidth], [0.07, 2.4]);
    expect(material.toSettings().glassColor.a, 0);
  });

  test('shadows are one outer shadow, or none at zero opacity', () {
    const shadow = GlassMaterial({'shadowOpacity': 0.2, 'shadowBlur': 10, 'shadowOffsetY': 3});
    expect(shadow.shadows.single.blurStyle, BlurStyle.outer);
    expect(shadow.shadows.single.offset, const Offset(0, 3));
    expect(const GlassMaterial({'shadowOpacity': 0}).shadows, isEmpty);
  });

  test('the shipped table has every row at every anchor', () {
    for (final appearance in ['dark', 'light']) {
      for (final row in ['regular', 'clear', 'tinted', 'reduceTransparency', 'increaseContrast']) {
        for (final anchor in GlassMaterial.anchors) {
          expect(ios27Table.containsKey('$appearance.$row.${anchor.toInt()}'), isTrue, reason: '$appearance.$row.$anchor');
        }
      }
    }
  });

  test('tinted glass keeps its tint under reduce transparency', () {
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['tintAmount'], 0.9);
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['toneWhite'], 0.16);
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['tintBlack'], 1.3);
    expect(resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(reduceTransparency: true))['tintWhite'], 0.7);
  });

  test('tinted glass keeps its tint under increase contrast', () {
    final material = resolve(glass: Glass.regular.tint(accent), accessibility: const GlassAccessibilityData(increaseContrast: true));
    expect(material['tintAmount'], 0.9);
    expect(material['tintBlack'], 1.3);
    expect(material['tintWhite'], 0.7);
    expect(material['outline'], 0.9);
  });

  test('clear glass stays untinted under reduce transparency and increase contrast', () {
    for (final accessibility in const [GlassAccessibilityData(reduceTransparency: true), GlassAccessibilityData(increaseContrast: true)]) {
      expect(resolve(glass: Glass.clear.tint(accent), accessibility: accessibility)['tintAmount'], GlassMaterial.defaults['tintAmount']);
    }
  });

  test('untinted glass under reduce transparency keeps the RT row\'s own tintAmount', () {
    expect(resolve(accessibility: const GlassAccessibilityData(reduceTransparency: true))['tintAmount'], GlassMaterial.defaults['tintAmount']);
  });
}
```

Run, from `packages/ios_liquid_glass`: `flutter test test/liquid_glass_settings_test.dart test/glass_material_test.dart`
Expected: compile errors, `No named parameter with the name 'outline'`.

- [ ] **Step 2: Replace** `packages/ios_liquid_glass/lib/assets/shaders/displacement_encoding.glsl` with:

```glsl
// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared utilities for encoding and decoding displacement data

// Encode displacement offset, height, and alpha into RGBA channels
// R: X displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// G: Y displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// B: Height (normalized to thickness)
// A: Alpha for anti-aliasing
vec4 encodeDisplacementData(vec2 displacement, float maxDisplacement, float height, float thickness, float alpha) {
    vec2 normalizedDisp = (displacement / maxDisplacement) * 0.5 + 0.5;
    normalizedDisp = clamp(normalizedDisp, 0.0, 1.0);
    
    float normalizedHeight = thickness > 0.0 ? clamp(height / thickness, 0.0, 1.0) : 0.0;
    
    return vec4(normalizedDisp.x, normalizedDisp.y, normalizedHeight, alpha);
}

vec4 encodeGeometry(vec2 displacement, float maxDisplacement, float signedDistance, float thickness) {
    vec2 normalizedDisp = clamp((displacement / maxDisplacement) * 0.5 + 0.5, 0.0, 1.0);
    float distance = clamp(signedDistance / max(thickness, 0.001), -1.0, 1.0);
    return vec4(normalizedDisp, 0.5 - 0.5 * distance, 1.0);
}

float decodeSignedDistance(vec4 encoded, float thickness) {
    return (0.5 - encoded.b) * 2.0 * thickness;
}

// Decode displacement from RG channels
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    vec2 normalized = encoded.rg;
    vec2 displacement = (normalized - 0.5) * 2.0 * maxDisplacement;
    return displacement;
}

// Decode height from B channel
float decodeHeight(vec4 encoded, float thickness) {
    return encoded.b * thickness;
}
```

- [ ] **Step 3: Replace** `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_geometry_blended.frag` with:

```glsl
// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry precomputation shader for blended liquid glass shapes
// This shader pre-computes the refraction displacement and encodes it into a texture
// Only needs to be re-run when shape geometry or layout changes

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "sdf.glsl"
#include "displacement_encoding.glsl"

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec4 uOpticalProps;
layout(location = 2) uniform float uNumShapes;
layout(location = 3) uniform float uShapeData[MAX_SHAPES * 6];

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uOutlineBand = max(uOpticalProps.y, 0.0);
float uBlend = uOpticalProps.w;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif
    
    float sd = sceneSDF(fragCoord, int(uNumShapes), uShapeData, uBlend);
    
    if (sd >= uOutlineBand + 1.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    float maxDisplacement = uThickness * 10.0;
    
    if (sd >= 0.0) {
        vec2 gradient = vec2(dx, dy);
        vec2 inward = length(gradient) > 0.0 ? -normalize(gradient) : vec2(0.0);
        fragColor = encodeGeometry(inward * maxDisplacement * 0.5, maxDisplacement, sd, uThickness);
        return;
    }
    
    float n_cos = max(uThickness + sd, 0.0) / uThickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
    
    float x = uThickness + sd;
    float sqrtTerm = sqrt(max(0.0, uThickness * uThickness - x * x));
    float height = mix(sqrtTerm, uThickness, float(sd < -uThickness));
    
    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 displacement = baseRefract.xy * baseRefractLength;
    
    fragColor = encodeGeometry(displacement, maxDisplacement, sd, uThickness);
}
```

- [ ] **Step 4: Replace** `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag` with:

```glsl
// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;
uniform vec4 uGlassColor;
uniform vec4 uOptics;
uniform vec4 uTone;
uniform vec4 uTintSheen;
uniform vec4 uOutline;
uniform vec4 uLight;
uniform vec2 uLightDirection;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float toneCurve(float l) {
    return uTone.x * (1.0 - l) * (1.0 - 2.0 * l) + 4.0 * uTone.y * l * (1.0 - l) + uTone.z * l * (2.0 * l - 1.0);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 screenUV = fragCoord / uSize;
    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, geometryUV);
    if (geometryData.a < 0.5) {
        fragColor = vec4(0.0);
        return;
    }

    float thickness = max(uOptics.x, 0.001);
    float signedDistance = decodeSignedDistance(geometryData, thickness);
    vec2 displacement = decodeDisplacement(geometryData, thickness * 10.0);
    vec2 normal = length(displacement) > 0.0001 ? normalize(displacement) : vec2(0.0);

    float coverage = clamp(0.5 - signedDistance, 0.0, 1.0);
    float outlineStrength = mix(uOutline.y, uOutline.x, abs(normal.x));
    float outlineCoverage = clamp(uOutline.z + 0.5 - signedDistance, 0.0, 1.0) * (1.0 - coverage);
    float outlineAlpha = clamp(outlineStrength, 0.0, 1.0) * outlineCoverage;
    if (coverage <= 0.0) {
        fragColor = vec4(0.0, 0.0, 0.0, outlineAlpha);
        return;
    }

    float edgeDistance = clamp(-signedDistance, 0.0, thickness);
    float rise = 1.0 - edgeDistance / thickness;
    float heightNorm = sqrt(max(0.0, 1.0 - rise * rise));
    float bevel = 1.0 - heightNorm;

    vec2 texel = 1.0 / uSize;
    float spread = uOptics.y * bevel;
    vec4 centre = texture(uBackgroundTexture, screenUV + displacement * texel);
    vec3 color = vec3(
        texture(uBackgroundTexture, screenUV + displacement * (1.0 + spread) * texel).r,
        centre.g,
        texture(uBackgroundTexture, screenUV + displacement * (1.0 - spread) * texel).b
    );

    float luminance = dot(color, LUMA);
    vec3 chroma = color - vec3(luminance);
    float toned = clamp(toneCurve(luminance), 0.0, 1.0);
    color = clamp(vec3(toned) + chroma * uOptics.z, 0.0, 1.0);

    vec3 tintTone = clamp(uGlassColor.rgb * mix(uTintSheen.x, uTintSheen.y, luminance), 0.0, 1.0);
    color = mix(color, tintTone, uGlassColor.a);

    float power = max(uLight.z, 0.001);
    float lobes = pow(max(0.0, dot(normal, uLightDirection)), power) + uLight.w * pow(max(0.0, dot(normal, -uLightDirection)), power);
    float fade = 1.0 - smoothstep(0.7 * thickness, thickness, edgeDistance);
    float line = uLight.x * exp(-edgeDistance / max(uLight.y, 0.001));
    float sheen = uTintSheen.z * exp(-edgeDistance / max(uTintSheen.w, 0.001));
    color = clamp(color + vec3(lobes * fade * (line + sheen)), 0.0, 1.0);

    float alpha = coverage + outlineAlpha;
    fragColor = vec4(color * coverage, alpha);
}
```

- [ ] **Step 5: Replace** `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart` with the version below. Upstream's dartdoc is kept.

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_render_scope.dart';

/// Represents the settings for a liquid glass effect.
class LiquidGlassSettings with Equatable {
  /// Creates a new [LiquidGlassSettings] with the given settings.
  const LiquidGlassSettings({
    this.visibility = 1.0,
    this.glassColor = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20,
    this.blur = 5,
    this.chromaticAberration = .01,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = .5,
    this.ambientStrength = 0,
    this.refractiveIndex = 1.2,
    this.saturation = 1.5,
    this.fillRatio = 0.8,
    this.toneBlack = 0,
    this.toneMid = 0.5,
    this.toneWhite = 1,
    this.tintBlack = 1,
    this.tintWhite = 1,
    this.outline = 0,
    this.outlineTop = 0,
    this.outlineWidth = 0.5,
    this.specular = 0,
    this.specularWidth = 1.5,
    this.specularPower = 2,
    this.specularFill = 0.4,
    this.sheen = 0,
    this.sheenWidth = 3,
  });

  /// Creates a new [LiquidGlassSettings] with the given settings where each
  /// setting works like it does in Figma, where it is a percentage from
  /// 0 to 100.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
    double visibility = 1.0,
    double lightIntensity = 50,
    double lightAngle = 0.5 * pi,
    Color glassColor = const Color.fromARGB(0, 255, 255, 255),
  }) : this(
          visibility: visibility,
          refractiveIndex: 1 + (refraction / 100) * 0.2,
          thickness: depth,
          chromaticAberration: 4 * (dispersion / 100),
          lightIntensity: lightIntensity / 100,
          blur: frost,
          lightAngle: lightAngle,
          ambientStrength: 0.1,
          saturation: 1.5,
          glassColor: glassColor,
        );

  /// Retrieves the nearest [LiquidGlassSettings] from the widget tree.
  ///
  /// This will look for the nearest ancestor [LiquidGlassLayer] or
  /// [LiquidGlassRenderScope] widget in the widget tree.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// A factor that can be used to scale all thickness-related properties.
  ///
  /// Defaults to 1.0.
  final double visibility;

  /// The color tint of the glass effect.
  ///
  /// Opacity defines the intensity of the tint.
  final Color glassColor;

  /// The effective glass color taking visibility into account.
  Color get effectiveGlassColor =>
      glassColor.withValues(alpha: glassColor.a * visibility);

  /// The thickness of the glass surface.
  ///
  /// Thicker surfaces refract the light more intensely.
  final double thickness;

  /// The effective thickness taking visibility into account.
  double get effectiveThickness => thickness * visibility;

  /// The blur of the glass effect.
  ///
  /// Higher values create a more frosted appearance.
  ///
  /// Defaults to 0.
  final double blur;

  /// The effective blur taking visibility into account.
  double get effectiveBlur => blur * visibility;

  /// The chromatic aberration of the glass effect (WIP).
  ///
  /// This is a little ugly still.
  ///
  /// Higher values create more pronounced color fringes.
  final double chromaticAberration;

  /// The effective chromatic aberration taking visibility into account.
  double get effectiveChromaticAberration => chromaticAberration * visibility;

  /// The angle of the light source in radians.
  ///
  /// This determines where the highlights on shapes will come from.
  final double lightAngle;

  /// The intensity of the light source.
  ///
  /// Higher values create more pronounced highlights.
  final double lightIntensity;

  /// The effective light intensity taking visibility into account.
  double get effectiveLightIntensity => lightIntensity * visibility;

  /// The strength of the ambient light.
  ///
  /// Higher values create more pronounced ambient light.
  final double ambientStrength;

  /// The effective ambient strength taking visibility into account.
  double get effectiveAmbientStrength => ambientStrength * visibility;

  /// The strength of the refraction.
  ///
  /// Higher values create more pronounced refraction.
  /// Defaults to 1.51
  final double refractiveIndex;

  /// The saturation adjustment for pixels that shine through the glass.
  ///
  /// 1.0 means no change, values < 1.0 desaturate the background,
  /// values > 1.0 increase saturation.
  /// Defaults to 1.0
  final double saturation;

  /// The effective saturation taking visibility into account.
  double get effectiveSaturation => 1 + (saturation - 1) * visibility;

  final double fillRatio;

  final double toneBlack;

  double get effectiveToneBlack => toneBlack * visibility;

  final double toneMid;

  double get effectiveToneMid => 0.5 + (toneMid - 0.5) * visibility;

  final double toneWhite;

  double get effectiveToneWhite => 1 + (toneWhite - 1) * visibility;

  final double tintBlack;

  final double tintWhite;

  final double outline;

  double get effectiveOutline => outline * visibility;

  final double outlineTop;

  double get effectiveOutlineTop => outlineTop * visibility;

  final double outlineWidth;

  final double specular;

  double get effectiveSpecular => specular * visibility;

  final double specularWidth;

  final double specularPower;

  final double specularFill;

  final double sheen;

  double get effectiveSheen => sheen * visibility;

  final double sheenWidth;

  /// Creates a new [LiquidGlassSettings] with the given settings.
  LiquidGlassSettings copyWith({
    double? visibility,
    Color? glassColor,
    double? thickness,
    double? blur,
    double? chromaticAberration,
    double? blend,
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    double? refractiveIndex,
    double? saturation,
    double? fillRatio,
    double? toneBlack,
    double? toneMid,
    double? toneWhite,
    double? tintBlack,
    double? tintWhite,
    double? outline,
    double? outlineTop,
    double? outlineWidth,
    double? specular,
    double? specularWidth,
    double? specularPower,
    double? specularFill,
    double? sheen,
    double? sheenWidth,
  }) =>
      LiquidGlassSettings(
        visibility: visibility ?? this.visibility,
        glassColor: glassColor ?? this.glassColor,
        thickness: thickness ?? this.thickness,
        blur: blur ?? this.blur,
        chromaticAberration: chromaticAberration ?? this.chromaticAberration,
        lightAngle: lightAngle ?? this.lightAngle,
        lightIntensity: lightIntensity ?? this.lightIntensity,
        ambientStrength: ambientStrength ?? this.ambientStrength,
        refractiveIndex: refractiveIndex ?? this.refractiveIndex,
        saturation: saturation ?? this.saturation,
        fillRatio: fillRatio ?? this.fillRatio,
        toneBlack: toneBlack ?? this.toneBlack,
        toneMid: toneMid ?? this.toneMid,
        toneWhite: toneWhite ?? this.toneWhite,
        tintBlack: tintBlack ?? this.tintBlack,
        tintWhite: tintWhite ?? this.tintWhite,
        outline: outline ?? this.outline,
        outlineTop: outlineTop ?? this.outlineTop,
        outlineWidth: outlineWidth ?? this.outlineWidth,
        specular: specular ?? this.specular,
        specularWidth: specularWidth ?? this.specularWidth,
        specularPower: specularPower ?? this.specularPower,
        specularFill: specularFill ?? this.specularFill,
        sheen: sheen ?? this.sheen,
        sheenWidth: sheenWidth ?? this.sheenWidth,
      );

  @override
  List<Object?> get props => [
        visibility,
        glassColor,
        thickness,
        blur,
        chromaticAberration,
        lightAngle,
        lightIntensity,
        ambientStrength,
        refractiveIndex,
        saturation,
        fillRatio,
        toneBlack,
        toneMid,
        toneWhite,
        tintBlack,
        tintWhite,
        outline,
        outlineTop,
        outlineWidth,
        specular,
        specularWidth,
        specularPower,
        specularFill,
        sheen,
        sheenWidth,
      ];
}
```

- [ ] **Step 6: Wire the uniforms and the band.**
  - In `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart`, `_updateShaderSettings` becomes:

```dart
  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.effectiveThickness * devicePixelRatio,
          settings.effectiveChromaticAberration,
          settings.effectiveSaturation,
          0,
          settings.effectiveToneBlack,
          settings.effectiveToneMid,
          settings.effectiveToneWhite,
          0,
          settings.tintBlack,
          settings.tintWhite,
          settings.effectiveSheen,
          settings.sheenWidth * devicePixelRatio,
          settings.effectiveOutline,
          settings.effectiveOutlineTop,
          settings.outlineWidth * devicePixelRatio,
          0,
          settings.effectiveSpecular,
          settings.specularWidth * devicePixelRatio,
          settings.specularPower,
          settings.specularFill,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        );
    });
  }
```

  - In `packages/ios_liquid_glass/lib/src/liquid_glass_blend_group.dart`, `updateShaderWithSettings` sends `settings.outlineWidth * devicePixelRatio` instead of `settings.effectiveChromaticAberration` as the second float, and `gatherShapeData` returns `(layerBounds ?? Rect.zero).inflate(blend * .25 + settings.outlineWidth + 1)`.
  - In `packages/ios_liquid_glass/lib/src/internal/render_liquid_glass_geometry.dart`, the anonymous extension at the end of the file gets a name, so the settings test can reach it, and rebuilds on a new outline width:

```dart
@internal
extension GeometryRebuild on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return effectiveThickness != other.effectiveThickness ||
        refractiveIndex != other.refractiveIndex ||
        outlineWidth != other.outlineWidth;
  }
}
```

  - Replace `packages/ios_liquid_glass/lib/src/material/glass_material.dart` with (Task 3's clear-glass condition is already in it):

```dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/liquid_glass_settings.dart';
import 'package:ios_liquid_glass/src/material/ios27.dart';

@immutable
class GlassMaterial {
  const GlassMaterial(this.values);

  static const List<double> anchors = [44, 88, 200];

  static const Map<String, double> defaults = {
    'thickness': 18,
    'refractiveIndex': 1.2,
    'dispersion': 0.02,
    'frost': 4,
    'toneBlack': 0,
    'toneMid': 0.5,
    'toneWhite': 1,
    'saturation': 1.2,
    'tintAmount': 0,
    'tintBlack': 1,
    'tintWhite': 1,
    'outline': 0,
    'outlineTop': 0,
    'outlineWidth': 0.5,
    'specular': 0,
    'specularWidth': 0.65,
    'specularPower': 2,
    'specularFill': 0.9,
    'sheen': 0,
    'sheenWidth': 2.5,
    'lightAngle': 1.5708,
    'shadowOffsetY': 0,
    'shadowBlur': 0,
    'shadowOpacity': 0,
  };

  final Map<String, double> values;

  double operator [](String name) => values[name] ?? defaults[name]!;

  GlassMaterial lerp(GlassMaterial other, double t) => GlassMaterial({
    for (final name in defaults.keys) name: this[name] + (other[name] - this[name]) * t,
  });

  GlassMaterial withOverrides(Map<String, double> overrides) =>
      overrides.isEmpty ? this : GlassMaterial({...values, ...overrides});

  LiquidGlassSettings toSettings({Color? tint}) => LiquidGlassSettings(
    thickness: this['thickness'],
    refractiveIndex: this['refractiveIndex'],
    chromaticAberration: this['dispersion'],
    blur: this['frost'],
    toneBlack: this['toneBlack'],
    toneMid: this['toneMid'],
    toneWhite: this['toneWhite'],
    saturation: this['saturation'],
    glassColor: tint == null ? const Color(0x00000000) : tint.withValues(alpha: this['tintAmount']),
    tintBlack: this['tintBlack'],
    tintWhite: this['tintWhite'],
    outline: this['outline'],
    outlineTop: this['outlineTop'],
    outlineWidth: this['outlineWidth'],
    specular: this['specular'],
    specularWidth: this['specularWidth'],
    specularPower: this['specularPower'],
    specularFill: this['specularFill'],
    sheen: this['sheen'],
    sheenWidth: this['sheenWidth'],
    lightAngle: this['lightAngle'],
  );

  List<BoxShadow> get shadows => this['shadowOpacity'] <= 0
      ? const []
      : [
          BoxShadow(
            blurStyle: BlurStyle.outer,
            color: const Color(0xFF000000).withValues(alpha: this['shadowOpacity']),
            blurRadius: this['shadowBlur'],
            offset: Offset(0, this['shadowOffsetY']),
          ),
        ];

  static String rowFor(Glass glass, GlassAccessibilityData accessibility) {
    if (accessibility.reduceTransparency) return 'reduceTransparency';
    if (accessibility.increaseContrast) return 'increaseContrast';
    if (glass.kind == GlassKind.clear) return 'clear';
    return glass.tintColor == null ? 'regular' : 'tinted';
  }

  static GlassMaterial resolve({
    required Glass glass,
    required double shorterSide,
    required Brightness brightness,
    GlassAccessibilityData accessibility = const GlassAccessibilityData(),
    Map<String, Map<String, double>> table = ios27Table,
  }) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';
    final row = rowFor(glass, accessibility);
    final material = _resolveRow(appearance, row, shorterSide, table);
    if ((row == 'reduceTransparency' || row == 'increaseContrast') && glass.kind == GlassKind.regular && glass.tintColor != null) {
      final tinted = _resolveRow(appearance, 'tinted', shorterSide, table);
      return material.withOverrides({
        'tintAmount': tinted['tintAmount'],
        'tintBlack': tinted['tintBlack'],
        'tintWhite': tinted['tintWhite'],
      });
    }
    return material;
  }

  static GlassMaterial _resolveRow(
    String appearance,
    String row,
    double shorterSide,
    Map<String, Map<String, double>> table,
  ) {
    GlassMaterial at(double anchor) => GlassMaterial(table['$appearance.$row.${anchor.toInt()}'] ?? const {});
    final side = shorterSide.clamp(anchors.first, anchors.last);
    for (var i = 0; i < anchors.length - 1; i++) {
      final low = anchors[i], high = anchors[i + 1];
      if (side <= high) {
        final t = (math.log(side) - math.log(low)) / (math.log(high) - math.log(low));
        if (t <= 0) return at(low);
        if (t >= 1) return at(high);
        return at(low).lerp(at(high), t);
      }
    }
    return at(anchors.last);
  }
}
```

- [ ] **Step 7: Round the geometry image sizes.** Create `packages/ios_liquid_glass/test/pixel_count_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/src/internal/snap_rect_to_pixels.dart';

void main() {
  test('a pixel-snapped geometry of an outlined glass is exactly as many pixels as its bounds', () {
    for (final (x, y, w, h, pixelsWide, pixelsTall) in [(76.0, 329.0, 250.0, 88.0, 760, 274), (126.0, 237.0, 150.0, 44.0, 460, 142), (21.0, 465.0, 360.0, 200.0, 1090, 610)]) {
      final local = Rect.fromLTWH(0, 0, w, h).inflate(1.55).snapToPixels(3);
      final screen = local.shift(Offset(x, y)).snapToPixels(3);
      expect((screen.width * 3).toPixelCount(), pixelsWide);
      expect((screen.height * 3).toPixelCount(), pixelsTall);
    }
  });
}
```

Run it: it fails to compile (`toPixelCount` is undefined). Then replace `packages/ios_liquid_glass/lib/src/internal/snap_rect_to_pixels.dart` with:

```dart
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

@internal
extension SnapRectToPixels on Rect {
  Rect snapToPixels(double devicePixelRatio) {
    return Rect.fromLTRB(
      left.snapToPixel(devicePixelRatio: devicePixelRatio),
      top.snapToPixel(devicePixelRatio: devicePixelRatio),
      right.snapToPixel(devicePixelRatio: devicePixelRatio),
      bottom.snapToPixel(devicePixelRatio: devicePixelRatio),
    );
  }
}

@internal
extension PixelCount on double {
  int toPixelCount() => round();
}

extension on double {
  double snapToPixel({required double devicePixelRatio}) {
    return (this * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }
}
```

and replace every `.ceil()` that sizes a geometry image with `.toPixelCount()`: `(bounds.width * devicePixelRatio).ceil()` and its height in `_buildGeometryPicture` and the two `matteBounds.width.ceil()` / `matteBounds.height.ceil()` pairs (`renderAsync`, `render`) in `render_liquid_glass_geometry.dart`, and `size.width.ceil()` / `size.height.ceil()` in `_buildGeometryImage` of `liquid_glass_render_object.dart`. `grep -n "ceil()" lib/src/internal/render_liquid_glass_geometry.dart lib/src/rendering/liquid_glass_render_object.dart` then prints nothing, and the test passes.

- [ ] **Step 8: Seed the table.** This is the only table write outside `lab.py tune --write`, like 2A's seed (ruling 3). It drops the four hairline fields and writes, from the prototype:
  - the edge fields per appearance, tuned on 200 pt glass over `black` and `white` (`20260930-173453` dark, `20260930-202218` light), and a stronger outline for dark Reduce Transparency and Increase Contrast (native reads 7 and 3 luma in the outline on white);
  - the shadow per appearance and size, fitted to native (sigma, offset, opacity) and tuned at 200 pt with `--pad 60` (`20260930-210741`, `20260930-212328`); clear glass gets none;
  - the tone points of the regular, tinted and accessibility rows from `lab.py tonefit` on 2A's native captures (Task 2 Step 7);
  - the light 200 pt lens (`thickness 4`, `refractiveIndex 1.075`, `20260930-215835`): 2A's 48 pt came from a rim measure that never looked at the ends.

  Save as `seed_edge_model.py` in the session scratchpad and run it from `packages/mobile`:

```python
import sys

sys.path.insert(0, "tool/glass_lab/harness")
import material_table

RETIRED = ("hairline", "hairlineWidth", "hairlineDark", "hairlineLight")
EDGE = {
    "dark": {"outline": 0.85, "outlineTop": 0.0, "outlineWidth": 0.55, "specular": 0.28, "specularWidth": 0.55, "specularPower": 2.0, "specularFill": 1.025, "sheen": 0.06, "sheenWidth": 2.0, "lightAngle": 1.5708},
    "light": {"outline": 0.35, "outlineTop": 0.125, "outlineWidth": 0.55, "specular": 0.28, "specularWidth": 0.5, "specularPower": 2.0, "specularFill": 0.95, "sheen": 0.06, "sheenWidth": 2.75, "lightAngle": 1.5708},
}
STRONG_OUTLINE = {("dark", "reduceTransparency"): 0.97, ("dark", "increaseContrast"): 0.97}
SHADOW = {
    ("dark", 44): (3.5, 8.0, 0.012),
    ("dark", 88): (11.3, 8.0, 0.054),
    ("dark", 200): (29.0, 8.0, 0.16),
    ("light", 44): (3.5, 8.0, 0.012),
    ("light", 88): (9.5, 8.0, 0.039),
    ("light", 200): (29.6, 8.0, 0.12),
}

TONE = {
    ("dark", "regular", 44): (0.1263, 0.5211, 0.7207),
    ("dark", "regular", 88): (0.1246, 0.4779, 0.5767),
    ("dark", "regular", 200): (0.1253, 0.4527, 0.4773),
    ("light", "regular", 44): (0.5152, 0.7758, 1.0031),
    ("light", "regular", 88): (0.5226, 0.7745, 0.9971),
    ("light", "regular", 200): (0.5336, 0.7968, 0.9967),
    ("dark", "reduceTransparency", 44): (0.0784, 0.0808, 0.0781),
    ("dark", "reduceTransparency", 88): (0.0784, 0.0804, 0.0782),
    ("dark", "reduceTransparency", 200): (0.0784, 0.0802, 0.0782),
    ("light", "reduceTransparency", 44): (0.9799, 0.9866, 1.0019),
    ("light", "reduceTransparency", 88): (0.981, 0.9877, 1.0007),
    ("light", "reduceTransparency", 200): (0.9809, 0.9887, 1.0006),
    ("dark", "increaseContrast", 44): (0.1077, 0.1562, 0.1796),
    ("dark", "increaseContrast", 88): (0.1098, 0.168, 0.1956),
    ("dark", "increaseContrast", 200): (0.1187, 0.2148, 0.291),
    ("light", "increaseContrast", 44): (0.7207, 0.872, 1.0036),
    ("light", "increaseContrast", 88): (0.73, 0.8739, 1.0002),
    ("light", "increaseContrast", 200): (0.7496, 0.8895, 0.9992),
}
TONE_FROM = {"tinted": "regular"}
LENS = {("light", 200): (4.0, 1.075)}

rows = material_table.read()
for key, values in rows.items():
    appearance, row, anchor = key.split(".")
    for name in RETIRED:
        values.pop(name, None)
    values.update(EDGE[appearance])
    values["outline"] = STRONG_OUTLINE.get((appearance, row), values["outline"])
    blur, offset, opacity = SHADOW[(appearance, int(anchor))]
    values.update(shadowBlur=blur, shadowOffsetY=offset, shadowOpacity=0.0 if row == "clear" else opacity)
    tone = TONE.get((appearance, TONE_FROM.get(row, row), int(anchor)))
    if tone:
        values.update(toneBlack=tone[0], toneMid=tone[1], toneWhite=tone[2])
    lens = LENS.get((appearance, int(anchor)))
    if lens:
        values.update(thickness=lens[0], refractiveIndex=lens[1])
material_table.write(rows)
print(f"seeded {len(rows)} rows")
```

Run: `python3 <scratchpad>/seed_edge_model.py`
Expected: `seeded 30 rows`. Then `python3 -m unittest tool/glass_lab/harness/tests/test_tune.py` stays `OK` (the writer-format and every-row tests read the new file). The prototype applied this script to 2A's committed table and got exactly the table it measured.

- [ ] **Step 9: Run the gates.** Package: `flutter analyze` ("No issues found!") and `flutter test` (all pass). App, from `packages/mobile`: `flutter analyze` and `flutter test`; Operator reads no hairline field, so it stays green.

- [ ] **Step 10: Prove the shader compiles for Impeller and draws the edge.** Run `python3 tool/glass_lab/harness/lab.py build example`, then one start-only evaluation (it scores the seeded row and changes nothing):

```bash
python3 tool/glass_lab/harness/lab.py tune --scene material.regular --appearance dark --backdrops black,white --size 200 --region s200 --params outline=0.85:0.85:1 --passes 1
```

Expected: one candidate, and in its `log.jsonl` `rim_rms` about 1.5 on `black` and 2.3 on `white`, every side under 2.4 (prototype `20260930-173453`, candidate 64). 2A's table measured 7.1 and 19.2 with this measure (re-analysis of run `20260930-082046`).

- [ ] **Step 11: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "feat(mobile): ios_liquid_glass draws the iOS 27 edge: crisp silhouette, outer outline, line and sheen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The scroll edge blurs with real Gaussians (finding 7)

**Files:**
- Create: `packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_mask.frag`
- Delete: `packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag`
- Modify: `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart`, `packages/ios_liquid_glass/lib/src/material/scroll_edge_material.dart` (two defaults), `packages/ios_liquid_glass/pubspec.yaml` (shader list), `packages/ios_liquid_glass/lib/src/material/ios27_scroll_edge.dart` (only through the seed script in Step 6)
- Test: `packages/ios_liquid_glass/test/scroll_edge_effect_test.dart`

**Interfaces:**
- Produces:
  - `ScrollEdgeEffect.levels({blur, knee, capBlur, capExtent})` → `List<ScrollEdgeLevel>`: `knee 0` (hard, automatic) is one uniform Gaussian of `blur` over the whole band; `knee > 0` (soft) is `ScrollEdgeEffect.softLevels` (8) stacked Gaussians whose combined sigma, `sqrt(Σσ²)`, is `blur` where the blur weight is 1 and falls with it; a cap level adds `capBlur` over the top inset.
  - The soft blur ramps on its own: `ScrollEdgeMaterial` gains `blurKnee` (default 0.45, like `knee`) and `blurReach` (default 1, the fraction of the band the blur ramp spans). A hard band (`knee 0`) ignores both, and an explicit `ScrollEdgeEffect.knee` (Operator's `blocks_body`) drives the dim and the blur alike.
  - `ScrollEdgeLevel({sigma, low, high, cap})`, `uniform`, `weightAt(distance, height, knee, capExtent)`; `ScrollEdgeEffect.weightAt(distance, height, knee)` and `capWeightAt(distance, capExtent)` (the same smoothsteps the 2A shader used).
  - Each masked level is `BackdropFilter(ImageFilter.compose(outer: ImageFilter.shader(scroll_edge_mask), inner: ImageFilter.blur(σ)))`. The mask shader multiplies the blurred backdrop by the level's weight; the backdrop filter's source-over draw then cross-fades it with what lies below. A uniform level is a plain `ImageFilter.blur`.
  - `ScrollEdgeTintPainter` (public in `src/`, not exported) paints the dim and cap as a 24-stop vertical gradient of the tint, and the 1 pt divider line, instead of the shader.
  - The `blur` and `capBlur` fields now mean the Gaussian sigma in pt. The 2A shader's 7 × 7 taps at spacing r/3 with weights `exp(−(i² + j²)/8)` were a sigma of 2r/3, so 2A's committed rows mean something else now; Step 6 replaces them with rows tuned on this renderer.
- Why compose and not `ShaderMask` (prototype `20260930-181321`, soft, dark, same row): a `ShaderMask` over a `BackdropFilter` renders no blur at all under Impeller on the iOS 27 simulator (the text under the band stays sharp, MAD 27.37); the composed mask blurs smoothly with no grid and no doubled text (MAD 21.31 at the untuned seed row). The `ShaderMask` path stays only as the fallback where `ImageFilter.isShaderFilterSupported` is false (widget tests, Skia).
- Why 8 levels: at the same tuned row, 4 levels measured soft dark MAD 4.03 and 8 levels 3.98 (`20260930-191855`, `20260930-193014`); light 4.32 → 4.21 (`20260930-190154`, `20260930-193453`). Task 6's `perf.edge` measures their cost.

- [ ] **Step 1: Write the failing tests.** Replace `packages/ios_liquid_glass/test/scroll_edge_effect_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/scroll_edge/scroll_edge_effect.dart';

void main() {
  testWidgets('does not intercept taps on content below it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: Stack(
            children: [
              Positioned.fill(child: GestureDetector(onTap: () => taps++, child: const ColoredBox(color: Colors.orange))),
              const Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120)),
            ],
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 40));
    expect(taps, 1);
    expect(tester.getSize(find.byType(ScrollEdgeEffect)).height, 120);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the fallback with no exception once settled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: const Stack(
            children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hidden edge effect draws no blur at all', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: const Stack(
            children: [
              Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120, visibility: 0)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.getSize(find.byType(ScrollEdgeEffect)).height, 120);
  });

  ScrollEdgeTintPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ScrollEdgeTintPainter)).painter! as ScrollEdgeTintPainter;

  for (final (brightness, expected) in const [(Brightness.light, Color(0xFFFFFFFF)), (Brightness.dark, Color(0xFF000000))]) {
    testWidgets('the band tints with the default edge tint (${brightness.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GlassTheme(
            data: GlassThemeData(brightness: brightness),
            child: const Stack(
              children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
            ),
          ),
        ),
      );
      expect(painterOf(tester).tint, expected);
    });
  }

  testWidgets('the theme edge tint overrides the default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassTheme(
          data: GlassThemeData(brightness: Brightness.light, scrollEdgeTint: Color(0xFFFAF7F2)),
          child: Stack(
            children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120))],
          ),
        ),
      ),
    );
    expect(painterOf(tester).tint, const Color(0xFFFAF7F2));
  });

  test('a hard band is one true Gaussian over the whole band', () {
    final levels = ScrollEdgeEffect.levels(blur: 5, knee: 0, capBlur: 0, capExtent: 0);
    expect(levels, hasLength(1));
    expect(levels.single.sigma, 5);
    expect(levels.single.uniform, isTrue);
    expect(levels.single.weightAt(10, 120, 0, 0), 1);
    expect(levels.single.weightAt(130, 120, 0, 0), 0);
  });

  test('a soft band stacks Gaussians whose combined sigma grows to the full blur at the edge', () {
    final levels = ScrollEdgeEffect.levels(blur: 8, knee: 0.4, capBlur: 0, capExtent: 0);
    expect(levels, hasLength(ScrollEdgeEffect.softLevels));
    final combined = levels.fold<double>(0, (sum, level) => sum + level.sigma * level.sigma);
    expect(combined, closeTo(64, 1e-9));
    for (final level in levels) {
      expect(level.weightAt(0, 120, 0.4, 0), 1);
      expect(level.weightAt(120, 120, 0.4, 0), 0);
    }
    expect(levels.first.weightAt(100, 120, 0.4, 0), greaterThan(levels.last.weightAt(100, 120, 0.4, 0)));
  });

  test('the blur ramp has its own knee and reach, and a hard band ignores them', () {
    expect(ScrollEdgeMaterial.defaults['blurKnee'], ScrollEdgeMaterial.defaults['knee']);
    expect(ScrollEdgeMaterial.defaults['blurReach'], 1);
    final soft = ScrollEdgeEffect.levels(blur: 4, knee: 0.3, capBlur: 0, capExtent: 0);
    expect(soft.first.weightAt(100, 120 * 0.8, 0.3, 0), 0);
    expect(soft.first.weightAt(100, 120, 0.3, 0), greaterThan(0));
  });

  testWidgets('a hard band stays one uniform blur whatever its blur knee', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassTheme(
          data: GlassThemeData(brightness: Brightness.dark),
          child: GlassMaterialOverride(
            values: {'edge.blurKnee': 0.3, 'edge.blurReach': 0.5},
            child: Stack(
              children: [Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 120, style: ScrollEdgeStyle.hard))],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });

  test('the cap level only covers the cap', () {
    final levels = ScrollEdgeEffect.levels(blur: 5, knee: 0, capBlur: 3, capExtent: 60);
    final cap = levels.last;
    expect(cap.cap, isTrue);
    expect(cap.weightAt(10, 120, 0, 60), 1);
    expect(cap.weightAt(70, 120, 0, 60), 0);
  });

  test('the tint follows the band weight and the cap, and draws the line only when asked', () {
    const painter = ScrollEdgeTintPainter(
      fromTop: true, tint: Color(0xFF000000), dim: 0.6, knee: 0, cap: 0.9, capExtent: 50, line: 0.3, lineShade: 0.5,
    );
    expect(painter.alphaAt(10, 100), closeTo(0.9, 1e-9));
    expect(painter.alphaAt(80, 100), closeTo(0.6, 1e-9));
    expect(painter.alphaAt(100, 100), 0);
  });
}
```

Run, from `packages/ios_liquid_glass`: `flutter test test/scroll_edge_effect_test.dart`
Expected: compile errors, `Undefined name 'ScrollEdgeTintPainter'` and `levels`.

- [ ] **Step 2: Swap the shader.** Run `git rm lib/assets/shaders/scroll_edge_blur.frag` (from the package), create `packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_mask.frag`:

```glsl
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBandOriginY;
uniform float uBandHeight;
uniform float uFromTop;
uniform float uKnee;
uniform vec4 uRamp;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    float dist = uFromTop > 0.5 ? frag.y - uBandOriginY : uBandOriginY + uBandHeight - frag.y;
    float t = 1.0 - clamp(dist / uBandHeight, 0.0, 1.0);
    float w = uKnee > 0.0 ? smoothstep(0.0, uKnee, t) : step(0.0001, t);
    float cap = uRamp.z > 0.0 ? 1.0 - smoothstep(uRamp.z * 0.6, uRamp.z, dist) : 0.0;
    float level = uRamp.w > 0.5 ? cap : clamp((w - uRamp.x) / max(uRamp.y - uRamp.x, 0.0001), 0.0, 1.0);
    fragColor = texture(uTexture, frag / uSize) * level;
}
```

and in `packages/ios_liquid_glass/pubspec.yaml` replace the line `    - lib/assets/shaders/scroll_edge_blur.frag` with `    - lib/assets/shaders/scroll_edge_mask.frag`.

- [ ] **Step 3: Replace** `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart` and `packages/ios_liquid_glass/lib/src/material/scroll_edge_material.dart` with:

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';
import 'package:ios_liquid_glass/src/material/scroll_edge_material.dart';

enum ScrollEdge { top, bottom }

class ScrollEdgeEffect extends StatefulWidget {
  const ScrollEdgeEffect({
    super.key,
    required this.edge,
    required this.height,
    this.style = ScrollEdgeStyle.automatic,
    this.visibility = 1,
    this.knee,
    this.capExtent = 0,
  });

  static const double fadeExtent = 16;
  static const double lineWidth = 1;
  static const int softLevels = 8;
  static const int rampStops = 24;
  static const String shaderAsset = 'packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_mask.frag';

  static double topVisibility(ScrollMetrics metrics) =>
      ((metrics.pixels - metrics.minScrollExtent) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static double bottomVisibility(ScrollMetrics metrics) =>
      ((metrics.maxScrollExtent - metrics.pixels) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static ScrollEdgeMaterial materialOf(BuildContext context, ScrollEdgeStyle style) => ScrollEdgeMaterial.resolve(
    style: style,
    brightness: GlassTheme.brightnessOf(context),
  ).withOverrides(GlassMaterialOverride.of(context));

  static double weightAt(double distance, double height, double knee) {
    final t = 1 - (distance / height).clamp(0.0, 1.0);
    if (knee <= 0) return t > 0.0001 ? 1 : 0;
    final x = (t / knee).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double capWeightAt(double distance, double capExtent) {
    if (capExtent <= 0) return 0;
    final x = ((distance - capExtent * 0.6) / (capExtent * 0.4)).clamp(0.0, 1.0);
    return 1 - x * x * (3 - 2 * x);
  }

  static List<ScrollEdgeLevel> levels({required double blur, required double knee, required double capBlur, required double capExtent}) {
    final bands = <ScrollEdgeLevel>[];
    if (blur > 0) {
      if (knee <= 0) {
        bands.add(ScrollEdgeLevel(sigma: blur, low: 0, high: 0));
      } else {
        for (var k = 1; k <= softLevels; k++) {
          final target = blur * k / softLevels;
          final previous = blur * (k - 1) / softLevels;
          bands.add(ScrollEdgeLevel(sigma: math.sqrt(target * target - previous * previous), low: (k - 1) / softLevels, high: k / softLevels));
        }
      }
    }
    if (capExtent > 0 && capBlur > 0) bands.add(ScrollEdgeLevel(sigma: capBlur, low: 0, high: 0, cap: true));
    return bands;
  }

  final ScrollEdge edge;
  final double height;
  final ScrollEdgeStyle style;
  final double visibility;
  final double? knee;
  final double capExtent;

  @override
  State<ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

@immutable
class ScrollEdgeLevel {
  const ScrollEdgeLevel({required this.sigma, required this.low, required this.high, this.cap = false});

  final double sigma;
  final double low;
  final double high;
  final bool cap;

  bool get uniform => !cap && high <= low;

  double weightAt(double distance, double height, double knee, double capExtent) {
    if (cap) return ScrollEdgeEffect.capWeightAt(distance, capExtent);
    if (uniform) return distance < height ? 1 : 0;
    final w = ScrollEdgeEffect.weightAt(distance, height, knee);
    return ((w - low) / (high - low)).clamp(0.0, 1.0);
  }
}

class _ScrollEdgeEffectState extends State<ScrollEdgeEffect> {
  final _boxKey = GlobalKey();
  ui.FragmentProgram? _program;
  final List<ui.FragmentShader> _shaders = [];
  double? _originY;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      unawaited(_loadProgram());
    }
  }

  Future<void> _loadProgram() async {
    final ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset(ScrollEdgeEffect.shaderAsset);
    } on Object {
      return;
    }
    if (!mounted) return;
    setState(() => _program = program);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _boxKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final newOriginY = box.localToGlobal(Offset.zero).dy * dpr;
      if (_originY != newOriginY) {
        setState(() => _originY = newOriginY);
      }
    });
  }

  ui.FragmentShader _shaderAt(int index) {
    while (_shaders.length <= index) {
      _shaders.add(_program!.fragmentShader());
    }
    return _shaders[index];
  }

  @override
  void dispose() {
    for (final shader in _shaders) {
      shader.dispose();
    }
    super.dispose();
  }

  Widget _level(int index, ScrollEdgeLevel level, double knee, double reach) {
    final blur = ui.ImageFilter.blur(sigmaX: level.sigma, sigmaY: level.sigma, tileMode: TileMode.mirror);
    final originY = _originY;
    if (level.uniform) {
      return ClipRect(child: BackdropFilter(filter: blur, child: const SizedBox.expand()));
    }
    if (_program != null && originY != null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final shader = _shaderAt(index)
        ..setFloat(0, 0)
        ..setFloat(1, 0)
        ..setFloat(2, originY)
        ..setFloat(3, widget.height * reach * dpr)
        ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
        ..setFloat(5, knee)
        ..setFloat(6, level.low)
        ..setFloat(7, level.high)
        ..setFloat(8, widget.capExtent * dpr)
        ..setFloat(9, level.cap ? 1 : 0);
      return ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(outer: ui.ImageFilter.shader(shader), inner: blur),
          child: const SizedBox.expand(),
        ),
      );
    }
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => _ramp(rect, (distance) => level.weightAt(distance, rect.height * reach, knee, widget.capExtent)),
      child: ClipRect(child: BackdropFilter(filter: blur, child: const SizedBox.expand())),
    );
  }

  ui.Shader _ramp(Rect rect, double Function(double distance) alphaAt) {
    const count = ScrollEdgeEffect.rampStops;
    final stops = [for (var i = 0; i <= count; i++) i / count];
    final colors = [for (final stop in stops) const Color(0xFFFFFFFF).withValues(alpha: alphaAt(stop * rect.height))];
    final fromTop = widget.edge == ScrollEdge.top;
    return ui.Gradient.linear(
      fromTop ? rect.topCenter : rect.bottomCenter,
      fromTop ? rect.bottomCenter : rect.topCenter,
      colors,
      stops,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    final material = ScrollEdgeEffect.materialOf(context, widget.style);
    final visibility = widget.visibility.clamp(0.0, 1.0).toDouble();
    final tint = theme.scrollEdgeTint ?? (dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    final knee = widget.knee ?? material['knee'];
    final blurKnee = knee <= 0 ? 0.0 : widget.knee ?? material['blurKnee'];
    final blurReach = widget.knee == null ? material['blurReach'] : 1.0;
    final levels = ScrollEdgeEffect.levels(
      blur: material['blur'] * visibility,
      knee: blurKnee,
      capBlur: material['capBlur'] * visibility,
      capExtent: widget.capExtent,
    );
    _scheduleMeasure();
    return IgnorePointer(
      child: SizedBox(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        child: visibility <= 0
            ? null
            : Stack(
                fit: StackFit.expand,
                children: [
                  for (final (index, level) in levels.indexed) _level(index, level, blurKnee, blurReach),
                  CustomPaint(
                    painter: ScrollEdgeTintPainter(
                      fromTop: widget.edge == ScrollEdge.top,
                      tint: tint,
                      dim: material['dim'] * visibility,
                      knee: knee,
                      cap: material['cap'] * visibility,
                      capExtent: widget.capExtent,
                      line: material['line'] * visibility,
                      lineShade: material['lineShade'],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ScrollEdgeTintPainter extends CustomPainter {
  const ScrollEdgeTintPainter({
    required this.fromTop,
    required this.tint,
    required this.dim,
    required this.knee,
    required this.cap,
    required this.capExtent,
    required this.line,
    required this.lineShade,
  });

  final bool fromTop;
  final Color tint;
  final double dim;
  final double knee;
  final double cap;
  final double capExtent;
  final double line;
  final double lineShade;

  double alphaAt(double distance, double height) {
    final w = ScrollEdgeEffect.weightAt(distance, height, knee);
    final c = ScrollEdgeEffect.capWeightAt(distance, capExtent);
    return (dim * w) * (1 - c) + cap * c;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const count = ScrollEdgeEffect.rampStops;
    final stops = [for (var i = 0; i <= count; i++) i / count];
    final colors = [for (final stop in stops) tint.withValues(alpha: alphaAt(stop * size.height, size.height).clamp(0.0, 1.0))];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          fromTop ? rect.topCenter : rect.bottomCenter,
          fromTop ? rect.bottomCenter : rect.topCenter,
          colors,
          stops,
        ),
    );
    if (line > 0) {
      final top = fromTop ? size.height - ScrollEdgeEffect.lineWidth : 0.0;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, ScrollEdgeEffect.lineWidth),
        Paint()..color = Color.from(alpha: line.clamp(0.0, 1.0), red: lineShade, green: lineShade, blue: lineShade),
      );
    }
  }

  @override
  bool shouldRepaint(ScrollEdgeTintPainter old) =>
      old.fromTop != fromTop ||
      old.tint != tint ||
      old.dim != dim ||
      old.knee != knee ||
      old.cap != cap ||
      old.capExtent != capExtent ||
      old.line != line ||
      old.lineShade != lineShade;
}
```

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/material/ios27_scroll_edge.dart';

enum ScrollEdgeStyle { soft, hard, automatic }

@immutable
class ScrollEdgeMaterial {
  const ScrollEdgeMaterial(this.values);

  static const String overridePrefix = 'edge.';

  static const Map<String, double> defaults = {
    'extent': 34,
    'blur': 4,
    'dim': 0.6,
    'knee': 0.45,
    'blurKnee': 0.45,
    'blurReach': 1,
    'cap': 0.88,
    'capBlur': 6,
    'line': 0,
    'lineShade': 0.5,
  };

  final Map<String, double> values;

  double operator [](String name) => values[name] ?? defaults[name]!;

  ScrollEdgeMaterial withOverrides(Map<String, double> overrides) {
    final picked = {
      for (final entry in overrides.entries)
        if (entry.key.startsWith(overridePrefix)) entry.key.substring(overridePrefix.length): entry.value,
    };
    return picked.isEmpty ? this : ScrollEdgeMaterial({...values, ...picked});
  }

  static ScrollEdgeMaterial resolve({
    required ScrollEdgeStyle style,
    required Brightness brightness,
    Map<String, Map<String, double>> table = ios27ScrollEdgeTable,
  }) {
    final appearance = brightness == Brightness.dark ? 'dark' : 'light';
    return ScrollEdgeMaterial(table['$appearance.${style.name}'] ?? const {});
  }
}
```

- [ ] **Step 4: Run the tests.** `flutter test test/scroll_edge_effect_test.dart` passes; `flutter analyze` prints "No issues found!".

- [ ] **Step 5: Run every gate.** Package, example and app `flutter analyze` and `flutter test`. Operator's `home_shell_test.dart` and `terminal_body_layout_test.dart` still count one `BackdropFilter` under a bottom edge, because those edges are `automatic` until Task 7.

- [ ] **Step 6: Seed the edge rows.** The rows below are the prototype's, tuned with this renderer (soft from a fit of native's dim profile, `20260930-184134`, `20260930-191855`, `20260930-190154`; hard `20260930-193656`, `20260930-195957`; automatic copied from hard). They also add the two new fields. Save as `seed_scroll_edge.py` in the session scratchpad and run it from `packages/mobile`:

```python
import sys

sys.path.insert(0, "tool/glass_lab/harness")
import material_table

ROWS = {
    "dark.soft": {"blur": 3.75, "blurKnee": 0.6, "blurReach": 1.0, "cap": 0.6, "capBlur": 0.0, "dim": 0.52, "extent": 94.0, "knee": 0.55, "line": 0.0, "lineShade": 0.5},
    "dark.hard": {"blur": 5.0, "blurKnee": 0.0, "blurReach": 1.0, "cap": 0.6, "capBlur": 7.0, "dim": 0.5714, "extent": 55.0, "knee": 0.0, "line": 0.375, "lineShade": 1.0},
    "dark.automatic": {"blur": 5.0, "blurKnee": 0.0, "blurReach": 1.0, "cap": 0.6, "capBlur": 7.0, "dim": 0.5714, "extent": 55.0, "knee": 0.0, "line": 0.375, "lineShade": 1.0},
    "light.soft": {"blur": 4.5, "blurKnee": 0.5, "blurReach": 1.0, "cap": 0.55, "capBlur": 0.0, "dim": 0.3, "extent": 94.0, "knee": 0.5, "line": 0.0, "lineShade": 0.5},
    "light.hard": {"blur": 3.25, "blurKnee": 0.0, "blurReach": 1.0, "cap": 0.78, "capBlur": 0.0, "dim": 0.775, "extent": 55.0, "knee": 0.0, "line": 0.425, "lineShade": 0.45},
    "light.automatic": {"blur": 3.25, "blurKnee": 0.0, "blurReach": 1.0, "cap": 0.78, "capBlur": 0.0, "dim": 0.775, "extent": 55.0, "knee": 0.0, "line": 0.425, "lineShade": 0.45},
}

material_table.write(ROWS, table=material_table.SCROLL_EDGE)
print(f"seeded {len(ROWS)} rows")
```

Expected: `seeded 6 rows`; `python3 -m unittest tool/glass_lab/harness/tests/test_tune.py` stays `OK`.

- [ ] **Step 7: Prove it on the simulator.** `python3 tool/glass_lab/harness/lab.py build example`, then:

```bash
python3 tool/glass_lab/harness/lab.py tune --scene material.edge.soft --appearance dark --backdrops scroll --params edge.knee=0.55:0.55:1 --passes 1
```

Expected: one candidate with `mad` about 4.0 and `luminance` about 0.13 (prototype `20260930-193014`: 3.98 and 0.13). Open `candidates/0001/scroll/ready.png` in the printed folder and check the band: a smooth progressive blur, no grid pattern, no doubled text. 2A measured MAD 21.27 here.

- [ ] **Step 8: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "fix(mobile): ios_liquid_glass scroll edge blurs with stacked Gaussians instead of a sparse kernel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Example app and frame cost: native Run geometry and centring, anchor-scoped overrides, a cheaper shadow cut-out, `perf.material` and `perf.edge` (findings 5 and 9)

**Files:**
- Modify:
  - `packages/ios_liquid_glass/lib/src/material/glass_material_override.dart`, `packages/ios_liquid_glass/lib/src/api/glass_material_context.dart`
  - `packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart`, `glass_lab_screen.dart`, `scenes/lab_parts.dart`, `scenes/material_scenes.dart`, `scenes/perf_scenes.dart`
  - `packages/ios_liquid_glass/lib/src/glass_shadow.dart`
- Test: `packages/ios_liquid_glass/test/glass_effect_test.dart`, `packages/ios_liquid_glass/test/glass_shadow_test.dart` (new), `packages/ios_liquid_glass/example/test/lab_test.dart`

**Interfaces:**
- Produces:
  - `GlassMaterialOverride({values, side, child})` and `GlassMaterialOverride.forSide(context, shorterSide)`: with a `side`, the overrides reach only glass whose shorter side, clamped to 44–200, is within 1 pt of it. `of(context)` is unchanged (the scroll edge reads its `edge.` keys there). `resolveGlassMaterial` uses `forSide`.
  - `GlassLabLaunch.materialSide` from the launch file's `"materialSide"`, passed to the override by `GlassLabScreen`. Task 2's `tune` sends it.
  - The `material.tinted` "Run" button is a fixed 78 × 37 pt box with its label centred, native's size (`lab.py geometry material.tinted` reads `run [162, 501, 78, 37]`; the 2A padding made it 86 × 40, which lifted the column so the 88 pt block sat 2 pt high).
  - `LabCentered` places its column with `WholePointCenter`, which rounds the centred offset to whole points, as SwiftUI placed the native column. With the Run fixed, the tinted column is 173 pt tall, so plain centring put the block at 364.5 pt against native's 365 (prototype run `20260930-224352`: box and centre 1.0).
  - `perf.material`: the `perf.glass` layout (twelve 110 × 44 and one 360 × 200) built from `GlassEffect`, so each glass draws its tuned row, outline band and shadow; `perf.edge`: a soft `ScrollEdgeEffect` over the top 94 pt plus the inset. Task 2's `probe.PERF_SCENES` already names both.

- [ ] **Step 1: Write the failing tests.**
  - In `packages/ios_liquid_glass/test/glass_effect_test.dart`, insert before the test `foreground is white in dark, black in light and white on tinted glass`:

```dart
  testWidgets('side-scoped overrides reach only the glass at that anchor', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: GlassMaterialOverride(
        values: const {'frost': 17},
        side: 200,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassEffect(child: SizedBox(width: 360, height: 200)),
              GlassEffect(child: SizedBox(width: 250, height: 88)),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    final blurs = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).map((layer) => layer.settings.blur).toList();
    expect(blurs.first, 17);
    expect(blurs.last, isNot(17));
  });
```

  - Replace `packages/ios_liquid_glass/example/test/lab_test.dart` with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
import 'package:ios_liquid_glass_example/lab/scenes/lab_parts.dart';
import 'package:ios_liquid_glass_example/lab/scenes/perf_scenes.dart';

List<String> labSceneIds() {
  final raw = jsonDecode(File('../../../tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>;
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      if (entry['app'] == 'lab') entry['id'] as String,
  ];
}

void main() {
  test('reads material overrides from the launch file', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'material.regular', 'material': {'toneBlack': 0.2, 'toneWhite': 1}});
    expect(launch?.material, {'toneBlack': 0.2, 'toneWhite': 1.0});
    expect(launch?.materialSide, isNull);
    expect(GlassLabLaunch.fromJson({'scene': 'material.regular', 'materialSide': 200})?.materialSide, 200);
  });

  test('consume reads the launch file once and deletes it', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('{"scene": "material.clear"}');
    expect(GlassLabLaunch.consume(directory)?.scene, 'material.clear');
    expect(GlassLabLaunch.consume(directory), isNull);
  });

  test('perf stats report median, p90 and max', () {
    expect(PerfScenes.stats([4, 1, 3, 2, 5]), {'median': 3, 'p90': 5, 'max': 5});
    expect(PerfScenes.stats([]), {'median': 0, 'p90': 0, 'max': 0});
  });

  test('tool scenes are registered outside the manifest', () {
    expect(labSceneIds(), isNot(contains('perf.glass')));
    expect(GlassLabRegistry.tools.keys, containsAll(['perf.none', 'perf.glass', 'perf.material', 'perf.edge']));
  });

  testWidgets('the tinted Run button has native geometry, 78 by 37 points', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: 'material.tinted'))));
    await tester.pump();
    expect(tester.getSize(find.bySemanticsIdentifier('tinted.run')), const Size(78, 37));
    semantics.dispose();
  });

  test('scenes centre on whole points, as SwiftUI places the native column', () {
    const center = WholePointCenter();
    expect(center.getPositionForChild(const Size(402, 778), const Size(250, 173)), const Offset(76, 303));
    expect(center.getPositionForChild(const Size(402, 778), const Size(360, 428)), const Offset(21, 175));
  });

  test('every registered scene is in the manifest', () {
    expect(labSceneIds(), containsAll(GlassLabRegistry.scenes.keys));
  });

  testWidgets('every manifest scene renders its scene or the missing placeholder', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    for (final id in labSceneIds()) {
      await tester.pumpWidget(MaterialApp(home: GlassLabScreen(launch: GlassLabLaunch(scene: id))));
      await tester.pump();
      final missing = GlassLabRegistry.scenes.containsKey(id) ? findsNothing : findsOneWidget;
      expect(find.bySemanticsIdentifier('scene.missing'), missing, reason: id);
      expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget, reason: id);
      expect(tester.takeException(), isNull, reason: id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
    semantics.dispose();
  });
}
```

Run: package `flutter test test/glass_effect_test.dart` and example `flutter test`.
Expected: `No named parameter with the name 'side'`; the example does not compile (`materialSide` and `WholePointCenter` are undefined; once they exist, the Run button measures `Size(86.0, 40.0)` until Step 4); `perf.material` and `perf.edge` are not registered.

- [ ] **Step 2: Scope the overrides.** Replace `packages/ios_liquid_glass/lib/src/material/glass_material_override.dart` and `packages/ios_liquid_glass/lib/src/api/glass_material_context.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class GlassMaterialOverride extends InheritedWidget {
  const GlassMaterialOverride({super.key, required this.values, this.side, required super.child});

  final Map<String, double> values;
  final double? side;

  static Map<String, double> of(BuildContext context) {
    if (!kDebugMode) return const {};
    return context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>()?.values ?? const {};
  }

  static Map<String, double> forSide(BuildContext context, double shorterSide) {
    if (!kDebugMode) return const {};
    final scope = context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>();
    if (scope == null) return const {};
    final side = scope.side;
    if (side != null && (shorterSide.clamp(44.0, 200.0) - side).abs() >= 1) return const {};
    return scope.values;
  }

  @override
  bool updateShouldNotify(GlassMaterialOverride oldWidget) => !mapEquals(oldWidget.values, values) || oldWidget.side != side;
}
```

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';

GlassMaterial resolveGlassMaterial(BuildContext context, {required Glass glass, required double shorterSide}) =>
    GlassMaterial.resolve(
      glass: glass,
      shorterSide: shorterSide,
      brightness: GlassTheme.brightnessOf(context),
      accessibility: GlassAccessibility.of(context),
    ).withOverrides(GlassMaterialOverride.forSide(context, shorterSide));
```

- [ ] **Step 3: The launch file and the lab screen.** Replace `packages/ios_liquid_glass/example/lib/lab/glass_lab_launch.dart` and `glass_lab_screen.dart` with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class GlassLabLaunch {
  const GlassLabLaunch({required this.scene, this.backdrop = defaultBackdrop, this.bare = false, this.material = const {}, this.materialSide});

  static const String defaultBackdrop = 'stripes';
  static const String launchFile = 'launch.json';
  static Directory directory = Directory('');

  final String scene;
  final String backdrop;
  final bool bare;
  final Map<String, double> material;
  final double? materialSide;

  static GlassLabLaunch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final scene = json['scene'];
    if (scene is! String || scene.isEmpty) return null;
    final backdrop = json['backdrop'];
    final material = json['material'];
    final materialSide = json['materialSide'];
    return GlassLabLaunch(
      scene: scene,
      backdrop: backdrop is String && backdrop.isNotEmpty ? backdrop : defaultBackdrop,
      bare: json['bare'] == true,
      material: material is Map<String, dynamic>
          ? {for (final entry in material.entries) if (entry.value is num) entry.key: (entry.value as num).toDouble()}
          : const {},
      materialSide: materialSide is num ? materialSide.toDouble() : null,
    );
  }

  static GlassLabLaunch? consume(Directory labDirectory) {
    final file = File('${labDirectory.path}/$launchFile');
    if (!file.existsSync()) return null;
    try {
      return fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException {
      return null;
    } finally {
      file.deleteSync();
    }
  }

  static Future<GlassLabLaunch?> load() async {
    directory = Directory('${(await getApplicationDocumentsDirectory()).path}/glass_lab');
    return consume(directory);
  }
}
```

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import 'glass_lab_launch.dart';
import 'glass_lab_marker.dart';
import 'glass_lab_probe.dart';
import 'glass_lab_registry.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: GlassMaterialOverride(
        values: launch.material,
        side: launch.materialSide,
        child: GlassLabAccessibilityProbe(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned.fill(child: GlassLabRegistry.build(launch)),
                const Positioned(left: 0, top: 0, child: GlassLabReady()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Whole-point centring and the Run button.** Replace `packages/ios_liquid_glass/example/lib/lab/scenes/lab_parts.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_marker.dart';

class LabCentered extends StatelessWidget {
  const LabCentered({super.key, required this.backdrop, required this.children, this.gap = 48, this.bottom});

  final String backdrop;
  final List<Widget> children;
  final double gap;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: backdrop)),
        SafeArea(
          child: CustomSingleChildLayout(
            delegate: const WholePointCenter(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (bottom != null) Positioned(left: 0, right: 0, bottom: 120, child: Center(child: bottom)),
      ],
    );
  }
}

class WholePointCenter extends SingleChildLayoutDelegate {
  const WholePointCenter();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(((size.width - childSize.width) / 2).roundToDouble(), ((size.height - childSize.height) / 2).roundToDouble());

  @override
  bool shouldRelayout(WholePointCenter oldDelegate) => false;
}

class LabBlock extends StatelessWidget {
  const LabBlock({super.key, required this.width, required this.height, this.glass = Glass.regular, this.shape = const GlassShape.capsule()});

  final double width;
  final double height;
  final Glass glass;
  final GlassShape shape;

  @override
  Widget build(BuildContext context) =>
      GlassEffect(glass: glass, shape: shape, child: SizedBox(width: width, height: height));
}

class LabButton extends StatelessWidget {
  const LabButton({super.key, required this.title, required this.id, this.onTap});

  final String title;
  final String id;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassLabMarker(
      id,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: const ShapeDecoration(color: Color(0xFFFFFFFF), shape: StadiumBorder()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF000000))),
          ),
        ),
      ),
    );
  }
}
```

Then, in `packages/ios_liquid_glass/example/lib/lab/scenes/material_scenes.dart`, the `tinted.run` `GlassEffect`'s child becomes:

```dart
            child: const SizedBox(
              width: 78,
              height: 37,
              child: GlassForeground(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Icon(Icons.play_arrow_rounded, size: 20), SizedBox(width: 6), Text('Run', style: TextStyle(fontSize: 17))],
                ),
              ),
            ),
```

- [ ] **Step 5: The perf scenes.** Replace `packages/ios_liquid_glass/example/lib/lab/scenes/perf_scenes.dart` with:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_launch.dart';
import '../glass_lab_probe.dart';

sealed class PerfScenes {
  static const String file = 'perf.json';
  static const Duration warmup = Duration(seconds: 2);
  static const Duration window = Duration(seconds: 6);

  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'perf.none': (launch) => const PerfScene(id: 'perf.none'),
    'perf.glass': (launch) => const PerfScene(id: 'perf.glass'),
    'perf.material': (launch) => const PerfScene(id: 'perf.material'),
    'perf.edge': (launch) => const PerfScene(id: 'perf.edge'),
  };

  static Map<String, double> stats(List<double> values) {
    final sorted = [...values]..sort();
    double at(double q) => sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * q).round()];
    return {'median': at(0.5), 'p90': at(0.9), 'max': at(1)};
  }
}

class PerfScene extends StatefulWidget {
  const PerfScene({super.key, required this.id});

  final String id;

  @override
  State<PerfScene> createState() => _PerfSceneState();
}

class _PerfSceneState extends State<PerfScene> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat();
  final List<FrameTiming> _timings = [];
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(PerfScenes.warmup, _start);
  }

  void _start() {
    if (!mounted) return;
    _recording = true;
    SchedulerBinding.instance.addTimingsCallback(_collect);
    Future<void>.delayed(PerfScenes.window, _finish);
  }

  void _collect(List<FrameTiming> timings) => _timings.addAll(timings);

  void _finish() {
    if (!_recording) return;
    _recording = false;
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    double ms(Duration d) => d.inMicroseconds / 1000;
    writeLabFile(PerfScenes.file, {
      'scene': widget.id,
      'frames': _timings.length,
      'raster_ms': PerfScenes.stats([for (final t in _timings) ms(t.rasterDuration)]),
      'build_ms': PerfScenes.stats([for (final t in _timings) ms(t.buildDuration)]),
    });
  }

  @override
  void dispose() {
    if (_recording) SchedulerBinding.instance.removeTimingsCallback(_collect);
    _motion.dispose();
    super.dispose();
  }

  Widget _glass(double radius, Widget child) => widget.id == 'perf.material'
      ? GlassEffect(child: child)
      : LiquidGlass.withOwnLayer(
          settings: const LiquidGlassSettings(),
          shape: LiquidRoundedSuperellipse(borderRadius: radius),
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _motion,
          builder: (context, child) => Transform.translate(offset: Offset(-size.width * _motion.value, 0), child: child),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: size.width * 2,
            child: Row(
              children: [
                for (var i = 0; i < 2; i++) SizedBox(width: size.width, height: size.height, child: const GlassLabBackdrop(id: 'stripes')),
              ],
            ),
          ),
        ),
        if (widget.id == 'perf.edge')
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ScrollEdgeEffect(edge: ScrollEdge.top, style: ScrollEdgeStyle.soft, height: MediaQuery.paddingOf(context).top + 94, capExtent: MediaQuery.paddingOf(context).top),
          ),
        if (widget.id == 'perf.glass' || widget.id == 'perf.material')
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 4; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var column = 0; column < 3; column++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: _glass(22, const SizedBox(width: 110, height: 44)),
                            ),
                        ],
                      ),
                    ),
                  _glass(40, const SizedBox(width: 360, height: 200)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Cut the shadow out with a clip.** An offset shadow used to be drawn into a `saveLayer` and cut out with a `dstOut` shape; thirteen of them cost 2.3 ms of raster time in `perf.material` (prototype: 14.92 ms tuned against 12.62 ms with shadows off), which put the tuned material 21.6% over the old renderer. A difference clip does the same without a layer (13.03 ms), and its bounds now reach past three sigma, so the tail is no longer cut short (2A's saveLayer bounds stopped it about 36 pt below the glass; native reaches 0 at 45). Create `packages/ios_liquid_glass/test/glass_shadow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/glass_shadow.dart';

Widget _shadow() => const Center(
  child: GlassShadow(
    shape: LiquidRoundedRectangle(borderRadius: 999),
    settings: LiquidGlassSettings(),
    shadows: [BoxShadow(color: Color(0x29000000), blurRadius: 29, offset: Offset(0, 8))],
    child: SizedBox(width: 360, height: 200),
  ),
);

void main() {
  testWidgets('an offset shadow is cut out of the glass with a clip, not a save layer', (tester) async {
    await tester.pumpWidget(_shadow());
    final shadow = tester.renderObject(find.byType(GlassShadow));
    expect(shadow, paints..save()..clipPath()..rrect()..restore());
    expect(shadow, isNot(paints..something((method, arguments) => method == #saveLayer)));
  });

  testWidgets('the clip keeps the whole tail, three sigma below the glass, and hides the glass', (tester) async {
    await tester.pumpWidget(_shadow());
    final shadow = tester.renderObject<RenderBox>(find.byType(GlassShadow));
    final glass = Offset.zero & shadow.size;
    const sigma = 29 * 0.57735 + 0.5;
    expect(
      shadow,
      paints..clipPath(
        pathMatcher: isPathThat(
          includes: [glass.bottomCenter + const Offset(0, 8 + 3 * sigma), glass.centerRight + const Offset(3 * sigma, 0)],
          excludes: [glass.center, glass.topCenter + const Offset(0, 2)],
        ),
      ),
    );
  });
}
```

Run it: both tests fail (a `saveLayer` is painted and no `clipPath`). Then replace `packages/ios_liquid_glass/lib/src/glass_shadow.dart` with the version below (upstream's dartdoc is kept) and run it again: it passes.

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:meta/meta.dart';

/// Paints [BoxShadow]s for a [LiquidShape] using canvas primitives
/// (drawRRect, drawCircle, drawRSuperellipse, etc.) instead of drawPath.
///
/// This avoids the cost of rasterizing an arbitrary [Path] with a blur
/// [MaskFilter], which is significantly slower than the dedicated GPU-
/// accelerated primitives that Impeller/Skia provide for simple shapes.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows], and
  /// optional [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    required this.settings,
    super.child,
    super.key,
  });

  /// The shape to paint shadows for.
  final LiquidShape shape;

  final LiquidGlassSettings settings;

  /// The list of shadows to paint.
  ///
  /// Only outer-equivalent shadows are supported; [BoxShadow.blurStyle] is
  /// ignored. When any shadow has a non-zero [BoxShadow.offset], the glass
  /// shape is cut out of the composed shadow stack so the shadow does not
  /// bleed through the translucent glass body.
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassShadow(
      shape: shape,
      shadows: shadows,
      visibility: settings.visibility,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    _RenderGlassShadow renderObject,
  ) {
    renderObject
      ..shape = shape
      ..shadows = shadows
      ..visibility = settings.visibility;
  }
}

class _RenderGlassShadow extends RenderProxyBox {
  _RenderGlassShadow({
    required LiquidShape shape,
    required List<BoxShadow> shadows,
    required double visibility,
  })  : _shape = shape,
        _shadows = shadows,
        _visibility = visibility.clamp(0, 1);

  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  List<BoxShadow> get shadows => _shadows;
  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    markNeedsPaint();
  }

  double get visibility => _visibility;
  double _visibility = 1;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value.clamp(0, 1);
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (shadows.isNotEmpty) {
      final rect = offset & size;
      final canvas = context.canvas;

      final needsCutout = shadows.any((s) => s.offset != Offset.zero);

      if (needsCutout) {
        var layerBounds = rect;
        for (final shadow in shadows) {
          layerBounds = layerBounds.expandToInclude(
            rect.shift(shadow.offset).inflate(
                  shadow.spreadRadius + (shadow.blurRadius * 2 + 2) * visibility,
                ),
          );
        }
        canvas
          ..save()
          ..clipPath(
            Path.combine(
              PathOperation.difference,
              Path()..addRect(layerBounds),
              _shapePath(rect.deflate(.5)),
            ),
          );
      }

      for (final shadow in shadows) {
        final shadowRect =
            rect.shift(shadow.offset).inflate(shadow.spreadRadius);
        final paint = shadow
            .copyWith(
              blurRadius: shadow.blurRadius * visibility,
              blurStyle: needsCutout ? BlurStyle.normal : BlurStyle.outer,
              color: shadow.color.withValues(
                alpha: shadow.color.a * visibility,
              ),
            )
            .toPaint();

        _drawShape(canvas, shadowRect, paint);
      }

      if (needsCutout) {
        canvas.restore();
      }
    }

    super.paint(context, offset);
  }

  Path _shapePath(Rect rect) => switch (shape) {
        LiquidRoundedSuperellipse(:final borderRadius) => Path()
          ..addRSuperellipse(
            RSuperellipse.fromRectAndRadius(
              rect,
              Radius.circular(borderRadius),
            ),
          ),
        LiquidOval() => Path()..addOval(rect),
        LiquidRoundedRectangle(:final borderRadius) => Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(borderRadius),
            ),
          ),
      };

  void _drawShape(Canvas canvas, Rect rect, Paint paint) {
    switch (shape) {
      case LiquidRoundedSuperellipse(:final borderRadius):
        canvas.drawRSuperellipse(
          RSuperellipse.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
          paint,
        );
      case LiquidOval():
        canvas.drawOval(rect, paint);
      case LiquidRoundedRectangle(:final borderRadius):
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(borderRadius),
          ),
          paint,
        );
    }
  }
}
```

- [ ] **Step 7: Run the gates.** Package, example: `flutter analyze` and `flutter test`.

- [ ] **Step 8: Prove the Run button, the block and the frame cost on the simulator.** `python3 tool/glass_lab/harness/lab.py build example`, then `python3 tool/glass_lab/harness/lab.py run material.tinted --appearance dark --backdrop black` and `lab.py report <run>`. Expected: in `material.tinted/dark-black/result.json`, `static.ready.flutter_box` equals `native_box` (`[76, 365, 250, 88]`), `bbox_pt` and `centre_pt` 0.0, and `rim_elements.block.rms` about 2.5 (prototype run `20260930-230435`; 2A measured 36.7 there with the four-sided rim). The Run button's own rim (27.8 in the prototype) is Task 8 Group D's.

Then `python3 tool/glass_lab/harness/lab.py perf --takes 3`. Expected (prototype `perf-2a1b.json`): `perf.none` about 0.75 ms, `perf.glass` about 12.65 ms, `perf.material` about 13.04 ms (7.8% over the old renderer's 12.10 ms), `perf.edge` about 5.7 ms.

- [ ] **Step 9: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "feat(mobile): lab overrides reach only the tuned anchor, the Run button has native geometry, perf measures the tuned material

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Operator's bottom scroll edges use the soft style (finding 8e)

**Files:**
- Modify: `lib/core/app_routes/home_shell.dart`, `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
- Test: `test/core/app_routes/home_shell_test.dart`, `test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart`

**Interfaces:**
- Produces: both bottom `ScrollEdgeEffect`s pass `style: ScrollEdgeStyle.soft`. The top edges (`ScrollUnderBars` in `app_scaffold.dart`, `settings_screen.dart`, `pull_requests_screen.dart`, `sessions_screen.dart`) keep `automatic`, which is measured.
- Why soft (ruling 11 of this plan): the only native bottom-edge evidence is none at all; the lab has no bottom-edge scene. `automatic` is tuned on the top edge, where iOS 27 draws a uniform bar with a divider (gotcha 24). At the bottom, that row puts a full-strength band with a divider line 37 pt above the tab bar (`home_shell`), and over `blocks_body`'s own knee it draws the divider where the fade has already reached zero, a line floating over undimmed content (code review bug 5). The soft row has no line (`line 0`), fades like the pre-2A Operator bottom edge (knee fade, no line), and is measured against native on the top edge. A measured bottom edge is a project 3 item (ROADMAP §6).
- The soft style stacks `ScrollEdgeEffect.softLevels` Gaussian levels (Task 5), so a visible bottom edge now holds several `BackdropFilter`s; the tests that counted exactly one now ask for at least one.

- [ ] **Step 1: Write the failing tests.**
  - In `test/core/app_routes/home_shell_test.dart`, test `uses the floating glass tab bar`, after `expect(bottomFade.single.height, 120);` add `expect(bottomFade.single.style, ScrollEdgeStyle.soft);`, and in test `the bottom edge effect shows only while a tab has content under the bar` change the first `expect(bottomBlur(), findsOneWidget);` to `expect(bottomBlur(), findsWidgets);`.
  - In `test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart`, test `scrolled up, the fade band sits under the composer only`, replace `expect(bottomBlur(), findsOneWidget);` with:

```dart
    expect(bottomEdge(tester).style, ScrollEdgeStyle.soft);
    expect(bottomBlur(), findsWidgets);
```

Run: `flutter test test/core/app_routes/home_shell_test.dart test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart`
Expected: 2 failures, `Expected: ScrollEdgeStyle.soft  Actual: ScrollEdgeStyle.automatic`.

- [ ] **Step 2: Pass the style.** In `lib/core/app_routes/home_shell.dart` (the bottom `ScrollEdgeEffect`, about line 147) add `style: ScrollEdgeStyle.soft,` after `edge: ScrollEdge.bottom,`. Do the same in `blocks_body.dart` (about line 426).

- [ ] **Step 3: Run the app gates.** From `packages/mobile`: `flutter analyze` prints "No issues found!"; `flutter test` passes (2,146 tests in the prototype).

- [ ] **Step 4: Commit**

```bash
git add lib/core/app_routes/home_shell.dart lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart test/core/app_routes/home_shell_test.dart test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart
git commit -m "fix(mobile): Operator's bottom scroll edges use the soft style until a bottom edge is measured

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The re-tuning campaign over all five backdrops (findings 3, 4, 6)

**Files:**
- Modify, only through `lab.py tune --write` and the three row-copy snippets below:
  - `packages/ios_liquid_glass/lib/src/material/ios27.dart`
  - `packages/ios_liquid_glass/lib/src/material/ios27_scroll_edge.dart`
- Create: `docs/liquid_glass/02a-looks/tuning-log-2a1.md`

**Interfaces:**
- Consumes: Tasks 1–7 (the all-sides rim, `--pad`, the freshness guard, anchor-scoped candidates, the edge model, the Gaussian scroll edge, the Run geometry), the manifest regions `s44`, `s88`, `s200`, `plain`, `dimmed`, `block`, `run` and `edge`.
- Produces: every row of both tables tuned against the new measures, and a log of every run with its start and best score and its folder.

**What to expect** (prototype, one appearance and size each, folders in `PROTOTYPE-2A1.md`):
- The seeded table (Task 4) already holds the prototype's best values for the 200 pt rows. Tuned there, over the steps' own backdrops: dark edge light rim 1.48 (`black`) and 2.33 (`white`); light 1.27 and 3.17; dark and light shadows box 0.0 and centre 0.0 on `white` and `text` with `--pad 60`; light tone and lens on `stripes`, `photo` and `white` every measure passing (`stripes` MAD 3.77, luminance 0.67, rim 3.95; `photo` 3.28, 0.97, 3.85; `white` 0.68, 0.16, 3.17).
- The 44 and 88 pt rows start from the 200 pt edge values, the fitted shadows and native's tone points, but were not tuned in the prototype; they are the bulk of this task. With the seeded table and no campaign, the prototype's Done run passed 5 of 10 `material.regular` cases (run `20260930-232714`): `dark-black` and every light case but `photo`. The failures are the dark 44 pt glass's curved ends (left and right sides 9–18) on `photo`, `stripes`, `text` and `white`, and `light-photo`'s box (3 pt, the 200 pt shadow over the photo).
- The scroll edge rows (Task 5 seed) measured soft dark MAD 3.98, soft light 4.21, hard dark 3.48, hard light 2.08. Soft light is the one still over 4; Group F's grids are centred on it.
- Reduce Transparency and Increase Contrast start from native's fitted tone points at every size; their edge light and frost are untested.

**How to run it.**
- One lab command at a time, with the Bash tool's `run_in_background`, then wait for the completion notice.
- Every step starts with a rebuild, because the previous step's `--write` changed the table and `tune` refuses a stale build. Define once, from `packages/mobile`:

```bash
step() {
  python3 tool/glass_lab/harness/lab.py build example > /dev/null || return 1
  python3 tool/glass_lab/harness/lab.py tune "$@" --write
}
```

- A candidate costs about 16.5 s per backdrop (prototype `20260930-173453`: 33 s for two). Each step's time below counts its passes plus the half-step refinement. The whole campaign is about 29 hours of simulator time: A 6, B 6.5, C 2.5, D 2.5, E 9, F 2.5.
- After every step, append one row to `docs/liquid_glass/02a-looks/tuning-log-2a1.md` (same columns as `tuning-log.md`: step, command, start, best, best values, folder, residual). The residual column quotes each backdrop's measures from the best candidate in `log.jsonl`, including `rim_sides`.
- Commit after each group, staging `docs/liquid_glass/02a-looks/tuning-log-2a1.md` and the two table files.

**Which backdrops, and why** (finding 4):
- Tone steps use all five backdrops. 2A tuned tone on `stripes`, `white` and `black` only, and `light-photo` came out 20–35 luma dark near the top.
- Shadow steps use `white` and `text`, with `--pad 60`. Native's shadow fit is the same on every light backdrop (sigma 17 pt, offset 8 pt, opacity 0.181 dark on `white`, `text` and `photo`; fit error 0.30–0.59 luma, prototype analysis of run `20260930-082046`), and on `black` a shadow is invisible.
- Edge-light steps use `black` and `white`: `black` shows the line and sheen alone, `white` the outline and the shadow at the edge.
- Lens steps use `stripes`, `photo` and `white`: the stripes show where the lens pulls content in at the curved ends (ruling 7), the photo shows refraction over detail.
- Accessibility steps use all five: Done item 5 measures all five.

**When a case will not reach its threshold** (MAD ≤ 4, luminance ≤ 3, rim ≤ 6, centre ≤ 1 pt, box ≤ 1 pt): run the same step once more with every grid narrowed to the best value ± 2 of the old steps, with the same count, clamped only by `tune.RANGES`. If it still fails, log the residual and go on. Never hand-edit table values; Task 9 reports what failed.

**Copying rows.** `copy_row FROM TO KEEP SIZE_FROM` is 2A's snippet (row `TO` becomes row `FROM`, except the `KEEP` fields, which come from `SIZE_FROM`); `copy_fields FROM TO FIELDS` copies only the listed fields; `copy_edge_row FROM TO` copies a whole scroll edge row:

```bash
copy_row() {
python3 - "$1" "$2" "$3" "$4" <<'EOF'
import sys
sys.path.insert(0, "tool/glass_lab/harness")
import material_table
source, target = sys.argv[1], sys.argv[2]
keep = [name for name in sys.argv[3].split(",") if name]
size_from = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else target
rows = material_table.read()
rows[target] = {**rows[source], **{name: rows[size_from][name] for name in keep if name in rows[size_from]}}
material_table.write(rows)
print(target, rows[target])
EOF
}
copy_fields() {
python3 - "$1" "$2" "$3" <<'EOF'
import sys
sys.path.insert(0, "tool/glass_lab/harness")
import material_table
source, target = sys.argv[1], sys.argv[2]
rows = material_table.read()
rows[target] = {**rows[target], **{name: rows[source][name] for name in sys.argv[3].split(",") if name in rows[source]}}
material_table.write(rows)
print(target, rows[target])
EOF
}
copy_edge_row() {
python3 - "$1" "$2" <<'EOF'
import sys
sys.path.insert(0, "tool/glass_lab/harness")
import material_table
rows = material_table.read(table=material_table.SCROLL_EDGE)
rows[sys.argv[2]] = dict(rows[sys.argv[1]])
material_table.write(rows, table=material_table.SCROLL_EDGE)
print(sys.argv[2], rows[sys.argv[2]])
EOF
}
SIZE=thickness,shadowOffsetY,shadowBlur,shadowOpacity
```

Every command below is `step` followed by its arguments. `R` means `--scene material.regular`, `B5` means `--backdrops stripes,photo,white,black,text`.

- [ ] **Group A: dark regular glass** (`R --appearance dark`), for each size in the order 200, 88, 44 (`--size S --region sS`):

| Step | Arguments | About |
|---|---|---|
| A1 shadow | `--backdrops white,text --pad 60 --params` 200: `shadowOpacity=0.13:0.19:4,shadowBlur=26:32:4,shadowOffsetY=6:10:5`; 88: `shadowOpacity=0.04:0.07:4,shadowBlur=8:14:4,shadowOffsetY=6:10:5`; 44: `shadowOpacity=0.006:0.018:4,shadowBlur=2:6:5,shadowOffsetY=6:10:5`; `--passes 2` | 20 min |
| A2 edge light | `--backdrops black,white --params specular=0.2:0.36:5,specularWidth=0.4:0.7:4,sheen=0.03:0.09:4,sheenWidth=1.5:2.5:3,specularFill=0.9:1.1:3,outline=0.7:1:4,outlineWidth=0.4:0.7:4 --passes 2` | 35 min |
| A3 lens | `--backdrops stripes,photo,white --params thickness=` 200: `4:16:4`; 88: `2:8:4`; 44: `2:12:6`; `,refractiveIndex=1.05:1.25:5,dispersion=0:0.08:5 --passes 2` | 25 min |
| A4 tone | `B5 --params` the row's line from the tone table below `--passes 1` | 45 min |

About 6 h for the group. Commit: `feat(mobile): ios_liquid_glass dark regular material retuned on five backdrops with the iOS 27 edge`.

- [ ] **Group B: light regular glass** (`R --appearance light`), sizes 200, 88, 44:

| Step | Arguments | About |
|---|---|---|
| B1 shadow | `--backdrops white,text --pad 60 --params` 200: `shadowOpacity=0.09:0.15:4,shadowBlur=26:32:4,shadowOffsetY=6:10:5`; 88: `shadowOpacity=0.028:0.052:4,shadowBlur=7:12:6,shadowOffsetY=6:10:5`; 44: `shadowOpacity=0.006:0.018:4,shadowBlur=2:6:5,shadowOffsetY=6:10:5`; `--passes 2` | 20 min |
| B2 edge light | `--backdrops black,white --params specular=0.2:0.36:5,specularWidth=0.4:0.7:4,sheen=0.03:0.09:4,sheenWidth=2:3.5:4,specularFill=0.85:1.05:3,outline=0.25:0.45:5,outlineTop=0:0.2:5,outlineWidth=0.4:0.7:4 --passes 2` | 40 min |
| B3 lens | `--backdrops stripes,photo,white --params thickness=` 200: `2:8:4`; 88: `2:18:5`; 44: `2:8:4`; `,refractiveIndex=1.05:1.25:5,dispersion=0:0.06:4 --passes 2` | 25 min |
| B4 tone | `B5 --params` the row's line from the tone table below `--passes 1` | 45 min |

About 6.5 h. Commit: `... light regular material retuned ...`.

- [ ] **Group C: clear glass** (`--scene material.clear --row clear --size 88 --region plain,dimmed`), dark then light:
  1. C1 shadow: `--backdrops photo,white --pad 60 --params shadowOpacity=0:0.03:4 --passes 1` (15 min). Native clear glass casts no shadow (fitted opacity 0.000 on white in both appearances), and the seed row starts at 0, so the expected best is 0.
  2. C2 edge light: `--backdrops photo,white --params` A2's grid (dark) or B2's (light) `--passes 2` (35 min).
  3. C3 tone: `--backdrops photo,white --params` the `clear.88` line of the tone table `--passes 2` (30 min).
  4. `copy_row <a>.clear.88 <a>.clear.44 thickness,refractiveIndex <a>.regular.44` and `copy_row <a>.clear.88 <a>.clear.200 thickness,refractiveIndex <a>.regular.200`. Clear glass is measured only at 88 pt; it takes regular's size-dependent lens and keeps its own zero shadow.

  About 2.5 h. Commit.

- [ ] **Group D: tinted glass** (`--scene material.tinted --row tinted --backdrops stripes,white,black`), dark then light:
  1. `copy_row <a>.regular.88 <a>.tinted.88 tintAmount,tintBlack,tintWhite`, then D1 block: `--size 88 --region block --params tintAmount=0.8:1:5,tintBlack=0.7:1.2:6,tintWhite=0.9:1.3:5,saturation=0.7:1.2:6 --passes 2` (35 min).
  2. `copy_row <a>.regular.44 <a>.tinted.44 tintAmount,tintBlack,tintWhite`, then D2 run: `--size 44 --region run --params tintAmount=0.8:1:5,tintBlack=0.6:1.2:7,tintWhite=0.9:1.3:5,specular=0:0.36:5,sheen=0:0.09:4,outline=0:1:5 --passes 2` (35 min). The Run button is 78 × 37 pt now (Task 6), so its row is measured without the 2A offset.
  3. `copy_row <a>.tinted.88 <a>.tinted.200 $SIZE,thickness,refractiveIndex,toneBlack,toneMid,toneWhite <a>.regular.200`.

  About 2.5 h. Commit.

- [ ] **Group E: accessibility** (`R --size 88 --region s88 B5`), dark then light, for each mode: Reduce Transparency (`--a11y reduce-transparency`, row `reduceTransparency`) and Increase Contrast (`--a11y increase-contrast`, row `increaseContrast`); the row follows from `--a11y`. Done item 5 measures all three sizes, and native's accessibility tone changes with size (Increase Contrast dark `toneWhite` 0.18 at 44, 0.20 at 88, 0.29 at 200 by `lab.py tonefit`), so the seed already holds each size's own tone points and nothing below copies them:
  1. Take the finished regular lens and shadow at every size: `copy_fields <a>.regular.S <a>.<row>.S $SIZE,refractiveIndex,dispersion` for S = 44, 88, 200.
  2. E1 tone: `--params` the `<row>.88` line of the tone table `--passes 2` (75 min).
  3. E2 edge light: dark `--params outline=0.8:1:5,specular=0.2:0.36:5,sheen=0.03:0.09:4 --passes 1`; light `--params outline=0.25:0.45:5,outlineTop=0:0.2:5,specular=0.2:0.36:5,sheen=0.03:0.09:4 --passes 1` (45 min).
  4. Spread the 88 pt result without touching tone: `copy_fields <a>.<row>.88 <a>.<row>.S frost,saturation,outline,outlineTop,specular,sheen` for S = 44, 200.
  5. Check the 200 pt row: `step R --appearance <a> --a11y <mode> --size 200 --region s200 B5 --params frost=<the row's frost>:<same>:1 --passes 1` scores it without changing it (one candidate, 7 min). Log it.

  About 9 h for both modes and appearances. Commit.

- [ ] **Group F: scroll edge** (`--scene material.edge.<style> --backdrops scroll`), dark then light:

| Style | Arguments | About |
|---|---|---|
| soft | `--params edge.extent=86:102:5,edge.blur=3:5:5,edge.blurKnee=0.45:0.7:6,edge.blurReach=0.9:1:3,edge.dim=` dark `0.46:0.58:5`, light `0.24:0.36:5` `,edge.knee=0.45:0.65:5,edge.cap=` dark `0.52:0.68:5`, light `0.47:0.63:5` `--passes 2` | 35 min |
| hard | `--params edge.extent=51:59:5,edge.blur=` dark `4:6:5`, light `2.25:4.25:5` `,edge.dim=` dark `0.51:0.63:5`, light `0.715:0.835:5` `,edge.cap=` dark `0.5:0.7:5`, light `0.68:0.88:5` `,edge.capBlur=0:8:5,edge.line=` dark `0.275:0.475:5`, light `0.325:0.525:5` `,edge.lineShade=` dark `0.8:1:5`, light `0.25:0.65:5` `--passes 2` | 35 min |
| automatic | none: `copy_edge_row <a>.hard <a>.automatic`. Native `hard` and `automatic` are pixel-identical in these scenes (ROADMAP gotcha 24). | 0 |

About 2.5 h. Commit: `feat(mobile): ios_liquid_glass scroll edge rows retuned for the Gaussian renderer`.

The tone table. Each grid is the seeded row's value ± 0.04 black, ± 0.06 mid, ± 0.08 white, frost × 0.6–1.4, saturation ± 0.2; the seeded tone points are native's own, fitted by `lab.py tonefit` (Task 2), so the search refines around the measurement rather than 2A's three-backdrop values:

| Row | `--params` |
|---|---|
| `dark.regular.44` | `toneBlack=0.0863:0.1663:5,toneMid=0.4611:0.5811:5,toneWhite=0.6407:0.8007:5,frost=5.725:13.3584:5,saturation=0.7:1.1:5` |
| `dark.regular.88` | `toneBlack=0.0846:0.1646:5,toneMid=0.4179:0.5379:5,toneWhite=0.4967:0.6567:5,frost=8.4:19.6:5,saturation=0.7:1.1:5` |
| `dark.regular.200` | `toneBlack=0.0853:0.1653:5,toneMid=0.3927:0.5127:5,toneWhite=0.3973:0.5573:5,frost=10.8:25.2:5,saturation=0.7:1.1:5` |
| `dark.clear.88` | `toneBlack=0.2392:0.3192:5,toneMid=0.49:0.61:5,toneWhite=0.97:1.13:5,frost=17.04:39.76:5,saturation=0.95:1.35:5` |
| `dark.reduceTransparency.88` | `toneBlack=0.0384:0.1184:5,toneMid=0.0204:0.1404:5,toneWhite=-0.0018:0.1582:5,frost=43.2:100.8:5,saturation=0.925:1.325:5` |
| `dark.increaseContrast.88` | `toneBlack=0.0698:0.1498:5,toneMid=0.108:0.228:5,toneWhite=0.1156:0.2756:5,frost=8.4:19.6:5,saturation=0.7:1.1:5` |
| `light.regular.44` | `toneBlack=0.4752:0.5552:5,toneMid=0.7158:0.8358:5,toneWhite=0.9231:1.0831:5,frost=7.5666:17.6554:5,saturation=0.6:1:5` |
| `light.regular.88` | `toneBlack=0.4826:0.5626:5,toneMid=0.7145:0.8345:5,toneWhite=0.9171:1.0771:5,frost=12:28:5,saturation=0.6:1:5` |
| `light.regular.200` | `toneBlack=0.4936:0.5736:5,toneMid=0.7368:0.8568:5,toneWhite=0.9167:1.0767:5,frost=13.2:30.8:5,saturation=0.6:1:5` |
| `light.clear.88` | `toneBlack=0.085:0.165:5,toneMid=0.54:0.66:5,toneWhite=0.945:1.105:5,frost=2.4:5.6:5,saturation=0.9:1.3:5` |
| `light.reduceTransparency.88` | `toneBlack=0.941:1.021:5,toneMid=0.9277:1.0477:5,toneWhite=0.9207:1.0807:5,frost=36:84:5,saturation=0:0.3562:5` |
| `light.increaseContrast.88` | `toneBlack=0.69:0.77:5,toneMid=0.8139:0.9339:5,toneWhite=0.9202:1.0802:5,frost=12:28:5,saturation=0.6:1:5` |

- [ ] **Step G: Check the gates.** `python3 -m unittest discover tool/glass_lab/harness/tests` (the committed tables are still in writer format and have every row), the package `flutter test`, and `flutter test` in `packages/mobile`.

---

### Task 9: Verification runs (spec Done items 3–6 and 8)

**Files:**
- Create: `docs/liquid_glass/02a-looks/results-2a1.md`, `docs/liquid_glass/02a-looks/summary-material-2a1.md`

**Interfaces:**
- Consumes: the tuned tables (Task 8), `lab.py run`, `report`, `summary`, `perf`, and `docs/liquid_glass/02a-looks/operator-baseline.json` (2A).
- Produces: `results-2a1.md`, which records every re-measured Done item with its numbers, pass or fail, and the run folders. The ROADMAP (Task 10) quotes it.

- [ ] **Step 1: Rebuild both Flutter apps and check nothing is left on.**

```bash
python3 tool/glass_lab/harness/lab.py build example && python3 tool/glass_lab/harness/lab.py build operator
xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled
```

Expected: `built for 708879DD-...` twice, then `0`.

- [ ] **Step 2: Material scenes** (Done items 3 and 4). Only the scenes the Done items name, so the run takes about 35 minutes:

```bash
for scene in material.regular material.clear material.tinted material.edge; do python3 tool/glass_lab/harness/lab.py run $scene --appearance both; done
```

Run `lab.py report <run>` on each of the four run folders, then `lab.py summary docs/liquid_glass/02a-looks/summary-material-2a1.md <material.regular run>`. The report's `rim_rms` is now the worst of all four sides of every pinned glass (Task 1); `result.json` keeps `rim_legacy` and `rim_elements` for the table.
- `material.regular` must pass MAD ≤ 4, luminance ≤ 3, rim ≤ 6, centre ≤ 1 and box ≤ 1 on all 5 backdrops, both appearances.
- `material.clear` on `photo` and `white`; `material.tinted` on `stripes`, `white` and `black`.
- `material.edge.soft`, `.hard` and `.automatic` on MAD and luminance only.

- [ ] **Step 3: Accessibility** (Done item 5), about 25 minutes:

```bash
python3 tool/glass_lab/harness/lab.py run material.regular --appearance both --a11y reduce-transparency
python3 tool/glass_lab/harness/lab.py run material.regular --appearance both --a11y increase-contrast
xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled
```

Report each run. Same five thresholds as Step 2. The last command must print `0`.

- [ ] **Step 4: Operator's component scenes** (Done item 6), exactly as 2A's Task 12 Step 4, with the comparison script importing `metrics.THRESHOLDS` (2A's final version). `tabbar.rest`, `button.press` and `navbar.inline` have no pinned regions, so their `rim_rms` is the same centre-column measure 2A used, and the comparison with the project 1 baseline stays like for like.

```bash
python3 tool/glass_lab/harness/lab.py run tabbar.rest --app both --appearance both --flutter operator
python3 tool/glass_lab/harness/lab.py run button.press --app both --appearance both --flutter operator
python3 tool/glass_lab/harness/lab.py run navbar.inline --app both --appearance both --flutter operator
```

- [ ] **Step 5: Frame cost** (Done item 8), about 10 minutes:

```bash
python3 tool/glass_lab/harness/lab.py perf --takes 3 --out build/glass_lab/perf-2a1.json
python3 tool/glass_lab/harness/lab.py perf --takes 3 --scenes perf.none,perf.glass,perf.material --a11y reduce-transparency --out build/glass_lab/perf-2a1-rt.json
```

The budget is `perf.material` no more than 20% over the old renderer's `perf.glass` (12.10 ms median, 2A `flip-spike.md`). `perf.glass` runs in the same takes, so `perf.material ÷ perf.glass × 1.022` (2A's measured new/old ratio at the same settings) is the ratio to report beside the direct one. `perf.edge` has no budget; report its cost.

- [ ] **Step 6: Write** `docs/liquid_glass/02a-looks/results-2a1.md`:

```markdown
# 2A.1 results

Date: <today>. Branch `feat/ios-liquid-glass-2a` at <commit>. Simulator: iPhone 17 Pro (iOS 27), UDID 708879DD-8B2A-4547-863F-F49EE1474D8B.

The rim measure changed in 2A.1 (Task 1): all four sides of every pinned glass, and never looser than 2A's. 2A's numbers are re-analysed with it where a comparison is quoted.

| Done item | 2A | 2A.1 | Evidence |
|---|---|---|---|
| 3 Material scenes, strict thresholds | 0 of 20 | n of 20 | runs ... |
| 4 Scroll edge MAD and luminance | 2 of 6 | n of 6 | run ... |
| 5 Reduce Transparency and Increase Contrast | 0 of 20 | n of 20 | runs ... |
| 6 Operator components halve rim and luminance | 18 of 32 | n of 32 | runs ... |
| 8 Frame cost within 20% | +2.2% at default settings | material x ms vs old 12.10 ms | perf-2a1.json |

## Failing cases
For each case over a threshold: scene, case, measure, value, threshold, the worst `rim_elements` side, and one sentence from the filmstrip.

## Operator components
<the comparison table>

## Frame cost
<the perf table>
```

Fill every cell from the runs. Where a Done item did not pass, say so plainly.

- [ ] **Step 7: Commit**

```bash
git add docs/liquid_glass/02a-looks/results-2a1.md docs/liquid_glass/02a-looks/summary-material-2a1.md
git commit -m "docs(mobile): 2A.1 measured results against iOS 27

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Documents (the code review's stale facts, finding 8f)

**Files:**
- Replace: `packages/ios_liquid_glass/README.md`, `packages/ios_liquid_glass/FORK.md`, `tool/glass_lab/README.md`
- Modify: `packages/ios_liquid_glass/CHANGELOG.md`, `docs/liquid_glass/ROADMAP.md`, `docs/liquid_glass/02a-looks/results.md`, `docs/liquid_glass/02a-looks/flip-spike.md`

**Interfaces:**
- Consumes: `results-2a1.md` and `tuning-log-2a1.md` (Tasks 8 and 9).
- Produces: documents a fresh session can continue from, with every code review docs item fixed.

- [ ] **Step 1: Package documents.** Replace `packages/ios_liquid_glass/README.md` and `FORK.md` with the versions below. The README's frame-cost sentence quotes the prototype (13.04 ms, +7.8%, 4.98 ms); if Task 9 Step 5 measured values more than 0.3 ms away, write Task 9's instead. In `CHANGELOG.md`, append these bullets to the `## 0.1.0` list, after its last bullet (the package stays 0.1.0; upstream's own `0.1.1-dev` entries sit further down the file):

```markdown
 - (2A.1) **BREAKING** **FEAT**: the edge is the iOS 27 edge measured on the simulator: a crisp silhouette, a dark outline outside it that is strongest at the curved ends, and a line and sheen at the top and bottom. `LiquidGlassSettings` replaces the `hairline*` fields with `outline`, `outlineTop`, `outlineWidth`, `sheen` and `sheenWidth`.
 - (2A.1) **BREAKING** **FIX**: the scroll edge blurs with real Gaussians. Its `blur` and `capBlur` fields are now a sigma in points, and the soft style has its own `blurKnee` and `blurReach`.
 - (2A.1) **FIX**: shadows reach native's soft tail, and clear glass casts none.
 - (2A.1) **FIX**: `Glass.clear.tint(c)` stays untinted under Reduce Transparency and Increase Contrast, and its foreground is not the tinted one.
 - (2A.1) **FEAT**: `GlassMaterialOverride.side` limits debug overrides to one size anchor.
```

````markdown
# ios_liquid_glass

iOS 27 Liquid Glass for Flutter, measured against native.

Every look parameter in this package comes from an automatic search against screenshots of native SwiftUI glass on the iOS 27 simulator. The numbers ship as a table, `ios27Table`. The measuring instrument, a native catalog, a touch driver and a comparison harness, lives in the repository that develops this package (`tool/glass_lab/`).

Requires Impeller (iOS, or Android with Impeller). The accessibility bridge is iOS only; on other platforms the package falls back to `MediaQuery`.

## Use

```dart
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

GlassEffect(
  child: Padding(
    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: GlassForeground(child: Text('Glass')),
  ),
)
```

The glass is drawn behind the child, in the shape you choose, sized by the child. Put it over content: glass shows what is behind it.

### SwiftUI names

| SwiftUI | ios_liquid_glass |
|---|---|
| `.glassEffect()` | `GlassEffect(child: ...)` |
| `.glassEffect(.clear)` | `GlassEffect(glass: Glass.clear, ...)` |
| `.glassEffect(.regular.tint(.green))` | `GlassEffect(glass: Glass.regular.tint(green), ...)` |
| `.glassEffect(.identity)` | `GlassEffect(glass: Glass.identity, ...)` |
| `.glassEffect(.regular.interactive())` | `Glass.regular.interactive()` (motion arrives in a later version) |
| `.glassEffect(in: .circle)`, `.rect(cornerRadius:)`, capsule | `GlassShape.circle()`, `GlassShape.rect(r)`, `GlassShape.superellipse(r)`, `GlassShape.capsule()` |
| `GlassEffectContainer(spacing:)` | `GlassEffectContainer(spacing: 20, child: ...)` |
| `.scrollEdgeEffectStyle(.soft / .hard / .automatic)` | `ScrollUnderBars(style: ScrollEdgeStyle.soft, child: ...)` or `ScrollEdgeEffect(...)` |
| the 35% dimming layer under clear glass | `GlassDimming(child: ...)` |

### Theme

`GlassTheme` is optional. Without it, glass follows the platform brightness.

```dart
GlassTheme(
  data: GlassThemeData(
    brightness: Brightness.dark,
    accent: Color(0xFF1ACB64),
    scrollEdgeTint: Color(0xFF000000),
  ),
  child: app,
)
```

- `accent` is what `Glass.regular.tint(GlassTheme.of(context).accent)` uses.
- `scrollEdgeTint` colours the scroll edge effect. By default it is black in dark mode and white in light mode.
- `GlassForeground` gives labels and symbols on glass their native colour: white in dark mode, black in light mode, and white on tinted glass.

### Accessibility

Reduce Transparency, Increase Contrast and Reduce Motion are read live. On iOS a small plugin reports Reduce Transparency, which Flutter's `MediaQuery` does not expose. Glass switches to its tuned `reduceTransparency` or `increaseContrast` material without a restart. `GlassAccessibility.of(context)` returns the current values.

### Size

Native glass changes with its size: a 200 pt glass casts a long soft shadow (sigma about 17 pt) where a 44 pt one casts almost none, and its tone and frost differ too. `GlassEffect` measures itself and interpolates the tuned material between the 44, 88 and 200 pt anchors on its shorter side. Pass `sideHint` to avoid a one-frame default before the first layout.

Inside a `GlassEffectContainer`, every grouped child shares the container's single glass layer, so the layer's settings (tone, frost, edge light) are resolved once from the container's own `side` (default 88). Each child's shadow still comes from its own measured size.

### Clear glass has no tint

`Glass.clear.tint(color)` still renders untinted, with or without Reduce Transparency and Increase Contrast, and its foreground is the plain one. Use `Glass.regular.tint(color)` for tinted glass.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction and the distance to the silhouette into a cached texture. It also covers a thin band just outside each shape.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It maps brightness through a three-point tone curve (black, mid, white) and tints with the accent across a brightness range. Then it draws the iOS 27 edge measured on the simulator: a crisp silhouette, a dark outline just outside it that is strongest at the curved ends, and a bright line and a soft sheen along the top and bottom, lit by two lobes of a vertical light.
- The shadow is one Gaussian per glass, offset downward, fitted to native's.
- The scroll edge effect stacks real Gaussian blurs, masked by a small shader, under a tinted gradient.

Frame cost, measured on the iOS 27 simulator with 13 glasses over a moving backdrop (debug build, raster median): 13.04 ms with the tuned material through `GlassEffect`, against 12.10 ms for the pre-fork renderer at its defaults (+7.8%); a soft scroll edge adds 4.98 ms. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
````

```markdown
# Why this package is vendored

Vendored from `liquid_glass_renderer` at upstream commit `ad3bcff` (2026-04-24), not the
last pub.dev release `0.2.0-dev.4` (2025-11-13). `main` carries five months of unreleased
work the app needs: `shadows` on `LiquidGlass`/`FakeGlass`, `LiquidGlass.auto`,
`LiquidGlassLayer.existsIn`, the Impeller saturation shader for `FakeGlass`, and fixes to
`FakeGlass` rendering on Skia.

It is the renderer behind the iOS-style glass chrome (tab bar, navigation bars, composer,
sheets). It is vendored rather than depended on so the app can tune the shaders and the
fallback path to its own design, and so an experimental pre-release cannot change under it.

`lib/`, `test/`, `LICENSE` and `CHANGELOG.md` are kept. Upstream's `doc/` GIFs and `coverage/`
are dropped. Upstream's `README.md` and `example/` were replaced in 2A by this package's own
README and example app.

Changes from upstream:

- `pubspec.yaml`: workspace resolution, `publish_to: none`, a `flutter_test` dev
  dependency kept for `test/`.
- Thickness is uploaded × devicePixelRatio to both the geometry and the final render pass,
  so `LiquidGlassSettings.thickness` is in logical points. Upstream left it in physical
  pixels, making the lens band a third as wide on a 3x screen. A DPR change re-uploads it.
  Blend was already uploaded × devicePixelRatio upstream (`liquid_glass_blend_group.dart`,
  `updateShaderWithSettings`); no change needed there.

- `sdfSquircle` in `sdf.glsl` is a p-norm continuous corner (`SQUIRCLE_EXPONENT`,
  `SQUIRCLE_EXTENT`) fitted to Flutter's `RoundedSuperellipseBorder`. Upstream used the
  rounded-rectangle formula, so the lens and the clip disagreed at the corners.

- `LiquidGlassSettings.fillRatio` is kept as upstream's public API (default 0.8), but the
  iOS 27 final pass does not read it; `GlassStyle`, which used to set it, was deleted with
  the rest of Operator's old glass API.

- `GlassDragBuilder` handles `onPointerCancel` in listener mode; upstream left a cancelled
  touch stuck pressed.
- `GlassGlow` fades out where the finger lifted; upstream slid the glow to the top-left
  corner on release.
- Removed `Glassify` (`experimental.dart`), the unused `LiquidGlassFilter`, and their
  shaders `liquid_glass_filter.frag` and `liquid_glass_arbitrary.frag`. The app uses
  neither, and both failed SkSL compilation on every build.
- Removed `lib/assets/shaders/shared.glsl`, unused once `Glassify` was removed.
- Removed the public `ShaderKeys` fields `legacyLiquidGlass`, `liquidGlassFilterShader`
  and `glassify`, which only `Glassify` referenced.


## ios_liquid_glass 0.1.0 (project 2A)

The package was renamed from `liquid_glass_renderer` to `ios_liquid_glass`, with library `package:ios_liquid_glass/ios_liquid_glass.dart` and shader root `packages/ios_liquid_glass/`. Its goal changed from a vendored renderer to an iOS 27 Liquid Glass package for any Flutter app. Changes to upstream's code:

- `liquid_glass_final_render.frag` is rewritten as the iOS 27 model:
  - rim-only dispersion;
  - a three-point tone curve on luminance with chroma saturation;
  - a tint brightness range;
  - an adaptive hairline;
  - a two-lobe specular in the rim band.
- Upstream's rim lighting (`render.glsl`, `lightIntensity`, `ambientStrength`, `fillRatio` in the shader) is gone. `render.glsl` is deleted. The geometry pass is unchanged.
- `LiquidGlassSettings` gains `toneBlack`, `toneMid`, `toneWhite`, `tintBlack`, `tintWhite`, `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight`, `specular`, `specularWidth`, `specularPower` and `specularFill`, with `effective*` getters where visibility applies. The old fields stay for `FakeGlass`.
- `LiquidGlassRenderObject._updateShaderSettings` packs the new uniforms into `vec4`s from index 6.
- `LiquidGlassSettings` and `LiquidShape` use `with Equatable` instead of the deprecated `EquatableMixin`. The library file declares `library;`.
- `GlassMaterial.resolve` keeps a tinted glass's `tintAmount`, `tintBlack` and `tintWhite` from the tinted row, at the same appearance and anchors, when Reduce Transparency or Increase Contrast picks the accessibility row for the rest of the material. The accessibility rows are tuned on their own for tone, frost and edge light, share only the lens and shadow fields with the regular rows, and carry a `tintAmount` of 0. Since 2A.1 this applies only to regular glass: `Glass.clear.tint(c)` stays untinted.
- `GlassEffect` and `GlassEffectContainer` share one internal resolve helper, `resolveGlassMaterial` in `lib/src/api/glass_material_context.dart`, instead of each repeating the same `GlassMaterial.resolve` call; each widget still calls `toSettings()` itself.
- New, not from upstream:
  - `lib/src/api/` (`Glass`, `GlassShape`, `GlassTheme`, `GlassEffect`, `GlassEffectScope`, `GlassEffectContainer`, `GlassDimming`, `GlassForeground`, `glass_material_context.dart`);
  - `lib/src/material/` (`GlassMaterial`, `ios27Table`, `ScrollEdgeMaterial`, `ios27ScrollEdgeTable`, `GlassMaterialOverride`);
  - `lib/src/accessibility/`;
  - `lib/src/scroll_edge/` and `scroll_edge_blur.frag`, moved from Operator;
  - the iOS plugin in `ios/`;
  - the `example/` app.

## ios_liquid_glass 0.1.0, project 2A.1 fix round

- The geometry pass (`liquid_glass_geometry_blended.frag`) writes the signed distance to the silhouette, normalised by the thickness, into the blue channel instead of the bevel height, uses alpha as an inside-the-shape-or-outline-band flag, and covers a band `outlineWidth` + 1 px outside every shape. Its second uniform float carries that band in physical pixels. `encodeGeometry` and `decodeSignedDistance` in `displacement_encoding.glsl` replace the old encoding.
- The geometry bounds grow by `outlineWidth` + 1 pt so the band is inside the texture and the shader layer's clip; a change of `outlineWidth` rebuilds the geometry.
- Geometry pictures and images are sized with `toPixelCount()` (rounding) instead of `ceil()`. The extents are already snapped to pixels, and `ceil` turned a floating-point 760.0000000000001 into 761, which sampled the geometry one pixel off at the right and bottom of glass at fractional positions.
- `liquid_glass_final_render.frag`: coverage is a one-pixel ramp at the silhouette (upstream faded the last two pixels); a dark outline is drawn outside the silhouette with a strength that follows the normal (`outline` at the ends, `outlineTop` at the top and bottom); inside, an exponential line (`specular`, `specularWidth`) and sheen (`sheen`, `sheenWidth`) are weighted by the two light lobes and fade out over the last 30% of the bevel. The adaptive inner hairline is gone.
- `LiquidGlassSettings` loses `hairline`, `hairlineWidth`, `hairlineDark`, `hairlineLight` and `effectiveHairline`, and gains `outline`, `outlineTop`, `outlineWidth`, `sheen` and `sheenWidth` with their `effective*` getters.
- `GlassShadow` cuts an offset shadow out of the glass with a difference clip instead of a `saveLayer` and a `dstOut` shape, and sizes the clip to three sigma of the blur (upstream's layer bounds stopped the tail at one blur radius).
- `scroll_edge_blur.frag` is replaced by `scroll_edge_mask.frag`. `ScrollEdgeEffect` stacks real Gaussians (`ImageFilter.compose` of a blur and the mask shader) and paints the dim, cap and divider line itself.
- `GlassMaterialOverride` takes an optional `side`; `resolveGlassMaterial` applies overrides only to glass at that size anchor.

Record every later change to `lib/` in this file.

Upstream: https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer
```

What they fix from the code review: FORK's stale "README image links do not resolve" and "`example/` dropped" (docs item 5), the accessibility rows' description (item 3), the shared helper and `toSettings()` (item 4); README's container sentence, which now says each grouped child's shadow comes from its own size (item 6), the size paragraph, which no longer claims thickness grows monotonically (item 7), and the clear-glass promise, true again after Task 3 (item 8).

- [ ] **Step 2: Lab README.** Replace `tool/glass_lab/README.md` with:

````markdown
# Glass lab

This lab measures Flutter glass against native iOS 27 Liquid Glass. It measures the `ios_liquid_glass` package through its example app, and Operator's own glass components through Operator's debug lab.

It has three parts:
- a native SwiftUI catalog (`native/GlassLab`);
- an XCUITest driver that plays identical touches on any app (`native/GlassLabDriver`);
- a Python harness that records the apps, compares them, and tunes the package's material (`harness/`).

The specs are `docs/liquid_glass/01-reference-lab/spec.md` (the lab) and `docs/liquid_glass/02a-looks/spec.md` (tuning, probes).

## Requirements

- Xcode 27 with the iOS 27 simulator runtime.
- Flutter 3.44.5.
- `ffmpeg`.
- Python 3 with Pillow and numpy.

The harness uses the simulator named "iPhone 17 Pro (iOS 27)" and creates it if it is missing.

## Commands

Run everything from `packages/mobile`.

```bash
python3 tool/glass_lab/harness/lab.py build
python3 tool/glass_lab/harness/lab.py prepare
python3 tool/glass_lab/harness/lab.py run material.regular
python3 tool/glass_lab/harness/lab.py report
```

- **`build [native|example|operator|all]`** builds and installs the apps:
  - GlassLab and the driver, after regenerating the Xcode project;
  - the `ios_liquid_glass` example app, in debug;
  - Operator, in debug.

  `flutter build ios` alone fails under Xcode 27, so this command runs `--config-only` and then `xcodebuild`.
- **`prepare`** sets the status bar to 9:41, generates the backgrounds, copies them into all three apps, and takes Apple's apps past their first-run screens. On a fresh simulator, check each Apple app once by screenshot afterwards; first-run screens change between iOS builds.
- **`run <scene|group|prefix|all>`** records scenes into `build/glass_lab/runs/<timestamp>/`. Options:
  - `--app native|flutter|both`;
  - `--appearance light|dark|both`;
  - `--backdrop <id>`;
  - `--a11y <mode>`;
  - `--flutter example|operator`, where `flutter` means the example app unless you pass `--flutter operator`.
- **`report [<run dir>]`** analyses a run and writes `report.html` beside it. With no argument it uses the latest run.
- **`summary <out.md> [<run dir>]`** writes a Markdown summary of a run.
- **`repeat [<scene>] [--times 3]`** records native takes and compares them to each other, then updates `noise.json`. With no scene it covers `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`. Rerun it after an Xcode or simulator update.
- **`geometry <scene>`** prints the native glass boxes of a scene in points, for positioning Flutter scenes.
- **`baseline [--flutter example|operator]`** runs every scene in both apps and both appearances, plus the accessibility runs, then `report`. It takes about four hours.
- **`tune`** searches material parameters against native (see below).
- **`perf [--takes 3] [--scenes a,b] [--a11y <mode>] [--out file]`** measures raster time in the example's `perf.none` (moving backdrop only), `perf.glass` (13 glasses at `const LiquidGlassSettings()`), `perf.material` (the same glasses as `GlassEffect`, drawing their tuned rows, outlines and shadows) and `perf.edge` (a soft scroll edge) scenes, and reports each scene's cost over `perf.none`. Takes run in alternating order.
- **`a11y`** launches the example and turns each accessibility mode on and off while it runs. It fails unless every change reaches the app live.
- **`flip [<run>] --regular <run>`** checks whether native glass in `material.flip` changes appearance with the content behind it.

## How a scene runs

`scenes.json` lists every scene. Each entry has an id, a group, backgrounds, appearances and a list of steps. The step types are:
- `wait`, `tap`, `doubleTap`;
- `press {at, duration}`;
- `pressDrag {from, to, pressDuration, velocity, hold}`.

A target is either a point `[x, y]` in points, an accessibility identifier or label, or `{"element": id, "dx": ..., "dy": ...}`.

Optional fields:
- `regions`: named rectangles in points;
- `track`: a region that pins where the scene is compared;
- `measures`: the still-image measures that count, from `mad`, `luminance`, `rim_rms`, `bbox_pt` and `centre_pt`; all of them by default.

For example, the edge scenes pin the top 240 pt and count only `mad` and `luminance`.

For each case, the harness:
1. Launches the scene once in bare mode, background only, for a reference screenshot.
2. Starts `simctl io recordVideo` and runs the driver. The driver launches the app, waits for `scene.ready`, settles for 1.5 s and saves `ready.png`, then plays the steps, settles again and saves `settled.png`.

The native app reads its scene from the `GLASS_LAB_SCENE`, `GLASS_LAB_BACKDROP` and `GLASS_LAB_BARE` launch variables. Flutter cannot see launch variables on iOS. Instead:
- the harness writes `Documents/glass_lab/launch.json` into the Flutter app's container before each launch, as `{scene, backdrop, bare, material, materialSide}`;
- the debug build reads it and deletes it on start;
- `material` is an optional map of material overrides by field name. Scroll edge fields are prefixed `edge.`;
- `materialSide` limits the overrides to glass at that size anchor (44, 88 or 200 pt, after clamping the glass's shorter side), so a 200 pt candidate does not repaint the 44 and 88 pt glass in the same scene.

Before each capture the harness closes every other lab app, so the captured app is launched from the home screen and no "◀ app" back link appears in its status bar.

Backgrounds live in each app's `Documents/glass_lab/`.

If a Flutter app has not built a scene yet, it shows a `missing: <id>` placeholder, the driver skips the steps, and the report counts the scene as missing.

## Tuning

```bash
python3 tool/glass_lab/harness/lab.py tune --scene material.regular --appearance dark \
  --backdrops stripes,white,black --size 88 --region s88 \
  --params toneWhite=0.45:0.75:7,frost=12:40:8 --passes 2 --write
```

- Each candidate sends the whole current table row merged with that candidate's values into the launch file's `material` map (commit `4b096dd`), scoped to `--size` by `materialSide` for material rows, and captures `ready.png`.
- The first candidate is always the committed row, exactly as written. Grid and refinement candidates are clamped to `tune.RANGES`, which covers the shader's whole domain (tone points −0.5–2, `specular` and `sheen` from −1, alphas 0–1, widths and blurs from 0).
- It is scored against native as each measure divided by its threshold, capped at 10, and summed. The rim is scored on all four sides of each `--region` at its exact edge.
- The search is coordinate descent, then a half-step refinement.
- `--region` names manifest regions to compare, padded by `--pad` points (default 12). Shadow steps use `--pad 60`, enough for native's shadow tail. Scenes with a `track` use it.
- `--appearance`, `--size` and `--row` pick the table row to write. `--a11y reduce-transparency` and `--a11y increase-contrast` imply their row; a `--row` they would not render is rejected.

`tune`, `run` and `perf` refuse to start when the example (or Operator) app was built from other sources than the ones on disk: `build` stamps a hash of the package's `lib/` and the app's `lib/` next to the app. Run `lab.py build example` before every `tune`, including after the previous `tune --write`; it takes about 15 s when only Dart changed.

Output goes to `build/glass_lab/tune/<timestamp>/`: `log.jsonl`, `best.json` and `best-<backdrop>.png`. `--write` rewrites the row in `packages/ios_liquid_glass/lib/src/material/ios27.dart`, or in `ios27_scroll_edge.dart` for `material.edge.*` scenes. Never edit those tables by hand.

## Reading the report

Still-image measures compare the lossless screenshots:
- colour difference in the region;
- brightness difference;
- the edge profile: luma across each side of the glass, ±12 pt around its edge. For scenes with pinned regions (every region except the `track`), all four sides of each region are compared at its exact edge, and `rim_rms` is the worst of those and the older centre-column measure on the detected box (`rim_legacy`), so it can only be stricter;
- the glass bounding box and its centre.

Motion measures compare the recordings:
- They use the recorder's real frame times, which run at up to 120 Hz.
- Each burst of change is one event.
- Events are lined up by best fit.
- Each event is checked for peak time, settle time, overshoot and a fitted spring (response and damping).

Motion limits are max(fixed threshold, 1.5 × `noise.json`), because touch timing on the simulator varies a little between runs. The report also lists any Flutter frame gaps over 25 ms, so a debug-build stall is not mistaken for a wrong spring.
````

It drops the "physically meaningless" wording (docs item 9) and documents `--pad`, the freshness guard, `materialSide`, closing other apps, the four-sided rim and the perf scenes.

- [ ] **Step 3: 2A documents.**
  - `docs/liquid_glass/02a-looks/results.md`, Done item 1 row: change "harness 80 tests OK, package 47 tests" to "harness 80 tests OK and package 47 tests at Task 12; 84 and 51 after the final fix wave (see Gates)" (docs item 1).
  - `results.md` Done item 8 row and `flip-spike.md`'s frame-cost paragraph: "raster mean" becomes "the mean of two takes' raster medians" (docs item 12).
  - Add one line under the title of `results.md`: "Superseded for Done items 3–6 and 8 by `results-2a1.md` (2A.1), which also changed the rim measure."
  - `summary-material.md` line 3 ("against Operator's Flutter glass", docs item 10): add after it "(the run used the example app; `lab.py summary` names the target since 2A.1)". Task 2 fixed the generator.

- [ ] **Step 4: ROADMAP.** Update `docs/liquid_glass/ROADMAP.md`. Every number comes from `results-2a1.md`; every path is checked with `ls`.
  - Status table, row 2A: "**DONE with 2A.1**" or "**PARTLY DONE**", with the Done items still failing, and "2A.1 fixes on the same branch".
  - §2 paths: `scroll_edge_mask.frag` replaces `scroll_edge_blur.frag`; the final render model is "crisp silhouette, outer outline, line and sheen"; add `docs/liquid_glass/02a-looks/plan-2a1.md`, `results-2a1.md`, `tuning-log-2a1.md`.
  - §3 gates: the counts at the end of 2A.1 (harness, package, example, app), replacing the stale 47 and 80 (docs item 2). §3 lab commands: add `lab.py tonefit <run> [--a11y MODE]`, `tune --pad N`, `perf --scenes a,b --a11y MODE`, and "`tune`, `run` and `perf` refuse a stale build".
  - §4 gotchas: amend 21 ("`tune` refuses a stale build; rebuild before every step") and drop its Operator mention (docs item 11); amend 25 ("fixed in 2A.1 by the shadow fit and `--pad 60`"); add:
    - 27: `ShaderMask` (and any save layer) over a `BackdropFilter` renders no blur under Impeller; mask a backdrop blur with `ImageFilter.compose(outer: ImageFilter.shader(mask), inner: ImageFilter.blur(...))`, which the backdrop filter draws source-over (2A.1 prototype `20260930-181321`).
    - 28: a lab app launched while another lab app is still running can show iOS's "◀ App" back link under the clock; the harness closes the other lab apps before every capture (2A.1).
    - 29: native iOS 27 glass edges: a crisp silhouette pixel, a dark outline just outside the silhouette that is strongest where the normal is horizontal (none at the top in dark appearance), a bright line and a sheen inside at the top and bottom only, and no inner hairline; the 2A AA faded the silhouette pixel to 26 where native reads 95 (2A.1).
    - 30: native shadows are one Gaussian: sigma 17 pt, offset 8 pt at 200 pt (opacity 0.16–0.18 dark, 0.12 light), sigma 6–7 pt at 88, about 2.5 pt at 44; clear glass casts none (2A.1).
    - 31: native capsules have continuous corners: at 200 pt the flat top starts about 19 pt later than a circle-ended capsule and the edge sits up to 1.3 pt lower near the arc start; the package's capsule is circle-ended. Not fixed (see §6).
    - 32: never `ceil()` a pixel-snapped extent: floating point makes 760 px into 760.0000000000001 and the geometry image one pixel too big, which drops the last lit column and row of glass at fractional positions (2A.1, `toPixelCount`).
    - 33: a `saveLayer` per shadow is expensive under Impeller: thirteen offset shadows cut out with `saveLayer` + `dstOut` cost 2.3 ms on the simulator, a difference clip 0.4 ms (2A.1).
    - 34: native tone points can be read off native captures alone (`lab.py tonefit`); tune tone on all five backdrops, never on three (2A's light rows missed `photo` by 20–35 luma).
  - §5 unchanged.
  - §6 Project 2A: add a "2A.1" subsection after "Delivered": the review's findings in one line each, the plan path, the prototype path, the results (Done items 3–6 and 8, before and after), the open items that remain (at least: the continuous-corner capsule, a measured bottom scroll edge, Operator's accent-tinted icons in `navbar.inline`, `material.interactive`). Remove the open items 2A.1 closed (tinted offset, clear shadow, bottom edges, frame cost at the tuned material).
  - §7 checklist rows for 2A items: new pass counts.
  - §8: a "2A.1 results" block like the 2A one.
  - §9: next steps are the user's review of 2A.1, the merge decision, then project 2B's spec.

- [ ] **Step 5: Check the gates one last time.** Package, example and app: `flutter analyze` and `flutter test`. Harness: `python3 -m unittest discover tool/glass_lab/harness/tests`.

- [ ] **Step 6: Commit**

```bash
git add packages/ios_liquid_glass/README.md packages/ios_liquid_glass/FORK.md packages/ios_liquid_glass/CHANGELOG.md tool/glass_lab/README.md docs/liquid_glass
git commit -m "docs(mobile): 2A.1 documents, results and the code review's stale facts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
