# Spike: can native plain interactive glass react to a press on the iOS 27 simulator?

2026-10-03, branch `proto/2b` (worktree `/Users/omaraly/development/AI/Operator-2b-proto`, from `development` 8354acf02). Probe code commit **5999b4412**. Simulator "iPhone 17 Pro (iOS 27)", `708879DD-8B2A-4547-863F-F49EE1474D8B`, only. Throwaway; never merged.

Paths are relative to `packages/mobile/` unless they start with `docs/`. Run folders are under `build/glass_lab/runs/` in the proto worktree (git-ignored); `spike-interactive/…` means `build/glass_lab/spike-interactive/…` there.

## Question and answer

**Question.** Can native plain `.glassEffect(.regular.interactive())` be made to visibly react to a press on the iOS 27 simulator?

**Answer.** Yes: it reacts to XCUITest and HID touches exactly like `.buttonStyle(.glass)` as soon as the glass holds rendered content that is hit (a `Text`, a `Button` label, or just `Color.white.opacity(0.001)`); `material.interactive` never reacted because its only content is `Color.clear`, so the touch hits nothing inside the glass and UIKit's `_UIFlexInteractionPanGestureRecognizer` never joins the touch.

## Why `material.interactive` shows nothing

Every probe launch logged each touch as the app received it (`TouchProbe`, below): the hit view and `UITouch.gestureRecognizers`. Summary for every `began` touch in every case (`docs/liquid_glass/02b-motion/research/spike-interactive/touch_summary.jsonl`, raw logs in `spike-interactive/touches/`):

| Variants | Hit view | Recognizers on the touch (besides `_UISystemGestureGateGestureRecognizer`) | Reacted |
|---|---|---|---|
| v0, v1, v11, v12, v14 | `_UIHostingView` | none | no |
| v2, v2b, v9 (a SwiftUI gesture on the block) | `_UIHostingView` | `UIKitResponderGestureRecognizer` | no |
| v3, v5, v13, v15, v16–v19 (rendered content inside the effect) | `_UIHostingView` | `_UIFlexInteractionPanGestureRecognizer` | yes |
| v4, v7, v8 (SwiftUI `Button`) | nil | `UIKitResponderGestureRecognizer`, `_UIFlexInteractionPanGestureRecognizer` | yes |
| v6 (UIKit `UIGlassEffect.isInteractive`) | `_UIVisualEffectContentView` | `_UIFlexInteractionPanGestureRecognizer` | yes |
| v10 (UIKit `UIButton.Configuration.glass()`) | `UIButton` | `_UIFlexInteractionPanGestureRecognizer` | yes |

Without exception across 58 logged launches (injections A, B and C), a press reacts exactly when `_UIFlexInteractionPanGestureRecognizer` is on the touch. The touches always arrive (as gotcha 10 says). What decides it is what the touch hits inside the effect:
- a content shape alone does not do it (v12 inside the effect, v14 outside it), which is why gotcha 13's fix did not explain gotcha 10;
- a SwiftUI gesture alone does not do it (v2, v2b, v9);
- `GlassEffectContainer` does not change it (v1, v11);
- rendered content does: `Text` (v3, v5), a `Button` label (v4), and `Color.white.opacity(0.001)` (v13). The press need not land on glyphs: v3 pressed 90 pt left of centre, off the label, reacts the same (`probe.offtext.v3`).

Gotcha 10's six variants were never recorded, so whether any of them had rendered content is not known.

**v13 keeps `material.interactive`'s still image.** Its `ready.png` is byte-identical to v0's (MAD 0.00, max difference 0 over y 72–650 pt, dark-stripes runs `20261003-012138` and `20261003-005944`).

## How it was measured

**Probe scenes.** One element per scene, centred in the safe area (centre (201, 451) pt) over the lab `Backdrop`. Each variant is registered under four prefixes, one per injection: `probe.interactive.vN`, `probe.coord.vN`, `probe.hid.vN` and `probe.offtext.vN` (`ProbeScenes.swift:29-39`). 43 manifest entries in `scenes.json:2279-4302`.

**Touch probe** (`TouchProbe.swift`, only in `probe.*` scenes and not in bare launches, `GlassLabApp.swift:39-43`):
- it swizzles `UIWindow.sendEvent(_:)` (`TouchProbe.swift:22-28`), calls the original first (`:66-67`), then logs each touch to `Documents/glass_lab/touches/<scene>-<appearance>-<backdrop>-<epoch>.jsonl`: phase, `CACurrentMediaTime`, location, `majorRadius`, `force`, hit view class and gesture recognizers with their states;
- it paints an 18 pt marker at (16, 662) pt: black at rest, red on `began`, green on `moved`, blue on `ended`. The marker gives touch-down and release in video time and sits outside every pinned region.
- The positive controls react with it installed, so it does not block reactions.

**Injections.**
- **A**: the lab driver with `material.interactive`'s steps: wait 0.5; `press` 1.0 s on element `glass`; wait 1.0; `pressDrag` from `glass` to `glass` +60 pt (press 0.3 s, 120 pt/s, hold 0.5); wait 1.0. The driver already presses through `XCUICoordinate`: an element target becomes `element.coordinate(withNormalizedOffset: (0.5, 0.5))` and then `press(forDuration:)` (`GlassLabDriver/Step.swift`, `StepPlayer.coordinate` and `play`). Element and coordinate presses differ only in how the point is found.
- **A-off**: v3 with the same steps at the absolute point (111, 451), off the label glyphs.
- **B**: an absolute-coordinate `XCUICoordinate` press from the app origin at (201, 451) (v11 and v15: (136, 451)), with a **2.0 s** hold, then `pressDrag` +60 pt (press 0.5 s, 120 pt/s, hold 1.0).
- **C**: HID touches through `mcp__Claude_Code_iOS_Simulator__control`, on v0, v3, v7 and v13 in dark-stripes:
  - `tap` with `duration` 1, which the app logged as holds of 605 to 1040 ms;
  - then `touch_path`: hold 300 ms, +60 pt in 4 × 125 ms, hold 500 ms (logged as 1.35–1.38 s).
  - The app was launched with `simctl launch` and `SIMCTL_CHILD_GLASS_LAB_*` (`research/spike-interactive/hid_prep.sh`) and recorded with `simctl io … recordVideo --codec=h264`.
  - HID touches arrive with `majorRadius` 20 against XCUITest's 23.6, so they take a different injection path. They gave the same result in every case.

**Cases.** Injection A ran on dark-stripes and light-photo, which covers both appearances and both `material.interactive` backdrops. B and C ran on dark-stripes.

**Per-frame measures** (`research/spike-interactive/probe_analyze.py`):
- Every recorded frame is read at full resolution and at its real timestamp (`-fps_mode passthrough`), inside a pinned region: the rest glass box padded by 30 pt.
- The rest glass box is `ready.png` against the bare launch, 3 × 3-smoothed max-channel difference > 20, at least 6 px per row or column.
- The rest frame is the last video frame before touch-down.
- **Δw, Δh**: how far the box of pixels that changed against the rest frame (> 12, at least 3 px per row or column) reaches beyond the rest box, in pt, in 1/3 pt steps.
- **Δluma**: change in mean luma of the rest-box region.
- **MAD**: mean absolute difference of the rest-box region against the rest frame.
- **Reacted** means Δw or Δh ≥ 1 pt, Δluma ≥ 2 or MAD ≥ 2 on at least 2 consecutive frames during the press.
- **Timing**, first press only: touch-down (marker) to the first frame at ≥ 90 % of the peak, and release to the first frame after which the measure stays within 10 % of its peak.

**Limits.**
- Δw and Δh cannot see the glass shrinking below rest, so undershoot after release is unmeasured.
- An outline-spike edge measure was tried and dropped: on `stripes`, codec noise at a stripe boundary outscored the glass outline. A crop check of v3's right end put the spike on the blue/purple boundary, 2–3 pt outside the real edge.
- The rest boxes of v7 and v19 include some shadow, so their growth reads low. v19 measures 362.33 × 211 against its 360 × 200 frame; its peak change box is 365.67 × 203, so against the frame it grows about +5.7 / +3.0.
- The video is variable-rate. In v13 light-photo the first press has a recording gap at touch-down: the marker shows 690 ms held against 984 ms in the app's log, so that press's "0 ms" rise times are not valid.
- The spike's `scenes.json` breaks `test_manifest.RealManifestTests.test_lab_ids_match_the_native_registry` on `proto/2b`, because the probe ids are generated rather than written as literals. The other 103 harness tests pass.

## Results

The **injection** column uses the codes above (A, A-off, B, C). Two values `x / y` are dark-stripes / light-photo. Peaks are the largest over both presses (the 1.0 s or 2.0 s press, and the pressDrag). **Timing** is the first press, in ms: `w` is size rise to 90 % / release to within 10 %; `L` is luma rise to 90 % / release to within 10 %. Folder: `build/glass_lab/runs/<folder>`; `spike-interactive/hid` is the HID case root.

| Variant | Native code | Injection | Case | Reacted | Peak Δw (pt) | Peak Δh (pt) | Peak Δluma | Peak MAD | Timing (ms) | Run folder |
|---|---|---|---|---|---|---|---|---|---|---|
| v0 | `Color.clear.frame(width: 250, height: 88).glassEffect(.regular.interactive())` (the `material.interactive` block) | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | -0.01 / -0.01 | 0.32 / 0.47 | - / - | 20261003-005944 / 20261003-011019 |
| v0 | same | B | dark-stripes | no | 0 | 0 | 0 | 0.01 | - | 20261003-013631 |
| v0 | same | C | dark-stripes | no | 0 | +0.33 | +0.03 | 0.87 | - | spike-interactive/hid |
| v1 | `GlassEffectContainer { v0 }` | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.00 | - / - | 20261003-005944 / 20261003-011019 |
| v2 | v0 `.contentShape(.rect(cornerRadius: 44)).onTapGesture {}` (after the effect) | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.00 / 0.00 | - / - | 20261003-005944 / 20261003-011019 |
| v2 | same | B | dark-stripes | no | 0 | 0 | -0.01 | 0.33 | - | 20261003-013721 |
| v2b | `Color.clear.frame(250×88).contentShape(.rect(cornerRadius: 44)).onTapGesture {}.glassEffect(.regular.interactive())` | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.02 | - / - | 20261003-005944 / 20261003-011019 |
| v3 | `Text("Glass").font(.title).frame(width: 250, height: 88).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 44))` | A | dark-stripes / light-photo | yes / yes | +12 / +12.67 | +4.67 / +5 | +17.43 / +19.04 | 17.72 / 20.70 | w 195/150, L 43/407 / w 168/148, L 102/398 | 20261003-005944 / 20261003-011019 |
| v3 | same | A-off | dark-stripes / light-photo | yes / yes | +12 / +12.67 | +4.67 / +5 | +16.82 / +18.78 | 17.13 / 20.14 | w 128/165, L 0/415 / w 213/177, L 113/423 | 20261003-012341 / 20261003-013049 |
| v3 | same | B | dark-stripes | yes | +12 | +4.67 | +17.38 | 17.73 | w 220/150, L 55/398 | 20261003-013949 |
| v3 | same | C | dark-stripes | yes | +12 | +4.67 | +17.37 | 17.74 | w 190/165, L 53/417 | spike-interactive/hid |
| v4 | `Button {} label: { Text("Glass").frame(width: 250, height: 88) }.buttonStyle(.plain).glassEffect(.regular.interactive())` | A | dark-stripes / light-photo | yes / yes | +12 / +12.67 | +4.67 / +5.33 | +17.63 / +19.05 | 17.28 / 19.63 | w 208/167, L 32/417 / w 207/183, L 105/422 | 20261003-005944 / 20261003-011019 |
| v5 | v3 with `.regular.tint(.blue).interactive()` | A | dark-stripes / light-photo | yes / yes | +12 / +12 | +4.67 / +4.33 | +15.54 / +21.43 | 15.51 / 25.53 | w 133/162, L 5/415 / w 208/150, L 53/400 | 20261003-005944 / 20261003-011019 |
| v6 | `UIVisualEffectView(effect: UIGlassEffect(style: .regular))`, `isInteractive = true`, `cornerConfiguration = .capsule()`, `UIViewRepresentable` framed 250×88 | A | dark-stripes / light-photo | yes / yes | +12 / +12.67 | +4.67 / +5.33 | +12.99 / +15.05 | 14.13 / 15.71 | w 158/152, L 75/367 / w 145/168, L 95/270 | 20261003-005944 / 20261003-011019 |
| v6 | same | B | dark-stripes | yes | +12.33 | +4.67 | +13.01 | 14.17 | w 142/138, L 77/352 | 20261003-014120 |
| v7 | `Button {} label: { Text("Glass").frame(width: 250, height: 88) }.buttonStyle(.glass)` | A | dark-stripes / light-photo | yes / yes | +10.67 / +11.33 | +4 / +5.33 | +18.29 / +18.1 | 18.13 / 18.37 | w 143/150, L 0/400 / w 203/147, L 103/390 | 20261003-005944 / 20261003-011019 |
| v7 | same | B | dark-stripes | yes | +10.67 | +4 | +18.31 | 18.13 | w 202/135, L 50/387 | 20261003-014208 |
| v7 | same | C | dark-stripes | yes | +10.67 | +4 | +18.29 | 18.10 | w 182/147, L 35/402 | spike-interactive/hid |
| v8 | `Button {} label: { Image(systemName: "plus").frame(width: 44, height: 44) }.buttonStyle(.glass).buttonBorderShape(.circle)` | A | dark-stripes / light-photo | yes / yes | +17.67 / +17.33 | +17.33 / +17.67 | +40.59 / +43.87 | 49.30 / 47.01 | w 163/125, L 112/607 / w 158/150, L 107/613 | 20261003-005944 / 20261003-011019 |
| v8 | same | B | dark-stripes | yes | +17.67 | +17.33 | +40.59 | 49.29 | w 158/138, L 112/598 | 20261003-014253 |
| v9 | v0 `.contentShape(.rect(cornerRadius: 44)).simultaneousGesture(DragGesture(minimumDistance: 0)…)` | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.02 | - / - | 20261003-005944 / 20261003-011019 |
| v10 | `UIButton(configuration: .glass())` titled "Glass", `UIViewRepresentable` framed 250×88 | A | dark-stripes / light-photo | yes / yes | +12.33 / +12.67 | +4.67 / +5.33 | +12.91 / +15.41 | 14.47 / 16.44 | w 142/150, L 53/350 / w 140/148, L 87/275 | 20261003-005944 / 20261003-011019 |
| v11 | `GlassEffectContainer(spacing: 20) { HStack(spacing: 10) { 2 × Color.clear.frame(width: 120, height: 88).glassEffect(.regular.interactive()) } }`, left one pressed | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.00 | - / - | 20261003-005944 / 20261003-011019 |
| v12 | `Color.clear.frame(250×88).contentShape(.rect(cornerRadius: 44)).glassEffect(.regular.interactive())` | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.00 | - / - | 20261003-012046 / 20261003-012825 |
| v12 | same | B | dark-stripes | no | 0 | 0 | 0 | 0.02 | - | 20261003-013810 |
| v13 | `Color.white.opacity(0.001).frame(width: 250, height: 88).glassEffect(.regular.interactive())` | A | dark-stripes / light-photo | yes / yes | +12 / +12.67 | +4.67 / +5.33 | +17.74 / +19.04 | 16.99 / 19.06 | w 210/148, L 35/403 / w 0/153, L 0/408 (light: video gap, see Limits) | 20261003-012138 / 20261003-012914 |
| v13 | same | B | dark-stripes | yes | +12 | +4.67 | +17.73 | 17.06 | w 203/123, L 27/387 | 20261003-014034 |
| v13 | same | C | dark-stripes | yes | +12 | +4.67 | +17.77 | 17.04 | w 188/157, L 55/413 | spike-interactive/hid |
| v14 | v0 `.contentShape(.rect(cornerRadius: 44))` (after the effect, no gesture) | A | dark-stripes / light-photo | no / no | 0 / 0 | 0 / 0 | 0 / 0 | 0.01 / 0.00 | - / - | 20261003-012250 / 20261003-013003 |
| v14 | same | B | dark-stripes | no | 0 | 0 | 0 | 0.01 | - | 20261003-013901 |
| v15 | `GlassEffectContainer(spacing: 20) { HStack(spacing: 10) { Text("A"), Text("B") each .font(.title).frame(width: 120, height: 88).glassEffect(.regular.interactive()) } }`, A pressed | A | dark-stripes / light-photo | yes / yes | +6 / +6.33 (union box) | +9 / +9.67 | +8.36 / +12.61 | 10.02 / 13.77 | w 160/128, L 32/538 / w 75/152, L 25/537 | 20261003-012738 / 20261003-013528 |
| v16 | `Text("+").font(.title).frame(width: 58, height: 58).glassEffect(.regular.interactive(), in: .circle)` | A | dark-stripes / light-photo | yes / yes | +17.67 / +17.33 | +17.33 / +17.33 | +40.53 / +43.83 | 49.35 / 47.63 | w 158/138, L 110/615 / w 160/153, L 108/747 | 20261003-012427 / 20261003-013133 |
| v17 | `Text("Glass").font(.title).frame(width: 138, height: 53).glassEffect(.regular.interactive(), in: .capsule)` | A | dark-stripes / light-photo | yes / yes | +16.67 / +16.67 | +6.33 / +6.67 | +17.75 / +23.07 | 22.93 / 34.17 | w 153/170, L 68/538 / w 135/142, L 100/527 | 20261003-012517 / 20261003-013222 |
| v18 | `Text("Glass").font(.title).frame(width: 250, height: 44).glassEffect(.regular.interactive(), in: .capsule)` | A | dark-stripes / light-photo | yes / yes | +17.67 / +17.67 | +3.33 / +3.67 | +14.62 / +17.9 | 17.42 / 22.33 | w 157/163, L 32/433 / w 153/165, L 105/433 | 20261003-012604 / 20261003-013310 |
| v19 | `Text("Glass").font(.title).frame(width: 360, height: 200).glassEffect(.regular.interactive(), in: .rect(cornerRadius: 32))` | A | dark-stripes / light-photo | yes / yes | +3.67 / +4.33 (≈ +5.7 against the frame) | +1 / +4 | +4.92 / +3.98 | 6.11 / 4.70 | w 193/130, L 77/365 / w 167/155, L 117/315 | 20261003-012651 / 20261003-013358 |

Positive control: v7 reacted under every injection (A, B, C), so injection and measurement work. Every case of v0, v1, v2, v2b, v9, v11, v12 and v14 stays at MAD ≤ 0.87, which is H.264 noise. Their videos hold no frames during the press other than the 2–4 the marker itself causes.

Rest and peak crops at full resolution, one pair per reactor, dark-stripes first press: `spike-interactive/crops/<scene>-dark-stripes-{rest,peak}.png`. Per-frame series: `spike-interactive/series/`.

## Outset or scale? (v7, v8 and the size series)

| Variant | What | Rest glass box (pt) | Δw | Δh | Δw/w | Δh/h |
|---|---|---|---|---|---|---|
| v8 | `.buttonStyle(.glass)` circle, 44 pt label | 59.33 × 58.67 | +17.67 | +17.33 | 1.298 | 1.295 |
| v16 | interactive `.glassEffect` circle, 58 pt frame | 59.33 × 58.67 | +17.67 | +17.33 | 1.298 | 1.295 |
| v17 | capsule 138 × 53 | 139.33 × 53.67 | +16.67 | +6.33 | 1.120 | 1.118 |
| v18 | capsule 250 × 44 | 251.33 × 44.67 | +17.67 | +3.33 | 1.070 | 1.075 |
| v3 | capsule 250 × 88 | 252 × 88.67 | +12.00 | +4.67 | 1.048 | 1.053 |
| v7 | `.buttonStyle(.glass)`, 250 × 88 label | 276 × 102.67 | +10.67 | +4.00 | 1.039 | 1.039 |
| v19 | rect r32 360 × 200 | 360 × 200 frame (box with shadow 362.33 × 211) | ≈ +5.7 | ≈ +3.0 | ≈ 1.016 | ≈ 1.015 |

(dark-stripes, injection A; light-photo agrees within 0.67 pt except v7's height, +5.33 against +4.00, and v19.)

- **v7 against v8: neither a fixed outset nor one scale factor.**
  - v7 grows +10.67 pt (× 1.039) and v8 grows +17.67 pt (× 1.30).
  - Each element scales uniformly: Δw/w and Δh/h agree within 0.5 %.
  - The factor falls with size.
- **`.buttonStyle(.glass)` and interactive `.glassEffect` press identically at the same size.** v8 and v16 give identical numbers. v3, v4, v13, the UIKit effect v6 and the UIKit button v10 all give +12.0 to +12.33 / +4.67 at 250 × 88.
- **Short glass looks like a fixed outset.** Glass up to about 60 pt tall grows about 17 pt in width whatever its width (59, 139 and 251 pt). That is why `button.press`'s 138 and 174 pt buttons, both 53 pt tall, both read +16–17 pt and looked like a fixed outset (`context.md` §1).
- **Taller glass grows less, roughly as 1/height.** Inference from six sizes, not verified beyond them: Δw ≈ min(17.5, 1100 / h) pt, scaled uniformly.
  - It predicts 12.4 pt at h 88.67 (measured 12.0), 10.7 at 102.67 (10.67) and 5.5 at 200 (≈ 5.7).
  - Equivalently, past the cap the scale is 1 + 1100 / (w·h), which adds a roughly constant ≈ 2200 pt² of area.

## Other observations for 2B

- **Glow first, growth second.**
  - Luma reaches 90 % of its peak 0–120 ms after touch-down, often in the first recorded frame.
  - Size reaches 90 % 128–220 ms after touch-down (75 ms for v15's union box in light-photo).
- **Release.**
  - Size is back within 10 % after 123–183 ms.
  - Luma takes 270–615 ms (747 ms for v16 light-photo).
  - In SwiftUI glass the brightness decays from about +17 to +11.5 over about 400 ms, then drops to rest in one frame: 406 ms after release for v3 dark, 399 ms for v3 light and 400 ms for v7. v8 drops from +9.6 at 606 ms.
  - UIKit v6 decays smoothly, with no drop.
- **The pressDrag (+60 pt at 120 pt/s) does not move or stretch the glass.** The change box stays centred, and the glow dims during the drag (v3: luma +17.1 down to +14.6).
- **A 2.0 s hold changes nothing** (injection B): reactors reach the same peaks and non-reactors stay flat.
- **Tint (v5)** reacts the same: Δluma +15.5 (dark-stripes) and +21.4 (light-photo).
- **v15, two interactive shapes in one container.** The shapes are `Text` 120 × 88 with a 10 pt gap in `GlassEffectContainer(spacing: 20)`, and A is pressed.
  - A scales: the union box grows +9.0 / +9.67 in height, which matches the 1100 / h rule (9.2 predicted).
  - Neighbour B does not change: its MAD is 0.18–0.82, against A's 19.3–25.1 (`research/spike-interactive/v15_split.py`). There is no glow spread to the neighbour in this setup.

## SDK names for v6 (iPhoneSimulator27.0.sdk)

UIKit headers under `System/Library/Frameworks/UIKit.framework/Headers`:
- `UIGlassEffect.h`:
  - `@interface UIGlassEffect : UIVisualEffect`;
  - `+effectWithStyle:`, Swift `UIGlassEffect(style:)`;
  - `UIGlassEffectStyleRegular` and `UIGlassEffectStyleClear`, Swift `UIGlassEffect.Style.regular` and `.clear`;
  - `@property (getter=isInteractive) BOOL interactive`, Swift `isInteractive`;
  - `tintColor`.
- `UIGlassEffect.h`: `UIGlassContainerEffect` with `spacing`.
- `UIView.h:762`: `cornerConfiguration` (`NS_REFINED_FOR_SWIFT`).
- `UICornerConfiguration.h:32`: `+capsuleConfiguration`, Swift `.capsule()`. v6 uses `view.cornerConfiguration = .capsule()`.
- `UIButtonConfiguration.h:93-96`: `glassButtonConfiguration`, `prominentGlassButtonConfiguration`, `clearGlassButtonConfiguration` and `prominentClearGlassButtonConfiguration`, Swift `UIButton.Configuration.glass()` and so on (v10).

SwiftUI: `Glass.interactive(_ isEnabled: Bool = true)` (`SwiftUICore.swiftinterface:7256`). There is no other public interaction API.

## Recommendation

**Use v13 as the native reference for `Glass.interactive()`:** `Color.white.opacity(0.001).frame(width: 250, height: 88).glassEffect(.regular.interactive())`. No fallback to `button.press` is needed.

- It is plain `.glassEffect(.regular.interactive())`, with no label, button or gesture.
- Its still image is byte-identical to today's `material.interactive`.
- It reacted under A, B and C.
- What it shows:
  - uniform growth of +12.0 / +4.67 pt (× 1.048) dark and +12.67 / +5.33 light;
  - Δluma +17.7 dark and +19.0 light, MAD 17.0 and 19.1;
  - glow rise to 90 % in 27–55 ms (dark) and growth to 90 % in 188–210 ms;
  - on release, size settles in 123–157 ms and glow in 387–413 ms, with the one-frame drop about 400 ms after release.

To adopt it:
1. Give `InteractiveScene` (`tool/glass_lab/native/GlassLab/MaterialScenes.swift:65-74`) v13's content in place of `GlassBlock`'s `Color.clear`. Its still reference stays the same, and the scene gets a measurable press.
2. Measure the press per element in a pinned region, as here, not by the harness's largest blob.
3. Add v16–v19's sizes, or at least 58, 250 × 44 and 360 × 200, so 2B pins the size law: about 17 pt for short glass, falling as 1/h for tall glass.

`button.press` stays a component reference for project 3. ROADMAP gotchas 10 and 13 and `context.md` §1's "fixed outset" inference should be corrected from this report.

## Where the probe code lives (`proto/2b`, commit 5999b4412)

- `packages/mobile/tool/glass_lab/native/GlassLab/ProbeScenes.swift`:
  - registry `:4-40` (variant map `:5-27`, prefixes `:29`);
  - `ProbeStage` `:42`;
  - v0 `:53`, v1 `:63`, v2 `:75`, v2b `:87`, v3 `:101`, v4 `:113`, v5 `:126`;
  - v6 `:138` (`UIKitInteractiveGlass` `:148`);
  - v7 `:162`, v8 `:174`, v9 `:187`;
  - v10 `:199` (`UIKitGlassButton` `:209`);
  - v11 `:221`, v12 `:240`, v13 `:253`, v14 `:265`, v15 `:276`;
  - v16–v19 `ProbeSized` `:302-323`, sizes at `:23-26`.
- `packages/mobile/tool/glass_lab/native/GlassLab/TouchProbe.swift`:
  - logger `:10-63`;
  - `sendEvent` swizzle `:22-28` and `:65-70`;
  - marker `:72-99`.
- `packages/mobile/tool/glass_lab/native/GlassLab/GlassLabApp.swift:39-43`: the marker overlay for `probe.*` scenes.
- `packages/mobile/tool/glass_lab/native/GlassLab/SceneRegistry.swift:8`: the registry merge.
- `packages/mobile/tool/glass_lab/scenes.json:2279-4302`: 43 probe scenes.
- `docs/liquid_glass/02b-motion/research/spike-interactive/`:
  - `probe_analyze.py` (per-case measures);
  - `probe_batch.py`;
  - `make_table.py` (this report's table);
  - `touch_summary.py` and `touch_summary.jsonl`;
  - `v15_split.py`;
  - `hid_prep.sh`.
