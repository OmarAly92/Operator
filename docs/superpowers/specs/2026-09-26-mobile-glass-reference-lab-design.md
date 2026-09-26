# Mobile glass reference lab — design

Date: 2026-09-26
Branch: `feat/mobile-glass-lab`, worktree `../Operator-glass-lab`
Project 1 of 4 in the "complete native Liquid Glass" roadmap.

## Why

The user wants the mobile glass to be complete and indistinguishable from native iOS 27 Liquid Glass: every component, animation and behaviour, first as a package, then applied across Operator. Apple publishes almost no numbers for Liquid Glass: no blur radii, durations, springs or sizes ([research/apple-inventory.md](research/2026-09-26-liquid-glass/apple-inventory.md) §9). The only reliable way to match it is to measure native output.

The tab bar proved this method (commit 947f03e8e), but it was done by hand, one component at a time, on iOS 26.5. The target is now **iOS 27**, which changed the material:
- a darker edge;
- brighter specular highlights;
- more diffusion;
- a new automatic scroll edge.

This was checked side by side on 2026-09-26.

This project builds the instrument that every later project is measured with:
- a native iOS 27 catalog of every iPhone Liquid Glass component;
- a touch driver that plays identical gestures on the native catalog, on Operator's Flutter glass lab, and on Apple's own apps;
- a measuring harness that compares the recordings numerically and writes a report.

The roadmap:
1. **Reference lab (this spec).**
2. **Glass engine.** The material itself, retuned to iOS 27.
3. **Component package.** The glass is extracted into its own workspace package and every component is built.
4. **Operator rollout.** Applied per component batch.

Projects 2–4 each get their own spec. This project fixes no glass. It ends with a baseline report that becomes their backlog.

## Research inputs

These are committed beside this spec under `research/2026-09-26-liquid-glass/`:
- `apple-inventory.md` — the 80-item Apple component and behaviour inventory, iOS 27 deltas, numbers ledger, and "behaviours most implementations miss". It is the checklist of what "complete" means.
- `flutter-repos.md`, `non-flutter.md` — techniques for projects 2–3. They are not used here.
- `operator-audit.md` — every Operator screen and the component each one uses. It is used by project 4.

## Decisions (settled with the user)

- **Target look:** iOS 27, on the iPhone 17 Pro simulator "iPhone 17 Pro (iOS 27)", UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`. The harness finds it by name and runtime, never by a hard-coded UDID.
- **Platform:** iPhone only. iPad, Mac, app icons, widgets and system-owned UI (keyboard, share sheet) are out of scope.
- **Touch approach A:** gestures are played by an XCUITest runner, identical across apps. Agent-driven taps and in-app injected touches are not used.

## Layout

`packages/mobile/tool/glass_lab/` replaces `packages/mobile/tool/glass_reference/`, which is deleted once the new lab covers its two scenes.

```
tool/glass_lab/
  README.md                 how to build, run one scene, run the baseline, read the report
  scenes.json               the scene manifest, single source of truth for ids, backdrops, gestures, regions
  backdrops/
    generate.py             deterministic backdrop generator (PIL + numpy, fixed seed)
    *.png                   generated, committed, 1206 x 2622 (3x of 402 x 874 pt); scroll.png is taller
  native/
    GlassLab.xcodeproj      checked in; app target GlassLab + UI test target GlassLabDriver
    GlassLab/               SwiftUI app: scene registry, backdrop view, one file per scene group
    GlassLabDriver/         XCUITest: reads scenes.json from its bundle, plays a scene's steps on a target app
  harness/
    lab.py                  CLI entry point (see Harness)
    record.py align.py metrics.py springfit.py report.py
    tests/                  unittest suites on synthetic frames
```

Build output goes to `packages/mobile/build/glass_lab/`, which is ignored with the rest of `/build/`. Add `tool/glass_lab/native/build/` to `.gitignore` if the Xcode build writes there, and remove the old `tool/glass_reference/build/` entry.

## Native catalog app (GlassLab)

- SwiftUI, deployment target iOS 27.0, built with Xcode 27 against the iOS 27 simulator SDK, bundle id `dev.operator.glasslab`. UIKit is used only where a behaviour has no SwiftUI API.
- **Scene selection.** At launch the app reads the `GLASS_LAB_SCENE` environment variable (a scene id) and shows exactly that scene full screen. With no id it shows a scrollable index of all scenes, so a person can browse the catalog.
- **Bare mode.** When `GLASS_LAB_BARE=1`, the scene renders only its backdrop, with no chrome and no controls. The harness uses this frame to find glass geometry by difference.
- **Ready marker.** A scene exposes an element with accessibility identifier `scene.ready` once it has laid out, plus identifiers for any control a step targets by name.
- **Palette.** The Operator palette constants already in `GlassReference.swift` (dark and light), so tints and accents match what Operator uses.
- **Backdrops.** Every scene draws one of the backdrop PNGs (bundled into the app) edge to edge under the status bar. Both apps therefore show byte-identical content behind the glass.
- **Scrolling scenes.** These put `scroll.png` in a ScrollView under the chrome.

### Backdrops

`generate.py` writes these deterministically, with a fixed seed; running it twice gives identical files:

| id | content | used to observe |
|---|---|---|
| `stripes` | the six vertical colour stripes of the current reference, with a dark or light body band matching the palette | edge lensing, dispersion, tint pickup |
| `photo` | procedural colourful image: soft gradients, blobs and fine noise; no third-party imagery | clear glass, dimming, adaptive shadow, vibrancy |
| `white` | flat white | shadow over light, flip to dark glyphs |
| `black` | flat black | dimming edge effect, flip to light |
| `text` | dense paragraphs rendered with the repo's Anthropic Sans at body size, black on white | adaptive shadow over text, legibility |
| `scroll` | one tall image: text, then photo, then a white band, then a black band | scroll under bars, light/dark flipping while content moves |

Each scene's manifest entry names its backdrops. The harness runs every listed backdrop.

### Scene catalog

Every row is at least one scene id. `§` refers to `apple-inventory.md`. Steps are the gesture script in `scenes.json`; "rest" scenes have no steps and are compared on the settled frame. Coordinates are in points on the 402 × 874 screen.

**Material**

| id | native API | backdrops | steps |
|---|---|---|---|
| `material.regular` | `glassEffect(.regular)` capsule at 150×44, 250×88 and 360×200 (size-dependent thickness, §2.10) | stripes, photo, white, black, text | rest |
| `material.clear` | `Glass.clear` capsules with and without the 35% dim layer (§2.2) | photo, white | rest |
| `material.tinted` | `Glass.tint(accent)` plus a `.glassProminent` button (§2.4) | stripes, white, black | rest |
| `material.interactive` | `Glass.regular.interactive()` capsule (§2.5) | stripes, photo | press-hold 1.0 s at centre; press, drag 60 pt right, hold 0.5 s, release |
| `material.flip` | small capsule (150×44) and large panel (360×200) over `scroll` (§2.9) | scroll | drag the content up so the white band, then the black band, pass under both |
| `material.materialize` | toggle adds and removes a glass capsule with `.materialize` (§2.13) | stripes, photo | tap the toggle, wait 1.2 s, tap again |
| `material.merge` | two 80×80 circles in `GlassEffectContainer(spacing: 40)` animated together and apart (§2.14) | stripes | tap "merge", wait 1.5 s, tap "split" |
| `material.union` | `glassEffectUnion` over four items in two unions (§2.15) | stripes | rest |
| `material.morph` | `glassEffectID` button expanding into a badge stack, Landmarks-style (§2.16) | stripes, photo | tap the button, wait 1.5 s, tap again |
| `material.shapes` | capsule, fixed radius and `ConcentricRectangle` inside a `containerShape` (§2.17) | stripes | rest |
| `material.edge.soft` / `.hard` / `.automatic` | a scroll view under an inline nav bar with each `scrollEdgeEffectStyle` (§2.19) | scroll | drag the content up 300 pt, hold 1 s |
| `material.content` | `.ultraThinMaterial` to `.thickMaterial` cards, the content layer (§2.22) | photo | rest |

**Navigation**

| id | native API | backdrops | steps |
|---|---|---|---|
| `tabbar.rest` | `TabView`, three tabs plus `Tab(role: .search)` (§3.1, §3.5) | stripes, photo, white, black | rest |
| `tabbar.press` | same | stripes | press-hold 1.0 s on tab 2 |
| `tabbar.drag` | same | stripes | press on tab 1, drag to tab 3 over 0.6 s, hold 0.4 s, release |
| `tabbar.minimize` | `tabBarMinimizeBehavior(.onScrollDown)` (§3.3) | scroll | drag content up 400 pt, wait 1 s, drag down 400 pt |
| `tabbar.accessory` | `tabViewBottomAccessory`, expanded then inline on scroll (§3.4) | scroll | drag content up 400 pt, wait 1 s, drag down |
| `tabbar.search` | search tab morphing into a field, keyboard up (§3.5) | photo | tap the search tab, wait 1.5 s, tap the close button |
| `tabbar.prominent` | iOS 27 `Tab(role: .prominent)` (§3.6) | stripes | rest; tap the prominent tab |
| `tabbar.badge` | `.badge(3)` on a tab (§3.7) | stripes | rest |
| `navbar.inline` | inline title, back button, trailing button group (§3.10–3.13) | stripes, white, black | rest |
| `navbar.large` | large title scrolling under the bar, with subtitle (§3.12) | scroll | drag content up 300 pt, hold 1 s |
| `navbar.groups` | `ToolbarItemGroup`, `ToolbarSpacer`, a prominent trailing action, a text item (§3.13–3.14) | stripes | rest; press-hold 0.8 s on a grouped item |
| `navbar.minimize` | iOS 27 `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` (§3.18) | scroll | drag content up 400 pt, wait 1 s, drag down |
| `navbar.push` | push and pop with toolbar items morphing across routes (§3.16) | stripes | tap a row, wait 1.2 s, tap back |
| `navbar.badge` | badge on a bar button (§3.17) | stripes | rest |
| `toolbar.bottom` | `.bottomBar` toolbar with groups (§3.15) | stripes, photo | rest |
| `search.bottom` | `.searchable` bottom field, field above keyboard (§3.20) | photo | tap the field, wait 1.5 s, tap cancel |
| `search.minimized` | `searchToolbarBehavior(.minimize)` (§3.20) | photo | tap the search button, wait 1.5 s, tap cancel |
| `search.scopes` | search scopes and tokens (§3.21) | white | tap the field, wait 1 s |

**Presentations**

| id | native API | backdrops | steps |
|---|---|---|---|
| `sheet.detents` | `presentationDetents([.height(120), .medium, .large])` with grabber (§4.1–4.2) | stripes, photo | drag the grabber to large, wait 1 s, drag to the small detent, wait 1 s |
| `sheet.scroll` | large sheet with scrolling content | stripes | drag the sheet content up 300 pt |
| `sheet.zoom` | sheet zooming out of a toolbar button, `matchedTransitionSource` plus `.zoom` (§4.3) | stripes | tap the button, wait 1.5 s, swipe the sheet down |
| `sheet.crossfade` | iOS 27 `NavigationTransition.crossFade` (§4.4) | stripes | tap to present, wait 1.2 s, tap to dismiss |
| `popover.bar` | popover from a bar button (§4.5) | stripes | tap the button, wait 1.2 s, tap outside |
| `menu.bar` | `Menu` from a "…" toolbar button (§4.6) | stripes, photo | tap "…", wait 1.2 s, tap outside |
| `menu.submenu` | menu with a submenu | stripes | tap "…", tap the submenu row, wait 1 s, tap outside |
| `menu.pressdrag` | press on the menu button, drag onto the third item, release (§4.6) | stripes | press 0.4 s on "…", drag to item 3 over 0.4 s, release |
| `contextmenu.card` | `.contextMenu` on a card, with preview and dimming (§4.7) | stripes | press-hold 1.0 s on the card, wait 1 s, tap outside |
| `alert.two` / `alert.three` | `.alert` with two and three actions (§4.9) | stripes, white | tap to present, wait 1 s, tap the cancel action |
| `confirm.source` | `.confirmationDialog` anchored to its button (§4.10) | stripes | tap the button, wait 1 s, tap outside |
| `push.zoom` | `navigationTransition(.zoom)` from a card (§4.11) | stripes | tap the card, wait 1.2 s, swipe back from the left edge |

**Controls**

| id | native API | backdrops | steps |
|---|---|---|---|
| `button.styles` | `.glass`, `.glassProminent`, `.glass(.clear)`, prominent clear, at small/regular/large/extraLarge, capsule and circle (§5.1–5.4) | stripes, white, black | rest |
| `button.press` | `.glass` and `.glassProminent` buttons (§2.5) | stripes | press-hold 0.8 s on each in turn |
| `toggle` | `Toggle` on and off (§5.5) | white, black, stripes | tap the off toggle; press on the knob, drag 30 pt, hold 0.5 s, release |
| `slider` | `Slider` default, with ticks, neutral value, and thumbless (§5.6) | white, stripes | press the thumb, drag 150 pt fast, release; press, drag slowly 80 pt, hold 0.5 s, release |
| `segmented` | `Picker(.segmented)` with 3 segments (§5.7) | white, stripes | tap segment 3; press segment 1, drag to segment 2, hold 0.4 s, release |
| `stepper` | `Stepper` (§5.8) | white | tap +, tap +, tap − |
| `picker.menu` | menu-style `Picker` (§5.9) | white | tap, wait 1 s, tap option 2 |
| `datepicker.compact` / `.inline` / `.wheel` | `DatePicker` styles (§5.9) | white | compact: tap, wait 1.2 s, tap outside; others rest |
| `pagecontrol` | `UIPageControl` with translucent platter (§5.10) | photo | rest |
| `textfield` | `TextField` and search field, focused and unfocused (§5.11) | white, black | tap the field, wait 1 s |
| `list.form` | `Form` inset grouped with section headers, taller rows (§5.12) | none (system background) | rest; drag the list up 200 pt |
| `swipe.row` | `swipeActions` on a list row (§5.14) | none | drag the row left 180 pt, hold 0.4 s, release |
| `progress` | `ProgressView` linear and circular, thumbless slider (§5.13) | white | rest |

**Accessibility variants** (§7.1–7.3). The harness can run any scene under Reduce Transparency, Increase Contrast or Reduce Motion. The baseline runs those three on `material.regular`, `tabbar.rest`, `tabbar.drag`, `menu.bar` and `sheet.detents`. Whether each setting can be switched from the command line on the iOS 27 simulator is verified first (see Risks). A setting that cannot be scripted is marked `manual` in the report, never faked.

**Apple app references** (native only, no Flutter counterpart). The same driver plays steps on Apple's own apps for behaviours that are best seen in real apps. The manifest marks these with `"app": "<bundle id>"`:

| id | app | steps |
|---|---|---|
| `apple.maps.sheet` | `com.apple.Maps` | drag the sheet from rest to full, then down to the smallest detent |
| `apple.photos.search` | `com.apple.mobileslideshow` | tap the search tab, wait 1.5 s, tap the Library tab |
| `apple.photos.scroll` | `com.apple.mobileslideshow` | drag the grid up 400 pt and back (tab bar over photos) |
| `apple.reminders.menu` | `com.apple.reminders` | tap "…", wait 1.2 s, tap outside |
| `apple.calendar.toolbar` | `com.apple.mobilecal` | rest (grouped toolbar and bottom bar) |
| `apple.settings.large` | `com.apple.Preferences` | drag the list up 300 pt (large title under the bar) |

A one-time `lab.py prepare` gets these apps past their first-run screens on a fresh simulator:
- It revokes location with `simctl privacy`.
- It plays a `prepare` step list per app that taps through onboarding.
- It always chooses the privacy-preserving option ("Not Now", "Don't Allow").

## Scene manifest (`scenes.json`)

A JSON array. Each entry:

```json
{
  "id": "menu.bar",
  "group": "presentations",
  "title": "Menu from a toolbar button",
  "inventory": "4.6",
  "app": "lab",
  "backdrops": ["stripes", "photo"],
  "appearances": ["light", "dark"],
  "steps": [
    {"wait": 0.8},
    {"tap": [363, 84]},
    {"wait": 1.2},
    {"tap": [200, 780]},
    {"wait": 1.0}
  ],
  "regions": {"chrome": [230, 60, 172, 330]},
  "track": "chrome"
}
```

- `app` is `lab` for catalog scenes; the harness runs it on both GlassLab and Operator. A bundle id means an Apple app reference, native only.
- `steps` vocabulary, all coordinates in points and all times in seconds:
  - `wait`, `tap [x,y]`, `doubleTap [x,y]`;
  - `press {at, duration}`;
  - `pressDrag {from, to, pressDuration, velocity, hold}`, which maps to XCUITest `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`, with velocity in pt/s or `"default"`;
  - `tapElement "<accessibility id>"`.
- XCUITest cannot draw arbitrary multi-point paths through public API. Scenes are therefore designed around single press-drag-release gestures, and the vocabulary stays within public API.
- `regions` are named rectangles in points. `track` names the region whose geometry and brightness are followed over time. The first region is the default.

## Driver (GlassLabDriver)

- One XCUITest method, `testScene`, reads the scene id and target bundle id from its environment. The harness passes them through `xcodebuild` as `TEST_RUNNER_GLASS_SCENE` and `TEST_RUNNER_GLASS_TARGET`, since Xcode forwards `TEST_RUNNER_`-prefixed variables to the runner.
- It launches the target with `XCUIApplication(bundleIdentifier:)`, with `launchEnvironment` carrying `GLASS_LAB_SCENE` and, when asked, `GLASS_LAB_BARE`.
- It waits up to 20 s for `scene.ready`, then plays the steps. It uses `app.coordinate(withNormalizedOffset: .zero).withOffset(...)` so points mean the same thing on every target.
- `scenes.json` is copied into the test bundle at build time, so the driver never reads the host filesystem.
- Apple app references are launched the same way, without scene environment variables, and wait on the app's own first element instead of `scene.ready`.

## Operator's Flutter lab

This is the existing debug-only `/glass-lab` route in `lib/core/widgets/glass/lab/`, reached from `main.dart` when a lab scene is requested.
- **Runtime selection.** The scene id comes from `Platform.environment['GLASS_LAB_SCENE']` at launch in debug builds, so one build serves every scene. The compile-time `--dart-define=GLASS_LAB_SCENE` path is removed, together with the in-app injected touch (`_injectLiftTouch`), which the driver replaces.
- **Scene registry.** Every manifest scene id with `app: lab` resolves to a widget. Scenes built from components Operator already has use them:
  - `tabbar.*` uses `GlassTabBar`;
  - `button.*` uses `GlassButton`;
  - `sheet.detents` and `sheet.scroll` use `AppSheet`;
  - `material.edge.*` uses `ScrollEdgeEffect`;
  - `navbar.inline` uses `GlobalAppbar`;
  - `material.regular`, `material.tinted` and `material.clear` use `GlassSurface`;
  - `material.interactive` uses a pressable `GlassSurface`.

  Every other id renders a placeholder: backdrop plus a centred "missing: <id>" label, with a `scene.missing` semantics identifier. The report can then show coverage.
- **Backdrops.** The Flutter lab loads the same PNGs from the app's data container. Before launching, the harness copies `backdrops/*.png` to `<container>/Documents/glass_lab/` (found with `simctl get_app_container ... data`), and the lab reads them from `Platform.environment['HOME']/Documents/glass_lab/`. They are not added to the app's asset bundle, so release builds do not ship them.
- **Markers and layout.** Semantics identifiers `scene.ready` and the per-control ids named in steps. Layouts copy the native scene's geometry, which `lab.py geometry <id>` reports from the native recording.
- Layout mismatches the report finds against the native geometry are backlog items for projects 2–4, not work for this project. The exception is the existing tab bar, button, sheet and scroll edge scenes, which must be positioned to match (see Done).

## Harness (`harness/lab.py`)

Python 3 with PIL and numpy only (both installed), plus `ffmpeg` and Xcode's `xcrun`/`xcodebuild`. No other installs. Commands:

- **`lab.py build`** builds three things for the iOS 27 simulator:
  - GlassLab and GlassLabDriver (`xcodebuild build-for-testing`);
  - Operator in debug with `flutter build ios --simulator --debug --config-only`, then `xcodebuild` on `ios/Runner.xcworkspace` with `-derivedDataPath build/dd`. `flutter build ios` alone fails under Xcode 27.

  It then installs both apps on the simulator.
- **`lab.py prepare`** handles simulator setup:
  - finds or boots "iPhone 17 Pro (iOS 27)";
  - sets the status bar override (9:41, full battery, full bars);
  - copies the backdrops into Operator's container;
  - runs the Apple app first-run preparation.
- **`lab.py run <scene-id|group|all> [--app native|flutter|both] [--appearance light|dark|both] [--backdrop <id>] [--a11y none|reduce-transparency|increase-contrast|reduce-motion]`** runs, for each combination:
  1. Sets the appearance (`simctl ui appearance`) and the accessibility setting.
  2. Captures one bare frame (`GLASS_LAB_BARE=1`, screenshot after ready).
  3. Starts `simctl io recordVideo --codec=h264`, runs `xcodebuild test-without-building -only-testing:GlassLabDriver/DriverTests/testScene` with the scene environment, stops the recording with SIGINT, and waits for the file to finalise.
  4. Extracts frames with ffmpeg at 60 fps, full resolution, into `build/glass_lab/runs/<timestamp>/<scene>/<app>-<appearance>-<backdrop>/`.
  5. Writes `settled.png`: the last frame, or for rest scenes a screenshot 1.5 s after ready.
- **`lab.py report [<run dir>]`** computes metrics and writes `report.html` in the run directory. With no argument it uses the latest run.
- **`lab.py baseline`** runs `prepare`, then every scene in both apps in both appearances with every listed backdrop, plus the accessibility variants, then `report`.
- **`lab.py geometry <scene-id>`** prints the native glass bounding boxes of a scene, in points, found by differencing against the bare frame. Flutter scene authors use it.

### Metrics (`metrics.py`, `align.py`, `springfit.py`)

All image math is done on the full 3× frames; results are reported in points and milliseconds.

- **Onset alignment.** For each recording, onset is the first frame after `scene.ready` where the mean absolute difference (MAD) of the tracked region against the previous frame exceeds 0.5 (0–255 scale). Native and Flutter series are aligned at onset. Rest scenes skip alignment.
- **Static (settled frame, per region):**
  - MAD against native, per RGB channel and averaged;
  - mean luminance (Rec. 709) difference;
  - rim profile: luminance sampled along the vertical line through the region's glass centre, 12 pt either side of the top and bottom edges, compared point by point;
  - glass bounding box: pixels differing from the bare frame by more than 6, largest connected component. Reported as x, y, width, height and the difference to native in points.
- **Motion (tracked region, per frame from onset):**
  - glass bounding box width, height and centre, plus mean luminance, as time series;
  - differences to native: RMS error, peak time (ms), peak overshoot (percent of travel), settle time (ms, within 2% of final);
  - `springfit.py` fits a damped oscillator to each normalised series by a numpy grid search over response 0.05–1.5 s and damping fraction 0.1–1.2. It reports the fitted response and damping for native and Flutter, so later projects can copy springs directly.
- **Initial pass thresholds**, used later to judge projects 2–4:

  | Measure | Threshold |
  |---|---|
  | Region MAD | ≤ 4.0 |
  | Luminance difference | ≤ 3.0 |
  | Rim profile RMS | ≤ 6.0 |
  | Bounding box difference | ≤ 1 pt on each edge |
  | Peak and settle time | ≤ 17 ms (one 60 Hz frame) |
  | Overshoot | ≤ 2 points of percent |
  | Fitted response | within 5% |
  | Fitted damping | within 0.05 |

  A scene passes when every measure passes. Thresholds live in one table in `metrics.py`.

### Report (`report.py`)

`report.html` is self-contained apart from image files in the run directory. It has:

- **Summary:** counts of scenes passing, failing, missing in Flutter, native-only, and manual accessibility variants.
- **Coverage table:** one row per scene. Columns are the Flutter status (implemented or missing), worst measure, pass or fail, and a link.
- **Per-scene page**, for each appearance and backdrop:
  - settled frames side by side: native, Flutter, and a difference map ×4;
  - a filmstrip of both recordings aligned at onset, one frame every 50 ms for 1 s after onset;
  - the time-series curves as inline SVG, native against Flutter;
  - the rim profiles as inline SVG;
  - the metric table with pass or fail per measure.
- **Apple app references:** filmstrips and fitted springs only.

## Testing the tooling

- `harness/tests/` uses `unittest` (no pytest), with synthetic frames made by numpy:
  - onset alignment recovers a known offset to within 1 frame;
  - the spring fit recovers a known response and damping to within 5% and 0.05;
  - the bounding-box finder recovers a drawn rounded rectangle to within 1 px;
  - the rim profile sampler returns the drawn gradient;
  - the metric thresholds classify known inputs correctly.

  Run with `python3 -m unittest discover tool/glass_lab/harness/tests`.
- **Repeatability check.** The same native scene recorded twice must agree:
  - settled MAD under 1.0 and bounding box identical, for `material.regular` and `tabbar.rest`;
  - peak and settle times within one frame, for `tabbar.drag` and `menu.bar`.

  If this fails, the rig is not trustworthy and fixing it comes before anything else.
- Flutter changes pass `flutter analyze` ("No issues found!") and `flutter test`. Tests pin:
  - scene id parsing from the environment;
  - registry resolution of every `app: lab` manifest id, read from the real `scenes.json`;
  - placeholder rendering for missing ids.

## Done

1. The Xcode project builds, and GlassLab shows every scene in the catalog on the iOS 27 simulator in light and dark.
2. Every scene runs through the driver on GlassLab without error. The Apple app references run on their apps after `prepare`.
3. Operator's lab resolves every `app: lab` id. The existing components render their scenes, positioned so their settled bounding box is within 1 pt of native:
   - `tabbar.rest`, `tabbar.press`, `tabbar.drag`;
   - `button.styles`, `button.press`;
   - `sheet.detents`;
   - `material.edge.*`;
   - `navbar.inline`;
   - `material.regular`, `material.tinted`, `material.clear`, `material.interactive`.
4. The harness unit tests pass, and the repeatability check passes.
5. `lab.py baseline` completes. Its report shows every scene, with native iOS 27 against Operator's current glass.
6. **Committed:** `docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-baseline.md`, a summary with the coverage table and each scene's worst measures. It is the ordered backlog for projects 2–4. The HTML report and frames stay in `build/`; the report may also be published as an artifact for the user.
7. `tool/glass_reference/` is deleted and its `.gitignore` entry replaced.
8. `flutter analyze` and `flutter test` are green, and the README documents every command.

## Out of scope

- Any change to how glass looks or moves in Operator. That is projects 2–4.
- Real-device runs. They come at the end of the roadmap.
- iOS 26.5 comparisons. The 26.5 simulator stays installed but the lab targets 27 only.
- iPad, Mac, icons, widgets and system-owned UI.

## Risks and first checks

The plan's first task is a spike that proves these before building on them. Each result is recorded in the README:

- XCUITest on the iOS 27 simulator can:
  - launch and drive Operator's debug Flutter build, GlassLab, and an Apple app by bundle id;
  - pass `launchEnvironment` through to the Flutter process;
  - see Flutter semantics identifiers as accessibility identifiers.
- `TEST_RUNNER_`-prefixed variables reach the runner through `xcodebuild test-without-building`.
- `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` timing is repeatable across runs to within one frame, measured with the repeatability check.
- Reduce Transparency, Increase Contrast and Reduce Motion can be switched from the command line on the iOS 27 simulator (`simctl ui` or `simctl spawn ... defaults write`), and the change reaches both apps without a reboot. Anything that cannot be switched is marked `manual`.
- `simctl io recordVideo` frame timestamps are good enough for 60 fps resampling. If they are not, recordings use `--codec=h264` with ffmpeg `-vsync cfr` and the report notes it.
- Flutter simulator builds are debug (JIT). Timing is wall-clock and valid, but a dropped frame shows as a stall. The report marks Flutter frame gaps longer than 25 ms, so a stall is not mistaken for a spring difference.

## Constraints

- **No code comments** in new or changed code: Swift, Dart or Python. Upstream comments already in the repo are kept.
- **Commits** end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`.
- **Worktree only.** Work happens in `../Operator-glass-lab`; the shared `development` checkout is not touched until merge.
- **Nothing downloaded.** Backdrop imagery is generated, and the only font is the repo's own Anthropic Sans.
- **Simulator etiquette.** Operator on the simulator is used only through its debug glass lab route. The harness never pairs, never enters passwords, and never touches the user's real sessions or desktops.
