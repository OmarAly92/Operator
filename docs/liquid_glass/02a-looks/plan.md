# ios_liquid_glass 2A: Package Foundation and the iOS 27 Look — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Turn the vendored renderer into `ios_liquid_glass`, a Flutter package that any app can use and that looks like native iOS 27 Liquid Glass, measured by the glass lab:
- renamed, with an iOS plugin that reads Reduce Transparency;
- a SwiftUI-style API (`Glass`, `GlassEffect`, `GlassEffectContainer`) over a tuned iOS 27 material table;
- a new final render step (tone curve, tint, hairline, specular);
- the scroll edge effect inside the package, with the soft, hard and automatic styles;
- an `example/` app that is the lab's Flutter target;
- Operator moved onto the new API.

**Architecture.**
- The renderer keeps its geometry pass, blend groups and caching. Only the final render shader and the settings it reads change.
- `GlassMaterial` holds every look parameter by name. `GlassMaterial.resolve` picks a row of the `ios27Table` by appearance, variant and accessibility, interpolates between the 44, 88 and 200 pt anchors on log size, and produces `LiquidGlassSettings` and shadows. `GlassEffect` measures itself and resolves its material.
- The tables are written only by `lab.py tune --write`, which searches parameters against native screenshots. The example app applies candidate values through the launch file (`material` map → `GlassMaterialOverride`).
- A CocoaPods plugin sends `{reduceTransparency, increaseContrast, reduceMotion}` over an `EventChannel`. `GlassAccessibility.of(context)` merges it with `MediaQuery`.

**Tech stack.** Flutter 3.44.5 / Dart with Impeller runtime-effect shaders (GLSL 460), Swift (Flutter plugin, CocoaPods), SwiftUI for the native catalog, Python 3 (stdlib, Pillow, numpy) for the harness, Xcode 27 and the iOS 27 simulator.

**Spec.** `docs/liquid_glass/02a-looks/spec.md`, approved on 2026-09-27. The master roadmap is `docs/liquid_glass/ROADMAP.md`; read its §3–§5 first.

**Where the code comes from.** Every code block below ran in a throwaway prototype (`../Operator-2a-proto`, branch `proto/2a`) on the "iPhone 17 Pro (iOS 27)" simulator before this plan was written:
- all gates passed: package 46 tests, example 6, harness 75, Operator 2,145, and `flutter analyze` clean everywhere;
- the example app and Operator both built with the plugin under Xcode 27;
- the lab measured it: a11y toggles live, perf A/B, edge alignment, flip, and tune loops.

Transcribe the code exactly, then run the verification steps. If a step fails, fix the cause and say what changed in the task report.

**Rulings the prototype forced, with evidence.** These refine the spec. Where this list and the spec differ, this list wins.
1. **Three-point tone curve instead of `lift` + `gain`** (spec B1.4, and its Risks section's spline fallback).
   - A linear curve could not fit `stripes` and `white` together on dark regular glass at 88 pt:
     - at gain 0.5, `white` MAD was 5.5 but `stripes` luminance was off by 15.7;
     - at gain 0.75, `stripes` was off by 8.7 but `white` MAD was 43.8.
   - With `toneBlack`, `toneMid` and `toneWhite`, one tune pass over tone, frost and saturation took the score from 17.85 to 7.18: `stripes` MAD 4.7 (luminance 1.9), `white` MAD 2.6 (1.1), `black` MAD 0.8 (0.3). The best values were toneWhite 0.57, toneBlack 0.125, toneMid 0.5, frost 22 and saturation 0.9. What remains is rim (up to 9.4) and shadow placement (box 5 pt on light backdrops), which Task 11's lens, rim and shadow steps tune.
   - The shader evaluates the quadratic through (0, black), (0.5, mid) and (1, white).
2. **The tint uses a brightness range, `tintBlack` and `tintWhite`**, not the spec's tone ÷ tint luminance.
   - Native tinted glass is the accent colour scaled by 0.8–1.08 with backdrop brightness. For example, `#1ACB64` over white in light mode reads (26, 202, 99), and over black it reads (14, 163, 76).
3. **The geometry pass needs no change** (spec B1.1). `liquid_glass_geometry_blended.frag` already builds a quarter-circle bevel, `height = sqrt(T² − (T + sd)²)`, with Snell refraction. Tune `thickness` and `refractiveIndex` instead.
4. **Accessibility state is a static `ValueNotifier`** (`GlassAccessibility.platform`), with no scope widget for apps to insert.
   - The lab showed all three toggles reaching a running app without a relaunch: `defaults write` for Reduce Transparency and Reduce Motion, `simctl ui increase_contrast` for Increase Contrast.
5. **B8, the light/dark flip, needs no implementation in 2A.**
   - Measured on the native `material.flip`: `.glassEffect()` glass never flips at 44 pt or at 200 pt, in either appearance. Small light glass over black read 130, where no flip predicts 132 and a flip predicts 32. Small dark glass over white read 182, where no flip predicts 184 and a flip predicts 252.
   - Bars and tab bars are re-checked in project 3.
6. **The edge scenes become static and pre-scrolled by 300 pt**, with their region pinned to the top 240 pt and only MAD and luminance checked.
   - The baseline's MAD of about 50 was layout, not the effect: content sat 117 pt higher in Flutter, a 300 pt drag scrolled native about 500 pt, and Operator's bar had a back button.
   - After the fix, content lines up to 0 px. With seed values, hard and automatic already measure band MAD 3.8.
7. **`GlassForeground` colours are measured:** white (`#FFFFFFFF`) in dark mode, black (`#FF000000`) in light mode, and white on tinted glass. This holds for native `button.styles` and the `material.tinted` "Run" label, which is 17 pt regular.
8. **Frame cost is unchanged.** Raster median in the example's `perf.glass` scene (13 own-layer glasses over a moving backdrop, iOS 27 simulator): new shader 12.54 ms, old shader 12.63 ms, no glass 0.65 ms. `FrameTiming` works in simulator debug builds.
9. **`material.content` stays in project 3**, as ROADMAP §7 assigns it. The spec's A5 list named it, but content materials are a component.
10. **API names that differ from the spec:**
    - `GlassMaterial.resolve` takes `shorterSide`, not a `Size`;
    - `GlassEffect` takes an optional `sideHint`, and `GlassEffectContainer` takes `glass` and `side`;
    - the foreground colour is `GlassForeground.colorOf(context)` rather than `Glass.foregroundColor(context)`, because `Glass` is a context-free value like SwiftUI's.
11. **The package's inherited widget is named `GlassEffectScope`**, because Operator already has a `GlassScope` and both are imported together.
12. **Scroll edge values live in their own table**, `ios27ScrollEdgeTable` in `ios27_scroll_edge.dart`. Their override keys are prefixed `edge.`, for example `edge.blur`, and `ScrollEdgeEffect` keeps its explicit `height`.
13. **Swift Package Manager is a follow-up.** Flutter warns that plugins without SPM support will become an error in a future version. Do not enable SPM globally; record it in the ROADMAP.
14. **`FakeGlass` keeps upstream's look in 2A.** `GlassEffect` never uses it, and Operator does not use it. It gets the tone curve when a project 3 component needs a non-shader fallback (spec B1, last paragraph).
15. **The shadow is static in 2A.** It is fitted on `white` and `text` (spec B3). The flip spike built no backdrop readback, so adaptive shadow moves to project 3, with a ROADMAP note (Task 13).

## Global Constraints

- **Paths and git**
  - Work only in the worktree `/Users/omaraly/development/AI/Operator-ios-liquid-glass`, on branch `feat/ios-liquid-glass-2a` made from `development`.
  - Never touch `/Users/omaraly/development/AI/Operator`, the shared checkout. Never touch `/Users/omaraly/development/AI/Operator-2a-proto`, the prototype; it is reference only.
  - Paths are relative to `packages/mobile/` unless they start with `docs/`, which is relative to the repository root.
  - Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. Never `git stash`.
- **Code**
  - No code comments in any new or changed code: Dart, Swift, Python, GLSL or shell. Keep upstream comments that already exist, including dartdoc in the vendored renderer files and the copyright line of each shader.
  - Never run `dart format` on whole files; match the surrounding style.
  - Material numbers in `lib/src/material/ios27.dart` and `ios27_scroll_edge.dart` change only through `lab.py tune --write`. The only exception is the seed files, which Tasks 4 and 6 give verbatim.
- **Simulator and tools**
  - Simulator: "iPhone 17 Pro (iOS 27)", runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-0`, UDID `708879DD-8B2A-4547-863F-F49EE1474D8B` on this machine. The harness finds it by name.
  - Never touch the iOS 26.5 simulator (`94D0C207-A90B-4806-BBAB-8AF9B3F16329`) or its Operator data.
  - `flutter build ios` alone fails under Xcode 27. Build lab apps only with `python3 tool/glass_lab/harness/lab.py build <native|example|operator>`.
  - Python may use the standard library, Pillow and numpy only. No `pip install`, and no downloads of any kind.
- **Gates**, for every task that touches their code:
  - App, from `packages/mobile`: `flutter analyze` prints "No issues found!" and `flutter test` is green.
  - Package, from `packages/mobile/packages/ios_liquid_glass`: `flutter analyze` and `flutter test`.
  - Example, from `packages/mobile/packages/ios_liquid_glass/example`: `flutter analyze` and `flutter test`.
  - Harness, from `packages/mobile`: `python3 -m unittest discover tool/glass_lab/harness/tests` prints OK.
  - `flutter test` prints a long SkSL error about `liquid_glass_geometry_blended` ("initializers are not permitted on arrays"). It is known and harmless; tests still pass.
- **Operator and the simulator**
  - Operator is used only through its debug glass lab. Never pair it, never enter a password, never touch real sessions or desktops.
  - When a system prompt appears, the only acceptable answers are "Don't Allow" or "Not Now".
- **Judging glass.** Judge only by lab measurements, never by eye. When a number looks wrong, open the screenshots.

## Review Focus

1. **An accessibility mode left on after an interrupted run**, for example a `tune` or `a11y` run stopped with Ctrl-C or a failed launch. Expected: the simulator always ends with all three modes off, or every later capture is wrong. Pinned by `AccessibilityTests.test_every_mode_is_switched_off_even_when_the_launch_fails` in Task 8, and by `cmd_tune` restoring `none` in a `finally` (Task 10).
2. **Edge-scene content drifting from native** because the scroll image loads after the first layout and the initial offset clamps to 0. Expected: Flutter and native content line up to 0 px. Pinned by the shift measurement in Task 7, Step 12, which must print `shift px 0` for all three styles.
3. **A `GlassEffect` switched to or from `Glass.identity` losing its child's state.** 2B animates exactly this switch. Expected: a stateful child keeps its state. Pinned by `switching to and from identity keeps the child state` in Task 4.
4. **A stale launch file or stale overrides.** A tune candidate's `material` map must never leak into the next launch. Expected: the app deletes `launch.json` as it reads it, and `GlassMaterialOverride` is ignored outside debug builds. Pinned by `consume reads the launch file once and deletes it` in Task 7, and by `GlassMaterialOverride.of` returning `{}` when `kDebugMode` is false.
5. **A table rewrite that drops or reorders rows.** `--write` rewrites whole Dart files. Expected: the committed tables round-trip byte for byte, and every appearance, row and anchor is present. Pinned by `test_the_committed_tables_are_in_writer_format` and `test_the_committed_tables_parse_with_every_row` in Task 10.

---

## File map

| Path (under `packages/mobile/`) | Responsibility | Task |
|---|---|---|
| `packages/ios_liquid_glass/` | The package, renamed from `packages/liquid_glass_renderer/` | 1 |
| `packages/ios_liquid_glass/pubspec.yaml` | Name, plugin class, shaders | 1, 2, 6 |
| `packages/ios_liquid_glass/lib/ios_liquid_glass.dart` | Public exports | 1, 2, 4, 6 |
| `packages/ios_liquid_glass/ios/ios_liquid_glass.podspec`, `ios/Classes/IosLiquidGlassPlugin.swift` | Accessibility `EventChannel` | 2 |
| `packages/ios_liquid_glass/lib/src/accessibility/glass_accessibility.dart` | `GlassAccessibilityData`, `GlassAccessibility` | 2 |
| `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag` | iOS 27 final render model | 3 |
| `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart` | Tone, tint, hairline and specular fields | 3 |
| `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart` | Uniform packing | 3 |
| `packages/ios_liquid_glass/lib/src/api/*.dart` | `Glass`, `GlassShape`, `GlassTheme`, `GlassEffect` and `GlassEffectScope`, `GlassEffectContainer`, `GlassDimming`, `GlassForeground` | 4 |
| `packages/ios_liquid_glass/lib/src/material/{glass_material,ios27,glass_material_override}.dart` | Material model, tuned table, debug overrides | 4 |
| `lib/core/widgets/glass/{glass_surface,glass_scope}.dart`, `lib/main.dart` | Operator adapters and `GlassTheme` at the root | 5 |
| `packages/ios_liquid_glass/lib/src/scroll_edge/*.dart`, `lib/assets/shaders/scroll_edge_blur.frag` | Scroll edge effect with styles | 6 |
| `packages/ios_liquid_glass/lib/src/material/{scroll_edge_material,ios27_scroll_edge}.dart` | Scroll edge material and table | 6 |
| `packages/ios_liquid_glass/example/` | Example app, lab scenes, perf scenes, probes | 7 |
| `tool/glass_lab/harness/{build,record,lab,manifest,analyze}.py` | Example target, `--flutter`, `measures`, new commands | 7, 8, 9, 10 |
| `tool/glass_lab/harness/probe.py` | `perf` and `a11y` probes | 8 |
| `tool/glass_lab/harness/{tune,material_table}.py` | Automatic tuning and table writer | 10 |
| `tool/glass_lab/harness/flip.py` | Flip analysis | 9 |
| `tool/glass_lab/native/GlassLab/MaterialScenes.swift`, `tool/glass_lab/scenes.json` | Pre-scrolled edge scenes, a third flip block, pinned regions | 7 |
| `docs/liquid_glass/02a-looks/flip-spike.md`, `tuning-log.md`, `results.md`, `operator-baseline.json` | Spike write-up, tuning log, final measurements | 9, 11, 12 |
| `docs/liquid_glass/ROADMAP.md`, package `README.md`, `FORK.md`, `CHANGELOG.md`, example `README.md`, `tool/glass_lab/README.md`, root `CLAUDE.md` | Documents | 13 |

**Task order and why.**
1. Rename.
2. Plugin.
3. Shader and settings.
4. API and material. Needs 2 and 3.
5. Operator adapters. Needs 4, and must land before 6 so Operator's `GlassTheme` supplies the scroll edge tint.
6. Scroll edge move.
7. Example app and lab target. Needs 4 and 6, so every example file is final when written.
8. Probes.
9. Flip spike and frame cost.
10. Tune tool.
11. Tuning campaign.
12. Verification.
13. Documents.

---

### Task 1: Rename the package to `ios_liquid_glass`

**Files:**
- Move: `packages/liquid_glass_renderer/` → `packages/ios_liquid_glass/`, and `lib/liquid_glass_renderer.dart` → `lib/ios_liquid_glass.dart`
- Modify: every Dart file that imports the package (23 files: package `lib/`, package `test/`, and 7 in Operator), `packages/ios_liquid_glass/pubspec.yaml`, `pubspec.yaml`
- Modify: `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart`, `lib/src/liquid_shape.dart` (`EquatableMixin` → `Equatable`)

**Interfaces:**
- Produces: package `ios_liquid_glass`, version `0.1.0`, library `package:ios_liquid_glass/ios_liquid_glass.dart` with the same exports as before; shader asset root `packages/ios_liquid_glass/`.

- [ ] **Step 1: Create the worktree** (skip if the controller already made it)

```bash
git -C /Users/omaraly/development/AI/Operator worktree add ../Operator-ios-liquid-glass -b feat/ios-liquid-glass-2a development
cd /Users/omaraly/development/AI/Operator-ios-liquid-glass/packages/mobile
flutter pub get
```

- [ ] **Step 2: Save the rename script** into the session scratchpad (not the repo) as `rename_package.py`:

```python
import re
import subprocess
import sys
from pathlib import Path

MOBILE = Path(sys.argv[1]).resolve()
OLD, NEW = "liquid_glass_renderer", "ios_liquid_glass"
PACKAGE = MOBILE / "packages" / NEW

subprocess.run(["git", "mv", f"packages/{OLD}", f"packages/{NEW}"], cwd=MOBILE, check=True)
subprocess.run(["git", "mv", f"packages/{NEW}/lib/{OLD}.dart", f"packages/{NEW}/lib/{NEW}.dart"], cwd=MOBILE, check=True)

REPLACEMENTS = [
    (f"package:{OLD}/{OLD}.dart", f"package:{NEW}/{NEW}.dart"),
    (f"package:{OLD}/src/", f"package:{NEW}/src/"),
    (f"library {OLD};", f"library {NEW};"),
    (f"{{@macro {OLD}.", f"{{@macro {NEW}."),
    (f"{{@template {OLD}.", f"{{@template {NEW}."),
    (f"'packages/{OLD}/'", f"'packages/{NEW}/'"),
]


def rewrite(path):
    text = path.read_text()
    updated = text
    for old, new in REPLACEMENTS:
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated)
        return True
    return False


changed = [p for root in (PACKAGE / "lib", PACKAGE / "test", MOBILE / "lib", MOBILE / "test") for p in root.rglob("*.dart") if rewrite(p)]

pubspec = PACKAGE / "pubspec.yaml"
text = pubspec.read_text()
text = re.sub(r"^name: .*$", f"name: {NEW}", text, count=1, flags=re.M)
text = re.sub(r"^description: .*$", 'description: "iOS 27 Liquid Glass for Flutter, measured against native. Forked from liquid_glass_renderer, see FORK.md."', text, count=1, flags=re.M)
text = re.sub(r"^version: .*$", "version: 0.1.0", text, count=1, flags=re.M)
pubspec.write_text(text)

app = MOBILE / "pubspec.yaml"
text = app.read_text()
text = text.replace(f"  - packages/{OLD}\n", f"  - packages/{NEW}\n").replace(f"  {OLD}:\n", f"  {NEW}:\n")
app.write_text(text)

print(f"rewrote {len(changed)} dart files")
```

- [ ] **Step 3: Run it** from `packages/mobile`

Run: `python3 <scratchpad>/rename_package.py .`
Expected: `rewrote 23 dart files`

- [ ] **Step 4: Make the library file analyse clean.** In `packages/ios_liquid_glass/lib/ios_liquid_glass.dart`, replace the line `library ios_liquid_glass;` with `library;`.

- [ ] **Step 5: Use `Equatable` instead of the deprecated mixin**
  - In `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart`, replace `class LiquidGlassSettings with EquatableMixin {` with `class LiquidGlassSettings with Equatable {`.
  - In `packages/ios_liquid_glass/lib/src/liquid_shape.dart`, replace `sealed class LiquidShape extends OutlinedBorder with EquatableMixin {` with `sealed class LiquidShape extends OutlinedBorder with Equatable {`.

- [ ] **Step 6: Resolve and run the gates**

```bash
flutter pub get
flutter analyze
flutter test
cd packages/ios_liquid_glass && flutter analyze && flutter test && cd ../..
```

Expected: both analyses print "No issues found!". The package tests pass. The app suite passes with the same number of tests as before the rename. `pubspec.lock` does not change: `git diff --stat pubspec.lock` prints nothing.

- [ ] **Step 7: Check nothing still names the old package**

Run: `grep -rn liquid_glass_renderer --include='*.dart' --include='*.yaml' --include='*.swift' --include='*.py' . | grep -v '/build/' | grep -v '.dart_tool'`
Expected: exactly one hit, the `description:` line of `packages/ios_liquid_glass/pubspec.yaml` ("Forked from liquid_glass_renderer, see FORK.md."). `FORK.md`, `CHANGELOG.md` and `README.md` keep the old name on purpose; Task 13 rewrites the README.

- [ ] **Step 8: Commit**

```bash
git add -A packages/ios_liquid_glass pubspec.yaml lib test
git commit -m "refactor(mobile): rename the liquid glass renderer to ios_liquid_glass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: iOS plugin for the accessibility settings Flutter cannot see

**Files:**
- Create: `packages/ios_liquid_glass/ios/ios_liquid_glass.podspec`
- Create: `packages/ios_liquid_glass/ios/Classes/IosLiquidGlassPlugin.swift`
- Create: `packages/ios_liquid_glass/lib/src/accessibility/glass_accessibility.dart`
- Create: `packages/ios_liquid_glass/test/glass_accessibility_test.dart`
- Modify: `packages/ios_liquid_glass/pubspec.yaml`, `packages/ios_liquid_glass/lib/ios_liquid_glass.dart`, `ios/Podfile.lock` (Operator's, regenerated by the build)

**Interfaces:**
- Produces:
  - `EventChannel('ios_liquid_glass/accessibility')`, emitting maps `{reduceTransparency: bool, increaseContrast: bool, reduceMotion: bool}` on listen and on every change;
  - `GlassAccessibilityData({reduceTransparency, increaseContrast, reduceMotion})`, with `fromMap`, `merge` and value equality;
  - `GlassAccessibility.channel`, `GlassAccessibility.platform` (`ValueNotifier<GlassAccessibilityData>`), `GlassAccessibility.debugOverride`, `GlassAccessibility.ensureListening()`, `GlassAccessibility.of(BuildContext)`, and the `@visibleForTesting` `GlassAccessibility.debugReset()`.

- [ ] **Step 1: Write the failing test** `packages/ios_liquid_glass/test/glass_accessibility_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  tearDown(GlassAccessibility.debugReset);

  Future<GlassAccessibilityData> read(WidgetTester tester, {MediaQueryData media = const MediaQueryData()}) async {
    late GlassAccessibilityData data;
    await tester.pumpWidget(
      MediaQuery(
        data: media,
        child: Builder(builder: (context) {
          data = GlassAccessibility.of(context);
          return const SizedBox();
        }),
      ),
    );
    return data;
  }

  test('parses the channel map and merges with or', () {
    final data = GlassAccessibilityData.fromMap({'reduceTransparency': true, 'increaseContrast': false});
    expect(data, const GlassAccessibilityData(reduceTransparency: true));
    expect(data.merge(const GlassAccessibilityData(reduceMotion: true)), const GlassAccessibilityData(reduceTransparency: true, reduceMotion: true));
  });

  testWidgets('without the plugin, contrast and motion come from MediaQuery and transparency is off', (tester) async {
    final data = await read(tester, media: const MediaQueryData(highContrast: true, disableAnimations: true));
    expect(data, const GlassAccessibilityData(increaseContrast: true, reduceMotion: true));
  });

  testWidgets('on iOS the channel supplies reduce transparency and updates live', (tester) async {
    late MockStreamHandlerEventSink sink;
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      GlassAccessibility.channel,
      MockStreamHandler.inline(onListen: (arguments, events) {
        sink = events;
        events.success({'reduceTransparency': true, 'increaseContrast': false, 'reduceMotion': false});
      }),
    );
    await read(tester);
    await tester.pump();
    expect(GlassAccessibility.platform.value.reduceTransparency, isTrue);
    sink.success({'reduceTransparency': false, 'increaseContrast': true, 'reduceMotion': false});
    await tester.pump();
    expect(await read(tester), const GlassAccessibilityData(increaseContrast: true));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a debug override wins', (tester) async {
    GlassAccessibility.debugOverride = const GlassAccessibilityData(reduceTransparency: true);
    expect(await read(tester, media: const MediaQueryData(highContrast: true)), const GlassAccessibilityData(reduceTransparency: true));
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run (from `packages/ios_liquid_glass`): `flutter test test/glass_accessibility_test.dart`
Expected: compile errors, because `GlassAccessibility` and `GlassAccessibilityData` are undefined.

- [ ] **Step 3: Write the Dart side** `packages/ios_liquid_glass/lib/src/accessibility/glass_accessibility.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@immutable
class GlassAccessibilityData {
  const GlassAccessibilityData({
    this.reduceTransparency = false,
    this.increaseContrast = false,
    this.reduceMotion = false,
  });

  factory GlassAccessibilityData.fromMap(Map<Object?, Object?> map) => GlassAccessibilityData(
    reduceTransparency: map['reduceTransparency'] == true,
    increaseContrast: map['increaseContrast'] == true,
    reduceMotion: map['reduceMotion'] == true,
  );

  final bool reduceTransparency;
  final bool increaseContrast;
  final bool reduceMotion;

  GlassAccessibilityData merge(GlassAccessibilityData other) => GlassAccessibilityData(
    reduceTransparency: reduceTransparency || other.reduceTransparency,
    increaseContrast: increaseContrast || other.increaseContrast,
    reduceMotion: reduceMotion || other.reduceMotion,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassAccessibilityData &&
      other.reduceTransparency == reduceTransparency &&
      other.increaseContrast == increaseContrast &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(reduceTransparency, increaseContrast, reduceMotion);
}

sealed class GlassAccessibility {
  static const EventChannel channel = EventChannel('ios_liquid_glass/accessibility');

  static final ValueNotifier<GlassAccessibilityData> platform = ValueNotifier(const GlassAccessibilityData());

  static GlassAccessibilityData? debugOverride;

  static StreamSubscription<Object?>? _subscription;

  static void ensureListening() {
    if (_subscription != null || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _subscription = channel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) platform.value = GlassAccessibilityData.fromMap(event);
      },
      onError: (Object _) {},
    );
  }

  @visibleForTesting
  static Future<void> debugReset() async {
    await _subscription?.cancel();
    _subscription = null;
    debugOverride = null;
    platform.value = const GlassAccessibilityData();
  }

  static GlassAccessibilityData of(BuildContext context) {
    final override = debugOverride;
    if (override != null) return override;
    ensureListening();
    final media = GlassAccessibilityData(
      increaseContrast: MediaQuery.maybeHighContrastOf(context) ?? false,
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    return media.merge(platform.value);
  }
}
```

- [ ] **Step 4: Export it.** In `packages/ios_liquid_glass/lib/ios_liquid_glass.dart`, add this as the first `export` line:

```dart
export 'src/accessibility/glass_accessibility.dart' show GlassAccessibility, GlassAccessibilityData;
```

- [ ] **Step 5: Run the test again**

Run: `flutter test test/glass_accessibility_test.dart`
Expected: 4 tests pass.

- [ ] **Step 6: Write the iOS plugin.** First `packages/ios_liquid_glass/ios/ios_liquid_glass.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'ios_liquid_glass'
  s.version          = '0.1.0'
  s.summary          = 'iOS 27 Liquid Glass for Flutter.'
  s.description      = 'Reads the iOS accessibility settings that Flutter does not expose.'
  s.homepage         = 'https://github.com/whynotmake-it/flutter_liquid_glass'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Omar Aly' => 'omarkarim5555@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
```

Then `packages/ios_liquid_glass/ios/Classes/IosLiquidGlassPlugin.swift`:

```swift
import Flutter
import UIKit

public class IosLiquidGlassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    private static let notifications: [Notification.Name] = [
        UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
        UIAccessibility.reduceMotionStatusDidChangeNotification,
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterEventChannel(name: "ios_liquid_glass/accessibility", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(IosLiquidGlassPlugin())
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        for name in Self.notifications {
            NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: name, object: nil)
        }
        send()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        sink = nil
        return nil
    }

    @objc private func settingsChanged() {
        send()
    }

    private func send() {
        sink?([
            "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
            "increaseContrast": UIAccessibility.isDarkerSystemColorsEnabled,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled,
        ])
    }
}
```

- [ ] **Step 7: Declare the plugin.** In `packages/ios_liquid_glass/pubspec.yaml`, add the `plugin:` block as the first key under `flutter:`, so that section reads:

```yaml
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: IosLiquidGlassPlugin
  shaders:
    - lib/assets/shaders/liquid_glass_geometry_blended.frag
    - lib/assets/shaders/liquid_glass_final_render.frag
    - lib/assets/shaders/fake_glass_color.frag
```

- [ ] **Step 8: Prove Operator builds with the plugin under Xcode 27**

Run (from `packages/mobile`): `flutter pub get && python3 tool/glass_lab/harness/lab.py build flutter`. Until Task 7 renames the targets, `flutter` means Operator.
Expected:
- the build finishes with `built for 708879DD-...`;
- `git diff ios/Podfile.lock` shows an `ios_liquid_glass` pod added;
- the output may warn that the plugin lacks Swift Package Manager support. That is accepted (ruling 13); do not enable SPM.

- [ ] **Step 9: Run the gates.** Package: `flutter analyze` and `flutter test`. App, from `packages/mobile`: `flutter analyze` and `flutter test`.

- [ ] **Step 10: Commit**

```bash
git add packages/ios_liquid_glass ios/Podfile.lock
git commit -m "feat(mobile): ios_liquid_glass reads Reduce Transparency through an iOS plugin

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The iOS 27 final render model

**Files:**
- Replace: `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag`
- Replace: `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart`
- Modify: `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart` (the `_updateShaderSettings` method)
- Delete: `packages/ios_liquid_glass/lib/assets/shaders/render.glsl`. Only the old final shader included it.
- Replace: `packages/ios_liquid_glass/test/liquid_glass_settings_test.dart`

**Interfaces:**
- Produces `LiquidGlassSettings` fields, all `double`, with defaults that leave the backdrop untouched:
  - `toneBlack` 0, `toneMid` 0.5, `toneWhite` 1;
  - `tintBlack` 1, `tintWhite` 1;
  - `hairline` 0, `hairlineWidth` 1, `hairlineDark` 0, `hairlineLight` 1;
  - `specular` 0, `specularWidth` 1.5, `specularPower` 2, `specularFill` 0.4.
- Produces `effectiveToneBlack`, `effectiveToneMid` and `effectiveToneWhite`, which fade to 0, 0.5 and 1 as `visibility` goes to 0, plus `effectiveHairline` and `effectiveSpecular`. The fields also go into `copyWith` and `props`.
- The shader's uniforms, in order: `uSize`, `uGeometryOffset`, `uGeometrySize`, then the look uniforms below, then samplers 0 (`uBackgroundTexture`) and 1 (`uGeometryTexture`).

  | Uniform | Floats (from index 6) | Contents |
  |---|---|---|
  | `uGlassColor` | 6–9 | tint rgb, tint amount (alpha) |
  | `uOptics` | 10–13 | thickness px, dispersion, saturation, 0 |
  | `uTone` | 14–17 | black, mid, white, 0 |
  | `uTintTone` | 18–21 | tint at black, tint at white, 0, 0 |
  | `uEdge` | 22–25 | hairline, hairline width px, hairline dark, hairline light |
  | `uLight` | 26–29 | specular, specular width px, specular power, specular fill |
  | `uLightDirection` | 30–31 | cos, sin of `lightAngle` |

- Consumes: the geometry texture, unchanged. Channels RG hold the displacement (max `thickness × 10`), B the height normalised to thickness, and A the coverage.

- [ ] **Step 1: Write the failing test.** Replace `packages/ios_liquid_glass/test/liquid_glass_settings_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

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
    expect([settings.hairline, settings.specular], [0, 0]);
  });

  test('visibility fades the tone curve and edge light towards no effect', () {
    const settings = LiquidGlassSettings(
      visibility: 0.5,
      toneBlack: 0.2,
      toneMid: 0.7,
      toneWhite: 0.6,
      hairline: 0.4,
      specular: 0.8,
    );
    expect(settings.effectiveToneBlack, closeTo(0.1, 1e-9));
    expect(settings.effectiveToneMid, closeTo(0.6, 1e-9));
    expect(settings.effectiveToneWhite, closeTo(0.8, 1e-9));
    expect(settings.effectiveHairline, closeTo(0.2, 1e-9));
    expect(settings.effectiveSpecular, closeTo(0.4, 1e-9));
  });

  test('copyWith and equality cover every iOS look field', () {
    const base = LiquidGlassSettings();
    final changed = [
      base.copyWith(toneBlack: 0.1),
      base.copyWith(toneMid: 0.4),
      base.copyWith(toneWhite: 0.9),
      base.copyWith(tintBlack: 0.8),
      base.copyWith(tintWhite: 1.1),
      base.copyWith(hairline: 0.3),
      base.copyWith(hairlineWidth: 2),
      base.copyWith(hairlineDark: 0.2),
      base.copyWith(hairlineLight: 0.8),
      base.copyWith(specular: 0.5),
      base.copyWith(specularWidth: 3),
      base.copyWith(specularPower: 4),
      base.copyWith(specularFill: 0.1),
    ];
    for (final settings in changed) {
      expect(settings, isNot(base));
    }
    expect(base.copyWith(toneMid: 0.4).copyWith(hairline: 0.3).toneMid, 0.4);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run (from `packages/ios_liquid_glass`): `flutter test test/liquid_glass_settings_test.dart`
Expected: compile errors for `toneBlack`, `tintBlack`, `hairline` and the other new fields.

- [ ] **Step 3: Replace the settings.** Replace `packages/ios_liquid_glass/lib/src/liquid_glass_settings.dart` with the version below. It is upstream's file with the new fields added; upstream's dartdoc is kept.

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
    this.hairline = 0,
    this.hairlineWidth = 1,
    this.hairlineDark = 0,
    this.hairlineLight = 1,
    this.specular = 0,
    this.specularWidth = 1.5,
    this.specularPower = 2,
    this.specularFill = 0.4,
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

  final double hairline;

  double get effectiveHairline => hairline * visibility;

  final double hairlineWidth;

  final double hairlineDark;

  final double hairlineLight;

  final double specular;

  double get effectiveSpecular => specular * visibility;

  final double specularWidth;

  final double specularPower;

  final double specularFill;

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
    double? hairline,
    double? hairlineWidth,
    double? hairlineDark,
    double? hairlineLight,
    double? specular,
    double? specularWidth,
    double? specularPower,
    double? specularFill,
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
        hairline: hairline ?? this.hairline,
        hairlineWidth: hairlineWidth ?? this.hairlineWidth,
        hairlineDark: hairlineDark ?? this.hairlineDark,
        hairlineLight: hairlineLight ?? this.hairlineLight,
        specular: specular ?? this.specular,
        specularWidth: specularWidth ?? this.specularWidth,
        specularPower: specularPower ?? this.specularPower,
        specularFill: specularFill ?? this.specularFill,
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
        hairline,
        hairlineWidth,
        hairlineDark,
        hairlineLight,
        specular,
        specularWidth,
        specularPower,
        specularFill,
      ];
}
```

- [ ] **Step 4: Run the settings test**

Run: `flutter test test/liquid_glass_settings_test.dart`
Expected: 6 tests pass.

- [ ] **Step 5: Replace the final render shader** `packages/ios_liquid_glass/lib/assets/shaders/liquid_glass_final_render.frag`. Keep the file name so the renderer wiring (`ShaderKeys.liquidGlassRender`) is untouched.

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
uniform vec4 uTintTone;
uniform vec4 uEdge;
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
    if (geometryData.a < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    float thickness = max(uOptics.x, 0.001);
    vec2 displacement = decodeDisplacement(geometryData, thickness * 10.0);
    float heightNorm = clamp(geometryData.b, 0.0, 1.0);
    float edgeDistance = thickness * (1.0 - sqrt(max(0.0, 1.0 - heightNorm * heightNorm)));
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

    vec3 tintTone = clamp(uGlassColor.rgb * mix(uTintTone.x, uTintTone.y, luminance), 0.0, 1.0);
    color = mix(color, tintTone, uGlassColor.a);

    vec3 hairlineColor = mix(vec3(uEdge.w), vec3(uEdge.z), smoothstep(0.35, 0.65, luminance));
    float hairlineMask = 1.0 - smoothstep(0.0, max(uEdge.y, 0.001), edgeDistance);
    color = mix(color, hairlineColor, clamp(uEdge.x * hairlineMask, 0.0, 1.0));

    vec2 normal = length(displacement) > 0.0001 ? normalize(displacement) : vec2(0.0);
    float power = max(uLight.z, 0.001);
    float key = pow(max(0.0, dot(normal, uLightDirection)), power);
    float fill = uLight.w * pow(max(0.0, dot(normal, -uLightDirection)), power);
    float specularMask = 1.0 - smoothstep(0.0, max(uLight.y, 0.001), edgeDistance);
    color = clamp(color + vec3((key + fill) * uLight.x * specularMask), 0.0, 1.0);

    float alpha = geometryData.a;
    fragColor = vec4(color * alpha, alpha);
}
```

The stages, in order:
1. **Dispersion**, rim only: 3 taps, red × (1 + k·bevel) and blue × (1 − k·bevel).
2. **Tone curve**: the quadratic through (0, black), (0.5, mid) and (1, white) on Rec. 709 luminance, with chroma × saturation.
3. **Tint**: `tint.rgb × mix(tintBlack, tintWhite, L)`, mixed in by the tint amount.
4. **Adaptive hairline**: dark over bright content, light over dark content.
5. **Dual-lobe specular** in the rim band: a key lobe along the light, and a fill lobe against it.

- [ ] **Step 6: Pack the new uniforms.** In `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart`, replace this method:

```dart
  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness * devicePixelRatio,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        )
        ..setFloat(settings.fillRatio);
    });
  }
```

with:

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
          0,
          0,
          settings.effectiveHairline,
          settings.hairlineWidth * devicePixelRatio,
          settings.hairlineDark,
          settings.hairlineLight,
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

- [ ] **Step 7: Delete the dead helper.** Run `git rm packages/ios_liquid_glass/lib/assets/shaders/render.glsl`, then check that `grep -rn 'render.glsl' packages/ios_liquid_glass/lib` prints nothing.

- [ ] **Step 8: Run the gates.** Package: `flutter analyze` and `flutter test`. App, from `packages/mobile`: `flutter analyze` and `flutter test`. Operator still draws through its own `GlassStyle` until Task 5; its tests do not read pixels, so they stay green.

- [ ] **Step 9: Prove the shader compiles for Impeller**

Run (from `packages/mobile`): `python3 tool/glass_lab/harness/lab.py build flutter`
Expected: it ends with `built for 708879DD-...`. A shader error fails this build with an `impellerc` message that names `liquid_glass_final_render.frag`. Pixels are checked in Task 7.

- [ ] **Step 10: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "feat(mobile): ios_liquid_glass final render step becomes the iOS 27 tone, tint, hairline and specular model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: SwiftUI-style API and the iOS 27 material system

**Files:**
- Create in `packages/ios_liquid_glass/lib/src/api/`: `glass.dart`, `glass_shape.dart`, `glass_theme.dart`, `glass_effect.dart`, `glass_effect_container.dart`, `glass_dimming.dart`, `glass_foreground.dart`
- Create in `packages/ios_liquid_glass/lib/src/material/`: `glass_material.dart`, `ios27.dart` (the seed table), `glass_material_override.dart`
- Create in `packages/ios_liquid_glass/test/`: `glass_test.dart`, `glass_material_test.dart`, `glass_effect_test.dart`
- Modify: `packages/ios_liquid_glass/lib/ios_liquid_glass.dart`

**Interfaces:**
- Consumes: `LiquidGlassSettings` from Task 3, and `GlassAccessibility` / `GlassAccessibilityData` from Task 2.
- Produces:
  - **`Glass`**: `Glass.regular`, `Glass.clear`, `Glass.identity`, `.tint(Color?)`, `.interactive([bool])`, `kind` (`GlassKind {regular, clear, identity}`), `tintColor`, `isInteractive`, and value equality.
  - **`GlassShape`**, sealed: `GlassShape.capsule()`, `.circle()`, `.rect(double cornerRadius)`, `.superellipse(double cornerRadius)`, each with `liquidShape` (`LiquidShape`) and `border` (`ShapeBorder`).
  - **`GlassThemeData({Brightness? brightness, Color? accent, Color? scrollEdgeTint})`** and **`GlassTheme({data, child})`**, with `GlassTheme.of(context)` and `GlassTheme.brightnessOf(context)`. The brightness falls back to `MediaQuery` platform brightness, then light.
  - **`GlassEffect({Glass glass = Glass.regular, GlassShape shape = const GlassShape.capsule(), double? sideHint, required Widget child})`**, with `GlassEffect.fallbackSide = 88`. It measures itself and resolves its material.
    - Inside a `GlassEffectContainer` that holds an equal `Glass`, it draws `LiquidGlass.grouped`; otherwise `LiquidGlass.withOwnLayer`.
    - `Glass.identity` draws the child alone, keeping the same child element.
  - **`GlassEffectScope`**: an inherited widget carrying the effect's `Glass`, read with `GlassEffectScope.maybeOf(context)`.
  - **`GlassEffectContainer({double spacing = 20, Glass glass = Glass.regular, double side = 88, required Widget child})`**, with `GlassEffectContainer.glassOf(context)`.
  - **`GlassDimming({double opacity = 0.35, GlassShape shape = const GlassShape.capsule(), required Widget child})`**.
  - **`GlassForeground({required Widget child})`**, with `GlassForeground.colorOf(context)` and the constants `dark` `#FFFFFFFF`, `light` `#FF000000`, `tinted` `#FFFFFFFF`.
  - **`GlassMaterial(Map<String, double> values)`**:
    - `GlassMaterial.defaults`, `GlassMaterial.anchors` `[44, 88, 200]`;
    - `operator []`, `lerp`, `withOverrides`, `toSettings({Color? tint})` and `shadows`;
    - `GlassMaterial.rowFor(Glass, GlassAccessibilityData)`, returning `regular`, `clear`, `tinted`, `reduceTransparency` or `increaseContrast`;
    - `GlassMaterial.resolve({required Glass glass, required double shorterSide, required Brightness brightness, GlassAccessibilityData accessibility = const GlassAccessibilityData(), Map<String, Map<String, double>> table = ios27Table})`.
  - **`ios27Table`**: keys `'<dark|light>.<row>.<44|88|200>'`. A missing field falls back to `GlassMaterial.defaults`.
  - **`GlassMaterialOverride({required Map<String, double> values, required Widget child})`**, with `GlassMaterialOverride.of(context)`. It returns `{}` outside debug builds.

- [ ] **Step 1: Write the failing tests**
  - `packages/ios_liquid_glass/test/glass_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  const accent = Color(0xFF1ACB64);

  test('variants are distinct values', () {
    expect(Glass.regular.kind, GlassKind.regular);
    expect(Glass.clear.kind, GlassKind.clear);
    expect(Glass.identity.kind, GlassKind.identity);
    expect(Glass.regular, isNot(Glass.clear));
  });

  test('tint and interactive build equal values from equal inputs', () {
    expect(Glass.regular.tint(accent), Glass.regular.tint(accent));
    expect(Glass.regular.tint(accent).hashCode, Glass.regular.tint(accent).hashCode);
    expect(Glass.regular.tint(accent), isNot(Glass.regular));
    expect(Glass.regular.interactive(), isNot(Glass.regular));
    expect(Glass.regular.interactive().interactive(false), Glass.regular);
  });

  test('modifiers keep each other', () {
    final glass = Glass.clear.tint(accent).interactive();
    expect(glass.kind, GlassKind.clear);
    expect(glass.tintColor, accent);
    expect(glass.isInteractive, isTrue);
    expect(glass.tint(null).isInteractive, isTrue);
  });
}
```

  - `packages/ios_liquid_glass/test/glass_material_test.dart`:

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
    'dark.tinted.88': {'tintAmount': 0.9},
    'dark.clear.88': {'frost': 1.0},
    'dark.reduceTransparency.88': {'toneBlack': 0.16, 'toneWhite': 0.16},
    'dark.increaseContrast.88': {'hairline': 0.9},
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
      'hairline': 0.3,
      'specular': 0.5,
    });
    final settings = material.toSettings(tint: accent);
    expect(settings.thickness, 20);
    expect(settings.chromaticAberration, 0.03);
    expect(settings.blur, 9);
    expect(settings.saturation, 1.4);
    expect([settings.toneBlack, settings.toneMid, settings.toneWhite], [0.1, 0.4, 0.8]);
    expect([settings.tintBlack, settings.tintWhite], [0.8, 1.1]);
    expect(settings.glassColor, accent.withValues(alpha: 0.9));
    expect(settings.hairline, 0.3);
    expect(settings.specular, 0.5);
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
}
```

  - `packages/ios_liquid_glass/test/glass_effect_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:ios_liquid_glass/src/shaders.dart';

const _accent = Color(0xFF1ACB64);

Widget _host(Widget child, {Brightness brightness = Brightness.dark, Map<String, double> overrides = const {}}) => MaterialApp(
  home: GlassTheme(
    data: GlassThemeData(brightness: brightness, accent: _accent),
    child: GlassMaterialOverride(values: overrides, child: Center(child: child)),
  ),
);

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(width: 150, height: 44, child: Text('$count'));
}

void main() {
  isLocalTest = true;

  testWidgets('draws its own layer with the material resolved for its measured size', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88))));
    await tester.pump();
    final layer = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer));
    final expected = GlassMaterial.resolve(glass: Glass.regular, shorterSide: 88, brightness: Brightness.dark);
    expect(layer.settings, expected.toSettings());
  });

  testWidgets('re-resolves when the appearance flips', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88))));
    await tester.pump();
    final dark = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), brightness: Brightness.light));
    await tester.pump();
    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings, isNot(dark));
  });

  testWidgets('joins a container that holds the same glass', (tester) async {
    await tester.pumpWidget(_host(const GlassEffectContainer(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [GlassEffect(child: SizedBox.square(dimension: 64)), GlassEffect(child: SizedBox.square(dimension: 64))],
      ),
    )));
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.byType(LiquidGlassBlendGroup), findsOneWidget);
  });

  testWidgets('tinted glass inside a regular container keeps its own layer', (tester) async {
    await tester.pumpWidget(_host(GlassEffectContainer(
      child: GlassEffect(glass: Glass.regular.tint(_accent), child: const SizedBox.square(dimension: 64)),
    )));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), _accent);
  });

  testWidgets('identity glass draws no glass', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: SizedBox(width: 10, height: 10))));
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('switching to and from identity keeps the child state', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: _Counter())));
    tester.state<_CounterState>(find.byType(_Counter)).count = 7;
    await tester.pumpWidget(_host(const GlassEffect(child: _Counter())));
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
    await tester.pumpWidget(_host(const GlassEffect(glass: Glass.identity, child: _Counter())));
    expect(tester.state<_CounterState>(find.byType(_Counter)).count, 7);
  });

  testWidgets('debug overrides reach the renderer', (tester) async {
    await tester.pumpWidget(_host(const GlassEffect(child: SizedBox(width: 250, height: 88)), overrides: const {'frost': 17}));
    await tester.pump();
    expect(tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.blur, 17);
  });

  testWidgets('foreground is white in dark, black in light and white on tinted glass', (tester) async {
    Color? seen;
    Widget probe() => GlassForeground(child: Builder(builder: (context) {
      seen = DefaultTextStyle.of(context).style.color;
      return const SizedBox(width: 40, height: 20);
    }));
    await tester.pumpWidget(_host(GlassEffect(child: probe())));
    expect(seen, GlassForeground.dark);
    await tester.pumpWidget(_host(GlassEffect(child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.light);
    await tester.pumpWidget(_host(GlassEffect(glass: Glass.regular.tint(_accent), child: probe()), brightness: Brightness.light));
    expect(seen, GlassForeground.tinted);
  });

  testWidgets('dimming paints the 35% black layer in the glass shape', (tester) async {
    await tester.pumpWidget(_host(const GlassDimming(child: SizedBox(width: 250, height: 88))));
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(GlassDimming), matching: find.byType(DecoratedBox)));
    final decoration = box.decoration as ShapeDecoration;
    expect(decoration.color, const Color(0xFF000000).withValues(alpha: 0.35));
    expect(decoration.shape, const StadiumBorder());
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run (from `packages/ios_liquid_glass`): `flutter test test/glass_test.dart test/glass_material_test.dart test/glass_effect_test.dart`
Expected: compile errors, because `Glass`, `GlassMaterial`, `GlassEffect` and the rest are undefined.

- [ ] **Step 3: Write the value types**
  - `lib/src/api/glass.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum GlassKind { regular, clear, identity }

@immutable
class Glass {
  const Glass._(this.kind, {this.tintColor, this.isInteractive = false});

  static const Glass regular = Glass._(GlassKind.regular);
  static const Glass clear = Glass._(GlassKind.clear);
  static const Glass identity = Glass._(GlassKind.identity);

  final GlassKind kind;
  final Color? tintColor;
  final bool isInteractive;

  Glass tint(Color? color) => Glass._(kind, tintColor: color, isInteractive: isInteractive);

  Glass interactive([bool enabled = true]) => Glass._(kind, tintColor: tintColor, isInteractive: enabled);

  @override
  bool operator ==(Object other) =>
      other is Glass && other.kind == kind && other.tintColor == tintColor && other.isInteractive == isInteractive;

  @override
  int get hashCode => Object.hash(kind, tintColor, isInteractive);
}
```

  - `lib/src/api/glass_shape.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ios_liquid_glass/src/liquid_shape.dart';

@immutable
sealed class GlassShape {
  const GlassShape();

  const factory GlassShape.capsule() = GlassCapsule;
  const factory GlassShape.circle() = GlassCircle;
  const factory GlassShape.rect(double cornerRadius) = GlassRect;
  const factory GlassShape.superellipse(double cornerRadius) = GlassSuperellipse;

  LiquidShape get liquidShape;

  ShapeBorder get border;
}

class GlassCapsule extends GlassShape {
  const GlassCapsule();

  @override
  LiquidShape get liquidShape => const LiquidRoundedRectangle(borderRadius: 999);

  @override
  ShapeBorder get border => const StadiumBorder();

  @override
  bool operator ==(Object other) => other is GlassCapsule;

  @override
  int get hashCode => (GlassCapsule).hashCode;
}

class GlassCircle extends GlassShape {
  const GlassCircle();

  @override
  LiquidShape get liquidShape => const LiquidOval();

  @override
  ShapeBorder get border => const CircleBorder();

  @override
  bool operator ==(Object other) => other is GlassCircle;

  @override
  int get hashCode => (GlassCircle).hashCode;
}

class GlassRect extends GlassShape {
  const GlassRect(this.cornerRadius);

  final double cornerRadius;

  @override
  LiquidShape get liquidShape => LiquidRoundedRectangle(borderRadius: cornerRadius);

  @override
  ShapeBorder get border => RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(cornerRadius)));

  @override
  bool operator ==(Object other) => other is GlassRect && other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(GlassRect, cornerRadius);
}

class GlassSuperellipse extends GlassShape {
  const GlassSuperellipse(this.cornerRadius);

  final double cornerRadius;

  @override
  LiquidShape get liquidShape => LiquidRoundedSuperellipse(borderRadius: cornerRadius);

  @override
  ShapeBorder get border => RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(cornerRadius)));

  @override
  bool operator ==(Object other) => other is GlassSuperellipse && other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(GlassSuperellipse, cornerRadius);
}
```

  - `lib/src/api/glass_theme.dart`:

```dart
import 'package:flutter/widgets.dart';

@immutable
class GlassThemeData {
  const GlassThemeData({this.brightness, this.accent, this.scrollEdgeTint});

  final Brightness? brightness;
  final Color? accent;
  final Color? scrollEdgeTint;

  @override
  bool operator ==(Object other) => other is GlassThemeData && other.brightness == brightness && other.accent == accent && other.scrollEdgeTint == scrollEdgeTint;

  @override
  int get hashCode => Object.hash(brightness, accent, scrollEdgeTint);
}

class GlassTheme extends InheritedWidget {
  const GlassTheme({super.key, required this.data, required super.child});

  final GlassThemeData data;

  static GlassThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassTheme>()?.data ?? const GlassThemeData();

  static Brightness brightnessOf(BuildContext context) =>
      of(context).brightness ?? MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;

  @override
  bool updateShouldNotify(GlassTheme oldWidget) => oldWidget.data != data;
}
```

- [ ] **Step 4: Write the material system**
  - `lib/src/material/glass_material.dart`:

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
    'hairline': 0,
    'hairlineWidth': 1,
    'hairlineDark': 0.1,
    'hairlineLight': 0.9,
    'specular': 0,
    'specularWidth': 1.5,
    'specularPower': 2,
    'specularFill': 0.4,
    'lightAngle': -2.356,
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
    hairline: this['hairline'],
    hairlineWidth: this['hairlineWidth'],
    hairlineDark: this['hairlineDark'],
    hairlineLight: this['hairlineLight'],
    specular: this['specular'],
    specularWidth: this['specularWidth'],
    specularPower: this['specularPower'],
    specularFill: this['specularFill'],
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

  - `lib/src/material/glass_material_override.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class GlassMaterialOverride extends InheritedWidget {
  const GlassMaterialOverride({super.key, required this.values, required super.child});

  final Map<String, double> values;

  static Map<String, double> of(BuildContext context) {
    if (!kDebugMode) return const {};
    return context.dependOnInheritedWidgetOfExactType<GlassMaterialOverride>()?.values ?? const {};
  }

  @override
  bool updateShouldNotify(GlassMaterialOverride oldWidget) => !mapEquals(oldWidget.values, values);
}
```

  - `lib/src/material/ios27.dart`: the seed table. It is written in exactly the format `material_table.py` produces (Task 10), and every value in it is a starting point that Task 11 replaces by tuning. The `dark.regular.*` tone, frost and saturation values are the prototype's first tune result; the rest are estimates.

```dart
const Map<String, Map<String, double>> ios27Table = {
  'dark.regular.44': {'dispersion': 0.02, 'frost': 22.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.9, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.125, 'toneMid': 0.5, 'toneWhite': 0.57},
  'dark.regular.88': {'dispersion': 0.02, 'frost': 22.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.9, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.125, 'toneMid': 0.5, 'toneWhite': 0.57},
  'dark.regular.200': {'dispersion': 0.02, 'frost': 22.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.9, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.125, 'toneMid': 0.5, 'toneWhite': 0.57},
  'dark.clear.44': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'dark.clear.88': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'dark.clear.200': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'dark.tinted.44': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.95, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'dark.tinted.88': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.95, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'dark.tinted.200': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.35, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.95, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'dark.reduceTransparency.44': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.16, 'toneMid': 0.21, 'toneWhite': 0.26},
  'dark.reduceTransparency.88': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.16, 'toneMid': 0.21, 'toneWhite': 0.26},
  'dark.reduceTransparency.200': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.16, 'toneMid': 0.21, 'toneWhite': 0.26},
  'dark.increaseContrast.44': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'dark.increaseContrast.88': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'dark.increaseContrast.200': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.1, 'hairlineLight': 0.55, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.12, 'specular': 0.4, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 1.0, 'tintWhite': 1.08, 'toneBlack': 0.1, 'toneMid': 0.475, 'toneWhite': 0.85},
  'light.regular.44': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.regular.88': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.regular.200': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.clear.44': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'light.clear.88': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'light.clear.200': {'dispersion': 0.02, 'frost': 1.5, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.1, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.0, 'toneMid': 0.475, 'toneWhite': 0.95},
  'light.tinted.44': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.95, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.tinted.88': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.95, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.tinted.200': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.25, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.95, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.reduceTransparency.44': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.93, 'toneMid': 0.98, 'toneWhite': 1.03},
  'light.reduceTransparency.88': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.93, 'toneMid': 0.98, 'toneWhite': 1.03},
  'light.reduceTransparency.200': {'dispersion': 0.02, 'frost': 12.0, 'hairline': 0.0, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.0, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 0.2, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.0, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.93, 'toneMid': 0.98, 'toneWhite': 1.03},
  'light.increaseContrast.44': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 12.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.increaseContrast.88': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 18.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
  'light.increaseContrast.200': {'dispersion': 0.02, 'frost': 4.0, 'hairline': 0.9, 'hairlineDark': 0.45, 'hairlineLight': 0.9, 'hairlineWidth': 1.5, 'lightAngle': -2.356, 'refractiveIndex': 1.2, 'saturation': 1.3, 'shadowBlur': 12.0, 'shadowOffsetY': 2.0, 'shadowOpacity': 0.1, 'specular': 0.5, 'specularFill': 0.35, 'specularPower': 2.0, 'specularWidth': 1.5, 'thickness': 26.0, 'tintAmount': 0.0, 'tintBlack': 0.8, 'tintWhite': 1.0, 'toneBlack': 0.3, 'toneMid': 0.65, 'toneWhite': 1.0},
};
```

- [ ] **Step 5: Write the widgets**
  - `lib/src/api/glass_effect.dart`:

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_effect_container.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/liquid_glass.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';

class GlassEffect extends StatefulWidget {
  const GlassEffect({
    super.key,
    this.glass = Glass.regular,
    this.shape = const GlassShape.capsule(),
    this.sideHint,
    required this.child,
  });

  static const double fallbackSide = 88;

  final Glass glass;
  final GlassShape shape;
  final double? sideHint;
  final Widget child;

  @override
  State<GlassEffect> createState() => _GlassEffectState();
}

class _GlassEffectState extends State<GlassEffect> {
  final _childKey = GlobalKey();
  double? _shorterSide;

  void _measured(Size size) {
    final side = size.shortestSide;
    if (_shorterSide != null && (side - _shorterSide!).abs() < 0.5) return;
    setState(() => _shorterSide = side);
  }

  @override
  Widget build(BuildContext context) {
    final child = _SizeReporter(
      key: _childKey,
      onSize: _measured,
      child: GlassEffectScope(glass: widget.glass, child: widget.child),
    );
    if (widget.glass.kind == GlassKind.identity) return child;
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final material = GlassMaterial.resolve(
          glass: widget.glass,
          shorterSide: _shorterSide ?? widget.sideHint ?? GlassEffect.fallbackSide,
          brightness: GlassTheme.brightnessOf(context),
          accessibility: GlassAccessibility.of(context),
        ).withOverrides(GlassMaterialOverride.of(context));
        final tint = widget.glass.tintColor;
        if (GlassEffectContainer.glassOf(context) == widget.glass) {
          return LiquidGlass.grouped(shape: widget.shape.liquidShape, shadows: material.shadows, child: child);
        }
        return LiquidGlass.withOwnLayer(
          settings: material.toSettings(tint: tint),
          shape: widget.shape.liquidShape,
          shadows: material.shadows,
          child: child,
        );
      },
    );
  }
}

class GlassEffectScope extends InheritedWidget {
  const GlassEffectScope({super.key, required this.glass, required super.child});

  final Glass glass;

  static Glass? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassEffectScope>()?.glass;

  @override
  bool updateShouldNotify(GlassEffectScope oldWidget) => oldWidget.glass != glass;
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({super.key, required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
```

  - `lib/src/api/glass_effect_container.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/accessibility/glass_accessibility.dart';
import 'package:ios_liquid_glass/src/api/glass.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';
import 'package:ios_liquid_glass/src/liquid_glass_blend_group.dart';
import 'package:ios_liquid_glass/src/material/glass_material.dart';
import 'package:ios_liquid_glass/src/material/glass_material_override.dart';
import 'package:ios_liquid_glass/src/rendering/liquid_glass_layer.dart';

class GlassEffectContainer extends StatelessWidget {
  const GlassEffectContainer({super.key, this.spacing = 20, this.glass = Glass.regular, this.side = 88, required this.child});

  final double spacing;
  final Glass glass;
  final double side;
  final Widget child;

  static Glass? glassOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ContainerScope>()?.glass;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final material = GlassMaterial.resolve(
          glass: glass,
          shorterSide: side,
          brightness: GlassTheme.brightnessOf(context),
          accessibility: GlassAccessibility.of(context),
        ).withOverrides(GlassMaterialOverride.of(context));
        return LiquidGlassLayer(
          settings: material.toSettings(tint: glass.tintColor),
          child: LiquidGlassBlendGroup(blend: spacing, child: _ContainerScope(glass: glass, child: child)),
        );
      },
    );
  }
}

class _ContainerScope extends InheritedWidget {
  const _ContainerScope({required this.glass, required super.child});

  final Glass glass;

  @override
  bool updateShouldNotify(_ContainerScope oldWidget) => oldWidget.glass != glass;
}
```

  - `lib/src/api/glass_dimming.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass_shape.dart';

class GlassDimming extends StatelessWidget {
  const GlassDimming({super.key, this.opacity = 0.35, this.shape = const GlassShape.capsule(), required this.child});

  final double opacity;
  final GlassShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: const Color(0xFF000000).withValues(alpha: opacity), shape: shape.border),
    child: child,
  );
}
```

  - `lib/src/api/glass_foreground.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/api/glass_effect.dart';
import 'package:ios_liquid_glass/src/api/glass_theme.dart';

class GlassForeground extends StatelessWidget {
  const GlassForeground({super.key, required this.child});

  static const Color dark = Color(0xFFFFFFFF);
  static const Color light = Color(0xFF000000);
  static const Color tinted = Color(0xFFFFFFFF);

  final Widget child;

  static Color colorOf(BuildContext context) {
    if (GlassEffectScope.maybeOf(context)?.tintColor != null) return tinted;
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

- [ ] **Step 6: Export the API.** In `packages/ios_liquid_glass/lib/ios_liquid_glass.dart`, add these lines to the `export` list, keeping it sorted by path:

```dart
export 'src/api/glass.dart' show Glass, GlassKind;
export 'src/api/glass_dimming.dart' show GlassDimming;
export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
export 'src/api/glass_foreground.dart' show GlassForeground;
export 'src/api/glass_shape.dart';
export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
export 'src/material/glass_material.dart' show GlassMaterial;
export 'src/material/glass_material_override.dart' show GlassMaterialOverride;
export 'src/material/ios27.dart' show ios27Table;
```

- [ ] **Step 7: Run the tests**

Run: `flutter test`
Expected: all package tests pass. `glass_test` has 3 tests, `glass_material_test` 9 and `glass_effect_test` 9.

- [ ] **Step 8: Run the gates.** Package: `flutter analyze`. App, from `packages/mobile`: `flutter analyze` and `flutter test`. Operator does not use the new API yet, so it only must still compile.

- [ ] **Step 9: Commit**

```bash
git add packages/ios_liquid_glass
git commit -m "feat(mobile): ios_liquid_glass gets a SwiftUI-style Glass API over an iOS 27 material table

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Operator moves onto the package API

**Files:**
- Replace: `lib/core/widgets/glass/glass_surface.dart`, `lib/core/widgets/glass/glass_scope.dart`
- Modify: `lib/main.dart` (`GlassTheme` at the root)
- Delete: `lib/core/widgets/glass/glass_style.dart`, `test/core/widgets/glass/glass_style_test.dart`, `lib/core/widgets/glass/lab/scenes/lab_material_scenes.dart`
- Modify imports only: `lib/core/widgets/glass/glass_button.dart`, `glass_tab_bar.dart`, `glass_toolbar.dart`, `lib/core/widgets/main_widgets/global_appbar.dart`, `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart`, `test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart`
- Modify: `lib/core/widgets/glass/lab/glass_lab_registry.dart`, `lib/core/widgets/glass/lab/scenes/lab_scene_parts.dart`
- Modify: `lib/core/app_themes/colors/{app_skin,light_skin,dark_skin}.dart` (remove the unused `glassRim`)
- Replace: `test/core/widgets/glass/glass_surface_test.dart`
- Modify: `test/core/widgets/sheet/app_sheet_test.dart`

**Interfaces:**
- Consumes: the Task 4 API.
- Produces, in Operator:
  - `GlassVariant {regular, clear, prominent, chrome}`, now declared in `glass_surface.dart`;
  - `glassForVariant(BuildContext, GlassVariant)`, returning a `Glass`. `prominent` becomes `Glass.regular.tint(GlassTheme.of(context).accent)`; `chrome` becomes `Glass.regular` until project 3 re-tunes the tab bar (spec A6);
  - `GlassSurface` keeps its constructor, minus `grouped`, and keeps the press lift. It draws a `GlassEffect` with `sideHint: size`;
  - `GlassScope` draws a `GlassEffectContainer(glass: glassForVariant(...), side: size)`;
  - the app root provides `GlassTheme(GlassThemeData(brightness from skin.themeMode, accent: skin.accent, scrollEdgeTint: skin.scrollEdgeTint))`.
- Removed: `GlassStyle`, `GlassSurface.outlineKey`, `rimKey` and `rimWidth`, `GlassSurface.grouped`, `AppSkin.glassRim`, and Operator's lab material scenes. Material scenes live in the example app from Task 7.

- [ ] **Step 1: Write the failing test.** Replace `test/core/widgets/glass/glass_surface_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

const _accent = Color(0xFF1ACB64);

Widget _host(Brightness brightness, Widget child) => MaterialApp(
  home: GlassTheme(
    data: GlassThemeData(brightness: brightness, accent: _accent),
    child: Center(child: child),
  ),
);

const _surface = GlassScope(
  variant: GlassVariant.regular,
  size: 44,
  child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 120, height: 44, child: Text('glass'))),
);

void main() {
  testWidgets('renders its child inside a glass layer', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, _surface));
    expect(find.text('glass'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching appearance updates the layer material without remounting', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, _surface));
    final before = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    final element = tester.element(find.byType(LiquidGlassLayer));
    await tester.pumpWidget(_host(Brightness.dark, _surface));
    final after = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings;
    expect(after, isNot(before));
    expect(tester.element(find.byType(LiquidGlassLayer)), same(element));
  });

  testWidgets('prominent glass keeps its own tinted layer inside a regular scope', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.prominent, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), _accent);
  });

  testWidgets('clear glass keeps its own layer with the clear material', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.clear, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    final clear = GlassMaterial.resolve(glass: Glass.clear, shorterSide: 44, brightness: Brightness.light);
    expect(inner.settings.toneBlack, clear['toneBlack']);
    expect(inner.settings.toneWhite, clear['toneWhite']);
  });

  testWidgets('a rounded rect uses a plain rounded rectangle at its radius, so it can morph from a capsule', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.light,
      const GlassSurface(kind: GlassShapeKind.roundedRect, size: 48, radius: 26, child: SizedBox(width: 200, height: 90)),
    ));
    final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    expect(glass.shape, isA<LiquidRoundedRectangle>());
    expect((glass.shape as LiquidRoundedRectangle).borderRadius, 26);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run (from `packages/mobile`): `flutter test test/core/widgets/glass/glass_surface_test.dart`
Expected: compile errors, because `glassForVariant` is undefined and `GlassVariant` has no import.

- [ ] **Step 3: Replace the adapters.** Replace `lib/core/widgets/glass/glass_surface.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';

enum GlassShapeKind { capsule, circle, rect, roundedRect }

enum GlassVariant { regular, clear, prominent, chrome }

Glass glassForVariant(BuildContext context, GlassVariant variant) => switch (variant) {
  GlassVariant.clear => Glass.clear,
  GlassVariant.prominent => Glass.regular.tint(GlassTheme.of(context).accent),
  GlassVariant.regular || GlassVariant.chrome => Glass.regular,
};

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.kind,
    required this.size,
    required this.child,
    this.radius = 0,
    this.pressable = false,
    this.enabled = true,
    this.glowAlpha = 0.35,
    this.variant = GlassVariant.regular,
  });

  static const double pressedScale = 1.08;

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool pressable;
  final bool enabled;
  final double glowAlpha;
  final GlassVariant variant;
  final Widget child;

  GlassShape get shape => switch (kind) {
    GlassShapeKind.capsule => const GlassShape.capsule(),
    GlassShapeKind.circle => const GlassShape.circle(),
    GlassShapeKind.rect => GlassShape.superellipse(radius),
    GlassShapeKind.roundedRect => GlassShape.rect(radius),
  };

  @override
  Widget build(BuildContext context) {
    final content = pressable && enabled
        ? GlassGlow(glowColor: const Color(0xFFFFFFFF).withValues(alpha: glowAlpha), child: child)
        : child;
    final glass = GlassEffect(glass: glassForVariant(context, variant), shape: shape, sideHint: size, child: content);
    return pressable ? _PressLift(enabled: enabled, child: glass) : glass;
  }
}

class _PressLift extends StatefulWidget {
  const _PressLift({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PressLift> createState() => _PressLiftState();
}

class _PressLiftState extends State<_PressLift> {
  bool _pressed = false;

  void _set(bool value) {
    if (value && !widget.enabled) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _PressLift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && !still ? GlassSurface.pressedScale : 1.0,
        duration: AppMotion.slow,
        curve: AppMotion.spring,
        child: widget.child,
      ),
    );
  }
}
```

Then replace `lib/core/widgets/glass/glass_scope.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

class GlassScope extends StatelessWidget {
  const GlassScope({super.key, required this.variant, required this.size, required this.child});

  final GlassVariant variant;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GlassEffectContainer(glass: glassForVariant(context, variant), side: size, child: child);
}
```

- [ ] **Step 4: Delete `GlassStyle` and fix its importers**

```bash
git rm lib/core/widgets/glass/glass_style.dart test/core/widgets/glass/glass_style_test.dart lib/core/widgets/glass/lab/scenes/lab_material_scenes.dart
```

- In `lib/core/widgets/glass/glass_button.dart`, `lib/core/widgets/glass/glass_tab_bar.dart`, `lib/feature/terminal/presentation/terminal_screen/ui/widgets/terminal_chat_header.dart` and `test/feature/terminal/presentation/terminal_screen/ui/terminal_composer_test.dart`, delete the line `import 'package:operator_mobile/core/widgets/glass/glass_style.dart';`. Each of them already imports `glass_surface.dart`.
- In `lib/core/widgets/glass/glass_toolbar.dart` and `lib/core/widgets/main_widgets/global_appbar.dart`, replace that line with `import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';`.
- In `lib/core/widgets/glass/lab/glass_lab_registry.dart`, delete the import of `scenes/lab_material_scenes.dart` and the entry `    ...LabMaterialScenes.scenes,`.
- In `lib/core/widgets/glass/lab/scenes/lab_scene_parts.dart`:
  - delete the imports of `glass_style.dart` and `glass_surface.dart`;
  - delete the whole `LabBlock` class, so the file keeps only `LabCentered`;
  - the remaining imports are `package:flutter/material.dart` and `package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart`.

- [ ] **Step 5: Remove the unused rim colour**
  - In `lib/core/app_themes/colors/app_skin.dart`, delete `  Color get glassRim;` and the blank line after it.
  - In `lib/core/app_themes/colors/light_skin.dart`, delete these lines and the blank line after them:
    ```dart
      @override
      Color get glassRim => const Color(0x241A1612);
    ```
  - In `lib/core/app_themes/colors/dark_skin.dart`, delete these lines and the blank line after them:
    ```dart
      @override
      Color get glassRim => const Color(0x00000000);
    ```

- [ ] **Step 6: Put `GlassTheme` at the app root.** In `lib/main.dart`:
  - add `import 'package:ios_liquid_glass/ios_liquid_glass.dart';` after the `flutter_screenutil` import;
  - replace this block:

```dart
            return SkinScope(
              skin: skin,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                minTextAdapt: true,
                builder: (context, child) => MaterialApp(
                  navigatorKey: sl<GlobalKey<NavigatorState>>(),
                  navigatorObservers: [AppRouteObserver.instance],
                  debugShowCheckedModeBanner: false,
                  theme: AppThemes.fromSkin(skin),
                  themeMode: skin.themeMode,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  initialRoute: widget.initialRoute,
                  onGenerateInitialRoutes: (name) => [AppRouter.generateRoute(RouteSettings(name: name))],
                  onGenerateRoute: AppRouter.generateRoute,
                ),
              ),
            );
```

  with:

```dart
            return SkinScope(
              skin: skin,
              child: GlassTheme(
                data: GlassThemeData(
                  brightness: skin.themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
                  accent: skin.accent,
                  scrollEdgeTint: skin.scrollEdgeTint,
                ),
                child: ScreenUtilInit(
                  designSize: const Size(390, 844),
                  minTextAdapt: true,
                  builder: (context, child) => MaterialApp(
                    navigatorKey: sl<GlobalKey<NavigatorState>>(),
                    navigatorObservers: [AppRouteObserver.instance],
                    debugShowCheckedModeBanner: false,
                    theme: AppThemes.fromSkin(skin),
                    themeMode: skin.themeMode,
                    localizationsDelegates: context.localizationDelegates,
                    supportedLocales: context.supportedLocales,
                    locale: context.locale,
                    initialRoute: widget.initialRoute,
                    onGenerateInitialRoutes: (name) => [AppRouter.generateRoute(RouteSettings(name: name))],
                    onGenerateRoute: AppRouter.generateRoute,
                  ),
                ),
              ),
            );
```

- [ ] **Step 7: Pin the sheet's search shadow to the material.** In `test/core/widgets/sheet/app_sheet_test.dart`:
  - delete `import 'package:operator_mobile/core/widgets/glass/glass_style.dart';`;
  - replace

```dart
    expect(glass.shadows, GlassStyle.shadows(const LightSkin(), size: AppSheetMetrics.searchHeight));
```

  with

```dart
    expect(
      glass.shadows,
      GlassMaterial.resolve(glass: Glass.regular, shorterSide: AppSheetMetrics.searchHeight, brightness: Brightness.light).shadows,
    );
```

- [ ] **Step 8: Run the gates**

Run (from `packages/mobile`): `flutter analyze && flutter test`
Expected:
- analyze prints "No issues found!";
- every test passes. The count drops by the deleted `glass_style_test.dart`, and the rewritten `glass_surface_test.dart` has fewer tests.
- `grep -rn 'glass_style\|glassRim\|GlassStyle' lib test` prints nothing.

- [ ] **Step 9: Build Operator** to prove the adapters compile for iOS

Run: `python3 tool/glass_lab/harness/lab.py build flutter`
Expected: ends with `built for 708879DD-...`.

- [ ] **Step 10: Commit**

```bash
git add -A lib test
git commit -m "refactor(mobile): Operator draws glass through the ios_liquid_glass API and theme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The scroll edge effect moves into the package, with iOS 27 styles

**Files:**
- Move and replace:
  - `lib/core/widgets/glass/scroll_edge_effect.dart` → `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart`
  - `lib/core/widgets/glass/scroll_under_bars.dart` → `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_under_bars.dart`
  - `shaders/scroll_edge_blur.frag` → `packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag`
  - `test/core/widgets/glass/scroll_edge_effect_test.dart` → `packages/ios_liquid_glass/test/scroll_edge_effect_test.dart`
  - `test/core/widgets/glass/scroll_under_bars_test.dart` → `packages/ios_liquid_glass/test/scroll_under_bars_test.dart`
- Create:
  - `packages/ios_liquid_glass/lib/src/material/scroll_edge_material.dart`
  - `packages/ios_liquid_glass/lib/src/material/ios27_scroll_edge.dart`
  - `packages/ios_liquid_glass/test/scroll_edge_material_test.dart`
- Replace: `packages/ios_liquid_glass/lib/ios_liquid_glass.dart` (final export list)
- Modify:
  - `packages/ios_liquid_glass/pubspec.yaml` and `pubspec.yaml` (the shader moves);
  - `lib/core/widgets/glass/glass_metrics.dart` (remove `topEdgeFadeExtent`);
  - the ten Operator files listed in Step 7.

**Interfaces:**
- Consumes: `GlassTheme` (Task 4) and `GlassMaterialOverride` (Task 4). Operator's root `GlassTheme` (Task 5) supplies `scrollEdgeTint`.
- Produces:
  - **`ScrollEdgeStyle {soft, hard, automatic}`**.
  - **`ScrollEdgeMaterial(Map<String, double>)`**:
    - fields `extent` (pt below the top inset), `blur` (pt), `dim` (tint alpha), `knee` (0 means a hard band), `cap` (alpha under the status bar), `capBlur` (pt), `line` (divider alpha) and `lineShade` (divider grey);
    - `ScrollEdgeMaterial.defaults` and `ScrollEdgeMaterial.overridePrefix` `'edge.'`;
    - `withOverrides(map)`, which reads only `edge.*` keys;
    - `ScrollEdgeMaterial.resolve({required ScrollEdgeStyle style, required Brightness brightness, table = ios27ScrollEdgeTable})`.
  - **`ios27ScrollEdgeTable`**, keyed `'<dark|light>.<soft|hard|automatic>'`.
  - **`ScrollEdgeEffect`**: `ScrollEdgeEffect({required ScrollEdge edge, required double height, ScrollEdgeStyle style = ScrollEdgeStyle.automatic, double visibility = 1, double? knee, double capExtent = 0})`, with `ScrollEdgeEffect.materialOf(context, style)`, `ScrollEdgeEffect.shaderAsset`, `topVisibility` and `bottomVisibility`.
  - **`ScrollUnderBars({ScrollEdgeStyle style = ScrollEdgeStyle.automatic, required Widget child})`**. Its band height is the top inset plus the style's `extent`.
- Shader uniforms, in order:
  - `uSize` (0–1), `uBandHeight` (2), `uMaxRadius` (3), `uFromTop` (4), `uBandOriginY` (5);
  - `uTint` (6–9), `uKnee` (10);
  - `uCapHeight` (11), `uCapAlpha` (12), `uCapRadius` (13);
  - `uLine` (14–17), `uLineWidth` (18);
  - sampler 0 `uTexture`.

- [ ] **Step 1: Move the files with history**

```bash
mkdir -p packages/ios_liquid_glass/lib/src/scroll_edge
git mv lib/core/widgets/glass/scroll_edge_effect.dart packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart
git mv lib/core/widgets/glass/scroll_under_bars.dart packages/ios_liquid_glass/lib/src/scroll_edge/scroll_under_bars.dart
git mv shaders/scroll_edge_blur.frag packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag
git mv test/core/widgets/glass/scroll_edge_effect_test.dart packages/ios_liquid_glass/test/scroll_edge_effect_test.dart
git mv test/core/widgets/glass/scroll_under_bars_test.dart packages/ios_liquid_glass/test/scroll_under_bars_test.dart
```

- [ ] **Step 2: Write the tests.** Replace `packages/ios_liquid_glass/test/scroll_edge_effect_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

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

  for (final (brightness, expected) in const [(Brightness.light, Color(0xFFFFFFFF)), (Brightness.dark, Color(0xFF000000))]) {
    testWidgets('the fallback tints with the default edge tint (${brightness.name})', (tester) async {
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
      final box = tester.widget<ColoredBox>(
        find.descendant(of: find.byType(BackdropFilter), matching: find.byType(ColoredBox)),
      );
      expect(box.color.withValues(alpha: 1), expected);
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
    final box = tester.widget<ColoredBox>(
      find.descendant(of: find.byType(BackdropFilter), matching: find.byType(ColoredBox)),
    );
    expect(box.color.withValues(alpha: 1), const Color(0xFFFAF7F2));
  });
}
```

Replace `packages/ios_liquid_glass/test/scroll_under_bars_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  testWidgets('puts a top edge fade over the child, sized to the bar inset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 106)),
            child: const GlassTheme(
              data: GlassThemeData(brightness: Brightness.light),
              child: ScrollUnderBars(child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.edge, ScrollEdge.top);
    expect(effect.style, ScrollEdgeStyle.automatic);
    expect(effect.height, 106 + ios27ScrollEdgeTable['light.automatic']!['extent']!);
    expect(effect.capExtent, 106);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('a soft style reaches further down than the automatic bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 62)),
            child: const GlassTheme(
              data: GlassThemeData(brightness: Brightness.dark),
              child: ScrollUnderBars(style: ScrollEdgeStyle.soft, child: Text('content')),
            ),
          ),
        ),
      ),
    );
    final effect = tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));
    expect(effect.style, ScrollEdgeStyle.soft);
    expect(effect.height, 62 + ios27ScrollEdgeTable['dark.soft']!['extent']!);
    expect(effect.height, greaterThan(62 + ios27ScrollEdgeTable['dark.automatic']!['extent']!));
  });

  Future<ScrollController> pumpList(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: ScrollUnderBars(
            child: ListView(
              controller: controller,
              children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('row $i'))],
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  ScrollEdgeEffect topEffect(WidgetTester tester) => tester.widget<ScrollEdgeEffect>(find.byType(ScrollEdgeEffect));

  Finder blur() => find.descendant(of: find.byType(ScrollEdgeEffect), matching: find.byType(BackdropFilter));

  testWidgets('at rest the top edge effect draws nothing', (tester) async {
    await pumpList(tester);
    expect(topEffect(tester).visibility, 0);
    expect(blur(), findsNothing);
  });

  testWidgets('the top edge effect fades in as content scrolls under it', (tester) async {
    final controller = await pumpList(tester);
    controller.jumpTo(8);
    await tester.pump();
    expect(topEffect(tester).visibility, 0.5);
    expect(blur(), findsOneWidget);
    controller.jumpTo(200);
    await tester.pump();
    expect(topEffect(tester).visibility, 1);
    controller.jumpTo(0);
    await tester.pump();
    expect(topEffect(tester).visibility, 0);
    expect(blur(), findsNothing);
  });

  testWidgets('a horizontal scroller inside does not drive the top edge effect', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GlassTheme(
          data: const GlassThemeData(brightness: Brightness.light),
          child: ScrollUnderBars(
            child: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              children: [for (var i = 0; i < 60; i++) SizedBox(width: 80, child: Text('col $i'))],
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(200);
    await tester.pump();
    expect(topEffect(tester).visibility, 0);
  });
}
```

Create `packages/ios_liquid_glass/test/scroll_edge_material_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

void main() {
  test('rows resolve per style and appearance and take prefixed overrides', () {
    final soft = ScrollEdgeMaterial.resolve(style: ScrollEdgeStyle.soft, brightness: Brightness.dark);
    expect(soft['extent'], ios27ScrollEdgeTable['dark.soft']!['extent']);
    final tuned = soft.withOverrides({'edge.blur': 9, 'frost': 3});
    expect(tuned['blur'], 9);
    expect(tuned.values.containsKey('frost'), isFalse);
  });

  test('the shipped table has every style in both appearances', () {
    for (final style in ScrollEdgeStyle.values) {
      for (final appearance in ['dark', 'light']) {
        expect(ios27ScrollEdgeTable.containsKey('$appearance.${style.name}'), isTrue);
      }
    }
  });

  test('missing fields fall back to defaults', () {
    const material = ScrollEdgeMaterial({});
    expect(material['knee'], ScrollEdgeMaterial.defaults['knee']);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run (from `packages/ios_liquid_glass`): `flutter test test/scroll_edge_effect_test.dart test/scroll_under_bars_test.dart test/scroll_edge_material_test.dart`
Expected: compile errors, because `ScrollEdgeStyle`, `ScrollEdgeMaterial` and `ios27ScrollEdgeTable` are undefined and the moved files still import Operator.

- [ ] **Step 4: Write the material and its seed table**
  - `packages/ios_liquid_glass/lib/src/material/scroll_edge_material.dart`:

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

  - `packages/ios_liquid_glass/lib/src/material/ios27_scroll_edge.dart`. This is the seed. `hard` and `automatic` start as the uniform bar measured in the baseline: 54 pt below the inset, with a divider in light mode only. `soft` starts as Operator's old ramp. Task 11 tunes all six rows.

```dart
const Map<String, Map<String, double>> ios27ScrollEdgeTable = {
  'dark.soft': {'blur': 4.0, 'cap': 0.88, 'capBlur': 6.0, 'dim': 0.6, 'extent': 118.0, 'knee': 0.45, 'line': 0.0, 'lineShade': 0.5},
  'dark.hard': {'blur': 4.0, 'cap': 0.6, 'capBlur': 4.0, 'dim': 0.6, 'extent': 54.0, 'knee': 0.0, 'line': 0.0, 'lineShade': 0.5},
  'dark.automatic': {'blur': 4.0, 'cap': 0.6, 'capBlur': 4.0, 'dim': 0.6, 'extent': 54.0, 'knee': 0.0, 'line': 0.0, 'lineShade': 0.5},
  'light.soft': {'blur': 4.0, 'cap': 0.94, 'capBlur': 6.0, 'dim': 0.78, 'extent': 118.0, 'knee': 0.45, 'line': 0.0, 'lineShade': 0.5},
  'light.hard': {'blur': 4.0, 'cap': 0.78, 'capBlur': 4.0, 'dim': 0.78, 'extent': 54.0, 'knee': 0.0, 'line': 0.25, 'lineShade': 0.5},
  'light.automatic': {'blur': 4.0, 'cap': 0.78, 'capBlur': 4.0, 'dim': 0.78, 'extent': 54.0, 'knee': 0.0, 'line': 0.25, 'lineShade': 0.5},
};
```

- [ ] **Step 5: Replace the moved code**
  - `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_edge_effect.dart`:

```dart
import 'dart:async';
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
  static const String shaderAsset = 'packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag';

  static double topVisibility(ScrollMetrics metrics) =>
      ((metrics.pixels - metrics.minScrollExtent) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static double bottomVisibility(ScrollMetrics metrics) =>
      ((metrics.maxScrollExtent - metrics.pixels) / fadeExtent).clamp(0.0, 1.0).toDouble();

  static ScrollEdgeMaterial materialOf(BuildContext context, ScrollEdgeStyle style) => ScrollEdgeMaterial.resolve(
    style: style,
    brightness: GlassTheme.brightnessOf(context),
  ).withOverrides(GlassMaterialOverride.of(context));

  final ScrollEdge edge;
  final double height;
  final ScrollEdgeStyle style;
  final double visibility;
  final double? knee;
  final double capExtent;

  @override
  State<ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

class _ScrollEdgeEffectState extends State<ScrollEdgeEffect> {
  final _boxKey = GlobalKey();
  ui.FragmentShader? _shader;
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
    setState(() {
      _shader = program.fragmentShader();
    });
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

  Widget _fallback(Color tint, double maxAlpha, double blur) {
    final outer = widget.edge == ScrollEdge.top ? Alignment.topCenter : Alignment.bottomCenter;
    final inner = widget.edge == ScrollEdge.top ? Alignment.bottomCenter : Alignment.topCenter;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: outer,
        end: inner,
        colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
      ).createShader(rect),
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: ColoredBox(color: tint.withValues(alpha: maxAlpha)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GlassTheme.of(context);
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    final material = ScrollEdgeEffect.materialOf(context, widget.style);
    final visibility = widget.visibility.clamp(0.0, 1.0).toDouble();
    final maxAlpha = material['dim'] * visibility;
    final tint = theme.scrollEdgeTint ?? (dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
    final shade = material['lineShade'];
    final shader = _shader;
    final originY = _originY;
    _scheduleMeasure();
    return IgnorePointer(
      child: SizedBox(
        key: _boxKey,
        height: widget.height,
        width: double.infinity,
        child: visibility <= 0
            ? null
            : shader == null || originY == null
            ? _fallback(tint, maxAlpha, material['blur'])
            : Builder(
                builder: (context) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  shader
                    ..setFloat(0, 0)
                    ..setFloat(1, 0)
                    ..setFloat(2, widget.height * dpr)
                    ..setFloat(3, material['blur'] * dpr * visibility)
                    ..setFloat(4, widget.edge == ScrollEdge.top ? 1 : 0)
                    ..setFloat(5, originY)
                    ..setFloat(6, tint.r)
                    ..setFloat(7, tint.g)
                    ..setFloat(8, tint.b)
                    ..setFloat(9, maxAlpha)
                    ..setFloat(10, widget.knee ?? material['knee'])
                    ..setFloat(11, widget.capExtent * dpr)
                    ..setFloat(12, material['cap'] * visibility)
                    ..setFloat(13, material['capBlur'] * dpr * visibility)
                    ..setFloat(14, shade)
                    ..setFloat(15, shade)
                    ..setFloat(16, shade)
                    ..setFloat(17, material['line'] * visibility)
                    ..setFloat(18, ScrollEdgeEffect.lineWidth * dpr);
                  return ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.shader(shader),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
```

  - `packages/ios_liquid_glass/lib/src/scroll_edge/scroll_under_bars.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/src/material/scroll_edge_material.dart';
import 'package:ios_liquid_glass/src/scroll_edge/scroll_edge_effect.dart';

class ScrollUnderBars extends StatefulWidget {
  const ScrollUnderBars({super.key, this.style = ScrollEdgeStyle.automatic, required this.child});

  final ScrollEdgeStyle style;
  final Widget child;

  @override
  State<ScrollUnderBars> createState() => _ScrollUnderBarsState();
}

class _ScrollUnderBarsState extends State<ScrollUnderBars> {
  final ValueNotifier<double> _visibility = ValueNotifier<double>(0);

  @override
  void dispose() {
    _visibility.dispose();
    super.dispose();
  }

  bool _onScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _visibility.value = ScrollEdgeEffect.topVisibility(metrics);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final extent = ScrollEdgeEffect.materialOf(context, widget.style)['extent'];
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<Notification>(onNotification: _onScroll, child: widget.child),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _visibility,
            builder: (context, visibility, _) => ScrollEdgeEffect(
              edge: ScrollEdge.top,
              style: widget.style,
              height: top + extent,
              visibility: visibility,
              capExtent: top,
            ),
          ),
        ),
      ],
    );
  }
}
```

  - `packages/ios_liquid_glass/lib/assets/shaders/scroll_edge_blur.frag`:

```glsl
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBandHeight;
uniform float uMaxRadius;
uniform float uFromTop;
uniform float uBandOriginY;
uniform vec4 uTint;
uniform float uKnee;
uniform float uCapHeight;
uniform float uCapAlpha;
uniform float uCapRadius;
uniform vec4 uLine;
uniform float uLineWidth;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    float distFromEdge = uFromTop > 0.5 ? (frag.y - uBandOriginY) : (uBandOriginY + uBandHeight - frag.y);
    float s = clamp(distFromEdge / uBandHeight, 0.0, 1.0);
    float t = 1.0 - s;
    float w = uKnee > 0.0 ? smoothstep(0.0, uKnee, t) : step(0.0001, t);
    float cap = uCapHeight > 0.0 ? 1.0 - smoothstep(uCapHeight * 0.6, uCapHeight, distFromEdge) : 0.0;
    float r = mix(uMaxRadius * w, uCapRadius, cap);
    float a = mix(uTint.a * w, uCapAlpha, cap);
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -3; i <= 3; i++) {
        for (int j = -3; j <= 3; j++) {
            vec2 o = vec2(float(i), float(j)) * (r / 3.0);
            float wk = exp(-float(i * i + j * j) / 8.0);
            acc += texture(uTexture, (frag + o) / uSize) * wk;
            wsum += wk;
        }
    }
    vec4 blurred = acc / wsum;
    vec4 color = mix(blurred, vec4(uTint.rgb * blurred.a, blurred.a), a);
    float line = distFromEdge > uBandHeight - uLineWidth ? uLine.a : 0.0;
    fragColor = mix(color, vec4(uLine.rgb * color.a, color.a), line);
}
```

- [ ] **Step 6: Register the shader in the package and export everything**
  - In `packages/ios_liquid_glass/pubspec.yaml`, add `    - lib/assets/shaders/scroll_edge_blur.frag` as the last entry of `shaders:`.
  - In `pubspec.yaml` (the app), delete the line `    - shaders/scroll_edge_blur.frag`. The `shaders:` list keeps `    - shaders/tab_lens.frag`.
  - Replace `packages/ios_liquid_glass/lib/ios_liquid_glass.dart` with the final export list:

```dart
/// Liquid Glass Effect for Flutter
library;

import 'package:flutter/foundation.dart' show kDebugMode;

export 'src/accessibility/glass_accessibility.dart' show GlassAccessibility, GlassAccessibilityData;
export 'src/api/glass.dart' show Glass, GlassKind;
export 'src/api/glass_dimming.dart' show GlassDimming;
export 'src/api/glass_effect.dart' show GlassEffect, GlassEffectScope;
export 'src/api/glass_effect_container.dart' show GlassEffectContainer;
export 'src/api/glass_foreground.dart' show GlassForeground;
export 'src/api/glass_shape.dart';
export 'src/api/glass_theme.dart' show GlassTheme, GlassThemeData;
export 'src/fake_glass.dart' show FakeGlass;
export 'src/glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'src/internal/glass_drag_builder.dart' show GestureMode;
export 'src/liquid_glass.dart' show LiquidGlass;
export 'src/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'src/liquid_glass_settings.dart' show LiquidGlassSettings;
export 'src/liquid_shape.dart';
export 'src/logging.dart' show LgrLogs;
export 'src/material/glass_material.dart' show GlassMaterial;
export 'src/material/glass_material_override.dart' show GlassMaterialOverride;
export 'src/material/ios27.dart' show ios27Table;
export 'src/material/ios27_scroll_edge.dart' show ios27ScrollEdgeTable;
export 'src/material/scroll_edge_material.dart' show ScrollEdgeMaterial, ScrollEdgeStyle;
export 'src/rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'src/scroll_edge/scroll_edge_effect.dart' show ScrollEdge, ScrollEdgeEffect;
export 'src/scroll_edge/scroll_under_bars.dart' show ScrollUnderBars;
export 'src/stretch.dart'
    show LiquidStretch, OffsetResistanceExtension, RawLiquidStretch;

/// Whether to paint the liquid glass geometry texture for debugging purposes.
///
/// When enabled, geometry textures will be drawn directly instead of the
/// liquid glass effect.
///
/// Will be set to `false` in release builds.
@pragma('vm:platform-const-if', !kDebugMode)
bool debugPaintLiquidGlassGeometry = false;
```

- [ ] **Step 7: Point Operator at the package.** In each of these ten files, replace the line that imports `package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart` or `.../scroll_under_bars.dart` with `import 'package:ios_liquid_glass/ios_liquid_glass.dart';`:
  - `lib/core/app_routes/home_shell.dart`
  - `lib/core/widgets/main_widgets/app_scaffold.dart`
  - `lib/core/widgets/sheet/app_sheet.dart`
  - `lib/feature/blocks/presentation/blocks_screen/ui/widgets/blocks_body.dart`
  - `lib/feature/settings/presentation/settings_screen/ui/settings_screen.dart`
  - `lib/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart`
  - `lib/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart`
  - `test/core/app_routes/home_shell_test.dart`
  - `test/core/widgets/core_widgets_test.dart`
  - `test/feature/terminal/presentation/terminal_screen/ui/terminal_body_layout_test.dart`

  If a file already imports `package:ios_liquid_glass/ios_liquid_glass.dart`, delete the old line instead of adding a duplicate. Then delete `  static const double topEdgeFadeExtent = 34;` from `lib/core/widgets/glass/glass_metrics.dart`; `ScrollUnderBars` now takes its band from the style.

- [ ] **Step 8: Run the tests**

Run (from `packages/ios_liquid_glass`): `flutter test`
Expected: all package tests pass, 46 in the prototype.

- [ ] **Step 9: Run every gate**
  - Package: `flutter analyze`.
  - App, from `packages/mobile`: `flutter pub get && flutter analyze && flutter test`. Expected: "No issues found!" and every test green, 2,145 in the prototype.
  - Check: `grep -rn 'widgets/glass/scroll_edge_effect\|widgets/glass/scroll_under_bars\|topEdgeFadeExtent' lib test` prints nothing.

- [ ] **Step 10: Build Operator.** Run `python3 tool/glass_lab/harness/lab.py build flutter`. Expected: ends with `built for 708879DD-...`, which proves the moved shader bundles from the package.

- [ ] **Step 11: Commit**

```bash
git add -A packages/ios_liquid_glass lib test shaders pubspec.yaml
git commit -m "feat(mobile): scroll edge effect moves into ios_liquid_glass with soft, hard and automatic styles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The example app becomes the lab's Flutter target

**Files:**
- Create: `packages/ios_liquid_glass/example/` (from `flutter create`), then replace or create:
  - `pubspec.yaml`, `lib/main.dart`, `test/lab_test.dart`;
  - `lib/lab/{glass_lab_launch,glass_lab_marker,glass_lab_backdrop,glass_lab_registry,glass_lab_screen,glass_lab_probe}.dart`;
  - `lib/lab/scenes/{lab_parts,material_scenes,perf_scenes}.dart`.
- Delete: `packages/ios_liquid_glass/example/test/widget_test.dart`
- Modify: `pubspec.yaml` (workspace member), `tool/glass_lab/harness/{build,record,lab,manifest,analyze}.py`, `tool/glass_lab/harness/tests/{test_manifest,test_record}.py`
- Modify: `tool/glass_lab/native/GlassLab/MaterialScenes.swift` (edge scenes pre-scroll 300 pt, flip gets a third block), `tool/glass_lab/scenes.json` (edge scenes become static with a pinned band)

**Interfaces:**
- Consumes: the whole package API (Tasks 2–6).
- Produces:
  - **The example app**: bundle id `dev.operator.iosliquidglass.example`, package `ios_liquid_glass_example`, workspace member. In debug it reads `Documents/glass_lab/launch.json`, `{scene, backdrop, bare, material}`, and deletes it.
  - **`GlassLabLaunch`**: `{scene, backdrop, bare, material}`, with `fromJson`, `consume(Directory)`, `load()`, `directory` and `current`.
  - **`GlassLabRegistry`**: `scenes` (manifest ids only), `tools` (`perf.none`, `perf.glass`) and `build(launch)`. It shows the missing placeholder `scene.missing` for unknown ids.
  - **Probes**:
    - `GlassLabAccessibilityProbe` writes `Documents/glass_lab/accessibility.json`, `{reduceTransparency, increaseContrast, reduceMotion}`, whenever the values change;
    - `PerfScenes` writes `Documents/glass_lab/perf.json`, `{scene, frames, raster_ms: {median, p90, max}, build_ms: {...}}`, after a 2 s warm-up and a 6 s window;
    - both write through `writeLabFile`, atomically, via a `.partial` file.
  - **Harness**:
    - `build.EXAMPLE`, `build.EXAMPLE_DATA`, `build.EXAMPLE_APP`, `build.EXAMPLE_BUNDLE`;
    - `build.FLUTTER_TARGETS = {"example": EXAMPLE_BUNDLE, "operator": FLUTTER_BUNDLE}`;
    - `build.flutter_app(udid, root, data_path, app_path)` and `build.example(udid)`;
    - `record.write_launch_file(folder, scene_id, backdrop, bare, material=None)`;
    - `record.drive(..., settle=1.5, material=None)`;
    - `record.target_for(scene, app, flutter_target="example")` and `record.capture(..., flutter_target="example")`;
    - `lab.py build native|example|operator|all`, and `lab.py run|baseline --flutter example|operator`, defaulting to `example`;
    - `manifest.STATIC_MEASURES` and `Scene.measures`: the scene's optional `"measures"` list. `analyze` checks only those measures.

- [ ] **Step 1: Create the example app**

```bash
cd packages/ios_liquid_glass
flutter create --platforms ios,android --org dev.operator.iosliquidglass --project-name ios_liquid_glass_example example
cd example
sed -E -i '' 's/(PRODUCT_BUNDLE_IDENTIFIER = dev\.operator\.iosliquidglass\.)[A-Za-z]+/\1example/' ios/Runner.xcodeproj/project.pbxproj
grep -c 'PRODUCT_BUNDLE_IDENTIFIER = dev.operator.iosliquidglass.example' ios/Runner.xcodeproj/project.pbxproj
git rm -q --cached test/widget_test.dart 2>/dev/null; rm -f test/widget_test.dart
cd ../../..
```

Expected: the `grep -c` prints `6`: three app configurations and three `RunnerTests` configurations ending in `.example.RunnerTests`. If the `pub get` inside `flutter create` complains about the workspace, ignore it; Step 2 fixes the pubspec and resolves again.

- [ ] **Step 2: Make it a workspace member.** Replace `packages/ios_liquid_glass/example/pubspec.yaml` with:

```yaml
name: ios_liquid_glass_example
description: "Example app for ios_liquid_glass, and the glass lab's Flutter target."
publish_to: none
version: 1.0.0+1
resolution: workspace

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter
  ios_liquid_glass:
  path_provider: ^2.1.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

In `pubspec.yaml` (the app), add `  - packages/ios_liquid_glass/example` right after `  - packages/ios_liquid_glass` under `workspace:`. Then run `flutter pub get` from `packages/mobile`.

- [ ] **Step 3: Write the failing test** `packages/ios_liquid_glass/example/test/lab_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_launch.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_registry.dart';
import 'package:ios_liquid_glass_example/lab/glass_lab_screen.dart';
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
    final launch = GlassLabLaunch.fromJson({'scene': 'material.regular', 'material': {'lift': 0.2, 'gain': 1}});
    expect(launch?.material, {'lift': 0.2, 'gain': 1.0});
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
    expect(GlassLabRegistry.tools.keys, containsAll(['perf.none', 'perf.glass']));
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

Run (from `example`): `flutter test`
Expected: compile errors, because `package:ios_liquid_glass_example/lab/...` does not exist yet.

- [ ] **Step 4: Write the lab plumbing** in `packages/ios_liquid_glass/example/lib/lab/`:
  - `glass_lab_launch.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class GlassLabLaunch {
  const GlassLabLaunch({required this.scene, this.backdrop = defaultBackdrop, this.bare = false, this.material = const {}});

  static const String defaultBackdrop = 'stripes';
  static const String launchFile = 'launch.json';
  static Directory directory = Directory('');
  static GlassLabLaunch? current;

  final String scene;
  final String backdrop;
  final bool bare;
  final Map<String, double> material;

  static GlassLabLaunch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final scene = json['scene'];
    if (scene is! String || scene.isEmpty) return null;
    final backdrop = json['backdrop'];
    final material = json['material'];
    return GlassLabLaunch(
      scene: scene,
      backdrop: backdrop is String && backdrop.isNotEmpty ? backdrop : defaultBackdrop,
      bare: json['bare'] == true,
      material: material is Map<String, dynamic>
          ? {for (final entry in material.entries) if (entry.value is num) entry.key: (entry.value as num).toDouble()}
          : const {},
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
    return current = consume(directory);
  }
}
```

  - `glass_lab_marker.dart`:

```dart
import 'package:flutter/widgets.dart';

class GlassLabMarker extends StatelessWidget {
  const GlassLabMarker(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(identifier: id, label: id, container: true, child: child);
}

class GlassLabReady extends StatelessWidget {
  const GlassLabReady({super.key});

  @override
  Widget build(BuildContext context) => const GlassLabMarker('scene.ready', child: SizedBox(width: 1, height: 1));
}
```

  - `glass_lab_backdrop.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import 'glass_lab_launch.dart';
import 'glass_lab_marker.dart';

class GlassLabBackdrop extends StatelessWidget {
  const GlassLabBackdrop({super.key, required this.id});

  static const Color missingColor = Color(0xFF808080);

  final String id;

  static File file(String id) => File('${GlassLabLaunch.directory.path}/$id.png');

  @override
  Widget build(BuildContext context) {
    if (id == 'none') {
      final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
      return ColoredBox(color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF), child: const SizedBox.expand());
    }
    if (id == 'scroll') return const GlassLabScrollBackdrop();
    return SizedBox.expand(
      child: Image.file(file(id), fit: BoxFit.fill, errorBuilder: (_, _, _) => const ColoredBox(color: missingColor)),
    );
  }
}

class GlassLabScrollBackdrop extends StatelessWidget {
  const GlassLabScrollBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return GlassLabMarker(
      'scroll.content',
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Image.file(
          GlassLabBackdrop.file('scroll'),
          width: size.width,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, _, _) => SizedBox(
            width: size.width,
            height: size.height * 3,
            child: const ColoredBox(color: GlassLabBackdrop.missingColor),
          ),
        ),
      ),
    );
  }
}
```

  - `glass_lab_probe.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import 'glass_lab_launch.dart';

void writeLabFile(String name, Object json) {
  final directory = GlassLabLaunch.directory;
  if (directory.path.isEmpty || !directory.existsSync()) return;
  final partial = File('${directory.path}/$name.partial');
  partial.writeAsStringSync(jsonEncode(json));
  partial.renameSync('${directory.path}/$name');
}

class GlassLabAccessibilityProbe extends StatefulWidget {
  const GlassLabAccessibilityProbe({super.key, required this.child});

  static const String file = 'accessibility.json';

  final Widget child;

  @override
  State<GlassLabAccessibilityProbe> createState() => _GlassLabAccessibilityProbeState();
}

class _GlassLabAccessibilityProbeState extends State<GlassLabAccessibilityProbe> {
  GlassAccessibilityData? _written;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlassAccessibility.platform,
      builder: (context, _) {
        final data = GlassAccessibility.of(context);
        if (data != _written) {
          _written = data;
          writeLabFile(GlassLabAccessibilityProbe.file, {
            'reduceTransparency': data.reduceTransparency,
            'increaseContrast': data.increaseContrast,
            'reduceMotion': data.reduceMotion,
          });
        }
        return widget.child;
      },
    );
  }
}
```

  - `glass_lab_registry.dart`:

```dart
import 'package:flutter/material.dart';

import 'glass_lab_backdrop.dart';
import 'glass_lab_launch.dart';
import 'glass_lab_marker.dart';
import 'scenes/material_scenes.dart';
import 'scenes/perf_scenes.dart';

sealed class GlassLabRegistry {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {...MaterialScenes.scenes};
  static final Map<String, Widget Function(GlassLabLaunch launch)> tools = {...PerfScenes.scenes};

  static Widget build(GlassLabLaunch launch) {
    if (launch.bare) return GlassLabBackdrop(id: launch.backdrop);
    final builder = scenes[launch.scene] ?? tools[launch.scene];
    return builder == null ? GlassLabMissing(launch: launch) : builder(launch);
  }
}

class GlassLabMissing extends StatelessWidget {
  const GlassLabMissing({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: launch.backdrop)),
        Center(
          child: GlassLabMarker(
            'scene.missing',
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('missing: ${launch.scene}', style: const TextStyle(fontSize: 15, color: Color(0xFF000000))),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

  - `glass_lab_screen.dart`:

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

- [ ] **Step 5: Write the scenes.** They copy the native catalog's layout point for point, in `tool/glass_lab/native/GlassLab/MaterialScenes.swift`.
  - `lib/lab/scenes/lab_parts.dart`:

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
          child: Center(
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

  - `lib/lab/scenes/material_scenes.dart`. The edge scenes jump to 300 pt only after the scroll image has decoded; otherwise the offset clamps to 0 (Review Focus 2).

```dart
import 'package:flutter/material.dart';
import 'package:ios_liquid_glass/ios_liquid_glass.dart';

import '../glass_lab_backdrop.dart';
import '../glass_lab_launch.dart';
import '../glass_lab_marker.dart';
import 'lab_parts.dart';

const Color labAccent = Color(0xFF1ACB64);

sealed class MaterialScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'material.regular': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: const [
        LabBlock(width: 150, height: 44),
        LabBlock(width: 250, height: 88),
        LabBlock(width: 360, height: 200),
      ],
    ),
    'material.clear': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 64,
      children: const [
        LabBlock(width: 250, height: 88, glass: Glass.clear),
        GlassDimming(child: LabBlock(width: 250, height: 88, glass: Glass.clear)),
      ],
    ),
    'material.tinted': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        LabBlock(width: 250, height: 88, glass: Glass.regular.tint(labAccent)),
        GlassLabMarker(
          'tinted.run',
          child: GlassEffect(
            glass: Glass.regular.tint(labAccent).interactive(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: GlassForeground(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.play_arrow_rounded, size: 20), SizedBox(width: 6), Text('Run', style: TextStyle(fontSize: 17))],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    'material.interactive': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [GlassLabMarker('glass', child: LabBlock(width: 250, height: 88, glass: Glass.regular.interactive()))],
    ),
    'material.shapes': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 40,
      children: [
        const LabBlock(width: 250, height: 60),
        const LabBlock(width: 250, height: 88, shape: GlassShape.rect(16)),
        SizedBox(
          width: 300,
          height: 180,
          child: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0x4DFFFFFF), borderRadius: BorderRadius.circular(40)),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: GlassEffect(shape: GlassShape.rect(28), child: SizedBox.expand()),
            ),
          ),
        ),
      ],
    ),
    'material.materialize': (launch) => LabCentered(
      backdrop: launch.backdrop,
      bottom: const LabButton(title: 'Toggle', id: 'toggle'),
      children: const [LabBlock(width: 250, height: 88)],
    ),
    'material.merge': (launch) => LabCentered(
      backdrop: launch.backdrop,
      bottom: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [LabButton(title: 'Merge', id: 'merge'), SizedBox(width: 24), LabButton(title: 'Split', id: 'split')],
      ),
      children: const [
        GlassEffectContainer(
          spacing: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
              SizedBox(width: 80),
              LabBlock(width: 80, height: 80, shape: GlassShape.circle()),
            ],
          ),
        ),
      ],
    ),
    'material.union': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        GlassEffectContainer(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, icon) in const [Icons.star, Icons.favorite, Icons.bolt, Icons.eco].indexed) ...[
                if (index > 0) const SizedBox(width: 16),
                GlassEffect(
                  shape: const GlassShape.rect(20),
                  child: SizedBox.square(dimension: 64, child: GlassForeground(child: Icon(icon, size: 24))),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    'material.morph': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        GlassLabMarker(
          'morph',
          child: GlassEffect(
            glass: Glass.regular.interactive(),
            shape: const GlassShape.circle(),
            child: const SizedBox.square(dimension: 56, child: GlassForeground(child: Icon(Icons.add, size: 22))),
          ),
        ),
      ],
    ),
    'material.flip': (launch) => const Stack(
      children: [
        Positioned.fill(child: GlassLabScrollBackdrop()),
        Positioned.fill(
          child: IgnorePointer(
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(height: 180),
                  LabBlock(width: 150, height: 44),
                  Spacer(),
                  LabBlock(width: 360, height: 200),
                  SizedBox(height: 96),
                  LabBlock(width: 150, height: 44),
                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    'material.edge.soft': (launch) => const EdgeScene(style: ScrollEdgeStyle.soft),
    'material.edge.hard': (launch) => const EdgeScene(style: ScrollEdgeStyle.hard),
    'material.edge.automatic': (launch) => const EdgeScene(style: ScrollEdgeStyle.automatic),
  };
}

class EdgeScene extends StatefulWidget {
  const EdgeScene({super.key, required this.style});

  static const double offset = 300;
  static const double barHeight = 54;
  static const double itemHeight = 44;

  final ScrollEdgeStyle style;

  @override
  State<EdgeScene> createState() => _EdgeSceneState();
}

class _EdgeSceneState extends State<EdgeScene> {
  final _controller = ScrollController();
  bool _scrolled = false;

  Widget _scrollOnce(BuildContext context, Widget child, int? frame, bool synchronous) {
    if (frame != null && !_scrolled) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpTo(EdgeScene.offset);
      });
    }
    return child;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final dark = GlassTheme.brightnessOf(context) == Brightness.dark;
    return ColoredBox(
      color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      child: Stack(
        children: [
          Positioned.fill(
            child: ScrollUnderBars(
              style: widget.style,
              child: GlassLabMarker(
                'scroll.content',
                child: SingleChildScrollView(
                  controller: _controller,
                  padding: EdgeInsets.only(top: top + EdgeScene.barHeight),
                  child: Image.file(
                    GlassLabBackdrop.file('scroll'),
                    width: width,
                    fit: BoxFit.fitWidth,
                    frameBuilder: _scrollOnce,
                    errorBuilder: (_, _, _) => SizedBox(width: width, height: 2000, child: const ColoredBox(color: GlassLabBackdrop.missingColor)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: EdgeScene.itemHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const GlassForeground(child: Text('Edge', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                Positioned(
                  right: 16,
                  child: GlassEffect(
                    child: const SizedBox(
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Center(child: GlassForeground(child: Text('Edit', style: TextStyle(fontSize: 17)))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

  - `lib/lab/scenes/perf_scenes.dart`:

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
    'perf.none': (launch) => const PerfScene(glass: false),
    'perf.glass': (launch) => const PerfScene(glass: true),
  };

  static Map<String, double> stats(List<double> values) {
    final sorted = [...values]..sort();
    double at(double q) => sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * q).round()];
    return {'median': at(0.5), 'p90': at(0.9), 'max': at(1)};
  }
}

class PerfScene extends StatefulWidget {
  const PerfScene({super.key, required this.glass});

  final bool glass;

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
      'scene': widget.glass ? 'perf.glass' : 'perf.none',
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
        if (widget.glass)
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
                              child: LiquidGlass.withOwnLayer(
                                settings: const LiquidGlassSettings(),
                                shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                                child: const SizedBox(width: 110, height: 44),
                              ),
                            ),
                        ],
                      ),
                    ),
                  LiquidGlass.withOwnLayer(
                    settings: const LiquidGlassSettings(),
                    shape: const LiquidRoundedSuperellipse(borderRadius: 40),
                    child: const SizedBox(width: 360, height: 200),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 6: Write the entry point** `packages/ios_liquid_glass/example/lib/main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lab/glass_lab_launch.dart';
import 'lab/glass_lab_registry.dart';
import 'lab/glass_lab_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launch = kDebugMode ? await GlassLabLaunch.load() : null;
  runApp(ExampleApp(launch: launch));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.launch});

  final GlassLabLaunch? launch;

  @override
  Widget build(BuildContext context) {
    final launch = this.launch;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: launch != null ? GlassLabScreen(launch: launch) : const SceneIndex(),
    );
  }
}

class SceneIndex extends StatelessWidget {
  const SceneIndex({super.key});

  @override
  Widget build(BuildContext context) {
    final ids = GlassLabRegistry.scenes.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('ios_liquid_glass')),
      body: ListView(
        children: [
          for (final id in ids)
            ListTile(
              title: Text(id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => GlassLabScreen(launch: GlassLabLaunch(scene: id))),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Run the example gates**

Run (from `packages/ios_liquid_glass/example`): `flutter analyze && flutter test`
Expected: "No issues found!" and 6 tests passing.

- [ ] **Step 8: Point the native scenes at the same layout.** In `tool/glass_lab/native/GlassLab/MaterialScenes.swift`:
  - In `FlipScene`, replace

```swift
            VStack {
                GlassBlock(width: 150, height: 44).padding(.top, 180)
                Spacer()
                GlassBlock(width: 360, height: 200).padding(.bottom, 180)
            }
```

  with

```swift
            VStack(spacing: 0) {
                GlassBlock(width: 150, height: 44).padding(.top, 180)
                Spacer()
                GlassBlock(width: 360, height: 200).padding(.bottom, 96)
                GlassBlock(width: 150, height: 44).padding(.bottom, 40)
            }
```

    At maximum scroll the new bottom block sits over the black part of the scroll backdrop. That is the only way to see small glass over black in light mode, which Task 9 needs.

  - In `EdgeScene`, add `    static let offset: CGFloat = 300` as the first line of the struct, and `    @State private var position = ScrollPosition(edge: .top)` after `let style: ScrollEdgeEffectStyle`. Then add two modifiers to the `ScrollView`, right before `.accessibilityIdentifier("scroll.content")`:

```swift
            .scrollPosition($position)
            .onAppear { position.scrollTo(y: EdgeScene.offset) }
```

- [ ] **Step 9: Pin the regions the tuner scores, and make the edge scenes static.**
  - Light glass on white is nearly invisible, so detected boxes are unreliable there. The element boxes are the scenes' fixed layout, measured on native.
  - The edge scenes get a static, pinned top band.

Run from `packages/mobile`:

```bash
python3 - <<'EOF'
import json
from pathlib import Path
path = Path("tool/glass_lab/scenes.json")
scenes = json.loads(path.read_text())
regions = {
    "material.regular": {"s44": [126, 237, 150, 44], "s88": [76, 329, 250, 88], "s200": [21, 465, 360, 200]},
    "material.clear": {"plain": [76, 331, 250, 88], "dimmed": [76, 483, 250, 88]},
    "material.tinted": {"block": [76, 365, 250, 88], "run": [162, 501, 78, 37]},
}
for scene in scenes:
    if scene["id"] in regions:
        scene["regions"] = regions[scene["id"]]
    if scene["id"].startswith("material.edge."):
        scene["steps"] = []
        scene["regions"] = {"edge": [0, 0, 402, 240]}
        scene["track"] = "edge"
        scene["measures"] = ["mad", "luminance"]
path.write_text(json.dumps(scenes, indent=2, ensure_ascii=False) + "\n")
EOF
git diff --stat tool/glass_lab/scenes.json
```

Expected: only `material.regular`, `material.clear`, `material.tinted` and the three `material.edge.*` entries change. `material.regular`, `clear` and `tinted` get `regions` but no `track`, so the report's analysis of them is unchanged.

- [ ] **Step 10: Teach the manifest and the analysis about `measures`.** In `tool/glass_lab/harness/manifest.py`:
  - after the `FIELDS = (...)` line, add `STATIC_MEASURES = ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")`;
  - in `Scene`, after `prepare: tuple = ()`, add `    measures: tuple = STATIC_MEASURES`;
  - in `validate`, right after the two lines that check `track`, add:

```python
        measures = entry.get("measures", list(STATIC_MEASURES))
        if not isinstance(measures, list) or not measures:
            errors.append(f"{where}: measures must be a non-empty list")
        else:
            errors += [f"{where}: unknown measure {m}" for m in measures if m not in STATIC_MEASURES]
```

  - in `parse`, after `prepare=tuple(entry.get("prepare", [])),`, add `            measures=tuple(entry.get("measures", STATIC_MEASURES)),`.

In `tool/glass_lab/harness/analyze.py`, replace the two lines that build `checks` and `measures` from `result["static"]` with:

```python
    checks = {f"{name}.{key}": value for name, stat in result["static"].items() for key, value in stat["pass"].items() if key in scene.measures}
    measures = {f"{name}.{key}": (stat[key], metrics.THRESHOLDS[key], "max") for name, stat in result["static"].items() for key in stat["pass"] if key in scene.measures}
```

In `tool/glass_lab/harness/tests/test_manifest.py`, add before `test_select_by_id_group_and_prefix`:

```python
    def test_measures_default_to_every_static_measure(self):
        scene = manifest.parse([valid_scene()])[0]
        self.assertEqual(scene.measures, manifest.STATIC_MEASURES)

    def test_measures_restrict_and_are_validated(self):
        scene = manifest.parse([valid_scene(measures=["mad", "luminance"])])[0]
        self.assertEqual(scene.measures, ("mad", "luminance"))
        errors = manifest.validate([valid_scene(measures=["mad", "sharpness"])])
        self.assertTrue(any("unknown measure sharpness" in e for e in errors))
        self.assertTrue(manifest.validate([valid_scene(measures=[])]))
```

- [ ] **Step 11: Add the example target to the harness.** First replace `tool/glass_lab/harness/tests/test_record.py` with:

```python
import json
import sys
import tempfile
import unittest
from pathlib import Path

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

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_record.py`
Expected: the two new tests fail, because `build.EXAMPLE_BUNDLE` and the `material` argument do not exist yet. Then make these changes:

  - `tool/glass_lab/harness/build.py`:
    - after `FLUTTER_APP = ...`, add

```python
EXAMPLE = MOBILE / "packages" / "ios_liquid_glass" / "example"
EXAMPLE_DATA = OUT / "example"
EXAMPLE_APP = EXAMPLE_DATA / "Build/Products/Debug-iphonesimulator/Runner.app"
```

    - after `FLUTTER_BUNDLE = ...`, add

```python
EXAMPLE_BUNDLE = "dev.operator.iosliquidglass.example"
FLUTTER_TARGETS = {"example": EXAMPLE_BUNDLE, "operator": FLUTTER_BUNDLE}
```

    - replace the whole `def flutter(udid):` function with:

```python
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


def flutter(udid):
    flutter_app(udid, MOBILE, FLUTTER_DATA, FLUTTER_APP)


def example(udid):
    flutter_app(udid, EXAMPLE, EXAMPLE_DATA, EXAMPLE_APP)
```

  - `tool/glass_lab/harness/record.py`:
    - replace `write_launch_file` with

```python
def write_launch_file(folder, scene_id, backdrop, bare, material=None):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    payload = {"scene": scene_id, "backdrop": backdrop, "bare": bare}
    if material:
        payload["material"] = material
    (folder / LAUNCH_FILE).write_text(json.dumps(payload))
```

    - in `drive`, change the signature to `def drive(udid, target, scene_id, steps, backdrop, bare, out_dir, settle=1.5, material=None):`, the folder line to `    folder = launch_folder(udid, target) if target in build.FLUTTER_TARGETS.values() and scene_id else None`, and the call to `        write_launch_file(folder, scene_id, backdrop, bare, material)`;
    - replace `target_for` with

```python
def target_for(scene, app, flutter_target="example"):
    if scene.native_only:
        return scene.app
    return build.NATIVE_BUNDLE if app == "native" else build.FLUTTER_TARGETS[flutter_target]
```

    - change `capture` to `def capture(udid, scene, app, backdrop, out_dir, flutter_target="example"):`, with its first body line after `out_dir = Path(out_dir)` reading `    target = target_for(scene, app, flutter_target)`.

  - `tool/glass_lab/harness/lab.py`:
    - `cmd_build` becomes

```python
def cmd_build(args):
    udid = sim.device()
    if args.target in ("native", "all"):
        build.native(udid)
    if args.target in ("example", "all"):
        build.example(udid)
    if args.target in ("operator", "all"):
        build.flutter(udid)
    print(f"built for {udid}")
```

    - in `cmd_prepare`, change `for bundle in (build.NATIVE_BUNDLE, build.FLUTTER_BUNDLE):` to `for bundle in (build.NATIVE_BUNDLE, *build.FLUTTER_TARGETS.values()):`;
    - `run_cases` takes a last parameter `flutter_target="example"` and passes it on: `record.capture(udid, scene, app, chosen, case_dir / app, flutter_target)`;
    - `cmd_run` passes `args.flutter` as the last argument of `run_cases`. `cmd_baseline` passes `args.flutter` to both of its `run_cases` calls;
    - in `parser()`:
      - `b.add_argument("target", nargs="?", default="all", choices=("native", "example", "operator", "all"))`;
      - after the `--a11y` argument of `run`, add `r.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))`;
      - replace `commands.add_parser("baseline").set_defaults(func=cmd_baseline)` with

```python
    bl = commands.add_parser("baseline")
    bl.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    bl.set_defaults(func=cmd_baseline)
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: OK, 49 tests: 45 before, plus 2 manifest and 2 record tests. `test_lab_ids_match_the_native_registry` still passes, because no scene id changed.

- [ ] **Step 12: Build all three apps and measure placement and edges.** From `packages/mobile`:

```bash
python3 tool/glass_lab/harness/lab.py build all
python3 tool/glass_lab/harness/lab.py prepare
python3 tool/glass_lab/harness/lab.py run material.regular --appearance dark --backdrop black
python3 tool/glass_lab/harness/lab.py run material.edge --appearance dark
```

Then measure the edge alignment on the last run:

```bash
python3 - <<'EOF'
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, "tool/glass_lab/harness")
import metrics
run = sorted(Path("build/glass_lab/runs").iterdir())[-1]
for style in ("soft", "hard", "automatic"):
    case = run / f"material.edge.{style}" / "dark-scroll"
    native, flutter = metrics.load(case / "native/ready.png"), metrics.load(case / "flutter/ready.png")
    profile = lambda image: image.mean(2)[:, 60:1140].mean(1)
    a, b = profile(native), profile(flutter)
    shift = min(range(-60, 61), key=lambda s: np.abs(a[900:2400] - b[900 + s:2400 + s]).mean())
    band = metrics.static_compare(native, flutter, native, flutter, (0, 0, 402, 240))
    print(style, "shift px", shift, "band mad", round(band["mad"], 1))
EOF
```

Expected:
- `material.regular` `dark-black` is "compared" in the report. Its `ready.bbox_pt` and `ready.centre_pt` are 0.0 for all three sizes, because dark glass on black has no visible shadow and placement matches native exactly.
- The edge script prints `shift px 0` for `soft`, `hard` and `automatic`. With seed values, the prototype measured band MAD 33.6 (soft), 3.8 (hard) and 3.8 (automatic). Task 11 tunes them.
- Open `build/glass_lab/runs/<run>/report.html` and look at the edge filmstrips. The native bar and the example bar have the same title and "Edit" position (centre y 84 pt).

- [ ] **Step 13: Commit**

```bash
git add -A packages/ios_liquid_glass/example pubspec.yaml tool/glass_lab
git commit -m "feat(mobile): ios_liquid_glass example app is the glass lab's Flutter target

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Lab probes for live accessibility and frame cost

**Files:**
- Create: `tool/glass_lab/harness/probe.py`, `tool/glass_lab/harness/tests/test_probe.py`
- Modify: `tool/glass_lab/harness/lab.py` (the `perf` and `a11y` commands)

**Interfaces:**
- Consumes:
  - the example's `accessibility.json` and `perf.json` (Task 7);
  - `record.launch_folder`, `record.write_launch_file` and `record.clear_launch_file`;
  - `sim.accessibility(udid, mode)`, which writes the simulator defaults and `simctl ui increase_contrast`.
- Produces:
  - `probe.perf(udid, bundle, takes=3)`, returning `{perf.none: {...}, perf.glass: {...}, glass_cost_ms}`. It runs the takes in alternating order, because A/B timing drifts with order;
  - `probe.perf_order(scenes, takes)` and `probe.perf_summary(results)`;
  - `probe.accessibility_check(udid, bundle, modes=...)`, returning `{mode: {live: bool, seen: {...}}}`. It always restores `none` and terminates the app, even on failure;
  - `probe.wait_for(read, accept, timeout, interval=0.25)`, which raises `TimeoutError`;
  - `lab.py perf [--flutter example|operator] [--appearance dark|light] [--takes 3] [--out file]`;
  - `lab.py a11y [--flutter example|operator]`, which exits non-zero when a mode is not delivered live.

- [ ] **Step 1: Write the failing test** `tool/glass_lab/harness/tests/test_probe.py`:

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

- [ ] **Step 2: Run it to see it fail**

Run (from `packages/mobile`): `python3 -m unittest tool/glass_lab/harness/tests/test_probe.py`
Expected: `ModuleNotFoundError: No module named 'probe'`.

- [ ] **Step 3: Write** `tool/glass_lab/harness/probe.py`:

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
PERF_SCENES = ("perf.none", "perf.glass")
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
    if all(scene in summary for scene in PERF_SCENES):
        summary["glass_cost_ms"] = summary["perf.glass"]["raster_median_ms"] - summary["perf.none"]["raster_median_ms"]
    return summary


def perf(udid, bundle, takes=3):
    results = {scene: [] for scene in PERF_SCENES}
    for scene_id in perf_order(PERF_SCENES, takes):
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

- [ ] **Step 4: Add the commands to** `tool/glass_lab/harness/lab.py`:
  - add `import probe` after `import metrics`;
  - add these two functions right before `def cmd_geometry(args):`

```python
def cmd_perf(args):
    udid = sim.device()
    sim.appearance(udid, args.appearance)
    summary = probe.perf(udid, build.FLUTTER_TARGETS[args.flutter], args.takes)
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
```

  - in `parser()`, right before `g = commands.add_parser("geometry")`:

```python
    f = commands.add_parser("perf")
    f.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    f.add_argument("--appearance", default="dark", choices=("light", "dark"))
    f.add_argument("--takes", type=int, default=3)
    f.add_argument("--out")
    f.set_defaults(func=cmd_perf)
    y = commands.add_parser("a11y")
    y.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    y.set_defaults(func=cmd_a11y)
```

- [ ] **Step 5: Run the harness tests**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: OK, 54 tests: `test_probe` adds 5.

- [ ] **Step 6: Prove every accessibility setting reaches the running app live** (spec Done item 1)

Run: `python3 tool/glass_lab/harness/lab.py a11y`
Expected: exit status 0. The printed JSON shows `"live": true` for `reduce-transparency`, `increase-contrast` and `reduce-motion`, each with only its own flag true in `seen`, and no `"reset": false`. Then run `xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled`, which must print `0`.

- [ ] **Step 7: Prove the frame probe works**

Run: `python3 tool/glass_lab/harness/lab.py perf --takes 2`
Expected: about 720 frames per scene. `perf.none` has a raster median under 1.5 ms, and `perf.glass` has one of about 12–13 ms on this machine; the prototype measured 0.65 and 12.54. Task 9 does the old-versus-new comparison.

- [ ] **Step 8: Commit**

```bash
git add tool/glass_lab/harness
git commit -m "feat(mobile): glass lab probes live accessibility changes and glass frame cost

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Flip spike and frame cost (spec B8 and Done items 7–8)

**Files:**
- Create: `tool/glass_lab/harness/flip.py`, `tool/glass_lab/harness/tests/test_flip.py`, `docs/liquid_glass/02a-looks/flip-spike.md`
- Modify: `tool/glass_lab/harness/lab.py` (the `flip` command)

**Interfaces:**
- Consumes:
  - native `material.flip` recordings, whose overview frames are 1x at 20 fps;
  - native `material.regular` `ready.png` files on `white` and `black` in both appearances;
  - `analyze.window` (the scene's frames) and `probe.perf` (Task 8).
- Produces:
  - `flip.report(run_dir, regular_run=None)`, a Markdown table;
  - `flip.inner`, `flip.ring` (5th and 95th percentile of the backdrop band around a box), `flip.over`, `flip.verdict` and `flip.predictions`;
  - the fixed boxes `flip.REGULAR` (44 and 200 pt blocks of `material.regular`) and `flip.FLIP` (`small_top`, `large`, `small_bottom` of `material.flip`);
  - `lab.py flip [run_dir] [--regular run_dir] [--out file]`.

- [ ] **Step 1: Write the failing test** `tool/glass_lab/harness/tests/test_flip.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import flip


class FlipTests(unittest.TestCase):
    def test_reads_inside_and_around_a_box(self):
        image = np.zeros((100, 100, 3), dtype=np.float32)
        image[40:60, 20:80] = 200
        box = (20, 40, 60, 20)
        self.assertAlmostEqual(flip.inner(image, box, 1), 200)
        self.assertEqual(flip.ring(image, box, 1), (0.0, 0.0))

    def test_over_takes_the_median_where_the_backdrop_matches(self):
        rows = [
            {"small_top": (250, 255, 182)},
            {"small_top": (251, 255, 184)},
            {"small_top": (120, 255, 90)},
            {"small_top": (0, 5, 40)},
            {"small_top": (0, 200, 70)},
        ]
        self.assertEqual(flip.over(rows, "small_top", "white"), 183)
        self.assertEqual(flip.over(rows, "small_top", "black"), 40)
        self.assertIsNone(flip.over(rows, "large", "white"))

    def test_verdicts(self):
        self.assertEqual(flip.verdict(182, 185, 250), "no flip")
        self.assertEqual(flip.verdict(245, 185, 250), "flips")
        self.assertEqual(flip.verdict(215, 185, 250), "neither")
        self.assertEqual(flip.verdict(None, 185, 250), "not seen")


if __name__ == "__main__":
    unittest.main()
```

Run (from `packages/mobile`): `python3 -m unittest tool/glass_lab/harness/tests/test_flip.py`
Expected: `ModuleNotFoundError: No module named 'flip'`.

- [ ] **Step 2: Write** `tool/glass_lab/harness/flip.py`:

```python
from pathlib import Path

import numpy as np

import analyze
import metrics

WHITE = 245
BLACK = 10
TOLERANCE = 12
GAP = 4
BAND = 6
REGULAR = {44: (126, 237, 150, 44), 200: (21, 465, 360, 200)}
FLIP = {"small_top": (126, 242, 150, 44), "large": (21, 460, 360, 200), "small_bottom": (126, 756, 150, 44)}


def scaled(box, scale):
    return tuple(int(round(v * scale)) for v in box)


def inner(image, box, scale):
    x, y, w, h = scaled(box, scale)
    return float(metrics.luma(image[y + h // 4 : y + h - h // 4, x + w // 4 : x + w - w // 4]).mean())


def ring(image, box, scale):
    x, y, w, h = scaled(box, scale)
    g, b = int(round(GAP * scale)), int(round(BAND * scale))
    above = metrics.luma(image[max(0, y - g - b) : y - g, x : x + w])
    below = metrics.luma(image[y + h + g : y + h + g + b, x : x + w])
    values = np.concatenate([above.ravel(), below.ravel()])
    return float(np.percentile(values, 5)), float(np.percentile(values, 95))


def observe(paths, boxes, scale=1):
    rows = []
    for path in paths:
        image = metrics.load(path)
        rows.append({name: (*ring(image, box, scale), inner(image, box, scale)) for name, box in boxes.items()})
    return rows


def over(rows, name, backdrop):
    accept = (lambda low, high: low >= WHITE) if backdrop == "white" else (lambda low, high: high <= BLACK)
    values = [row[name][2] for row in rows if name in row and accept(row[name][0], row[name][1])]
    return float(np.median(values)) if values else None


def verdict(observed, same, other, tolerance=TOLERANCE):
    if observed is None:
        return "not seen"
    if abs(observed - same) <= tolerance:
        return "no flip"
    if abs(observed - other) <= tolerance:
        return "flips"
    return "neither"


def predictions(run_dir):
    table = {}
    for appearance in ("light", "dark"):
        for backdrop in ("white", "black"):
            ready = metrics.load(Path(run_dir) / "material.regular" / f"{appearance}-{backdrop}" / "native" / "ready.png")
            for size, box in REGULAR.items():
                table[(appearance, backdrop, size)] = inner(ready, box, metrics.SCALE)
    return table


def report(run_dir, regular_run=None):
    run_dir = Path(run_dir)
    expected = predictions(regular_run or run_dir)
    lines = ["| Appearance | Glass | Over | Observed | Same appearance | Other appearance | Verdict |", "|---|---|---|---|---|---|---|"]
    for appearance in ("light", "dark"):
        case = run_dir / "material.flip" / f"{appearance}-scroll" / "native"
        found = analyze.window(case)
        rows = observe(found[2].paths if found else [], FLIP)
        other = "dark" if appearance == "light" else "light"
        for name in FLIP:
            size = 200 if name == "large" else 44
            for backdrop in ("white", "black"):
                seen = over(rows, name, backdrop)
                same, flipped = expected[(appearance, backdrop, size)], expected[(other, backdrop, size)]
                shown = "—" if seen is None else f"{seen:.0f}"
                lines.append(f"| {appearance} | {name} | {backdrop} | {shown} | {same:.0f} | {flipped:.0f} | {verdict(seen, same, flipped)} |")
    return "\n".join(lines) + "\n"
```

- [ ] **Step 3: Add the command to** `tool/glass_lab/harness/lab.py`:
  - add `import flip` after `import build`;
  - add before `def cmd_perf(args):`

```python
def cmd_flip(args):
    run_dir = Path(args.run_dir) if args.run_dir else latest_run()
    text = flip.report(run_dir, args.regular)
    print(text)
    if args.out:
        Path(args.out).write_text(text)
```

  - in `parser()`, before `f = commands.add_parser("perf")`:

```python
    l = commands.add_parser("flip")
    l.add_argument("run_dir", nargs="?")
    l.add_argument("--regular")
    l.add_argument("--out")
    l.set_defaults(func=cmd_flip)
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: OK, 57 tests: the 3 flip tests are added.

- [ ] **Step 4: Record native flip and the static predictions**

```bash
python3 tool/glass_lab/harness/lab.py run material.regular --app native
python3 tool/glass_lab/harness/lab.py run material.flip --app native
python3 tool/glass_lab/harness/lab.py flip --regular build/glass_lab/runs/<the material.regular run> --out build/glass_lab/flip.md
```

Expected: a 12-row table. The prototype printed this; values within ±3 are the same result:

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

If any row says `flips`, stop and report it. The decision below assumes no flip, and a flip changes 2A's scope.

- [ ] **Step 5: Measure frame cost, new against old.** Take the new renderer first:

```bash
python3 tool/glass_lab/harness/lab.py perf --takes 3 --out build/glass_lab/perf-new.json
```

Then put the old final shader, its helper and its uniform packing back **temporarily**:

```bash
S=packages/ios_liquid_glass/lib/assets/shaders
git show development:packages/mobile/packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag > $S/liquid_glass_final_render.frag
git show development:packages/mobile/packages/liquid_glass_renderer/lib/assets/shaders/render.glsl > $S/render.glsl
```

In `packages/ios_liquid_glass/lib/src/rendering/liquid_glass_render_object.dart`, replace the `_updateShaderSettings` method with the old one:

```dart
  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness * devicePixelRatio,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        )
        ..setFloat(settings.fillRatio);
    });
  }
```

Then build and measure:

```bash
python3 tool/glass_lab/harness/lab.py build example
python3 tool/glass_lab/harness/lab.py perf --takes 3 --out build/glass_lab/perf-old.json
```

Restore the new code and rebuild:

```bash
git checkout -- packages/ios_liquid_glass/lib
rm -f packages/ios_liquid_glass/lib/assets/shaders/render.glsl
git status --short packages/ios_liquid_glass
python3 tool/glass_lab/harness/lab.py build example
```

Expected:
- `git status` prints nothing for the package;
- `perf.glass.raster_median_ms` in `perf-new.json` is at most 1.2 × the one in `perf-old.json`. The prototype measured 12.54 new against 12.63 old, with 0.65 for `perf.none`.

- [ ] **Step 6: Write** `docs/liquid_glass/02a-looks/flip-spike.md` with these sections, filled from Steps 4 and 5:

```markdown
# 2A spike: light/dark flip and frame cost

Date: <today>. Simulator: iPhone 17 Pro (iOS 27). Spec: `02a-looks/spec.md` §B8, Done items 7 and 8.

## Question
Does native small glass flip between light and dark with the content behind it, and can the package match it cheaply?

## Method
- Native `material.flip` scrolls the `scroll` backdrop (text, photo, white, black) under three glass blocks: small at the top, large, and small at the bottom.
- `flip.py` reads the backdrop in a band around each block and the glass in the block's centre half. It takes the median glass value in frames where the band is uniformly white (5th percentile ≥ 245) or black (95th percentile ≤ 10).
- It compares that value with the same-size block of `material.regular` over `white` or `black`, in the same appearance ("no flip") and in the other appearance ("flips").

## Result
<the table from build/glass_lab/flip.md>

## Decision
Native `.glassEffect()` glass does not flip on iOS 27, at 44 pt or at 200 pt, in either appearance. The package already draws the same-appearance material, so B8 needs no implementation in 2A. Bars and tab bars are measured again in project 3 with the `tabbar.*` and `navbar.*` scenes.

## Frame cost (Done item 8)
| Renderer | perf.none raster median | perf.glass raster median | perf.glass p90 |
|---|---|---|---|
| old (development) | <from perf-old.json> | <...> | <...> |
| new (this branch) | <from perf-new.json> | <...> | <...> |

`perf.glass` is 13 own-layer glasses (12 of 110 × 44, one of 360 × 200) over a backdrop that moves every frame, in a debug build on the simulator. The new renderer is within <x>% of the old one, under the 20% budget. The real-device check is project 5.
```

- [ ] **Step 7: Commit**

```bash
git add tool/glass_lab/harness docs/liquid_glass/02a-looks/flip-spike.md
git commit -m "docs(mobile): 2A flip spike finds no native flip; the new renderer costs what the old one did

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Automatic tuning (`lab.py tune`)

**Files:**
- Create: `tool/glass_lab/harness/tune.py`, `tool/glass_lab/harness/material_table.py`, `tool/glass_lab/harness/tests/test_tune.py`
- Modify: `tool/glass_lab/harness/lab.py` (the `tune` command)

**Interfaces:**
- Consumes:
  - `record.drive(..., material=...)` (Task 7);
  - `metrics.static_compare`, `metrics.glass_boxes`, `metrics.union` and `metrics.crop`;
  - `Scene.track`, `Scene.regions` and `Scene.measures` (Task 7).
- Produces:
  - **`material_table`**:
    - `Table(path, name, key, order)`;
    - `material_table.MATERIAL` (`ios27.dart`, `ios27Table`, keys `a.row.anchor`) and `material_table.SCROLL_EDGE` (`ios27_scroll_edge.dart`, `ios27ScrollEdgeTable`, keys `a.style`);
    - `for_scene(scene_id)`, `parse(text, table)`, `format_table(rows, table)`, `read(path=None, table=MATERIAL)`, `write(rows, path=None, table=MATERIAL)` and `update(key, values, path=None, table=MATERIAL)`;
    - `EDGE_PREFIX = "edge."`, and `APPEARANCES`, `ROWS`, `ANCHORS`, `STYLES`.
  - **`tune`**:
    - `score(stat, measures)`: each measure is divided by its threshold and capped at 10;
    - `parse_params("name=lo:hi:n,...")`;
    - `coordinate_descent(evaluate, grid, start, min_gain=0.01, max_passes=4)`, returning `(best, best_score, log)`;
    - `element_box(boxes, size)`, `named_region(scene, names)`, `table_key(scene, appearance, row, size)`, `field(name)` and `filmstrip(native, flutter, region, dest)`;
    - `Evaluator`, and `run(udid, scene, appearance, backdrops, grid, row, size, flutter_target, out, write=False, max_passes=4, regions=())`.
  - **Output** in `build/glass_lab/tune/<timestamp>/`: `log.jsonl` (every candidate with its measures), `best.json`, `best-<backdrop>.png` (native | best candidate | difference × 4) and the candidates' screenshots.
  - **Command**: `lab.py tune --scene S --appearance light|dark --backdrops a,b --params name=lo:hi:n,... [--row regular|clear|tinted|reduceTransparency|increaseContrast] [--size 44|88|200] [--region name,name] [--a11y MODE] [--flutter example|operator] [--passes N] [--write]`.
- How a candidate is scored:
  - the example app gets the `material` map through the launch file, and `GlassMaterialOverride` applies it;
  - scenes with a `track` region (the edge scenes) compare that region, over the scene's `measures` only;
  - otherwise `--region` names regions from the manifest (Task 7), which are unioned and padded by 12 pt;
  - otherwise the native element whose shorter side is closest to `--size` is compared, padded by 12 pt;
  - each candidate costs about 10–15 s per backdrop.

- [ ] **Step 1: Write the failing test** `tool/glass_lab/harness/tests/test_tune.py`:

```python
import sys
import tempfile
import unittest
from pathlib import Path

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
        grid = tune.parse_params("lift=0:0.4:5,gain=0.5:1:2")
        self.assertEqual(grid["lift"], [0.0, 0.1, 0.2, 0.3, 0.4])
        self.assertEqual(grid["gain"], [0.5, 1.0])

    def test_parses_scroll_edge_names(self):
        self.assertEqual(tune.parse_params("edge.blur=2:6:3"), {"edge.blur": [2.0, 4.0, 6.0]})
        self.assertEqual(tune.field("edge.blur"), "blur")
        self.assertEqual(tune.field("lift"), "lift")


class DescentTests(unittest.TestCase):
    def test_finds_the_optimum_of_a_separable_bowl(self):
        target = {"lift": 0.2, "gain": 0.7}
        evaluate = lambda m: (m["lift"] - target["lift"]) ** 2 + (m["gain"] - target["gain"]) ** 2
        grid = tune.parse_params("lift=0:0.4:5,gain=0.5:1:6")
        best, value, log = tune.coordinate_descent(evaluate, grid, {"lift": 0.0, "gain": 1.0})
        self.assertAlmostEqual(best["lift"], 0.2)
        self.assertAlmostEqual(best["gain"], 0.7)
        self.assertLess(value, 1e-9)
        self.assertGreater(len(log), 1)

    def test_start_is_kept_when_nothing_is_better(self):
        best, value, _ = tune.coordinate_descent(lambda m: abs(m["lift"] - 0.1), {"lift": [0.0, 0.1, 0.2]}, {"lift": 0.1})
        self.assertEqual(best, {"lift": 0.1})
        self.assertEqual(value, 0)


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


class TableTests(unittest.TestCase):
    def test_round_trip_and_update(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "ios27.dart"
            table = {"dark.regular.44": {"lift": 0.1, "gain": 0.75}, "light.clear.200": {"frost": 1.5}}
            material_table.write(table, path)
            self.assertEqual(material_table.read(path), table)
            material_table.update("dark.regular.44", {"lift": 0.25}, path)
            self.assertEqual(material_table.read(path)["dark.regular.44"], {"lift": 0.25, "gain": 0.75})

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

Run: `python3 -m unittest tool/glass_lab/harness/tests/test_tune.py`
Expected: `ModuleNotFoundError: No module named 'material_table'`.

- [ ] **Step 2: Write** `tool/glass_lab/harness/material_table.py`:

```python
import re
from dataclasses import dataclass
from pathlib import Path

MATERIAL_DIR = Path(__file__).resolve().parents[3] / "packages" / "ios_liquid_glass" / "lib" / "src" / "material"
FIELD = re.compile(r"'(\w+)': (-?\d+(?:\.\d+)?(?:e-?\d+)?)")
APPEARANCES = ("dark", "light")
ROWS = ("regular", "clear", "tinted", "reduceTransparency", "increaseContrast")
ANCHORS = (44, 88, 200)
STYLES = ("soft", "hard", "automatic")
EDGE_PREFIX = "edge."


def material_order(key):
    appearance, row, anchor = key.split(".")
    return (APPEARANCES.index(appearance), ROWS.index(row), int(anchor))


def edge_order(key):
    appearance, style = key.split(".")
    return (APPEARANCES.index(appearance), STYLES.index(style))


@dataclass(frozen=True)
class Table:
    path: Path
    name: str
    key: str
    order: object


MATERIAL = Table(MATERIAL_DIR / "ios27.dart", "ios27Table", r"[a-zA-Z]+\.[a-zA-Z]+\.\d+", material_order)
SCROLL_EDGE = Table(MATERIAL_DIR / "ios27_scroll_edge.dart", "ios27ScrollEdgeTable", r"[a-zA-Z]+\.[a-zA-Z]+", edge_order)


def for_scene(scene_id):
    return SCROLL_EDGE if scene_id.startswith("material.edge.") else MATERIAL


def parse(text, table=MATERIAL):
    pattern = re.compile(rf"^\s*'({table.key})': \{{(.*)\}},\s*$")
    rows = {}
    for line in text.splitlines():
        match = pattern.match(line)
        if match:
            rows[match.group(1)] = {name: float(value) for name, value in FIELD.findall(match.group(2))}
    return rows


def number(value):
    text = f"{value:.4f}".rstrip("0")
    return text + "0" if text.endswith(".") else text


def format_table(rows, table=MATERIAL):
    lines = [f"const Map<String, Map<String, double>> {table.name} = {{"]
    for key in sorted(rows, key=table.order):
        body = ", ".join(f"'{name}': {number(value)}" for name, value in sorted(rows[key].items()))
        lines.append(f"  '{key}': {{{body}}},")
    lines.append("};")
    return "\n".join(lines) + "\n"


def read(path=None, table=MATERIAL):
    return parse(Path(path or table.path).read_text(), table)


def write(rows, path=None, table=MATERIAL):
    Path(path or table.path).write_text(format_table(rows, table))


def update(key, values, path=None, table=MATERIAL):
    rows = read(path, table)
    rows[key] = {**rows.get(key, {}), **values}
    write(rows, path, table)
    return rows
```

- [ ] **Step 3: Write** `tool/glass_lab/harness/tune.py`:

```python
import json
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
WEIGHTS = {"mad": 4.0, "luminance": 3.0, "rim_rms": 6.0, "centre_pt": 1.0, "bbox_pt": 1.0}
PAD = 12


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
    for _ in range(max_passes):
        before = best_score
        for name, values in grid.items():
            for value in values:
                if value == best.get(name):
                    continue
                candidate = {**best, name: value}
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
        for value in (best[name] - step, best[name] + step):
            candidate = {**best, name: round(value, 4)}
            result = evaluate(candidate)
            log.append((candidate, result))
            if result < best_score:
                best, best_score = candidate, result
    return best, best_score, log


def element_box(boxes, size):
    if not boxes:
        return None
    return min(boxes, key=lambda box: abs(min(box[2], box[3]) - size))


def named_region(scene, names):
    boxes = [tuple(scene.regions[name]) for name in names]
    return metrics.union(boxes, pad=PAD)


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
    def __init__(self, udid, scene, backdrops, size, flutter_target, out, regions=()):
        self.udid = udid
        self.scene = scene
        self.backdrops = backdrops
        self.size = size
        self.regions = tuple(regions)
        self.target = build.FLUTTER_TARGETS[flutter_target]
        self.out = Path(out)
        self.count = 0
        self.cache = {}
        self.records = []

    def _drive(self, target, backdrop, bare, folder, material=None):
        record.drive(self.udid, target, self.scene.id, [], backdrop, bare, folder, settle=1.0, material=material)
        return metrics.load(Path(folder) / "ready.png")

    def region(self, native, native_bare):
        if self.scene.track:
            return tuple(self.scene.regions[self.scene.track])
        if self.regions:
            return named_region(self.scene, self.regions)
        box = element_box(metrics.glass_boxes(native, native_bare), self.size)
        return metrics.union([box], pad=PAD) if box else (0, 0, *metrics.SCREEN)

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
        for backdrop in self.backdrops:
            native, native_bare, flutter_bare, region = self.references(backdrop)
            folder = self.out / "candidates" / f"{self.count:04d}" / backdrop
            flutter = self._drive(self.target, backdrop, False, folder, material)
            stat = metrics.static_compare(native, flutter, native_bare, flutter_bare, region)
            stats[backdrop] = {key: stat[key] for key in self.scene.measures}
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


def run(udid, scene, appearance, backdrops, grid, row, size, flutter_target, out, write=False, max_passes=4, regions=()):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    sim.appearance(udid, appearance)
    table = material_table.for_scene(scene.id)
    key = table_key(scene, appearance, row, size)
    current = material_table.read(table=table).get(key, {})
    start = {name: current.get(field(name), grid[name][len(grid[name]) // 2]) for name in grid}
    evaluate = Evaluator(udid, scene, backdrops, size, flutter_target, out, regions)
    best, best_score, _ = coordinate_descent(evaluate, grid, start, max_passes=max_passes)
    evaluate.filmstrips()
    summary = {"key": key, "scene": scene.id, "backdrops": backdrops, "start": start, "start_score": evaluate.records[0]["score"], "best": best, "best_score": best_score}
    (out / "best.json").write_text(json.dumps(summary, indent=2))
    if write:
        material_table.update(key, {field(name): value for name, value in best.items()}, table=table)
    return summary
```

- [ ] **Step 4: Add the command to** `tool/glass_lab/harness/lab.py`:
  - add `import tune` after `import sim`;
  - add before `def cmd_flip(args):`

```python
def cmd_tune(args):
    udid = sim.device()
    scene = manifest.select(manifest.load(), args.scene)[0]
    out = build.OUT / "tune" / time.strftime("%Y%m%d-%H%M%S")
    sim.accessibility(udid, args.a11y)
    try:
        summary = tune.run(
            udid, scene, args.appearance, args.backdrops.split(","), tune.parse_params(args.params),
            args.row, args.size, args.flutter, out, write=args.write, max_passes=args.passes,
            regions=args.region.split(",") if args.region else (),
        )
    finally:
        sim.accessibility(udid, "none")
    print(json.dumps(summary, indent=2))
    print(out)
```

  - in `parser()`, before `l = commands.add_parser("flip")`:

```python
    u = commands.add_parser("tune")
    u.add_argument("--scene", required=True)
    u.add_argument("--appearance", required=True, choices=("light", "dark"))
    u.add_argument("--backdrops", required=True)
    u.add_argument("--params", required=True)
    u.add_argument("--row", default="regular", choices=("regular", "clear", "tinted", "reduceTransparency", "increaseContrast"))
    u.add_argument("--size", type=int, default=88, choices=(44, 88, 200))
    u.add_argument("--region")
    u.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    u.add_argument("--flutter", default="example", choices=tuple(build.FLUTTER_TARGETS))
    u.add_argument("--passes", type=int, default=4)
    u.add_argument("--write", action="store_true")
    u.set_defaults(func=cmd_tune)
```

- [ ] **Step 5: Run the harness tests**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: OK, 75 tests in the prototype. The two committed-table tests pass, which proves the seed files of Tasks 4 and 6 are already in writer format.

- [ ] **Step 6: One real loop, without writing**

Run: `python3 tool/glass_lab/harness/lab.py tune --scene material.regular --appearance dark --backdrops stripes,black,white --size 88 --region s88 --params toneWhite=0.6:0.84:5 --passes 1`
Expected:
- about 8 candidates in 5–7 minutes;
- `best.json` shows `"key": "dark.regular.88"`, with `best_score` below `start_score`. In the prototype, `toneWhite` 0.85 → 0.6 took the score from 17.85 to 9.08;
- `best-stripes.png`, `best-black.png` and `best-white.png` exist;
- `git status --short packages/ios_liquid_glass` prints nothing, because nothing was written without `--write`.

- [ ] **Step 7: Commit**

```bash
git add tool/glass_lab/harness
git commit -m "feat(mobile): lab.py tune searches glass material parameters against native

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: The tuning campaign (the iOS 27 numbers)

**Files:**
- Modify, only through `lab.py tune --write` and the row-copy snippet below:
  - `packages/ios_liquid_glass/lib/src/material/ios27.dart`
  - `packages/ios_liquid_glass/lib/src/material/ios27_scroll_edge.dart`
- Create: `docs/liquid_glass/02a-looks/tuning-log.md`

**Interfaces:**
- Consumes: `lab.py tune` (Task 10), the example app (Task 7), and the manifest regions `s44`, `s88`, `s200`, `plain`, `dimmed`, `block`, `run` and `edge`.
- Produces: tuned `ios27Table` and `ios27ScrollEdgeTable` rows, plus a log of every run with its start and best score.

**What to expect.** In the prototype, one pass of A1 alone took dark regular 88 pt from score 17.85 to 7.18. Luminance passed on all three backdrops, and MAD passed on `white` and `black` (`stripes` was 4.7 against 4). A2 to A4 exist for the rim and the shadow; A1's grids are centred on the prototype's best values.

**How to run it.**
- Each `tune` run is long. Run it in the background and check its `log.jsonl`; never poll with short sleeps.
- One candidate costs about 12–15 s per backdrop. The search uses 3 backdrops (`stripes`, `white`, `black`); verification in Task 12 adds `photo` and `text`.
- Order matters: each step starts from the rows the previous step wrote.
- Rebuild the example app (`lab.py build example`) only when Dart code changes, never between tune runs. Tuning changes only the table, and the launch-file overrides carry the candidates.
- After every step, append one line to `docs/liquid_glass/02a-looks/tuning-log.md`: the step id, the command, `start_score`, `best_score`, the `best` values, and the tune folder name.
- Commit after each group (A to F). The message says which rows were tuned.

**When a case will not reach its threshold** (MAD ≤ 4, luminance ≤ 3, rim ≤ 6, centre ≤ 1 pt, box ≤ 1 pt):
- run the same step once more with every grid narrowed to the best value ± 2 of the old steps, with the same count;
- if it still fails, write the residual numbers into the tuning log and go on. Never hand-edit table values. Task 12 reports what failed.

**Copying rows.** Some steps start one row from another. `copy_row FROM TO KEEP SIZE_FROM` sets row `TO` to row `FROM`, except that the comma-separated `KEEP` fields come from row `SIZE_FROM`, which defaults to `TO` itself. Define it once in the shell, from `packages/mobile`:

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
SIZE=thickness,shadowOffsetY,shadowBlur,shadowOpacity
```

The prototype ran this snippet on a copy of the table; `test_the_committed_tables_are_in_writer_format` stayed green afterwards.

Every command below runs from `packages/mobile` and starts with `python3 tool/glass_lab/harness/lab.py tune`. `B3` means `--backdrops stripes,white,black`.

- [ ] **Group A: dark regular glass** (`--scene material.regular --appearance dark --row regular`)

| Step | Arguments after the common ones | About |
|---|---|---|
| A1 tone and frost | `B3 --size 88 --region s88 --params toneWhite=0.45:0.75:7,toneBlack=0.05:0.25:5,toneMid=0.3:0.6:7,frost=12:40:8,saturation=0.6:1.4:5 --passes 2 --write` | 70 min |
| A2 lens | `B3 --size 88 --region s88 --params thickness=8:32:7,refractiveIndex=1.05:1.5:6,dispersion=0:0.08:5 --passes 2 --write` | 40 min |
| A3 rim light | `B3 --size 88 --region s88 --params hairline=0:0.8:5,hairlineWidth=0.5:2.5:5,hairlineDark=0:0.5:6,hairlineLight=0.3:1:8,specular=0:0.8:5,specularWidth=0.5:3:6,specularPower=1:6:6,specularFill=0:0.8:5,lightAngle=-3.14:0:7 --passes 2 --write` | 2 h |
| A4 shadow | `--backdrops white,text --size 88 --region s88 --params shadowOpacity=0:0.3:7,shadowBlur=2:30:8,shadowOffsetY=0:8:9 --passes 2 --write` | 35 min |
| A5 settle | A1's arguments with `--passes 1` | 30 min |
| A6 small | `copy_row dark.regular.88 dark.regular.44 $SIZE`, then `B3 --size 44 --region s44 --params toneWhite=0.45:0.75:7,toneMid=0.3:0.6:7,frost=6:40:7,thickness=4:24:6,shadowOpacity=0:0.3:7,shadowBlur=2:30:8,hairlineWidth=0.5:2.5:5,specularWidth=0.5:3:6 --passes 1 --write` | 50 min |
| A7 large | `copy_row dark.regular.88 dark.regular.200 $SIZE`, then `B3 --size 200 --region s200 --params toneWhite=0.45:0.75:7,toneMid=0.3:0.6:7,frost=12:60:7,thickness=12:48:7,shadowOpacity=0:0.3:7,shadowBlur=2:40:8,hairlineWidth=0.5:2.5:5,specularWidth=0.5:3:6 --passes 1 --write` | 50 min |

Commit: `feat(mobile): ios_liquid_glass dark regular material tuned against iOS 27`.

- [ ] **Group B: light regular glass.** Repeat A1 to A7 with `--appearance light` and the `light.regular.*` rows. A1's `toneWhite` grid becomes `0.8:1:5` and `toneBlack` becomes `0.3:0.7:9`: light glass lifts black to about 0.52 (native reads 133 on black and 250 on white). Commit: `... light regular material tuned ...`.

- [ ] **Group C: clear glass** (`--scene material.clear --row clear --region plain,dimmed --size 88 --backdrops photo,white`), for dark then light:
  1. `copy_row <a>.regular.88 <a>.clear.88 ""`, where `<a>` is `dark` or `light`;
  2. `--params toneWhite=0.6:1:9,toneBlack=0:0.3:7,toneMid=0.3:0.7:9,frost=0:20:6,saturation=0.8:1.6:5 --passes 2 --write`;
  3. `copy_row <a>.clear.88 <a>.clear.44 $SIZE <a>.regular.44` and `copy_row <a>.clear.88 <a>.clear.200 $SIZE <a>.regular.200`. Clear glass is only measured at 88 pt, so its size dependence follows regular.

  Commit.

- [ ] **Group D: tinted glass** (`--scene material.tinted --row tinted --backdrops stripes,white,black`), for dark then light:
  1. `copy_row <a>.regular.88 <a>.tinted.88 tintAmount,tintBlack,tintWhite`;
  2. `--size 88 --region block --params tintAmount=0.6:1:9,tintBlack=0.6:1.2:7,tintWhite=0.8:1.3:6,saturation=0.8:1.6:5 --passes 2 --write`;
  3. `copy_row <a>.tinted.88 <a>.tinted.44 $SIZE <a>.regular.44`. The "Run" button is 37 pt, so it resolves to the 44 anchor. Then `--size 44 --region run --params tintAmount=0.6:1:9,tintBlack=0.6:1.2:7,tintWhite=0.8:1.3:6,hairline=0:0.8:5,specular=0:0.8:5 --passes 1 --write`;
  4. `copy_row <a>.tinted.88 <a>.tinted.200 $SIZE <a>.regular.200`.

  Commit.

- [ ] **Group E: accessibility** (`--scene material.regular --region s88 --size 88 --backdrops stripes,white,black`), for dark then light:
  - **Reduce Transparency** (`--row reduceTransparency --a11y reduce-transparency`):
    1. `copy_row <a>.regular.88 <a>.reduceTransparency.88 ""`;
    2. `--params toneBlack=0:1:11,toneMid=0:1:11,toneWhite=0:1:11,saturation=0:1:5,frost=12:60:5,specular=0:0.5:3,hairline=0:0.5:3 --passes 2 --write`. Native Reduce Transparency is an almost opaque fill, so black, mid and white should converge;
    3. `copy_row <a>.reduceTransparency.88 <a>.reduceTransparency.44 $SIZE <a>.regular.44`, and the same for `.200`.
  - **Increase Contrast** (`--row increaseContrast --a11y increase-contrast`):
    1. `copy_row <a>.regular.88 <a>.increaseContrast.88 ""`;
    2. `--params hairline=0.2:1:5,hairlineWidth=0.5:3:6,hairlineDark=0:0.6:7,hairlineLight=0.4:1:7,toneBlack=0:0.4:5,toneWhite=0.4:1:7 --passes 2 --write`;
    3. `copy_row <a>.increaseContrast.88 <a>.increaseContrast.44 $SIZE <a>.regular.44`, and the same for `.200`.

  Commit.

- [ ] **Group F: scroll edge** (`--scene material.edge.<style> --backdrops scroll`), each style in dark then light. `--size`, `--row` and `--region` are ignored here; the band region and the MAD and luminance measures come from the manifest.

| Style | Arguments |
|---|---|
| soft | `--params edge.extent=60:180:7,edge.blur=2:14:7,edge.dim=0.2:0.9:8,edge.knee=0.2:1:5,edge.cap=0.4:1:7,edge.capBlur=2:12:6 --passes 2 --write` |
| hard | `--params edge.extent=44:64:6,edge.blur=2:14:7,edge.dim=0.2:0.9:8,edge.cap=0.2:1:5,edge.capBlur=2:12:6,edge.line=0:0.6:7,edge.lineShade=0:1:5 --passes 2 --write` |
| automatic | the same as hard |

Commit: `feat(mobile): ios_liquid_glass scroll edge styles tuned against iOS 27`.

- [ ] **Step G: Check the gates.** The committed tables must still be in writer format, which the harness tests check:
  - `python3 -m unittest discover tool/glass_lab/harness/tests`;
  - the package `flutter test`, whose material tests read the shipped table;
  - `flutter test` in `packages/mobile`.

---

### Task 12: Verification runs (spec Done items 3–6)

**Files:**
- Create: `docs/liquid_glass/02a-looks/operator-baseline.json` (project 1 numbers, given below), `docs/liquid_glass/02a-looks/results.md`

**Interfaces:**
- Consumes: the tuned tables (Task 11), `lab.py run`, `report` and `summary`.
- Produces: `results.md`, which records every Done item with its measured numbers, pass or fail. The ROADMAP (Task 13) quotes it.

- [ ] **Step 1: Rebuild both Flutter apps from the tuned tables**

Run: `python3 tool/glass_lab/harness/lab.py build example && python3 tool/glass_lab/harness/lab.py build operator`

- [ ] **Step 2: Material scenes on the example app** (Done items 3 and 4)

```bash
python3 tool/glass_lab/harness/lab.py run material --appearance both
python3 tool/glass_lab/harness/lab.py report
python3 tool/glass_lab/harness/lab.py summary docs/liquid_glass/02a-looks/summary-material.md
```

This takes about 50 minutes. Read `report.html` and open the filmstrips of every failing case.

- `material.regular` must pass MAD ≤ 4, luminance ≤ 3, rim ≤ 6, centre ≤ 1 and box ≤ 1 on all 5 backdrops, in both appearances.
- `material.clear` must pass on `photo` and `white`, and `material.tinted` on `stripes`, `white` and `black`.
- `material.edge.*` pass on MAD and luminance only.
- Motion scenes (`material.interactive`, `materialize`, `merge`, `union`, `morph`) are measured statically here; their motion is 2B. `material.content` stays missing (ruling 9). `material.flip` is informational.

- [ ] **Step 3: Accessibility** (Done item 5)

```bash
python3 tool/glass_lab/harness/lab.py run material.regular --appearance both --a11y reduce-transparency
python3 tool/glass_lab/harness/lab.py run material.regular --appearance both --a11y increase-contrast
python3 tool/glass_lab/harness/lab.py report <each run>
```

Each case must pass the same five thresholds as Step 2. Afterwards, `xcrun simctl spawn booted defaults read com.apple.Accessibility EnhancedBackgroundContrastEnabled` must print `0`.

- [ ] **Step 4: Operator's component scenes improve** (Done item 6). Create `docs/liquid_glass/02a-looks/operator-baseline.json`. These numbers come from the project 1 baseline run `20260927-035111`, the `ready` still image:

```json
{
 "tabbar.rest dark-black": {
  "rim_rms": 25.57,
  "luminance": 13.59,
  "mad": 24.86
 },
 "tabbar.rest dark-photo": {
  "rim_rms": 19.43,
  "luminance": 9.13,
  "mad": 19.7
 },
 "tabbar.rest dark-stripes": {
  "rim_rms": 9.54,
  "luminance": 7.05,
  "mad": 17.26
 },
 "tabbar.rest dark-white": {
  "rim_rms": 44.09,
  "luminance": 40.67,
  "mad": 47.37
 },
 "tabbar.rest light-black": {
  "rim_rms": 22.69,
  "luminance": 13.93,
  "mad": 19.08
 },
 "tabbar.rest light-photo": {
  "rim_rms": 12.49,
  "luminance": 3.88,
  "mad": 12.47
 },
 "tabbar.rest light-stripes": {
  "rim_rms": 9.74,
  "luminance": 5.16,
  "mad": 14.27
 },
 "tabbar.rest light-white": {
  "rim_rms": 5.22,
  "luminance": 0.68,
  "mad": 10.72
 },
 "button.press dark-stripes": {
  "rim_rms": 13.37,
  "luminance": 2.95,
  "mad": 9.76
 },
 "button.press light-stripes": {
  "rim_rms": 13.47,
  "luminance": 0.67,
  "mad": 12.22
 },
 "navbar.inline dark-black": {
  "rim_rms": 27.5,
  "luminance": 6.71,
  "mad": 8.68
 },
 "navbar.inline dark-stripes": {
  "rim_rms": 16.37,
  "luminance": 3.79,
  "mad": 5.84
 },
 "navbar.inline dark-white": {
  "rim_rms": 41.15,
  "luminance": 7.38,
  "mad": 11.05
 },
 "navbar.inline light-black": {
  "rim_rms": 96.06,
  "luminance": 2.16,
  "mad": 9.79
 },
 "navbar.inline light-stripes": {
  "rim_rms": 58.81,
  "luminance": 2.0,
  "mad": 7.24
 },
 "navbar.inline light-white": {
  "rim_rms": 44.8,
  "luminance": 1.29,
  "mad": 7.39
 }
}
```

Then run the component scenes on Operator:

```bash
python3 tool/glass_lab/harness/lab.py run tabbar.rest --app both --appearance both --flutter operator
python3 tool/glass_lab/harness/lab.py run button.press --app both --appearance both --flutter operator
python3 tool/glass_lab/harness/lab.py run navbar.inline --app both --appearance both --flutter operator
python3 tool/glass_lab/harness/lab.py report <each run>
```

Compare them from the repository root, passing the three run folders:

```bash
python3 - packages/mobile/build/glass_lab/runs/<tabbar run> packages/mobile/build/glass_lab/runs/<button run> packages/mobile/build/glass_lab/runs/<navbar run> <<'EOF'
import json
import sys
from pathlib import Path

LIMITS = {"rim_rms": 6.0, "luminance": 3.0}
baseline = json.loads(Path("docs/liquid_glass/02a-looks/operator-baseline.json").read_text())
runs = [Path(arg) for arg in sys.argv[1:]]
failed = 0
print("| Case | Measure | Baseline | Now | Verdict |")
print("|---|---|---|---|---|")
for key, before in baseline.items():
    scene, case = key.split(" ")
    found = [run / scene / case / "result.json" for run in runs if (run / scene / case / "result.json").exists()]
    stat = json.loads(found[-1].read_text()).get("static", {}).get("ready") if found else None
    for measure, limit in LIMITS.items():
        now = stat[measure] if stat else float("inf")
        good = now <= before[measure] / 2 or now <= limit
        failed += not good
        print(f"| {key} | {measure} | {before[measure]:.2f} | {now:.2f} | {'ok' if good else 'NOT HALVED'} |")
print(f"\n{failed} measures not halved")
EOF
```

**Ruling** (recorded here because the spec's wording would fail on noise): a measure passes when it is at most half its baseline, or already within its threshold (rim ≤ 6, luminance ≤ 3). Several baseline luminance values are already under 3, and halving 0.67 is below the lab's resolution. The script prints one row per case and measure, and ends with the number not halved.

- [ ] **Step 5: Write** `docs/liquid_glass/02a-looks/results.md`:

```markdown
# 2A results

Date: <today>. Branch `feat/ios-liquid-glass-2a` at <commit>. Simulator: iPhone 17 Pro (iOS 27).

| Done item | Result | Evidence |
|---|---|---|
| 1 Package: rename, plugin live toggles, gates, no old imports | pass/fail | Task 8 `lab.py a11y` output; gates |
| 2 Example app | pass/fail | lab_test; README |
| 3 Material scenes, strict thresholds | n of N cases pass | summary-material.md |
| 4 Scroll edge MAD and luminance | ... | ... |
| 5 Reduce Transparency and Increase Contrast | ... | ... |
| 6 Operator components halve rim and luminance | ... | the comparison table |
| 7 Flip spike | no flip; nothing to build | flip-spike.md |
| 8 Frame cost within 20% | new x ms against old y ms | flip-spike.md |
| 9 Documents | done | Task 13 |

## Failing cases
For each case over a threshold: the scene, case, measure, value, threshold, and what the filmstrip shows (one sentence from looking at it).

## Operator components
<the comparison table from Step 4>
```

Fill every cell from the runs. Where a Done item did not pass, say so plainly; the review decides what happens next.

- [ ] **Step 6: Commit**

```bash
git add docs/liquid_glass/02a-looks
git commit -m "docs(mobile): 2A measured results against iOS 27

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Documents (spec Done item 9)

**Files:**
- Replace: `packages/ios_liquid_glass/README.md`, `packages/ios_liquid_glass/example/README.md`, `tool/glass_lab/README.md`
- Modify: `packages/ios_liquid_glass/FORK.md`, `packages/ios_liquid_glass/CHANGELOG.md`, `docs/liquid_glass/ROADMAP.md`, `CLAUDE.md` (the repository root's)

**Interfaces:**
- Consumes: `results.md`, `flip-spike.md` and `tuning-log.md` (Tasks 9, 11 and 12).
- Produces: documents a fresh session can continue from.

- [ ] **Step 1: Package README.** Replace `packages/ios_liquid_glass/README.md`. Upstream's README described the old API and linked GIFs that were never vendored; the credit stays, in the last section.

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

Native glass gets thicker and deeper as it grows. `GlassEffect` measures itself and interpolates the material between the 44, 88 and 200 pt anchors on its shorter side. Pass `sideHint` to avoid a one-frame default before the first layout.

### Low level

The renderer underneath is still public: `LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassSettings`, `LiquidGlassBlendGroup`, `FakeGlass`, `GlassGlow` and `LiquidStretch`. `GlassMaterial.resolve(...)` returns the tuned material for any glass, size, appearance and accessibility state, and `toSettings()` turns it into `LiquidGlassSettings`.

## How the look is made

- The geometry pass computes a signed-distance field of every shape in a layer, blends nearby shapes, and bakes a quarter-circle bevel with Snell refraction into a cached texture.
- The final pass refracts the frosted backdrop through that texture, with dispersion at the rim only. It then maps brightness through a three-point tone curve (black, mid, white), tints with the accent across a brightness range, and draws an adaptive hairline and a two-lobe specular rim.

Frame cost is the same as the upstream renderer's. Measured on the iOS 27 simulator, 13 glasses over a moving backdrop take 12.5 ms raster time per frame. Check your target devices.

## Credits and licence

This package is a fork of [`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer) by Tim Lehmann ([whynotmake.it](https://whynotmake.it)), MIT licensed. The renderer's geometry pass, blend groups, caching, `FakeGlass`, `GlassGlow` and `LiquidStretch` are his work. `FORK.md` lists every change made since, and `LICENSE` is upstream's MIT licence.
````

If Task 12 measured a different `perf.glass` raster median, put that number in the "How the look is made" section.

- [ ] **Step 2: FORK.md.** In `packages/ios_liquid_glass/FORK.md`, insert this section right before the line `Record every later change to \`lib/\` in this file.`:

```markdown

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
- New, not from upstream:
  - `lib/src/api/` (`Glass`, `GlassShape`, `GlassTheme`, `GlassEffect`, `GlassEffectScope`, `GlassEffectContainer`, `GlassDimming`, `GlassForeground`);
  - `lib/src/material/` (`GlassMaterial`, `ios27Table`, `ScrollEdgeMaterial`, `ios27ScrollEdgeTable`, `GlassMaterialOverride`);
  - `lib/src/accessibility/`;
  - `lib/src/scroll_edge/` and `scroll_edge_blur.frag`, moved from Operator;
  - the iOS plugin in `ios/`;
  - the `example/` app.
```

- [ ] **Step 3: CHANGELOG.** Insert at the top of `packages/ios_liquid_glass/CHANGELOG.md`:

```markdown
## 0.1.0

 - **BREAKING** **REFACTOR**: renamed to `ios_liquid_glass`, with library `package:ios_liquid_glass/ios_liquid_glass.dart`.
 - **BREAKING** **FEAT**: the final render step is the iOS 27 model (tone curve, tint range, adaptive hairline, two-lobe specular, rim-only dispersion). Upstream's rim light settings no longer affect the shader.
 - **FEAT**: `Glass`, `GlassEffect`, `GlassEffectContainer`, `GlassShape`, `GlassTheme`, `GlassDimming` and `GlassForeground` mirror SwiftUI's glass API.
 - **FEAT**: `GlassMaterial` and the tuned `ios27Table`, keyed by appearance, variant, accessibility and size.
 - **FEAT**: an iOS plugin reports Reduce Transparency, Increase Contrast and Reduce Motion live.
 - **FEAT**: `ScrollEdgeEffect` and `ScrollUnderBars` with `ScrollEdgeStyle.soft`, `.hard` and `.automatic`.
 - **FEAT**: an `example/` app.
```

- [ ] **Step 4: Example README.** Replace `packages/ios_liquid_glass/example/README.md`:

````markdown
# ios_liquid_glass example

A plain Flutter app that uses only `ios_liquid_glass`. It shows the package works in a fresh project, and it is the glass lab's Flutter target.

## Run it

```bash
flutter run
```

The home screen lists every scene. Each one copies a scene of the native iOS 27 catalog point for point:
- regular glass at three sizes;
- clear glass with dimming;
- tinted glass and a prominent button;
- shapes;
- merging containers;
- the three scroll edge styles;
- the flip scene.

## Use the package in your own app

1. Add the dependency:

   ```yaml
   dependencies:
     ios_liquid_glass:
       path: <path to packages/ios_liquid_glass>
   ```

2. Put glass over content:

   ```dart
   import 'package:flutter/material.dart';
   import 'package:ios_liquid_glass/ios_liquid_glass.dart';

   class Demo extends StatelessWidget {
     const Demo({super.key});

     @override
     Widget build(BuildContext context) {
       return Stack(
         children: [
           Positioned.fill(child: Image.asset('assets/photo.jpg', fit: BoxFit.cover)),
           Center(
             child: GlassEffectContainer(
               child: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   GlassEffect(
                     shape: const GlassShape.circle(),
                     child: const SizedBox.square(dimension: 56, child: GlassForeground(child: Icon(Icons.add))),
                   ),
                   const SizedBox(width: 12),
                   GlassEffect(
                     glass: Glass.regular.tint(const Color(0xFF1ACB64)),
                     child: const Padding(
                       padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                       child: GlassForeground(child: Text('Run', style: TextStyle(fontSize: 17))),
                     ),
                   ),
                 ],
               ),
             ),
           ),
         ],
       );
     }
   }
   ```

3. On iOS, `pod install` runs automatically on the first build and adds the accessibility plugin.

## The lab hook

In debug builds, `lib/main.dart` looks for `Documents/glass_lab/launch.json`. If the file is there, the app opens that scene instead of the list and deletes the file. Its optional `material` map overrides material fields by name, which is how `lab.py tune` tries candidates. Release builds never read the file.
````

- [ ] **Step 5: Lab README.** Replace `tool/glass_lab/README.md`:

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
- **`perf [--takes 3] [--out file]`** measures raster time in the example's `perf.none` and `perf.glass` scenes. Takes run in alternating order.
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
- the harness writes `Documents/glass_lab/launch.json` into the Flutter app's container before each launch, as `{scene, backdrop, bare, material}`;
- the debug build reads it and deletes it on start;
- `material` is an optional map of material overrides by field name. Scroll edge fields are prefixed `edge.`.

Backgrounds live in each app's `Documents/glass_lab/`.

If a Flutter app has not built a scene yet, it shows a `missing: <id>` placeholder, the driver skips the steps, and the report counts the scene as missing.

## Tuning

```bash
python3 tool/glass_lab/harness/lab.py tune --scene material.regular --appearance dark \
  --backdrops stripes,white,black --size 88 --region s88 \
  --params toneWhite=0.45:0.75:7,frost=12:40:8 --passes 2 --write
```

- Each candidate writes its values into the launch file's `material` map and captures `ready.png`.
- It is scored against native as each measure divided by its threshold, capped at 10, and summed.
- The search is coordinate descent, then a half-step refinement.
- `--region` names manifest regions to compare; scenes with a `track` use it. `--row`, `--size` and `--appearance` pick the table row to write.

Output goes to `build/glass_lab/tune/<timestamp>/`: `log.jsonl`, `best.json` and `best-<backdrop>.png`. `--write` rewrites the row in `packages/ios_liquid_glass/lib/src/material/ios27.dart`, or in `ios27_scroll_edge.dart` for `material.edge.*` scenes. Never edit those tables by hand.

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
````

- [ ] **Step 6: ROADMAP.** Update `docs/liquid_glass/ROADMAP.md`. Every number comes from `results.md`; every path is checked with `ls`.
  - **Status table:** 2A becomes `**DONE** on branch feat/ios-liquid-glass-2a (<last commit>), awaiting review`, or `**PARTLY DONE**` if any Done item failed.
  - **§2 "The package":** replace the `packages/liquid_glass_renderer/...` rows with `packages/ios_liquid_glass/`, plus rows for:
    - `lib/src/api/`, `lib/src/material/` (tables written only by `lab.py tune --write`), `lib/src/accessibility/`, `lib/src/scroll_edge/`;
    - `ios/` (the plugin) and `example/` (the lab's Flutter target).
  - **§2 "Operator's glass layer":** delete the `glass_style.dart` and scroll edge rows (moved, done). Mark `glass_surface.dart` and `glass_scope.dart` as adapters over the package until project 3. The lab row now says Operator's debug lab keeps the component scenes only.
  - **§3 lab commands:** `build [native|example|operator|all]`, `run ... --flutter example|operator`, and the new `tune`, `perf`, `a11y` and `flip` commands. Gates: add the package and example gates, and update the test counts.
  - **§4 gotchas:** items 14–20 were added when the plan was written. Correct any that execution proved wrong, and append any new gotcha as item 21 onwards, with its evidence.
  - **§6 Project 2A:** replace the "Prototype" and "Next" bullets with:
    - "Delivered": the Done table from `results.md`, one line each;
    - "Open items": every failing case, SPM support, the `material.interactive` decision, adaptive shadow (ruling 15) and `FakeGlass` tone (ruling 14);
    - "Rulings": a pointer to the plan's ruling list.
  - **§7 checklist:** set the Package column for the 2A rows from the results: regular, clear, identity, tinted, lensing, specular rim, adaptive shadow, size, foreground, scroll edge, Reduce Transparency and Increase Contrast. Use `yes` only where the scene passed. Flip becomes `no native flip on iOS 27 simulator (flip-spike.md)`.
  - **§8:** add a subsection "2A results" with the headline numbers from `results.md`.
  - **§9:** the next step is project 2B's spec. Pending user decisions: push `development`, merge 2A, and `material.interactive`.

- [ ] **Step 7: CLAUDE.md.** In the repository root's `CLAUDE.md`, "Vendored packages" section, add after the sentence about `xterm` and `speech_to_text`:

```markdown
`ios_liquid_glass` is the Liquid Glass package, forked from `liquid_glass_renderer` and turned into an iOS 27 look-alike for any Flutter app. Its `FORK.md` lists every change, its material tables are written only by `tool/glass_lab/harness/lab.py tune --write`, and `docs/liquid_glass/ROADMAP.md` is the source of truth for its roadmap.
```

- [ ] **Step 8: Check the gates one last time.** Package, example and app: `flutter analyze` and `flutter test`. Harness: `python3 -m unittest discover tool/glass_lab/harness/tests`. Then `grep -rn liquid_glass_renderer --include='*.dart' --include='*.yaml' packages lib test` prints only the package pubspec's `description` line.

- [ ] **Step 9: Commit**

```bash
git add packages/ios_liquid_glass/README.md packages/ios_liquid_glass/FORK.md packages/ios_liquid_glass/CHANGELOG.md packages/ios_liquid_glass/example/README.md tool/glass_lab/README.md
git add ../../docs/liquid_glass/ROADMAP.md ../../CLAUDE.md
git commit -m "docs(mobile): ios_liquid_glass README, fork notes, lab guide and roadmap for 2A

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
