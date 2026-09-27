# ios_liquid_glass: master roadmap

Last updated: 2026-09-27. Owner: Omar Aly (the user). This is the single source of truth for the whole Liquid Glass effort. Every other document in `docs/liquid_glass/` hangs off it.

**Status at a glance**

| # | Project | Status |
|---|---|---|
| 1 | Reference lab (measuring instrument) | **DONE**, merged to `development` (`7f74f5a0b`), not pushed |
| 2A | Package foundation + how glass looks | **SPEC APPROVED** (2026-09-27). **Plan in progress**: prototype in `../Operator-2a-proto`, see `PROTOTYPE-2A.md` there |
| 2B | How glass moves | NOT STARTED |
| 3 | Every iOS component inside the package | NOT STARTED |
| 4 | Operator adopts the package | NOT STARTED |
| 5 | Real-device verification pass | NOT STARTED |

---

## 0. How to use this document (fresh session, read first)

1. Read this whole file, then the spec of the project you are about to work on. Specs are under `docs/liquid_glass/<nn>-<name>/spec.md`.
2. Section 9 says exactly what to do next. Do that, nothing else.
3. Follow section 5 (working rules) exactly, including how a plan is written (prototype first) and who reviews.
4. When a project changes state, update the status table above and that project's section in §6. Commit this file with the change.
5. Never trust memory over this file and `git log`. If they disagree, check the code and fix this file.

---

## 1. The goal

**In the user's words (2026-09-27):** "my goal is to improve this package `packages/mobile/packages/liquid_glass_renderer` so it be identical to original iOS liquid glass, so I can use this package in any other Flutter project if I needed liquid glass." Earlier (2026-09-26): "I want everything, I want perfection."

So:
- **The product is the package.** It will be renamed from `liquid_glass_renderer` to **`ios_liquid_glass`**; the user decided the name on 2026-09-27. It must be:
  - complete: every iPhone Liquid Glass material, motion and component;
  - identical to native iOS 27, measured and not eyeballed;
  - usable in any Flutter app, with no Operator code or theme inside.
- **Operator (`packages/mobile`) is only its first consumer.** Operator's own glass code in `lib/core/widgets/glass/` moves into the package over projects 2A and 3. Operator ends up using the package's widgets with its own tint colour and fonts.

### Decision log

| Date | Decision | By |
|---|---|---|
| 2026-09-23 | Mobile goes full iOS Liquid Glass, iOS only. Android must still compile. The Pencil design prototype no longer governs mobile. The AppSkin palette and fonts are kept. | user |
| 2026-09-26 | Target look is **iOS 27**, not 26.5. iOS 27 glass differs: a darker edge hairline, brighter specular, more diffusion, and a new automatic scroll edge. | user |
| 2026-09-26 | Order: reference lab → engine → components → Operator rollout, each with its own spec. | user |
| 2026-09-26 | Lab touch approach A: an XCUITest driver plays identical touches on native, the Flutter lab and Apple's apps. | user |
| 2026-09-27 | Split project 2 into 2A (looks) then 2B (motion). | user |
| 2026-09-27 | The package is the product, reusable in any Flutter app. Rename it to `ios_liquid_glass`. | user |
| 2026-09-27 | Keep the renderer's geometry and blend pass and its caching; replace the final lighting and colour step with an iOS 27 model. | agreed |
| pending | Native `material.interactive` shows no press reaction on the simulator. Recommendation: keep it as a still-image reference and check `.interactive()` on a real iPhone in project 5. | user to decide |

---

## 2. Where everything is

Repository: `/Users/omaraly/development/AI/Operator`. Default branch `development`; release branch `master`, which is never used for this work. All mobile paths below are relative to `packages/mobile/` unless they start with `docs/`.

### The package (the product)
| Path | What |
|---|---|
| `packages/liquid_glass_renderer/` | The package today. It becomes `packages/ios_liquid_glass/` in 2A. It is a pub workspace member (listed under `workspace:` in `pubspec.yaml` line ~33, depended on at line ~75). |
| `packages/liquid_glass_renderer/lib/liquid_glass_renderer.dart` | Public exports: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow`, `LiquidStretch`, shapes (`LiquidRoundedSuperellipse`, `LiquidOval`, `LiquidRoundedRectangle`). |
| `packages/liquid_glass_renderer/lib/src/` | `liquid_glass.dart`, `liquid_glass_blend_group.dart`, `rendering/liquid_glass_layer.dart`, `rendering/liquid_glass_render_object.dart`, `liquid_glass_settings.dart`, `glass_glow.dart`, `glass_shadow.dart`, `fake_glass.dart`, `stretch.dart`, `internal/*` |
| `packages/liquid_glass_renderer/lib/assets/shaders/` | `liquid_glass_geometry_blended.frag` (SDF geometry and blending, cached), `liquid_glass_final_render.frag` (refraction, tint, rim light: **the part 2A replaces**), `render.glsl`, `sdf.glsl`, `displacement_encoding.glsl`, `fake_glass_color.frag` |
| `packages/liquid_glass_renderer/FORK.md` | Every change made to upstream. Upstream is `whynotmake-it/flutter_liquid_glass`, vendored at `ad3bcff` (2026-04-24), MIT, by Tim Lehmann. Keep `LICENSE` and credit forever. |

### Operator's glass layer (moves into the package over 2A and 3)
| Path | What | Moves in |
|---|---|---|
| `lib/core/widgets/glass/glass_style.dart` | `GlassVariant {regular, clear, prominent, chrome}`, `GlassStyle.resolve` (size, variant and appearance → `LiquidGlassSettings`), `GlassStyle.shadows` | 2A, replaced by the package's material table |
| `lib/core/widgets/glass/glass_surface.dart` | `GlassSurface` (kind, size, variant, pressable) over `LiquidGlass` | 2A (becomes `GlassEffect`) |
| `lib/core/widgets/glass/glass_scope.dart` | `GlassScope` over `LiquidGlassLayer` | 2A (becomes `GlassEffectContainer`) |
| `lib/core/widgets/glass/scroll_edge_effect.dart` + `shaders/scroll_edge_blur.frag`, `scroll_under_bars.dart` | Scroll edge effect | 2A |
| `lib/core/widgets/glass/glass_metrics.dart` | Layout constants (tab bar 62, insets and so on) | 3 |
| `lib/core/widgets/glass/glass_tab_bar.dart`, `glass_tab_bar_logic.dart`, `glass_lens.dart` + `shaders/tab_lens.frag` | Tab bar with the minifying lens (tuned on iOS 26.5 in commit `947f03e8e`) | 3 |
| `lib/core/widgets/glass/glass_button.dart`, `glass_bar_item.dart`, `glass_toolbar.dart`, `frosted_header.dart`, `glass_sheet.dart` | Buttons, bar items, toolbar, frosted header, simple sheet | 3 |
| `lib/core/widgets/sheet/app_sheet.dart` | Multi-page sheet (`showAppSheet`, detents fit/medium/large) | 3 |
| `lib/core/widgets/main_widgets/global_appbar.dart` | Operator's nav bar built on the glass layer | stays in Operator, rebuilt on package parts in 4 |
| `lib/core/widgets/glass/lab/**` | Operator's debug glass lab (route `/glass-lab`, reads `Documents/glass_lab/launch.json`) | 2A moves the lab scenes into the package's `example/` app |

### The lab (measuring instrument, project 1)
| Path | What |
|---|---|
| `tool/glass_lab/README.md` | How to use the lab (commands below) |
| `tool/glass_lab/scenes.json` | 66 scenes: 60 lab scenes plus 6 Apple app references. The manifest is the source of truth. |
| `tool/glass_lab/noise.json` | Native-vs-native motion noise floor (committed) |
| `tool/glass_lab/native/` | `gen_project.py` → `GlassLab.xcodeproj`. `GlassLab/` is the SwiftUI iOS 27 catalog (bundle `dev.operator.glasslab`). `GlassLabDriver/` is the XCUITest driver. |
| `tool/glass_lab/backdrops/generate.py` | Deterministic backdrops (stripes, photo, white, black, text, scroll), generated into `build/glass_lab/backdrops/` and never committed |
| `tool/glass_lab/harness/` | `lab.py` CLI; `manifest, sim, build, record, analyze, align, metrics, springfit, report` modules; `tests/` (45 unittest tests) |
| `build/glass_lab/` | Build output and runs (git-ignored). The project 1 baseline run lives **in the worktree** `/Users/omaraly/development/AI/Operator-glass-lab/packages/mobile/build/glass_lab/runs/20260927-035111/` (report.html inside); the repeat takes are in `.../runs/20260927-024701/`. |

### Documents
| Path | What |
|---|---|
| `docs/liquid_glass/ROADMAP.md` | This file |
| `docs/liquid_glass/research/apple-inventory.md` | **The definition of "complete"**: 80 Apple Liquid Glass components and behaviours, iOS 27 deltas, numbers ledger, and "behaviours most implementations miss" |
| `docs/liquid_glass/research/flutter-repos.md` | Flutter implementations surveyed, with techniques worth borrowing (liquid_glass_widgets morph engine and blur ramp, liquid_glass_easy adaptivity and metaballs) |
| `docs/liquid_glass/research/non-flutter.md` | Non-Flutter implementations: Kyant0/AndroidLiquidGlass shader, kube.io optics, SDF smooth-union, dual-lobe rim; ranked techniques |
| `docs/liquid_glass/research/operator-audit.md` | Every Operator screen and the component each uses (the input to project 4) |
| `docs/liquid_glass/01-reference-lab/spec.md`, `plan.md`, `baseline.md` | Project 1 |
| `docs/liquid_glass/02a-looks/spec.md` | Project 2A spec |
| `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-engine-design.md`, `2026-09-24-mobile-glass-chrome-design.md`, `2026-09-24-mobile-sheets-design.md` (+ plans and reports in `docs/superpowers/`) | History: the first engine and chrome work on iOS 26.5, before this roadmap |

### Worktrees
- `/Users/omaraly/development/AI/Operator-glass-lab`: branch `feat/mobile-glass-lab`, project 1. Merged; it can be removed when the baseline run in its `build/` is no longer needed.
- The shared checkout `/Users/omaraly/development/AI/Operator` is used by several sessions at once. Work in a worktree; touch the shared checkout only to merge or push when the user asks.

---

## 3. Environment and tools

- **Machine:** macOS (Darwin 27). Xcode 27.0 (27A266a). Flutter 3.44.5 (CI pins it). Python 3.14 with Pillow and numpy; pytest is not installed, so use unittest. `ffmpeg` is at `/opt/homebrew/bin`. `timeout` exists (Homebrew) but sends SIGTERM; use `kill -INT` for Python cleanup.
- **Simulators:**
  - **"iPhone 17 Pro (iOS 27)"**: UDID `708879DD-8B2A-4547-863F-F49EE1474D8B`, runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-0`. All lab work runs here. The harness finds it by name and runtime.
  - "iPhone 17 Pro" on iOS 26.5: UDID `94D0C207-A90B-4806-BBAB-8AF9B3F16329`. It holds the user's **paired, real Operator**. Do not touch its data; use it only for 26.5 comparisons.
  - The iOS 27 simulator's languages are `en-EG`, `ar-EG`, inherited from the Mac. The keyboard is English with a globe key, and calendars start on Saturday. This is harmless because both apps share it.
- **Building Operator for the simulator:** `flutter build ios` alone **fails under Xcode 27**. Use:
  ```bash
  flutter build ios --simulator --debug --config-only
  xcodebuild build -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/glass_lab/flutter IPHONEOS_DEPLOYMENT_TARGET=15.0
  ```
  `tool/glass_lab/harness/build.py` does exactly this.
- **Lab commands** (from `packages/mobile`; see `tool/glass_lab/README.md`):
  - `lab.py build [native|flutter|both]`, then `lab.py prepare`;
  - `lab.py run <scene|group|prefix|all> [--app native|flutter|both] [--appearance light|dark|both] [--backdrop id] [--a11y none|reduce-transparency|increase-contrast|reduce-motion]`;
  - `lab.py report [run]`, `lab.py summary <out.md> [run]`, `lab.py repeat [scene]`, `lab.py geometry <scene>`;
  - `lab.py baseline`, which takes about 4 h, so run it in the background.

  Each case takes about 36 s. A driver failure no longer stalls for 600 s, because the harness passes `-collect-test-diagnostics never`.
- **Gates:**
  - from `packages/mobile`: `flutter analyze` must print "No issues found!", and `flutter test` must be green (2,172 tests at the end of project 1);
  - `python3 -m unittest discover tool/glass_lab/harness/tests` must print OK.

---

## 4. Gotchas already learned (with evidence)

1. **Dart's `Platform.environment` is empty on iOS** (it logged 0 entries). Launch variables cannot reach Flutter. The lab passes the scene through `Documents/glass_lab/launch.json`, which the harness writes before each launch and the app deletes on start.
2. **Operator's first launch on a fresh simulator shows a notification permission prompt.** The driver dismisses springboard alerts with "Don't Allow" or "Not Now", and only those.
3. **`flutter test` prints a long SkSL error** for `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"). It comes from the renderer shader, is known and harmless, and tests pass.
4. **The simulator records variable-rate video at up to 120 Hz.** Analyse at the real frame timestamps, never at a fixed 60 fps: resampling faked one-frame timing errors.
5. **Test-runner clock times do not map onto video time.** Windows are found from content, by matching the lossless `ready.png` and `settled.png` screenshots.
6. **The Dynamic Island area (top 72 pt) differs** between XCUIScreen screenshots and video, so it is excluded from matching.
7. **XCUITest touch timing jitters.** Motion limits are max(fixed threshold, 1.5 × native-vs-native noise). Still images are exact (0.00 between native takes).
8. **Glass box matching.** Faint glass (dark glass on black, white on white) shows only its contents. The harness therefore matches Flutter's shapes to the native element they overlap, and widens native to its parts, never to a full-screen dim layer. This fix is commit `caf1991ab`. Before it, the baseline reported fake 130–300 pt placement errors.
9. **Spring fits must use each app's full event.** Fits on lag-trimmed curves moved with the alignment (fixed in `caf1991ab`).
10. **Native `.glassEffect(.regular.interactive())` shows no visible press reaction** to XCUITest touches on the iOS 27 simulator. Six variants were tried and the touches do arrive. `.buttonStyle(.glass)` does react.
11. **On iOS 27 the search tab sits inside the tab bar capsule** as a fourth item; on 26.5 it was a separate circle. The native tab bar measures x 20, y 791, 362 × 62 pt.
12. **Flutter's `find.bySemanticsIdentifier` needs `tester.ensureSemantics()`.** Flutter semantics identifiers and labels do reach XCUITest.
13. **Color.clear in SwiftUI is not hit-testable** unless it has a content shape. This did not explain gotcha 10.

---

## 5. Working rules

### Process for every project (the user's standing workflow)
1. **Spec** here: brainstorming, then the user approves the written spec.
2. **Plan** here, **prototype first**. Build a throwaway prototype in the session scratchpad, make it compile and run on the iOS 27 simulator, and run its tests. Then generate the plan with the tested code embedded. That is how project 1's plan reached "every task passed review". The user then approves the plan.
3. **Execution** in a **fresh session**, with `superpowers:subagent-driven-development`, in a new worktree and branch. The user starts it from a handoff prompt that you write, in the style of project 1's.
4. **Review** back here, and never trust green gates alone:
   - diff the branch against the plan's code;
   - rerun every gate;
   - open the actual measurements and screenshots;
   - fix what is wrong, commit, and re-measure.
5. **Merge** into `development` when the user says; push only when asked.

### Hard rules
- **No code comments** in any new or changed code (Swift, Dart, Python, shell, GLSL). Keep existing upstream comments.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. **Never `git stash` in the shared checkout.**
- Work in a worktree. The shared checkout is for merges and pushes only.
- Never pair Operator with a desktop, never enter a password, never touch the user's real sessions or desktops, and never use the iOS 26.5 simulator's Operator data.
- System prompts on the simulator get only "Don't Allow" or "Not Now".
- No downloads and no `pip install`. Python uses the standard library, Pillow and numpy.
- Judge glass against native measurements, never from memory. When a number looks wrong, open the screenshots.
- Keep `docs/liquid_glass/ROADMAP.md` current.

---

## 6. Projects in detail

### Project 1: Reference lab (DONE)
- **Spec, plan, baseline:** `docs/liquid_glass/01-reference-lab/`.
- **Branch:** `feat/mobile-glass-lab`, merged into `development` as `7f74f5a0b` on 2026-09-27. **Not pushed yet.**
- **Delivered:**
  - native iOS 27 catalog (60 scenes);
  - XCUITest driver;
  - harness (still-image measures from lossless screenshots; motion from real frame timestamps, split into events, aligned jointly, springs fitted on full events);
  - Operator debug lab route;
  - `noise.json`;
  - a committed baseline summary (`baseline.md`, 228 cases: 96 fail, 120 missing, 12 references, 0 errors).
- **Review fixes** (`caf1991ab`): element matching, full-event spring fits and joint alignment, count-mismatch ranking, run robustness, `repeat` exit code, no diagnostics stall, native stepper legible in dark mode, Operator lab status bar icons.
- **Open items carried forward:**
  - `material.interactive` has no native motion (decision pending, §1).
  - Flutter scenes exist only for the components Operator already has: tab bar rest/press/drag, `button.press` and `button.styles`, `sheet.detents`, `navbar.inline`, regular/tinted/clear/interactive material, and edge effects. Everything else reads "missing" until the package builds it.
  - Apple prepare taps are not idempotent.
  - `events.count` compares by order only.

### Project 2A: Package foundation + how glass looks (SPEC APPROVED, plan in progress)
- **Spec:** `docs/liquid_glass/02a-looks/spec.md`. Read it for every detail.
- **Summary:**
  - Rename to `ios_liquid_glass` and make it a plugin with an iOS part for Reduce Transparency.
  - A SwiftUI-mirroring public API (`Glass`, `GlassEffect`, `GlassEffectContainer`).
  - iOS 27 material defaults inside the package.
  - An `example/` app that becomes the lab's Flutter target.
  - A new final-render lighting and colour model: dark hairline plus dual specular, a brightness transfer curve, frosting, quarter-circle bevel, rim-only dispersion, size-dependent material, adaptive shadow.
  - Clear and tinted variants, the scroll edge effect, the accessibility modes, and a spike on light/dark flipping.
  - A `lab.py tune` automatic parameter search.
  - Operator's `GlassStyle`, `GlassSurface` and `GlassScope` replaced by the package API.
- **Prototype (2026-09-27):** worktree `/Users/omaraly/development/AI/Operator-2a-proto` (branch `proto/2a`, uncommitted, throwaway). **`PROTOTYPE-2A.md` at its root** records what is proven and where the code is:
  - rename;
  - plugin;
  - new shader;
  - API and material table;
  - scroll edge moved into the package;
  - Operator migration (2,145 tests green);
  - example app;
  - harness `--flutter` target and `tune`, with one real loop improving the score from 15.33 to 14.67.
- **Next:** finish the plan in `docs/liquid_glass/02a-looks/plan.md` from that prototype → the user reviews it → a fresh session executes it → review here.

### Project 2B: How glass moves (NOT STARTED)
- **Scope:**
  - interactive press response: scale up, bounce, glow spreading to neighbouring glass in the same container, drag stretch;
  - materialize and dematerialize, by ramping lensing, blur and highlight rather than alpha;
  - shape merging with container spacing, union, identity morph (`glassEffectID` equivalent);
  - re-tuned springs for any glass the package owns;
  - Reduce Motion (no elasticity; fades instead of blur ramps).
- **Measured native data to start from** (`noise.json`, baseline):
  - menu open width spring response about 0.26–0.30 s, damping 0.74–0.81 (fit error about 0.03);
  - tab bar drag width response about 0.27–0.34 s, damping about 0.37–0.40.
  - Native materialize and dematerialize are about 250 ms and 350 ms in a third-party 120 fps capture (research/apple-inventory §2.13).
- **Lab scenes:** `material.interactive` (see the pending decision), `material.materialize`, `material.merge`, `material.union`, `material.morph`, `tabbar.press`, `tabbar.drag`, `button.press`.
- **Next:** write the spec after 2A merges.

### Project 3: Every iOS component inside the package (NOT STARTED)
- **Scope:** everything in §7 marked project 3.
  - Move Operator's tab bar (with lens), toolbar, bar items, buttons, frosted header, simple and multi-page sheets into the package as generic components.
  - Build the missing ones: menus that grow from their button, context menu, popover, alert, action sheet or confirmation dialog, switch, slider, segmented control, stepper, pickers, page control, search field and search tab, nav bar with large title and minimization, bottom toolbar, tab bar accessory and minimize, badges, swipe actions, push zoom and sheet zoom transitions, lists and forms styling, progress.
  - Each gets its lab scene implemented in the package's `example/` app and must pass against native.
- **Next:** spec after 2B.

### Project 4: Operator adopts the package (NOT STARTED)
- **Scope:** replace Operator's widgets with the package's on every screen listed in `research/operator-audit.md`. Its biggest gaps:
  - Material dialogs;
  - four plain Material bottom sheets;
  - no menus;
  - Material switches;
  - Material pull-to-refresh and snackbars;
  - `MaterialPageRoute` transitions;
  - opaque settings rows (content stays solid per Apple's rule, but gets iOS 27 list styling).

  Delete Operator's `lib/core/widgets/glass/` leftovers.
- **Next:** spec after 3.

### Project 5: Real-device verification (NOT STARTED)
- **Scope:**
  - run the key scenes on the user's real iPhone (iOS 27);
  - check `.interactive()` (§1 pending);
  - tilt-driven highlights;
  - 120 Hz smoothness and frame cost of the package's shaders.

---

## 7. Component checklist (the definition of complete)

Source: `research/apple-inventory.md` §1, which has 80 rows. The table lists the iPhone-relevant ones. A lab scene id means the native reference already exists in the catalog.

"Package" means the thing exists in the package and matches native, measured.

| Item (inventory §) | Lab scene | Project | Package |
|---|---|---|---|
| Regular glass (2.1) | material.regular | 2A | no (Operator GlassSurface, not native-exact) |
| Clear glass + 35% dimming (2.2) | material.clear | 2A | no |
| Identity glass (2.3) | none | 2A | no |
| Tinted glass (2.4) | material.tinted | 2A | no |
| Interactive press (2.5) | material.interactive, button.press | 2B | no |
| Lensing / edge refraction (2.6) | material.* | 2A | partly (renderer lens, 26.5-tuned) |
| Specular rim, dark iOS 27 hairline (2.7) | material.* | 2A | no |
| Adaptive shadow (2.8) | material.* on white and text | 2A | no |
| Light/dark flip of small glass (2.9) | material.flip | 2A (spike) | no |
| Size-dependent thickness (2.10) | material.regular (3 sizes) | 2A | partly |
| Vibrant foreground (2.11) | material.* | 2A | no |
| Materialize / dematerialize (2.13) | material.materialize | 2B | no |
| Container shared sampling and merging (2.14) | material.merge | 2B | partly (renderer blend groups) |
| Union (2.15) | material.union | 2B | no |
| Identity morph (2.16) | material.morph | 2B | no |
| Capsule, fixed, concentric shapes (2.17) | material.shapes | 2A shapes / 3 concentric | partly |
| Scroll edge effect soft, hard, automatic (2.19) | material.edge.* | 2A | no (Operator one, MAD 50) |
| Content-layer materials (2.22) | material.content | 3 | no |
| Floating tab bar + search tab (3.1, 3.5) | tabbar.rest, tabbar.search | 3 | no (Operator GlassTabBar) |
| Tab selection lens (3.2) | tabbar.press, tabbar.drag | 3 | no (Operator lens, 26.5-tuned) |
| Tab bar minimize (3.3) | tabbar.minimize | 3 | no |
| Tab bar bottom accessory (3.4) | tabbar.accessory | 3 | no |
| Prominent tab (3.6) | tabbar.prominent | 3 | no |
| Tab badge (3.7) | tabbar.badge | 3 | no |
| Nav bar, back button, groups (3.10–3.13) | navbar.inline, navbar.groups | 3 | no |
| Large title + subtitle (3.12) | navbar.large | 3 | no |
| Prominent toolbar action (3.14) | navbar.groups | 3 | no |
| Bottom toolbar (3.15) | toolbar.bottom | 3 | no |
| Toolbar morph across push/pop (3.16) | navbar.push | 3 | no |
| Bar button badge (3.17) | navbar.badge | 3 | no |
| Nav bar minimization, iOS 27 (3.18) | navbar.minimize | 3 | no |
| Bottom search field, minimized search (3.20) | search.bottom, search.minimized | 3 | no |
| Search scopes (3.21) | search.scopes | 3 | no |
| Sheets: inset partial, opaque full (4.1–4.2) | sheet.detents, sheet.scroll | 3 | no (Operator AppSheet, opaque, one detent) |
| Sheet zoom from source (4.3) | sheet.zoom | 3 | no |
| Cross-fade sheet, iOS 27 (4.4) | sheet.crossfade | 3 | no |
| Popover from bar button (4.5) | popover.bar | 3 | no |
| Menus growing from their button (4.6) | menu.bar, menu.submenu, menu.pressdrag | 3 | no |
| Context menu (4.7) | contextmenu.card | 3 | no |
| Alerts (4.9) | alert.two, alert.three | 3 | no |
| Confirmation dialog from source (4.10) | confirm.source | 3 | no |
| Push zoom transition (4.11) | push.zoom | 3 | no |
| Glass / prominent / clear buttons, sizes, shapes (5.1–5.4) | button.styles, button.press | 3 | no (Operator GlassButton) |
| Switch (5.5) | toggle | 3 | no |
| Slider (5.6) | slider | 3 | no |
| Segmented control (5.7) | segmented | 3 | no |
| Stepper (5.8) | stepper | 3 | no |
| Pickers (5.9) | picker.menu, datepicker.* | 3 | no |
| Page control (5.10) | pagecontrol | 3 | no |
| Text and search fields (5.11) | textfield | 3 | no |
| Lists and forms (5.12) | list.form | 3 | no |
| Progress (5.13) | progress | 3 | no |
| Swipe actions (5.14) | swipe.row | 3 | no |
| Reduce Transparency (7.1) | a11y runs | 2A | no (Flutter cannot read it; plugin needed) |
| Increase Contrast (7.2) | a11y runs | 2A | partly (outline only) |
| Reduce Motion (7.3) | a11y runs | 2B | no |

Out of scope: iPad and Mac items (sidebar, pointer, iPad tab bar), app icons, widgets, system-owned UI (keyboard, share sheet).

---

## 8. Baseline facts to carry forward (project 1, re-analysed after `caf1991ab`)

- **Still-image difference, Operator vs native** (region MAD, target ≤ 4; luminance ≤ 3; rim-profile RMS ≤ 6):

  | Where | MAD | Rim RMS |
  |---|---|---|
  | Typical | ~14 | ~19 |
  | Dark mode | 18 | 18 |
  | Light mode | 12 | 20 |
  | Reduce Transparency | 56 | 31 |
  | Increase Contrast | 22 | 22 |
  | Edge effects | ~50 | >100 |
  | Sheet | 35 | 28 |

- **Placement is right.** On black, where shadows are invisible, glass box centres match native (0.0 pt). Elsewhere Operator's even shadow shifts the box centre by 4–8 pt.
- **What is visibly wrong:**
  - Operator's glass is nearly invisible over black, where native shows a visible grey capsule.
  - The rim picks up background colour; native uses a dark hairline with a bright top highlight.
  - The tint is flat; native reshapes backdrop brightness per mode and size.
  - Shadows are even; native's are offset downward and adaptive.
  - Operator's tab bar footprint is 377 × 82 against native's 362 × 62.
  - Operator's sheet is opaque and doesn't move to the small detent.
  - The nav bar has two circles where native has one grouped capsule.
- **Native springs measured:**
  - menu open: response ≈ 0.28 s, damping ≈ 0.78;
  - tab bar drag width: response ≈ 0.30 s, damping ≈ 0.38.
- **Noise floor (`noise.json`):**

  | Scene | Measure | Value |
  |---|---|---|
  | menu.bar event0 | width peak | 8 ms |
  | menu.bar event0 | width settle | 42 ms |
  | menu.bar event0 | width response | 15% |
  | tabbar.drag event0 | width settle | 133 ms |
  | tabbar.drag event0 | luma response | 44% |

---

## 9. Exact next steps

1. **Spec approved on 2026-09-27.** Still pending from the user: whether to push `development`, and the `material.interactive` decision.
2. **Write the 2A plan prototype-first. The prototype is mostly done**; read `/Users/omaraly/development/AI/Operator-2a-proto/PROTOTYPE-2A.md` first. Its original steps were, into `docs/liquid_glass/02a-looks/plan.md`:
   - Create a worktree `../Operator-ios-liquid-glass` on a new branch `feat/ios-liquid-glass-2a` off `development`.
   - Prototype in the session scratchpad:
     - the rename;
     - the plugin (Swift, `UIAccessibility.isReduceTransparencyEnabled` plus its notification);
     - the `example/` app building under Xcode 27 with the lab launch file;
     - the new final render shader compiling under Impeller;
     - `lab.py tune` driving parameter overrides through `launch.json`.
   - Make each piece run on the iOS 27 simulator, then embed the tested code in the plan the way `01-reference-lab/plan.md` does.
3. **Hand off** to a fresh session with a prompt that names this file, the 2A spec and plan, the worktree and the hard rules. Use project 1's handoff prompt as the model.
4. **Review** the result here: rerun the lab on the material scenes, compare with the baseline, and update §6 and §8.
