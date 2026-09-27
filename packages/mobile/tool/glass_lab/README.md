# Glass lab

This lab measures Operator's Flutter glass against native iOS 27 Liquid Glass.

It has three parts:
- a native SwiftUI catalog (`native/GlassLab`);
- an XCUITest driver that plays identical touches on any app (`native/GlassLabDriver`);
- a Python harness that records both apps and compares them (`harness/`).

The spec is `docs/liquid_glass/01-reference-lab/spec.md`.

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
python3 tool/glass_lab/harness/lab.py run menu.bar
python3 tool/glass_lab/harness/lab.py report
```

- **`build [native|flutter|both]`** regenerates the Xcode project, builds GlassLab and the driver, builds Operator in debug, and installs both apps.
- **`prepare`** sets the status bar to 9:41, generates the backgrounds, copies them into both apps, and takes Apple's apps past their first-run screens. On a fresh simulator, check each Apple app once by screenshot afterwards; first-run screens change between iOS builds.
- **`run <scene|group|prefix|all> [--app native|flutter|both] [--appearance light|dark|both] [--backdrop <id>] [--a11y <mode>]`** records scenes into `build/glass_lab/runs/<timestamp>/`.
- **`report [<run dir>]`** analyses a run and writes `report.html` beside it. With no argument it uses the latest run.
- **`summary <out.md> [<run dir>]`** writes a Markdown summary of a run.
- **`repeat [<scene>] [--times 3]`** records native takes and compares them to each other, then updates `noise.json`. With no scene it covers `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`. Rerun it after an Xcode or simulator update.
- **`geometry <scene>`** prints the native glass boxes of a scene in points, for positioning Flutter scenes.
- **`baseline`** runs `prepare`, then every scene in both apps and both appearances plus the accessibility runs, then `report`. It takes about four hours.

## How a scene runs

`scenes.json` lists every scene. Each entry has an id, a group, backgrounds, appearances and a list of steps. The step types are:
- `wait`, `tap`, `doubleTap`;
- `press {at, duration}`;
- `pressDrag {from, to, pressDuration, velocity, hold}`.

A target is either a point `[x, y]` in points, an accessibility identifier or label, or `{"element": id, "dx": ..., "dy": ...}`.

For each case, the harness:
1. Launches the scene once in bare mode, background only, for a reference screenshot.
2. Starts `simctl io recordVideo` and runs the driver. The driver launches the app, waits for `scene.ready`, settles for 1.5 s and saves `ready.png`, then plays the steps, settles again and saves `settled.png`.

The native app reads its scene from the `GLASS_LAB_SCENE`, `GLASS_LAB_BACKDROP` and `GLASS_LAB_BARE` launch variables. Flutter cannot see launch variables on iOS, so the harness writes `Documents/glass_lab/launch.json` into Operator's container before each launch, and Operator's debug build reads and deletes it on start. Backgrounds live in each app's `Documents/glass_lab/`.

If Operator has not built a scene yet, it shows a `missing: <id>` placeholder, the driver skips the steps, and the report counts the scene as missing.

## Reading the report

Still-image measures compare the lossless screenshots:
- colour difference in the region;
- brightness difference;
- the edge profile;
- the glass bounding box.

Motion measures compare the recordings:
- They use the recorder's real frame times, which run at up to 120 Hz.
- Each burst of change is one event.
- Events are lined up by best fit.
- Each event is checked for peak time, settle time, overshoot and a fitted spring (response and damping).

Motion limits are max(fixed threshold, 1.5 × `noise.json`), because touch timing on the simulator varies a little between runs. The report also lists any Flutter frame gaps over 25 ms, so a debug-build stall is not mistaken for a wrong spring.
