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
