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
- **`repeat [<scene>] [--times 3] [--appearance A] [--backdrop B] [--a11y MODE] [--into RUN]`** records native takes of every case of a scene and compares every pair of takes of a case (`pair-<i>-<j>`, each take captured once), then writes that case's noise into `noise.json` as `{scene: {case: {measure: noise}}}`: the motion measures, and the static and still-topology measures (`ready.mad`, `ready.topology.<region>.neck_pt`, …), so still scenes get noise floors too. A non-finite value never becomes a noise. `--into` appends takes to an earlier run (give it an absolute path: the driver resolves a relative one against `/`), so a case's noise covers takes from two sessions (record three, `reboot`, record two more `--into` the same run). With no scene it covers `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`. Rerun it after an Xcode or simulator update.
- **`reboot`** shuts the iOS 27 simulator down, boots it again and resets the status bar.
- **`measure <case dir> --scene <id>`** prints, for each app in a case folder, the touches read from the marker, each tracked shape's rest box (the last frame before the first touch), its largest and smallest box and whether an edge of either sat inside the tracker's blind band at a backdrop edge (`edge_in_band`), and each event's onset, owning step and progress features.
- **`fitvis <run> [<run> ...] [--levels 11] [--ramps 1.0,2.0,3.0,4.0] [--out DIR] [--write]`** fits the materialize motion table from native recordings (a run's `<scene>/<case>/native` and a `repeat` run's takes). The springs stay SwiftUI's; it fits, per preset and over every backdrop and take, the disappear exponent and the appear overshoot gain, with their spread over the takes, and from the Reduce Motion cases a second appear gain (the other accessibility cases are left out), and checks that native's default fits SwiftUI's 0.55 s / 1.0 in every case (`default_spring_check`, pass or fail). It photographs the example's `tool.visibility` scene at fixed visibilities under several blur ramps, keeps the ramp whose sharpness at quarter, half and three-quarter progress best matches native's at the same progress, then inverts Flutter's progress under that ramp into `ios27VisibilityForProgress`. It writes `build/glass_lab/fitvis/<time>/fit.json` (every fit with `at_grid_edge`); `--write` rewrites `packages/ios_liquid_glass/lib/src/motion/ios27_motion.dart`; never edit that table by hand. It refuses a stale example build and reuses scan shots already in `--out`.
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
- `track`: a region name, or a list of them, that pins where the scene is compared. In a scene with steps, each tracked region is a shape measured on its own (below);
- `measures`: the still-image measures that count, from `mad`, `luminance`, `rim_rms`, `bbox_pt` and `centre_pt`; all of them by default;
- `topology`: region names whose glass is counted and necked (spec L2): the number of separate glass components and, when they are one, the narrowest neck between its two lobes. In a still scene each topology region is compared on `ready.png` (`ready.topology.<region>.count`, limit 0, and `.neck_pt`, limit 1 pt); in a scene with steps, on join and split times and the neck over time (`topology.*` motion measures);
- `motion`: the motion measures that count for each tracked shape, from `delay_ms`, `topology.count`, `topology.join_ms`, `topology.split_ms`, `topology.neck_rms`, `<key>.<measure>` (`width`, `height`, `cx`, `cy` or `luma`, with `peak_ms`, `settle_ms`, `overshoot_pct`, `response_pct` or `damping`) and `progress.t10_90_ms`, `.settle_ms`, `.overshoot_pct`, `.response_pct`, `.damping`, `.rms` and `.sharpness`. With none, a tracked scene is checked only for its events.

For example, the edge scenes pin the top 240 pt and count only `mad` and `luminance`.

For each case, the harness:
1. Launches the scene once in bare mode, background only, for a reference screenshot.
2. Starts `simctl io recordVideo` and runs the driver. The driver launches the app, waits for `scene.ready`, settles for 1.5 s and saves `ready.png`, then plays the steps, settles again and saves `settled.png`.

The native app reads its scene from the `GLASS_LAB_SCENE`, `GLASS_LAB_BACKDROP` and `GLASS_LAB_BARE` launch variables. Flutter cannot see launch variables on iOS. Instead:
- the harness writes `Documents/glass_lab/launch.json` into the Flutter app's container before each launch, as `{scene, backdrop, bare, material, materialSide}`;
- the debug build reads it and deletes it on start;
- `material` is an optional map of material overrides by field name. Scroll edge fields are prefixed `edge.`;
- `materialSide` limits the overrides to glass at that size anchor (44, 88 or 200 pt, after clamping the glass's shorter side), so a 200 pt candidate does not repaint the 44 and 88 pt glass in the same scene.

`build native` stamps the native sources (`build/glass_lab/native/sources.sha256`, from `native/GlassLab` and `native/GlassLabDriver`), and `run`, `repeat` and `reproduce.py` refuse a native build older than its sources, as `run` refuses a stale Flutter build.

Before each capture the harness closes every other lab app, so the captured app is launched from the home screen and no "◀ app" back link appears in its status bar.

Scenes with touch steps show a touch marker in both apps, in the bare launch as well: an 18 pt square at (16, 662) pt, black at rest, red while a finger is down, green while it moves, blue on release and black again 250 ms later. The native app takes `GLASS_LAB_MARKER=1`; the example takes `"marker": true` in `launch.json`. The harness reads touch-down and touch-up from the marker's colour in the video, so touch times share the video's clock.

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

Nothing after the last frame that matches `settled.png` is analysed, so the app's teardown frame is never an event.

Scenes with a `track` and steps are measured per shape:
- each tracked region is cropped at full resolution from every video frame; the shape's box is found against the bare screenshot, with the threshold raised at the backdrop's own edges, where H.264 rings in every frame; a box edge within the 5 px of a strong backdrop edge is flagged, because the raised threshold can hide up to two pixels of rim there;
- each frame is also projected onto the line from the bare screenshot to `ready.png` at point resolution: `progress` is the alpha of the closest alpha mix, `residual` how far the frame is from that mix, and `sharpness` its Laplacian minus the mix's, inside the rest box; a materialize that blurs reads a residual over the H.264 floor and a negative sharpness;
- events belong to the step whose touch began last before them and pair with the other app's events of that step (`step<k>e<i>`); without a marker they pair by order (`event<i>`);
- each pair is compared on the scene's `motion` measures; progress is compared on its 10–90% time, settle time, overshoot, a fitted spring, the RMS of the normalised curves after lag alignment, and the sharpness at half progress; `delay_ms` compares touch-to-response delays;
- nothing passes by being absent: every measure the scene lists is judged for every pair and shape, an absent one as `inf`; an event left out of every pair fails `events.unpaired`, and a scene with touch steps fails `touches.native` or `touches.flutter` unless each video shows the expected touches; a spring fit on its grid edge or with RMS 0.15 or worse is reported as `fit_invalid` and fails;
- `result.json` keeps both apps' frame gaps over 25 ms inside events (`native_stalls`, `flutter_stalls`) and, per pair and shape, each app's first changed frame (`first_frame`: its gap from the rest frame and its share of the travel), so a first-frame stall, which the gap list skips, shows too.

Scripts beside `lab.py`: `reproduce.py materialize|press|menu` measures the 2A, spike and project 1 recordings the 2B.1 plan reproduces; `still_check.py <2A run> <new run>` compares still measures case by case and lists missing cases; `done_table.py <run>…` prints the materialize Done numbers; `rim_check.py <fitvis scan> <native run>` measures the edge light's depth below full visibility; `ghost_probe.py [tool.ghost|tool.ghost.standalone]` records a removal; `cold_probe.py <native case>` records the first transition of a launch without the warm-up.
