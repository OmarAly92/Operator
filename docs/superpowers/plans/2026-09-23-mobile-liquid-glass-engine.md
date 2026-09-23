# Mobile Liquid Glass Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Flutter mobile app a Liquid Glass engine whose chrome is indistinguishable from Apple's iOS 26 glass in the simulator. The engine is a tuned renderer plus core glass widgets, and proof is side-by-side screenshots against a native SwiftUI reference.

**Architecture:**
- **Renderer.** The vendored `liquid_glass_renderer` (workspace package) is fixed and extended: density-correct thickness, true continuous corners, directional specular, and interaction fixes.
- **Glass widgets.** App-side widgets live in `lib/core/widgets/glass/`. They resolve renderer settings from the app skin (`GlassStyle`) and give the rest of the app `GlassSurface`, `GlassButton`, `GlassToolbar`, `GlassTabBar`, `ScrollEdgeEffect` and `GlassSheetChrome`.
- **Proof.** A native SwiftUI reference app (`tool/glass_reference/`) and a debug-only Flutter "glass lab" route render the same fixed scene in the same iOS 26.5 simulator. Scripts capture both and compose diff images.

**Tech Stack:**
- Flutter 3.44.5 / Dart ^3.12.2, Impeller (iOS)
- `liquid_glass_renderer` (vendored), `motor`
- SwiftUI on iOS 26, built with `swiftc` (no Xcode project)
- `xcrun simctl`, Python 3 + Pillow 12.3

**Spec:** `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-engine-design.md`

## Global Constraints

- **Platform: iOS only.** Verify on the iPhone 17 Pro simulator, iOS 26.5 runtime (Xcode 26.6). Android is not verified or tuned, but it must still compile.
- **Gate for every task:** from `packages/mobile`, `flutter analyze` prints `No issues found!` and `flutter test` passes.
- **No code comments in anything you write.** This is the user's global rule. Keep upstream comments in vendored files you edit, but add none of your own.
- **Colours and timing:** colour comes only from `context.skin` (`AppSkin`), except the fixed lab test-pattern colours in Task 2. Timing and curves come from `AppMotion`. Haptics come from `Haptics`.
- **Feature code never imports `flutter_screenutil`.** Spacing and radii are raw numbers.
- **Every change under `packages/liquid_glass_renderer/lib`** gets one bullet in that package's `FORK.md` under "Changes from upstream".
- **Commits** end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Worktree:** `/Users/omaraly/development/AI/Operator-ios-polish`, branch `feat/mobile-ios-polish`. Never touch the main checkout at `/Users/omaraly/development/AI/Operator`; it has another session's uncommitted work.
- **Glass placement:** glass never sits on glass, and the top and bottom chrome never share one `LiquidGlassLayer`.
- **Appear/disappear** animates `LiquidGlassSettings.visibility`, never opacity.

## Review Focus

- **A tab-bar drag that is cancelled** (system gesture, incoming call, scroll takeover) must leave the selection unchanged and return the droplet to the selected tab. Tested in Task 11.
- **A disabled `GlassButton`** (`onPressed == null`) must not animate, fire haptics or call anything. Tested in Task 9.
- **Tapping the already-selected tab** must call `onSelected` with the same index exactly once per tap, because `HomeShell` uses that for scroll-to-top. Tested in Task 11.
- **Switching light/dark while glass is on screen** must update the glass tint without a remount. Tested in Task 8.
- **Large accessibility text** (text scale 2.0) must not overflow the tab bar or toolbar. Tested in Task 10 and Task 11.

---

### Task 1: Native SwiftUI reference and capture tooling

**Files:**
- Create: `packages/mobile/tool/glass_reference/GlassReference.swift`
- Create: `packages/mobile/tool/glass_reference/Info.plist`
- Create: `packages/mobile/tool/glass_reference/device.sh`
- Create: `packages/mobile/tool/glass_reference/run.sh`
- Create: `packages/mobile/tool/glass_reference/compare.py`
- Create: `packages/mobile/tool/glass_reference/README.md`
- Modify: `packages/mobile/.gitignore` (add `tool/glass_reference/build/`)

**Interfaces:**
- Produces:
  - `device.sh` prints the UDID of a booted iPhone 17 Pro on the newest iOS 26 runtime.
  - `run.sh <rest|sheet>` builds, installs and launches the native reference with env `GLASS_LAB_SCENE`.
  - `compare.py <native.png> <lab.png> <out.png>` writes `out.png` and `out_zoom.png`, and prints `top_mad=<float> bottom_mad=<float>`.
  - The fixed scene geometry, which Task 2 mirrors exactly:
    - top stripe band 182pt high
    - cards from y=202, 4 × 72pt, 12pt gap, 16pt side margin, radius 14
    - bottom stripe band 180pt, flush to the screen bottom
    - stripe colours `E5484D E89527 F0B45C 1ACB64 47BFFF 8E6CF0`

- [ ] **Step 1: Write the reference app**

`packages/mobile/tool/glass_reference/GlassReference.swift`:

```swift
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct Palette {
    let bg: Color
    let surface: Color
    let text: Color
    let secondary: Color
    let accent: Color

    static func of(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(bg: Color(hex: 0x18171C), surface: Color(hex: 0x1F1E24), text: Color(hex: 0xFFFFFF), secondary: Color(hex: 0xA09EA8), accent: Color(hex: 0x1ACB64))
        }
        return Palette(bg: Color(hex: 0xFAF7F2), surface: Color(hex: 0xFFFFFF), text: Color(hex: 0x1A1612), secondary: Color(hex: 0x6B6354), accent: Color(hex: 0x1ACB64))
    }
}

let stripeColors: [UInt32] = [0xE5484D, 0xE89527, 0xF0B45C, 0x1ACB64, 0x47BFFF, 0x8E6CF0]

struct Stripes: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(stripeColors, id: \.self) { Color(hex: $0) }
        }
    }
}

struct Card: View {
    let p: Palette
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session \(index + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
            Text("feat/branch-\(index + 1)").font(.system(size: 12)).foregroundStyle(p.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SceneContent: View {
    let p: Palette

    var body: some View {
        VStack(spacing: 0) {
            Stripes().frame(height: 182)
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { Card(p: p, index: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            Spacer(minLength: 0)
            Stripes().frame(height: 180)
        }
        .background(p.bg)
        .ignoresSafeArea()
    }
}

struct AgentsScreen: View {
    let p: Palette

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                SceneContent(p: p)
                Button {} label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(p.accent)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {}
                }
            }
        }
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showSheet = ProcessInfo.processInfo.environment["GLASS_LAB_SCENE"] == "sheet"

    var body: some View {
        let p = Palette.of(scheme)
        TabView {
            Tab("Agents", systemImage: "square.stack.3d.up") { AgentsScreen(p: p) }
            Tab("PRs", systemImage: "arrow.triangle.merge") { p.bg.ignoresSafeArea() }
            Tab("Settings", systemImage: "gearshape") { p.bg.ignoresSafeArea() }
        }
        .tint(p.accent)
        .sheet(isPresented: $showSheet) {
            Text("Sheet")
                .font(.headline)
                .presentationDetents([.medium])
        }
    }
}

@main
struct GlassReferenceApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

`packages/mobile/tool/glass_reference/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.operator.glassreference</string>
  <key>CFBundleExecutable</key><string>GlassReference</string>
  <key>CFBundleName</key><string>GlassReference</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>26.0</string>
  <key>UILaunchScreen</key><dict/>
  <key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict>
</plist>
```

- [ ] **Step 2: Write the device, run and compare scripts**

`packages/mobile/tool/glass_reference/device.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
UDID="$(xcrun simctl list devices available -j | python3 -c '
import sys, json
devs = json.load(sys.stdin)["devices"]
for rt in sorted((r for r in devs if "iOS-26" in r), reverse=True):
    for d in devs[rt]:
        if d["name"] == "iPhone 17 Pro":
            print(d["udid"])
            sys.exit(0)
sys.exit("no iPhone 17 Pro on an iOS 26 runtime")
')"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "$UDID"
```

`packages/mobile/tool/glass_reference/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${GLASS_DEVICE:-$("$HERE/device.sh")}"
SCENE="${1:-rest}"
APP="$HERE/build/GlassReference.app"
mkdir -p "$APP"
cp "$HERE/Info.plist" "$APP/Info.plist"
xcrun -sdk iphonesimulator swiftc -parse-as-library -target arm64-apple-ios26.0-simulator "$HERE/GlassReference.swift" -o "$APP/GlassReference"
codesign -s - --force "$APP" >/dev/null 2>&1
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" dev.operator.glassreference >/dev/null 2>&1 || true
SIMCTL_CHILD_GLASS_LAB_SCENE="$SCENE" xcrun simctl launch "$DEVICE" dev.operator.glassreference >/dev/null
```

`packages/mobile/tool/glass_reference/compare.py`:

```python
import sys
from PIL import Image, ImageChops, ImageDraw, ImageStat

STRIP = 450


def label(img, text):
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, 300, 64], fill=(0, 0, 0))
    draw.text((14, 12), text, fill=(255, 255, 255), font_size=40)
    return img


def mad(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def main(native_path, lab_path, out_path):
    native = Image.open(native_path).convert("RGB")
    lab = Image.open(lab_path).convert("RGB").resize(native.size)
    w, h = native.size
    diff = ImageChops.difference(native, lab).point(lambda v: min(255, v * 4))
    sheet = Image.new("RGB", (w * 3, h), (128, 128, 128))
    for i, panel in enumerate([label(native.copy(), "native"), label(lab.copy(), "lab"), label(diff, "diff x4")]):
        sheet.paste(panel, (i * w, 0))
    sheet.resize((w * 3 // 2, h // 2)).save(out_path)
    zoom = Image.new("RGB", (w * 2, STRIP * 2), (128, 128, 128))
    for i, img in enumerate([native, lab]):
        zoom.paste(img.crop((0, 0, w, STRIP)), (i * w, 0))
        zoom.paste(img.crop((0, h - STRIP, w, h)), (i * w, STRIP))
    zoom.save(out_path.replace(".png", "_zoom.png"))
    top = mad(native.crop((0, 0, w, STRIP)), lab.crop((0, 0, w, STRIP)))
    bottom = mad(native.crop((0, h - STRIP, w, h)), lab.crop((0, h - STRIP, w, h)))
    print(f"top_mad={top:.2f} bottom_mad={bottom:.2f}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
```

`packages/mobile/tool/glass_reference/README.md`:

```markdown
# Glass reference

A native SwiftUI app that renders the glass lab scene with Apple's real Liquid Glass.
It is the ground truth the Flutter glass engine is tuned against.

- `./run.sh rest` or `./run.sh sheet` builds it with `swiftc`, installs it on the
  iPhone 17 Pro iOS 26 simulator and launches it.
- `./run_lab.sh rest` does the same for the Flutter app's glass lab route (Task 2).
- `./capture.sh` screenshots both in light and dark for both scenes and writes
  `build/captures/compare_*.png`, plus `_zoom` crops of the top and bottom chrome.

The scene geometry is fixed in points and must stay identical in `GlassReference.swift`
and `lib/core/widgets/glass/lab/glass_lab_backdrop.dart`.
```

Append to `packages/mobile/.gitignore`:

```
tool/glass_reference/build/
```

Run: `chmod +x packages/mobile/tool/glass_reference/*.sh`

- [ ] **Step 3: Run the reference and look at it**

Run from `packages/mobile`:

```bash
tool/glass_reference/run.sh rest && sleep 4 && xcrun simctl io "$(tool/glass_reference/device.sh)" screenshot /tmp/native_rest.png
```

Expected: exit 0. Then open `/tmp/native_rest.png` with the Read tool and confirm:
- a stripe band at the top and bottom
- four cards
- a glass back circle and a glass "Edit" capsule at the top
- a floating glass tab bar with three tabs
- a green glass "Run" button above the tab bar

- [ ] **Step 4: Commit**

```bash
git add packages/mobile/tool/glass_reference packages/mobile/.gitignore
git commit -m "feat(mobile): native SwiftUI Liquid Glass reference and capture tooling

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Flutter glass lab route

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_scene.dart`
- Create: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_backdrop.dart`
- Create: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart`
- Create: `packages/mobile/tool/glass_reference/run_lab.sh`
- Create: `packages/mobile/tool/glass_reference/capture.sh`
- Modify: `packages/mobile/lib/core/app_routes/routes_strings.dart` (add `glassLab`)
- Modify: `packages/mobile/lib/core/app_routes/app_router.dart` (add the case)
- Modify: `packages/mobile/lib/main.dart` (debug-only initial route override)
- Test: `packages/mobile/test/core/widgets/glass/lab/glass_lab_scene_test.dart`

**Interfaces:**
- Consumes: the Task 1 scene geometry, `compare.py`, `device.sh`, `run.sh`.
- Produces:
  - `enum GlassLabScene { rest, sheet, corners }` with `static GlassLabScene parse(String? raw)` and `static GlassLabScene? fromEnvironment()`
  - `GlassLabBackdrop` (const widget)
  - `GlassLabScreen({required GlassLabScene scene})`, whose chrome later tasks replace
  - `RoutesStrings.glassLab == '/glass-lab'`
  - `run_lab.sh <scene>` and `capture.sh [outDir]`

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/lab/glass_lab_scene_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart';

void main() {
  group('GlassLabScene.parse', () {
    test('maps known names', () {
      expect(GlassLabScene.parse('sheet'), GlassLabScene.sheet);
      expect(GlassLabScene.parse('corners'), GlassLabScene.corners);
      expect(GlassLabScene.parse('rest'), GlassLabScene.rest);
    });

    test('falls back to rest for null and unknown values', () {
      expect(GlassLabScene.parse(null), GlassLabScene.rest);
      expect(GlassLabScene.parse('nonsense'), GlassLabScene.rest);
    });
  });

  testWidgets('lab screen renders the four scene cards', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: GlassLabScreen(scene: GlassLabScene.rest)));
    await tester.pump();
    for (var i = 1; i <= 4; i++) {
      expect(find.text('Session $i'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/lab/glass_lab_scene_test.dart`
Expected: FAIL. The compile error names `glass_lab_scene.dart` as not found.

- [ ] **Step 3: Implement the scene enum, backdrop and screen**

`packages/mobile/lib/core/widgets/glass/lab/glass_lab_scene.dart`:

```dart
import 'dart:io';

enum GlassLabScene {
  rest,
  sheet,
  corners;

  static GlassLabScene parse(String? raw) => switch (raw) {
        'sheet' => GlassLabScene.sheet,
        'corners' => GlassLabScene.corners,
        _ => GlassLabScene.rest,
      };

  static GlassLabScene? fromEnvironment() {
    final raw = Platform.environment['GLASS_LAB_SCENE'];
    return raw == null ? null : parse(raw);
  }
}
```

`packages/mobile/lib/core/widgets/glass/lab/glass_lab_backdrop.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassLabBackdrop extends StatelessWidget {
  const GlassLabBackdrop({super.key});

  static const double topBandHeight = 182;
  static const double bottomBandHeight = 180;
  static const double cardsTop = 20;
  static const double cardHeight = 72;
  static const double cardGap = 12;
  static const double sideMargin = 16;
  static const List<Color> stripes = [
    Color(0xFFE5484D),
    Color(0xFFE89527),
    Color(0xFFF0B45C),
    Color(0xFF1ACB64),
    Color(0xFF47BFFF),
    Color(0xFF8E6CF0),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.skin.bgBase,
      child: Column(
        children: [
          const SizedBox(height: topBandHeight, child: _Stripes()),
          Padding(
            padding: const EdgeInsets.fromLTRB(sideMargin, cardsTop, sideMargin, 0),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == 3 ? 0 : cardGap),
                    child: _LabCard(index: i),
                  ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: bottomBandHeight, child: _Stripes()),
        ],
      ),
    );
  }
}

class _Stripes extends StatelessWidget {
  const _Stripes();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final color in GlassLabBackdrop.stripes) Expanded(child: ColoredBox(color: color))],
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      height: GlassLabBackdrop.cardHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: ShapeDecoration(
        color: skin.bgSurface,
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText('Session ${index + 1}', style: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary)),
          const SizedBox(height: 4),
          AppText('feat/branch-${index + 1}', style: AppTextStyle.style12Regular.copyWith(color: skin.textTertiary)),
        ],
      ),
    );
  }
}
```

`packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.scene});

  final GlassLabScene scene;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return SkinScope(
      skin: dark ? const DarkSkin() : const LightSkin(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned.fill(child: GlassLabBackdrop()),
            Positioned(
              left: 21,
              right: 21,
              bottom: 21,
              height: 62,
              child: LiquidGlass.withOwnLayer(
                shape: const LiquidRoundedRectangle(borderRadius: 31),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire the route and the debug launch override**

In `packages/mobile/lib/core/app_routes/routes_strings.dart`, add below `usage`:

```dart
  static const String glassLab = '/glass-lab';
```

In `packages/mobile/lib/core/app_routes/app_router.dart`:
- add imports `dart:io`, `package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart` and `package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart`
- add this case inside the `switch (settings.name)` before the `default:` branch:

```dart
      case RoutesStrings.glassLab:
        return MaterialPageRoute(
          builder: (_) => GlassLabScreen(scene: GlassLabScene.parse(Platform.environment['GLASS_LAB_SCENE'])),
          settings: settings,
        );
```

In `packages/mobile/lib/main.dart`, add the import `package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart`. Then replace the `final initialRoute = switch (destination) {...};` statement with:

```dart
  final labScene = kDebugMode ? GlassLabScene.fromEnvironment() : null;
  final initialRoute = labScene != null
      ? RoutesStrings.glassLab
      : switch (destination) {
          LaunchDestination.onboarding => RoutesStrings.onboarding,
          LaunchDestination.desktops => RoutesStrings.connections,
          LaunchDestination.sessions => RoutesStrings.sessions,
        };
```

Keep the switch arms exactly as they are in the file; `main.dart:56-60` has exactly these three.

- [ ] **Step 5: Add the lab launcher and the capture script**

`packages/mobile/tool/glass_reference/run_lab.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOBILE="$(cd "$HERE/../.." && pwd)"
DEVICE="${GLASS_DEVICE:-$("$HERE/device.sh")}"
SCENE="${1:-rest}"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  (cd "$MOBILE" && flutter build ios --simulator --debug >/dev/null)
fi
xcrun simctl install "$DEVICE" "$MOBILE/build/ios/iphonesimulator/Runner.app"
xcrun simctl terminate "$DEVICE" dev.operator.operatorMobile >/dev/null 2>&1 || true
SIMCTL_CHILD_GLASS_LAB_SCENE="$SCENE" xcrun simctl launch "$DEVICE" dev.operator.operatorMobile >/dev/null
```

`packages/mobile/tool/glass_reference/capture.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/build/captures}"
SCENES="${SCENES:-rest sheet}"
mkdir -p "$OUT"
DEVICE="$("$HERE/device.sh")"
export GLASS_DEVICE="$DEVICE"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
BUILT=0
for APPEARANCE in light dark; do
  xcrun simctl ui "$DEVICE" appearance "$APPEARANCE"
  for SCENE in $SCENES; do
    "$HERE/run.sh" "$SCENE"
    sleep 4
    xcrun simctl io "$DEVICE" screenshot "$OUT/native_${APPEARANCE}_${SCENE}.png" >/dev/null
    SKIP_BUILD=$BUILT "$HERE/run_lab.sh" "$SCENE"
    BUILT=1
    sleep 8
    xcrun simctl io "$DEVICE" screenshot "$OUT/lab_${APPEARANCE}_${SCENE}.png" >/dev/null
    echo "$APPEARANCE/$SCENE: $(python3 "$HERE/compare.py" "$OUT/native_${APPEARANCE}_${SCENE}.png" "$OUT/lab_${APPEARANCE}_${SCENE}.png" "$OUT/compare_${APPEARANCE}_${SCENE}.png")"
  done
done
echo "$OUT"
```

Run: `chmod +x packages/mobile/tool/glass_reference/*.sh`

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/lab/glass_lab_scene_test.dart && flutter analyze`
Expected: all tests pass, and analyze prints `No issues found!`.

- [ ] **Step 7: Capture the first side-by-side**

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh`
Expected: it prints two `top_mad=… bottom_mad=…` lines and an output dir. Open `build/captures/compare_light_rest.png` with the Read tool and confirm:
- the lab's stripes and cards line up with the native ones at the same y positions (compare the card top edges)
- a glass capsule sits over the bottom stripes

Write the two printed lines into the commit message body. They are the baseline.

- [ ] **Step 8: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass/lab packages/mobile/lib/core/app_routes packages/mobile/lib/main.dart packages/mobile/tool/glass_reference packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): debug-only glass lab route mirroring the native reference scene

Baseline: <paste the two capture lines>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Renderer — density-correct thickness

**Files:**
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart:210-221` (`updateShaderWithSettings`)
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart:66-72` (the `devicePixelRatio` setter) and `:102-122` (`_updateShaderSettings`)
- Modify: `packages/mobile/packages/liquid_glass_renderer/FORK.md`

**Interfaces:**
- Consumes: the lab and capture tooling from Task 2.
- Produces: `LiquidGlassSettings.thickness` is now in logical points on every device. Later tasks tune thickness assuming points.

The geometry pass works in physical pixels. Shapes and blend are uploaded × devicePixelRatio (`liquid_glass_blend_group.dart:242-246`), and the final pass gets physical geometry bounds (`liquid_glass_render_object.dart:218-221`). Thickness is the only length uploaded unscaled, so the lens band is `thickness` physical pixels: one third of the intended width on a 3x iPhone. Both uploads must scale it, because the final pass decodes displacement with `uThickness * 10.0` (`liquid_glass_final_render.frag:65`) and must use the same value the geometry pass encoded with.

- [ ] **Step 1: Capture the before image**

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh /tmp/glass_before`
Expected: completes. Keep `/tmp/glass_before/lab_light_rest.png`.

- [ ] **Step 2: Scale thickness in the geometry upload**

In `liquid_glass_blend_group.dart`, in `updateShaderWithSettings`, change

```dart
        settings.effectiveThickness,
```

to

```dart
        settings.effectiveThickness * devicePixelRatio,
```

- [ ] **Step 3: Scale thickness in the render upload and re-upload when the DPR changes**

In `liquid_glass_render_object.dart`, in `_updateShaderSettings`, change

```dart
          settings.effectiveThickness,
```

to

```dart
          settings.effectiveThickness * devicePixelRatio,
```

and change the `devicePixelRatio` setter to

```dart
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _updateShaderSettings();
    needsGeometryUpdate = true;
    markNeedsPaint();
  }
```

- [ ] **Step 4: Log it in FORK.md**

Replace the "Changes from upstream" paragraph of `packages/liquid_glass_renderer/FORK.md` with:

```markdown
Changes from upstream:

- `pubspec.yaml`: workspace resolution, `publish_to: none`, dev dependencies removed.
- Thickness is uploaded × devicePixelRatio to both the geometry and the final render pass,
  so `LiquidGlassSettings.thickness` is in logical points. Upstream left it in physical
  pixels, making the lens band a third as wide on a 3x screen. A DPR change re-uploads it.
```

- [ ] **Step 5: Verify**

Run: `cd packages/mobile && flutter analyze && flutter test && SCENES=rest tool/glass_reference/capture.sh /tmp/glass_after`
Expected:
- analyze: `No issues found!`
- tests: pass
- capture: completes

Open `/tmp/glass_before/lab_light_rest.png` and `/tmp/glass_after/lab_light_rest.png` with the Read tool. The distorted rim band of the bottom capsule, where the stripes bend at the edge, must be visibly wider in the after image, about three times.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/packages/liquid_glass_renderer
git commit -m "fix(liquid-glass): make thickness density-independent

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Renderer — continuous-corner SDF that matches the clip

**Files:**
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/assets/shaders/sdf.glsl:17-25` (`sdfSquircle`)
- Modify: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart` (add the `corners` scene)
- Modify: `packages/mobile/packages/liquid_glass_renderer/FORK.md`

**Interfaces:**
- Consumes: `GlassLabScene.corners` from Task 2.
- Produces: `LiquidRoundedSuperellipse` lenses on the same continuous-corner outline as its clip (`RoundedSuperellipseBorder`).

`sdfSquircle` is the rounded-rect formula (compare `sdf.glsl:5-10`). The clip and shadow use Flutter's `RoundedSuperellipseBorder`, which follows iOS continuous corners, so the lens and the silhouette disagree at every corner. The replacement uses a p-norm corner over an extended radius. `SQUIRCLE_EXPONENT` and `SQUIRCLE_EXTENT` are fitted visually in Step 3.

- [ ] **Step 1: Add the corners scene to the lab**

In `glass_lab_screen.dart`:
- add the import `package:operator_mobile/core/app_themes/colors/app_skin.dart`
- replace the `children:` list of the `Stack` with:

```dart
          children: [
            const Positioned.fill(child: GlassLabBackdrop()),
            if (scene == GlassLabScene.corners)
              Center(
                child: SizedBox(
                  width: 300,
                  height: 200,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LiquidGlass.withOwnLayer(
                          settings: const LiquidGlassSettings(thickness: 12, blur: 0, glassColor: Color(0x00000000)),
                          shape: const LiquidRoundedSuperellipse(borderRadius: 60),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.all(Radius.circular(60)),
                                side: BorderSide(color: Color(0xFF000000), width: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Positioned(
                left: 21,
                right: 21,
                bottom: 21,
                height: 62,
                child: LiquidGlass.withOwnLayer(
                  shape: const LiquidRoundedRectangle(borderRadius: 31),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
```

Then remove the `app_skin.dart` import again if analyze reports it unused.

- [ ] **Step 2: Replace the SDF**

In `sdf.glsl`, replace the whole `sdfSquircle` function with:

```glsl
#define SQUIRCLE_EXPONENT 4.0
#define SQUIRCLE_EXTENT 1.28

float sdfSquircle(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r * SQUIRCLE_EXTENT, shortest);
    vec2 q = abs(p) - b + r;
    vec2 m = max(q, 0.0);
    float corner = pow(pow(m.x, SQUIRCLE_EXPONENT) + pow(m.y, SQUIRCLE_EXPONENT), 1.0 / SQUIRCLE_EXPONENT);
    return min(max(q.x, q.y), 0.0) + corner - r;
}
```

- [ ] **Step 3: Fit the constants against the clip outline**

Run: `cd packages/mobile && tool/glass_reference/run_lab.sh corners && sleep 8 && xcrun simctl io "$(tool/glass_reference/device.sh)" screenshot /tmp/corners.png`

Then crop the top-left corner at full resolution:

```bash
python3 -c "from PIL import Image; Image.open('/tmp/corners.png').crop((150,850,450,1150)).resize((900,900), Image.NEAREST).save('/tmp/corners_zoom.png')"
```

Open `/tmp/corners_zoom.png` with the Read tool. The outer edge of the refracted glass must sit exactly on the thin black outline all the way around the corner.
- If the glass edge bulges outside the outline at the 45° point, lower `SQUIRCLE_EXPONENT` by 0.5.
- If it cuts inside, raise it by 0.5.
- If the corner starts too early or late along the straight edge, adjust `SQUIRCLE_EXTENT` by ±0.05.

Rebuild (`tool/glass_reference/run_lab.sh corners`) and repeat until no gap is visible at the 3× zoom. Record the final values.

- [ ] **Step 4: Log it in FORK.md**

Append to the "Changes from upstream" list:

```markdown
- `sdfSquircle` in `sdf.glsl` is a p-norm continuous corner (`SQUIRCLE_EXPONENT`,
  `SQUIRCLE_EXTENT`) fitted to Flutter's `RoundedSuperellipseBorder`. Upstream used the
  rounded-rectangle formula, so the lens and the clip disagreed at the corners.
```

- [ ] **Step 5: Verify and commit**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!`, and the tests pass.

```bash
git add packages/mobile/packages/liquid_glass_renderer packages/mobile/lib/core/widgets/glass/lab
git commit -m "fix(liquid-glass): continuous-corner SDF matching RoundedSuperellipseBorder

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Renderer — directional specular with a fill ratio

**Files:**
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart`
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag:17-24,103-114`
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart:102-122`
- Modify: `packages/mobile/packages/liquid_glass_renderer/pubspec.yaml` (add `dev_dependencies: flutter_test`)
- Modify: `packages/mobile/packages/liquid_glass_renderer/FORK.md`
- Test: `packages/mobile/packages/liquid_glass_renderer/test/liquid_glass_settings_test.dart`

**Interfaces:**
- Produces: `LiquidGlassSettings.fillRatio` (double, default `0.8`, which keeps upstream's look), included in `copyWith` and `props`. The shader clamps edge brightness to [0, 1].

- [ ] **Step 1: Write the failing test**

Add to `packages/liquid_glass_renderer/pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
```

`packages/mobile/packages/liquid_glass_renderer/test/liquid_glass_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter pub get && cd packages/liquid_glass_renderer && flutter test test/liquid_glass_settings_test.dart`
Expected: FAIL, with `No named parameter with the name 'fillRatio'`.

- [ ] **Step 3: Add the setting**

In `liquid_glass_settings.dart`:
- add `this.fillRatio = 0.8,` to the main constructor after `this.saturation = 1.5,`
- add `double? fillRatio,` to `copyWith`'s parameters and `fillRatio: fillRatio ?? this.fillRatio,` to its body
- add `fillRatio,` to `props`
- add the field after `saturation`:

```dart
  /// How strongly the side facing away from the light is lit, relative to the
  /// lit side. 0 lights only the lit side; 1 lights both sides equally.
  final double fillRatio;
```

- [ ] **Step 4: Pass it to the shader and use it**

In `liquid_glass_final_render.frag`:
- after `uniform vec2 uLightDirection;` add `uniform float uFillRatio;`
- change `float totalInfluence = mainLight + oppositeLight * 0.8;` to `float totalInfluence = mainLight + oppositeLight * uFillRatio;`
- change `float brightness = (directional + ambient) * edgeFactor * thicknessScale * 0.8;` to `float brightness = clamp((directional + ambient) * edgeFactor * thicknessScale * 0.8, 0.0, 1.0);`

In `liquid_glass_render_object.dart`'s `_updateShaderSettings`, append after the `..setOffset(...)` call:

```dart
        ..setFloat(settings.fillRatio);
```

Move the statement's closing `;` accordingly, so `setOffset` ends with `)` and the new `setFloat` line ends the cascade.

- [ ] **Step 5: Log it in FORK.md**

Append:

```markdown
- `LiquidGlassSettings.fillRatio` (default 0.8, upstream's hard-coded value) sets how
  strongly the side facing away from the light is lit. The rim brightness is clamped to
  [0, 1]. Apple's rim is bright on the lit side with a dim fill opposite.
```

- [ ] **Step 6: Verify and commit**

Run: `cd packages/mobile/packages/liquid_glass_renderer && flutter test && cd ../.. && flutter analyze && flutter test && SCENES=rest tool/glass_reference/capture.sh`
Expected:
- package tests: pass
- analyze: `No issues found!`
- app tests: pass
- capture: completes, and the lab capsule still renders (a default `fillRatio` of 0.8 means no visible change)

```bash
git add packages/mobile/packages/liquid_glass_renderer
git commit -m "feat(liquid-glass): directional specular with fillRatio and clamped rim

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Renderer — interaction fixes and dead shader removal

**Files:**
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/glass_glow.dart:173-181` (`removeTouch`)
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/internal/glass_drag_builder.dart:61-84`
- Delete: `lib/experimental.dart`, `lib/src/glassify.dart`, `lib/src/rendering/liquid_glass_filter.dart`, `lib/assets/shaders/liquid_glass_filter.frag`, `lib/assets/shaders/liquid_glass_arbitrary.frag` (all under `packages/mobile/packages/liquid_glass_renderer/`)
- Modify: `packages/mobile/packages/liquid_glass_renderer/lib/src/shaders.dart` (drop the three dead keys)
- Modify: `packages/mobile/packages/liquid_glass_renderer/pubspec.yaml` (drop the two shaders)
- Modify: `packages/mobile/packages/liquid_glass_renderer/FORK.md`
- Test: `packages/mobile/packages/liquid_glass_renderer/test/glass_drag_builder_test.dart`

**Interfaces:**
- Produces: a cancelled pointer ends a drag, the touch glow fades where it is, and the package ships only the three shaders it uses.

- [ ] **Step 1: Write the failing test**

`packages/mobile/packages/liquid_glass_renderer/test/glass_drag_builder_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/glass_drag_builder.dart';

void main() {
  testWidgets('a cancelled pointer ends the drag in listener mode', (tester) async {
    final seen = <Offset?>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassDragBuilder(
            builder: (context, offset, child) {
              seen.add(offset);
              return const SizedBox(width: 100, height: 100);
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(seen.last, Offset.zero);
    await gesture.cancel();
    await tester.pump();
    expect(seen.last, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile/packages/liquid_glass_renderer && flutter test test/glass_drag_builder_test.dart`
Expected: FAIL at the last expectation (`Expected: null, Actual: Offset(0.0, 0.0)`).

- [ ] **Step 3: Handle cancel, and fade the glow in place**

In `glass_drag_builder.dart`, in the `GestureMode.listener` branch, add after the `onPointerUp:` handler:

```dart
          onPointerCancel: (event) {
            if (!mounted) return;
            setState(() {
              currentDragOffset = null;
            });
          },
```

In `glass_glow.dart`, in `removeTouch`, delete the line

```dart
    _offsetController.animateTo(Offset.zero);
```

- [ ] **Step 4: Remove the dead shaders and APIs**

Run from `packages/mobile/packages/liquid_glass_renderer`:

```bash
git rm lib/experimental.dart lib/src/glassify.dart lib/src/rendering/liquid_glass_filter.dart lib/assets/shaders/liquid_glass_filter.frag lib/assets/shaders/liquid_glass_arbitrary.frag
grep -rl 'shared.glsl' lib || git rm lib/assets/shaders/shared.glsl
```

In `lib/src/shaders.dart`, delete the `liquidGlassFilterShader`, `glassify` and `legacyLiquidGlass` fields. In `pubspec.yaml`, delete the lines `- lib/assets/shaders/liquid_glass_filter.frag` and `- lib/assets/shaders/liquid_glass_arbitrary.frag`.

- [ ] **Step 5: Log it in FORK.md**

Append:

```markdown
- `GlassDragBuilder` handles `onPointerCancel` in listener mode; upstream left a cancelled
  touch stuck pressed.
- `GlassGlow` fades out where the finger lifted; upstream slid the glow to the top-left
  corner on release.
- Removed `Glassify` (`experimental.dart`), the unused `LiquidGlassFilter`, and their
  shaders `liquid_glass_filter.frag` and `liquid_glass_arbitrary.frag`. The app uses
  neither, and both failed SkSL compilation on every build.
```

- [ ] **Step 6: Verify and commit**

Run: `cd packages/mobile/packages/liquid_glass_renderer && flutter test && cd ../.. && flutter analyze && flutter test && flutter build ios --simulator --debug 2>&1 | grep -c "liquid_glass_filter\|liquid_glass_arbitrary" || true`
Expected: all pass. The final count prints `0`: those shaders no longer appear in the build log.

```bash
git add -A packages/mobile/packages/liquid_glass_renderer
git commit -m "fix(liquid-glass): cancel ends drags, glow fades in place, drop dead shaders

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `GlassStyle` and `GlassMetrics`

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_style.dart`
- Create: `packages/mobile/lib/core/widgets/glass/glass_metrics.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_style_test.dart`

**Interfaces:**
- Consumes: `LiquidGlassSettings` including `fillRatio` (Task 5); `AppSkin`.
- Produces:
  - `enum GlassVariant { regular, clear, prominent }`
  - `sealed class GlassStyle` with:
    - `static LiquidGlassSettings resolve({required AppSkin skin, required GlassVariant variant, required double size, bool highContrast = false})`
    - `static List<BoxShadow> shadows(AppSkin skin)`
    - `static double thicknessFor(double size)`
    - `static double sizeProgress(double size)`
  - `sealed class GlassMetrics` with static constants: `hitTarget`, `toolbarSideInset`, `toolbarTopGap`, `toolbarItemGap`, `tabBarHeight`, `tabBarSideInset`, `tabBarBottomInset`, `tabGlyph`, `dropletInset`, `primaryButtonInset`, `sheetInset`, `displayCornerRadius`, `floatingSheetMaxFraction`.
  - `size` is the glass shape's shortest side in points. Every numeric constant here is a starting value that Task 14 tunes.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/glass_style_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

void main() {
  const light = LightSkin();
  const dark = DarkSkin();

  group('GlassStyle.thicknessFor', () {
    test('grows with size', () {
      expect(GlassStyle.thicknessFor(62), greaterThan(GlassStyle.thicknessFor(44)));
      expect(GlassStyle.thicknessFor(300), greaterThan(GlassStyle.thicknessFor(62)));
    });

    test('is clamped at both ends', () {
      expect(GlassStyle.thicknessFor(0), GlassStyle.thicknessFor(20));
      expect(GlassStyle.thicknessFor(2000), GlassStyle.thicknessFor(600));
    });
  });

  group('GlassStyle.resolve', () {
    test('clear is more transparent than regular', () {
      final regular = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      final clear = GlassStyle.resolve(skin: light, variant: GlassVariant.clear, size: 62);
      expect(clear.glassColor.a, lessThan(regular.glassColor.a));
    });

    test('prominent is tinted with the accent', () {
      final prominent = GlassStyle.resolve(skin: light, variant: GlassVariant.prominent, size: 44);
      expect(prominent.glassColor.withValues(alpha: 1), light.accent);
    });

    test('light and dark tint differently', () {
      final l = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      final d = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62);
      expect(l.glassColor, isNot(d.glassColor));
    });

    test('high contrast raises tint opacity', () {
      final normal = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62);
      final contrast = GlassStyle.resolve(skin: dark, variant: GlassVariant.regular, size: 62, highContrast: true);
      expect(contrast.glassColor.a, greaterThan(normal.glassColor.a));
    });

    test('uses a dim fill so the rim reads directional', () {
      final s = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 62);
      expect(s.fillRatio, lessThan(0.5));
    });

    test('bigger glass blurs more', () {
      final small = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 44);
      final big = GlassStyle.resolve(skin: light, variant: GlassVariant.regular, size: 400);
      expect(big.blur, greaterThan(small.blur));
    });
  });

  test('shadows are two outer-blur layers', () {
    final shadows = GlassStyle.shadows(light);
    expect(shadows, hasLength(2));
    expect(shadows.every((s) => s.blurStyle == BlurStyle.outer), isTrue);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_style_test.dart`
Expected: FAIL (`glass_style.dart` not found).

- [ ] **Step 3: Implement**

`packages/mobile/lib/core/widgets/glass/glass_metrics.dart`:

```dart
sealed class GlassMetrics {
  static const double hitTarget = 44;
  static const double toolbarSideInset = 16;
  static const double toolbarTopGap = 4;
  static const double toolbarItemGap = 8;
  static const double tabBarHeight = 62;
  static const double tabBarSideInset = 21;
  static const double tabBarBottomInset = 21;
  static const double tabGlyph = 28;
  static const double dropletInset = 4;
  static const double primaryButtonInset = 16;
  static const double sheetInset = 8;
  static const double displayCornerRadius = 55;
  static const double floatingSheetMaxFraction = 0.9;
}
```

`packages/mobile/lib/core/widgets/glass/glass_style.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';

enum GlassVariant { regular, clear, prominent }

sealed class GlassStyle {
  static const double _minSize = 20;
  static const double _maxSize = 600;

  static double sizeProgress(double size) =>
      ((size.clamp(_minSize, _maxSize) - _minSize) / (_maxSize - _minSize)).toDouble();

  static double thicknessFor(double size) => lerpDouble(10, 30, math.sqrt(sizeProgress(size)))!;

  static LiquidGlassSettings resolve({
    required AppSkin skin,
    required GlassVariant variant,
    required double size,
    bool highContrast = false,
  }) {
    final dark = skin.themeMode == ThemeMode.dark;
    final t = sizeProgress(size);
    final baseTint = switch (variant) {
      GlassVariant.regular => dark ? skin.bgSurface.withValues(alpha: 0.42) : const Color(0xFFFFFFFF).withValues(alpha: 0.32),
      GlassVariant.clear => dark ? skin.bgSurface.withValues(alpha: 0.12) : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
      GlassVariant.prominent => skin.accent.withValues(alpha: 0.85),
    };
    final tint = highContrast ? baseTint.withValues(alpha: math.min(0.92, baseTint.a + 0.3)) : baseTint;
    return LiquidGlassSettings(
      glassColor: tint,
      thickness: thicknessFor(size),
      blur: lerpDouble(2, 10, t)! * (variant == GlassVariant.clear ? 0.5 : 1),
      chromaticAberration: 0.02,
      lightAngle: 0.5 * math.pi,
      lightIntensity: lerpDouble(0.55, 0.8, t)!,
      ambientStrength: 0.1,
      refractiveIndex: 1.2,
      saturation: variant == GlassVariant.clear ? 1.2 : 1.6,
      fillRatio: 0.25,
    );
  }

  static List<BoxShadow> shadows(AppSkin skin) {
    final dark = skin.themeMode == ThemeMode.dark;
    return [
      BoxShadow(blurStyle: BlurStyle.outer, color: const Color(0xFF000000).withValues(alpha: dark ? 0.2 : 0.05), blurRadius: 2),
      BoxShadow(blurStyle: BlurStyle.outer, color: const Color(0xFF000000).withValues(alpha: dark ? 0.35 : 0.12), blurRadius: 24),
    ];
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_style_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass/glass_style.dart packages/mobile/lib/core/widgets/glass/glass_metrics.dart packages/mobile/test/core/widgets/glass/glass_style_test.dart
git commit -m "feat(mobile): GlassStyle presets and GlassMetrics

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `GlassScope` and `GlassSurface`

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_scope.dart`
- Create: `packages/mobile/lib/core/widgets/glass/glass_surface.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_surface_test.dart`

**Interfaces:**
- Consumes: `GlassStyle.resolve`, `GlassStyle.shadows`, `GlassVariant` (Task 7).
- Produces:
  - `GlassScope({required GlassVariant variant, required double size, required Widget child})`: one `LiquidGlassLayer` whose settings follow the skin and `MediaQuery.highContrastOf`.
  - `enum GlassShapeKind { capsule, circle, rect }`
  - `GlassSurface({required GlassShapeKind kind, double radius = 0, bool grouped = false, GlassVariant variant = GlassVariant.regular, required double size, required Widget child})`:
    - renders `LiquidGlass.auto`, or `LiquidGlass.grouped` when `grouped`
    - capsule is `LiquidRoundedRectangle(borderRadius: 999)`, circle is `LiquidOval()`, rect is `LiquidRoundedSuperellipse(borderRadius: radius)`
    - in high contrast it paints a 1px `skin.borderStrong` outline over the child

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/glass_surface_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

Widget _host(AppSkin skin, Widget child, {bool highContrast = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: SkinScope(skin: skin, child: Center(child: child)),
      ),
    );

const _surface = GlassScope(
  variant: GlassVariant.regular,
  size: 44,
  child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, child: SizedBox(width: 120, height: 44, child: Text('glass'))),
);

void main() {
  testWidgets('renders its child inside a glass layer', (tester) async {
    await tester.pumpWidget(_host(const LightSkin(), _surface));
    expect(find.text('glass'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching skin updates the layer tint without remounting', (tester) async {
    await tester.pumpWidget(_host(const LightSkin(), _surface));
    final before = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.glassColor;
    final element = tester.element(find.byType(LiquidGlassLayer));
    await tester.pumpWidget(_host(const DarkSkin(), _surface));
    final after = tester.widget<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).settings.glassColor;
    expect(after, isNot(before));
    expect(tester.element(find.byType(LiquidGlassLayer)), same(element));
  });

  testWidgets('prominent glass keeps its own layer inside a regular scope', (tester) async {
    await tester.pumpWidget(_host(
      const LightSkin(),
      const GlassScope(
        variant: GlassVariant.regular,
        size: 44,
        child: GlassSurface(kind: GlassShapeKind.capsule, size: 44, variant: GlassVariant.prominent, child: SizedBox(width: 80, height: 44)),
      ),
    ));
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    final inner = tester.widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer)).last;
    expect(inner.settings.glassColor.withValues(alpha: 1), const LightSkin().accent);
  });

  testWidgets('high contrast draws an outline', (tester) async {
    await tester.pumpWidget(_host(const DarkSkin(), _surface, highContrast: true));
    expect(find.byKey(GlassSurface.outlineKey), findsOneWidget);
    await tester.pumpWidget(_host(const DarkSkin(), _surface));
    expect(find.byKey(GlassSurface.outlineKey), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_surface_test.dart`
Expected: FAIL (`glass_scope.dart` not found).

- [ ] **Step 3: Implement**

`packages/mobile/lib/core/widgets/glass/glass_scope.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

class GlassScope extends StatelessWidget {
  const GlassScope({super.key, required this.variant, required this.size, required this.child});

  final GlassVariant variant;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassLayer(
      settings: GlassStyle.resolve(
        skin: context.skin,
        variant: variant,
        size: size,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      child: child,
    );
  }
}
```

`packages/mobile/lib/core/widgets/glass/glass_surface.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';

enum GlassShapeKind { capsule, circle, rect }

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.kind,
    required this.size,
    required this.child,
    this.radius = 0,
    this.grouped = false,
    this.variant = GlassVariant.regular,
  });

  static const Key outlineKey = ValueKey('glass-surface-outline');

  final GlassShapeKind kind;
  final double size;
  final double radius;
  final bool grouped;
  final GlassVariant variant;
  final Widget child;

  LiquidShape get _shape => switch (kind) {
        GlassShapeKind.capsule => const LiquidRoundedRectangle(borderRadius: 999),
        GlassShapeKind.circle => const LiquidOval(),
        GlassShapeKind.rect => LiquidRoundedSuperellipse(borderRadius: radius),
      };

  OutlinedBorder get _outline => switch (kind) {
        GlassShapeKind.capsule => const StadiumBorder(),
        GlassShapeKind.circle => const CircleBorder(),
        GlassShapeKind.rect => RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(radius))),
      };

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final highContrast = MediaQuery.highContrastOf(context);
    final content = highContrast
        ? DecoratedBox(
            key: outlineKey,
            position: DecorationPosition.foreground,
            decoration: ShapeDecoration(shape: _outline.copyWith(side: BorderSide(color: skin.borderStrong))),
            child: child,
          )
        : child;
    final shadows = GlassStyle.shadows(skin);
    final settings = GlassStyle.resolve(skin: skin, variant: variant, size: size, highContrast: highContrast);
    if (variant == GlassVariant.prominent) {
      return LiquidGlass.withOwnLayer(shape: _shape, shadows: shadows, settings: settings, child: content);
    }
    if (grouped) {
      return LiquidGlass.grouped(shape: _shape, shadows: shadows, child: content);
    }
    return LiquidGlass.auto(shape: _shape, shadows: shadows, settings: settings, child: content);
  }
}
```

Prominent glass always gets its own layer. `LiquidGlass.auto` would otherwise adopt an ancestor `GlassScope`'s regular settings and lose the accent tint.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_surface_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): GlassScope and GlassSurface

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `GlassButton`

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_button.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_button_test.dart`

**Interfaces:**
- Consumes: `GlassSurface`, `GlassShapeKind`, `GlassVariant`, `GlassMetrics.hitTarget` (Tasks 7–8); `GlassGlow`; `Haptics.tap`; `AppMotion.spring`, `AppMotion.slow`.
- Produces:
  - `GlassButton.icon({required IconData icon, required VoidCallback? onPressed, String? semanticLabel, bool prominent = false})`
  - `GlassButton.label({required String label, IconData? icon, required VoidCallback? onPressed, bool prominent = false})`
  - `static const double pressedScale = 1.08`
  - It exposes its current scale through an `AnimatedScale` descendant, which the tests read.
- Behaviour:
  - Icon buttons are a 44pt circle; label buttons are a capsule 44pt high with 16pt horizontal padding.
  - Pointer down scales to `pressedScale`. Up or cancel returns to 1.0 with the `AppMotion.spring` overshoot.
  - A tap fires `Haptics.tap()` and then `onPressed`.
  - Disabled, or with Reduce Motion on, the scale stays at 1.0; disabled also means no haptic.
  - Non-prominent buttons render on the nearest `GlassScope` layer. Prominent ones always use their own layer (`GlassSurface` with `variant: prominent` and `LiquidGlass.auto`, with no ancestor `GlassScope`) and an `skin.onAccent` foreground.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/glass_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final haptics = <MethodCall>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: SkinScope(skin: const LightSkin(), child: Center(child: child)),
        ),
      );

  double scaleOf(WidgetTester tester) => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('tap fires haptic then onPressed once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () => taps++)));
    await tester.tap(find.byType(GlassButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(haptics, hasLength(1));
  });

  testWidgets('press scales up and release returns to rest', (tester) async {
    await tester.pumpWidget(host(GlassButton.label(label: 'Edit', onPressed: () {})));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), GlassButton.pressedScale);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('cancel returns to rest without calling onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () => taps++)));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
    expect(taps, 0);
  });

  testWidgets('disabled button neither animates nor fires haptics', (tester) async {
    await tester.pumpWidget(host(const GlassButton.icon(icon: Icons.add, onPressed: null)));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
  });

  testWidgets('reduce motion keeps scale at rest', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {}), reduceMotion: true));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GlassButton)));
    await tester.pump();
    expect(scaleOf(tester), 1.0);
    await gesture.up();
  });

  testWidgets('meets the 44pt minimum hit target', (tester) async {
    await tester.pumpWidget(host(GlassButton.icon(icon: Icons.add, onPressed: () {})));
    final size = tester.getSize(find.byType(GlassButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_button_test.dart`
Expected: FAIL (`glass_button.dart` not found).

- [ ] **Step 3: Implement**

`packages/mobile/lib/core/widgets/glass/glass_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassButton extends StatefulWidget {
  const GlassButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.prominent = false,
  }) : label = null;

  const GlassButton.label({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
  }) : semanticLabel = null;

  static const double pressedScale = 1.08;

  final IconData? icon;
  final String? label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    Haptics.tap();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final foreground = widget.prominent ? skin.onAccent : skin.textPrimary;
    final isIcon = widget.label == null;
    final content = isIcon
        ? SizedBox.square(
            dimension: GlassMetrics.hitTarget,
            child: Icon(widget.icon, size: 20, color: foreground, semanticLabel: widget.semanticLabel),
          )
        : SizedBox(
            height: GlassMetrics.hitTarget,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 17, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  AppText(widget.label!, style: AppTextStyle.style16SemiBold.copyWith(color: foreground)),
                ],
              ),
            ),
          );
    return Semantics(
      button: true,
      enabled: _enabled,
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _handleTap : null,
          child: AnimatedScale(
            scale: _pressed && !reduceMotion ? GlassButton.pressedScale : 1.0,
            duration: AppMotion.slow,
            curve: AppMotion.spring,
            child: GlassSurface(
              kind: isIcon ? GlassShapeKind.circle : GlassShapeKind.capsule,
              size: GlassMetrics.hitTarget,
              variant: widget.prominent ? GlassVariant.prominent : GlassVariant.regular,
              child: GlassGlow(
                glowColor: const Color(0xFFFFFFFF).withValues(alpha: widget.prominent ? 0.25 : 0.35),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_button_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 5: Put it in the lab and compare**

In `glass_lab_screen.dart`, add this child to the `Stack`, after the `if/else` chrome entry and only when `scene != GlassLabScene.corners`:

```dart
            if (scene != GlassLabScene.corners)
              Positioned(
                right: GlassMetrics.primaryButtonInset,
                bottom: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.primaryButtonInset,
                child: GlassButton.label(label: 'Run', icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
              ),
```

Add the imports for `glass_button.dart` and `glass_metrics.dart`.

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh`
Expected: completes. Open `build/captures/compare_light_rest_zoom.png`. The lab's green "Run" capsule sits near the native one. Exact position and tint are tuned in Task 14.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): GlassButton with spring press, glow and haptics

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `GlassToolbar`

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_toolbar.dart`
- Modify: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_toolbar_test.dart`

**Interfaces:**
- Consumes: `GlassScope`, `GlassButton`, `GlassMetrics`, `GlassVariant`.
- Produces: `GlassToolbar({Widget? leading, String? title, List<Widget> trailing = const []})`.
  - It is a top-aligned widget that respects the top safe area.
  - Its row is `GlassMetrics.hitTarget` tall, `toolbarTopGap` below the safe area, with `toolbarSideInset` side padding.
  - The title is centred, one line, with ellipsis.
  - Trailing items are separated by `toolbarItemGap`.
  - It wraps the row in exactly one `GlassScope(variant: regular, size: hitTarget)`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/glass_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_toolbar.dart';

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(402, 874), padding: const EdgeInsets.only(top: 62), textScaler: TextScaler.linear(textScale)),
        child: SkinScope(skin: const LightSkin(), child: Material(child: Align(alignment: Alignment.topCenter, child: child))),
      ),
    );

GlassToolbar _toolbar() => GlassToolbar(
      leading: GlassButton.icon(icon: Icons.chevron_left, onPressed: () {}),
      title: 'Agents',
      trailing: [GlassButton.label(label: 'Edit', onPressed: () {})],
    );

void main() {
  testWidgets('lays out leading, centred title and trailing in one glass layer', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_toolbar()));
    expect(find.text('Agents'), findsOneWidget);
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    final title = tester.getCenter(find.text('Agents'));
    expect(title.dx, closeTo(201, 1));
    expect(tester.getTopLeft(find.byType(GlassButton).first).dy, greaterThanOrEqualTo(62));
  });

  testWidgets('large text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_toolbar(), textScale: 2));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_toolbar_test.dart`
Expected: FAIL (`glass_toolbar.dart` not found).

- [ ] **Step 3: Implement**

`packages/mobile/lib/core/widgets/glass/glass_toolbar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';

class GlassToolbar extends StatelessWidget {
  const GlassToolbar({super.key, this.leading, this.title, this.trailing = const []});

  final Widget? leading;
  final String? title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        GlassMetrics.toolbarSideInset,
        top + GlassMetrics.toolbarTopGap,
        GlassMetrics.toolbarSideInset,
        0,
      ),
      child: SizedBox(
        height: GlassMetrics.hitTarget,
        child: GlassScope(
          variant: GlassVariant.regular,
          size: GlassMetrics.hitTarget,
          child: NavigationToolbar(
            leading: leading,
            middle: title == null
                ? null
                : AppText(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.style16SemiBold.copyWith(color: context.skin.textPrimary),
                  ),
            trailing: trailing.isEmpty
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < trailing.length; i++) ...[
                        if (i > 0) const SizedBox(width: GlassMetrics.toolbarItemGap),
                        trailing[i],
                      ],
                    ],
                  ),
            middleSpacing: GlassMetrics.toolbarItemGap,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_toolbar_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 5: Put it in the lab**

In `glass_lab_screen.dart`, add as a `Stack` child, when `scene != GlassLabScene.corners`:

```dart
            if (scene != GlassLabScene.corners)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: GlassToolbar(
                  leading: GlassButton.icon(icon: Icons.chevron_left_rounded, onPressed: () {}),
                  title: 'Agents',
                  trailing: [GlassButton.label(label: 'Edit', onPressed: () {})],
                ),
              ),
```

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh`
Expected: completes. In `build/captures/compare_light_rest_zoom.png`, the lab toolbar's back circle, title and Edit capsule sit near the native ones.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): GlassToolbar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: `GlassTabBar` with the droplet

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_tab_bar_logic.dart`
- Create: `packages/mobile/lib/core/widgets/glass/glass_tab_bar.dart`
- Modify: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_tab_bar_logic_test.dart`
- Test: `packages/mobile/test/core/widgets/glass/glass_tab_bar_test.dart`

**Interfaces:**
- Consumes: `GlassScope`, `GlassSurface`, `GlassMetrics`, `GlassVariant`; `LiquidGlassBlendGroup`; `Haptics.select`; `AppMotion`.
- Produces:
  - `sealed class GlassTabBarLogic`:
    - `static int slotAt(double x, double width, int count)`
    - `static double slotCenter(int index, double width, int count)`
    - `static double dropletLeft({required double centerX, required double dropletWidth, required double barWidth})`
    - `static double stretchFor(double dx)`
  - `class GlassTabItem { const GlassTabItem({required IconData icon, required String label}); }`
  - `GlassTabBar({required List<GlassTabItem> items, required int selectedIndex, required ValueChanged<int> onSelected})`
  - `static const Key dropletKey`
  - It is `GlassMetrics.tabBarHeight` tall and fills the width it is given. The caller positions it with `GlassMetrics.tabBarSideInset` and `tabBarBottomInset`.
- Behaviour:
  - **At rest:** a quiet pill (`skin.bgSubtle`) sits behind the selected item.
  - **On touch:** the droplet lifts into grouped lensing glass, 1.15× the item height, follows the finger's x, and stretches horizontally by `stretchFor(dx)`.
  - **On release:** `Haptics.select()`, then `onSelected(slotAt(x))`. This fires even when the slot equals `selectedIndex`.
  - **On cancel:** no callback, and the droplet returns to `selectedIndex`.
  - **Reduce Motion:** no lift scale and no stretch.

- [ ] **Step 1: Write the failing logic test**

`packages/mobile/test/core/widgets/glass/glass_tab_bar_logic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar_logic.dart';

void main() {
  test('slotAt maps x to a clamped slot', () {
    expect(GlassTabBarLogic.slotAt(0, 300, 3), 0);
    expect(GlassTabBarLogic.slotAt(150, 300, 3), 1);
    expect(GlassTabBarLogic.slotAt(299, 300, 3), 2);
    expect(GlassTabBarLogic.slotAt(-40, 300, 3), 0);
    expect(GlassTabBarLogic.slotAt(900, 300, 3), 2);
  });

  test('slotCenter is the middle of each slot', () {
    expect(GlassTabBarLogic.slotCenter(0, 300, 3), 50);
    expect(GlassTabBarLogic.slotCenter(2, 300, 3), 250);
  });

  test('dropletLeft keeps the droplet inside the bar', () {
    expect(GlassTabBarLogic.dropletLeft(centerX: 10, dropletWidth: 100, barWidth: 300), 0);
    expect(GlassTabBarLogic.dropletLeft(centerX: 150, dropletWidth: 100, barWidth: 300), 100);
    expect(GlassTabBarLogic.dropletLeft(centerX: 295, dropletWidth: 100, barWidth: 300), 200);
  });

  test('stretchFor grows with speed and is capped', () {
    expect(GlassTabBarLogic.stretchFor(0), 1.0);
    expect(GlassTabBarLogic.stretchFor(8), greaterThan(1.0));
    expect(GlassTabBarLogic.stretchFor(-8), GlassTabBarLogic.stretchFor(8));
    expect(GlassTabBarLogic.stretchFor(1000), 1.2);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_tab_bar_logic_test.dart`
Expected: FAIL (`glass_tab_bar_logic.dart` not found).

- [ ] **Step 3: Implement the logic**

`packages/mobile/lib/core/widgets/glass/glass_tab_bar_logic.dart`:

```dart
sealed class GlassTabBarLogic {
  static int slotAt(double x, double width, int count) => (x / (width / count)).floor().clamp(0, count - 1);

  static double slotCenter(int index, double width, int count) => (index + 0.5) * width / count;

  static double dropletLeft({required double centerX, required double dropletWidth, required double barWidth}) =>
      (centerX - dropletWidth / 2).clamp(0, barWidth - dropletWidth).toDouble();

  static double stretchFor(double dx) => 1 + (dx.abs() / 40).clamp(0.0, 0.2);
}
```

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_tab_bar_logic_test.dart`
Expected: PASS.

- [ ] **Step 4: Write the failing widget test**

`packages/mobile/test/core/widgets/glass/glass_tab_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';

const _items = [
  GlassTabItem(icon: Icons.layers_outlined, label: 'Agents'),
  GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
  GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final haptics = <MethodCall>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget host({required int selected, required ValueChanged<int> onSelected, double textScale = 1}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SkinScope(
            skin: const LightSkin(),
            child: Material(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: GlassTabBar(items: _items, selectedIndex: selected, onSelected: onSelected),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('tapping an item selects it with a haptic', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    await tester.tap(find.text('PRs'));
    await tester.pumpAndSettle();
    expect(picked, [1]);
    expect(haptics, hasLength(1));
  });

  testWidgets('tapping the selected item reports it once per tap', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(picked, [0, 0]);
  });

  testWidgets('dragging across and releasing selects the slot under the finger', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, [2]);
  });

  testWidgets('a cancelled drag selects nothing and the droplet returns home', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: picked.add));
    final home = tester.getCenter(find.byKey(GlassTabBar.dropletKey));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Agents')));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Settings')));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(tester.getCenter(find.byKey(GlassTabBar.dropletKey)).dx, closeTo(home.dx, 0.5));
  });

  testWidgets('large text does not overflow', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}, textScale: 2));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_tab_bar_test.dart`
Expected: FAIL (`glass_tab_bar.dart` not found).

- [ ] **Step 6: Implement the tab bar**

`packages/mobile/lib/core/widgets/glass/glass_tab_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:operator_mobile/core/app_themes/app_motion.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar_logic.dart';

class GlassTabItem {
  const GlassTabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class GlassTabBar extends StatefulWidget {
  const GlassTabBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  static const Key dropletKey = ValueKey('glass-tab-bar-droplet');
  static const double liftScale = 1.15;

  final List<GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  double? _dragX;
  double _lastDx = 0;

  void _down(PointerDownEvent event) => setState(() {
        _dragX = event.localPosition.dx;
        _lastDx = 0;
      });

  void _move(PointerMoveEvent event) => setState(() {
        _dragX = event.localPosition.dx;
        _lastDx = event.delta.dx;
      });

  void _up(PointerUpEvent event, double width) {
    final slot = GlassTabBarLogic.slotAt(event.localPosition.dx, width, widget.items.length);
    setState(() {
      _dragX = null;
      _lastDx = 0;
    });
    Haptics.select();
    widget.onSelected(slot);
  }

  void _cancel(PointerCancelEvent event) => setState(() {
        _dragX = null;
        _lastDx = 0;
      });

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      height: GlassMetrics.tabBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final count = widget.items.length;
          final slotWidth = width / count;
          final dropletWidth = slotWidth - GlassMetrics.dropletInset * 2;
          final dropletHeight = GlassMetrics.tabBarHeight - GlassMetrics.dropletInset * 2;
          final lifted = _dragX != null;
          final centerX = _dragX ?? GlassTabBarLogic.slotCenter(widget.selectedIndex, width, count);
          final left = GlassTabBarLogic.dropletLeft(centerX: centerX, dropletWidth: dropletWidth, barWidth: width);
          final stretch = lifted && !reduceMotion ? GlassTabBarLogic.stretchFor(_lastDx) : 1.0;
          final lift = lifted && !reduceMotion ? GlassTabBar.liftScale : 1.0;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (event) => _up(event, width),
            onPointerCancel: _cancel,
            child: GlassScope(
              variant: GlassVariant.regular,
              size: GlassMetrics.tabBarHeight,
              child: LiquidGlassBlendGroup(
                blend: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: GlassSurface(
                        kind: GlassShapeKind.capsule,
                        size: GlassMetrics.tabBarHeight,
                        grouped: true,
                        child: SizedBox.expand(),
                      ),
                    ),
                    AnimatedPositioned(
                      key: GlassTabBar.dropletKey,
                      duration: lifted ? Duration.zero : AppMotion.slow,
                      curve: AppMotion.spring,
                      left: left,
                      top: GlassMetrics.dropletInset,
                      width: dropletWidth,
                      height: dropletHeight,
                      child: AnimatedScale(
                        scale: lift,
                        duration: AppMotion.base,
                        curve: AppMotion.spring,
                        child: Transform.scale(
                          scaleX: stretch,
                          scaleY: 1 / stretch,
                          child: lifted
                              ? const GlassSurface(
                                  kind: GlassShapeKind.capsule,
                                  size: GlassMetrics.tabBarHeight,
                                  grouped: true,
                                  child: SizedBox.expand(),
                                )
                              : DecoratedBox(
                                  decoration: ShapeDecoration(color: skin.bgSubtle, shape: const StadiumBorder()),
                                ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: _TabItemView(
                              item: widget.items[i],
                              selected: i == widget.selectedIndex,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabItemView extends StatelessWidget {
  const _TabItemView({required this.item, required this.selected});

  final GlassTabItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final color = selected ? skin.accent : skin.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
            style: AppTextStyle.style11SemiBold.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_tab_bar_test.dart test/core/widgets/glass/glass_tab_bar_logic_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 8: Put it in the lab**

In `glass_lab_screen.dart`, replace the placeholder bottom `Positioned(... LiquidGlass.withOwnLayer(...LiquidRoundedRectangle(borderRadius: 31)...))` in the `else` branch with:

```dart
              Positioned(
                left: GlassMetrics.tabBarSideInset,
                right: GlassMetrics.tabBarSideInset,
                bottom: GlassMetrics.tabBarBottomInset,
                child: GlassTabBar(
                  items: const [
                    GlassTabItem(icon: Icons.layers_outlined, label: 'Agents'),
                    GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
                    GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
              ),
```

Add the import for `glass_tab_bar.dart`. Remove `liquid_glass_renderer`'s import only if analyze reports it unused; the corners scene still uses it.

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh`
Expected: completes, and in `compare_light_rest_zoom.png` the lab tab bar sits over the bottom stripes where the native one does.

- [ ] **Step 9: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): GlassTabBar with lifting droplet selection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `ScrollEdgeEffect` (spike, then keep the winner)

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/scroll_edge_effect.dart`
- Create (variant B only): `packages/mobile/shaders/scroll_edge_blur.frag`, and add it under `flutter: shaders:` in `packages/mobile/pubspec.yaml`
- Modify: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart`
- Test: `packages/mobile/test/core/widgets/glass/scroll_edge_effect_test.dart`

**Interfaces:**
- Produces:
  - `enum ScrollEdge { top, bottom }`
  - `ScrollEdgeEffect({required ScrollEdge edge, required double height})`: a non-interactive band that blurs and fades the content behind it toward `skin.bgBase`, strongest at the screen edge and zero at its inner edge. It ignores pointers.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/scroll_edge_effect_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';

void main() {
  testWidgets('does not intercept taps on content below it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SkinScope(
          skin: const LightSkin(),
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/scroll_edge_effect_test.dart`
Expected: FAIL (`scroll_edge_effect.dart` not found).

- [ ] **Step 3: Implement variant A (gradient-masked backdrop blur)**

`packages/mobile/lib/core/widgets/glass/scroll_edge_effect.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';

enum ScrollEdge { top, bottom }

class ScrollEdgeEffect extends StatelessWidget {
  const ScrollEdgeEffect({super.key, required this.edge, required this.height});

  final ScrollEdge edge;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bg = context.skin.bgBase;
    final outer = edge == ScrollEdge.top ? Alignment.topCenter : Alignment.bottomCenter;
    final inner = edge == ScrollEdge.top ? Alignment.bottomCenter : Alignment.topCenter;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: outer,
            end: inner,
            colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ColoredBox(color: bg.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}
```

Run: `cd packages/mobile && flutter test test/core/widgets/glass/scroll_edge_effect_test.dart`
Expected: PASS.

- [ ] **Step 4: Put it in the lab and evaluate A**

In `glass_lab_screen.dart`, add these as `Stack` children directly after the `GlassLabBackdrop` entry, so they sit under the chrome, when `scene != GlassLabScene.corners`:

```dart
            if (scene != GlassLabScene.corners) ...[
              const Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 130)),
              const Positioned(left: 0, right: 0, bottom: 0, child: ScrollEdgeEffect(edge: ScrollEdge.bottom, height: 120)),
            ],
```

Run: `cd packages/mobile && SCENES=rest tool/glass_reference/capture.sh /tmp/edge_a`
Open `/tmp/edge_a/compare_light_rest_zoom.png` and `/tmp/edge_a/compare_dark_rest_zoom.png`. Accept A if both hold:
1. The stripes under the lab toolbar fade and soften toward the top edge the way the native ones do, with no visible hard line at the band's inner edge.
2. The blur is applied only inside the band. If the whole band looks unblurred, the mask did not apply to the backdrop filter, and A fails.

Record `top_mad` for later.

- [ ] **Step 5: Only if A failed, implement variant B (variable-blur shader)**

`packages/mobile/shaders/scroll_edge_blur.frag`:

```glsl
#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uMaxRadius;
uniform float uFromTop;
uniform vec4 uTint;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 uv = frag / uSize;
    float t = uFromTop > 0.5 ? 1.0 - uv.y : uv.y;
    float r = uMaxRadius * t;
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -3; i <= 3; i++) {
        for (int j = -3; j <= 3; j++) {
            vec2 o = vec2(float(i), float(j)) * (r / 3.0);
            float w = exp(-float(i * i + j * j) / 8.0);
            acc += texture(uTexture, (frag + o) / uSize) * w;
            wsum += w;
        }
    }
    vec4 blurred = acc / wsum;
    fragColor = mix(blurred, vec4(uTint.rgb * blurred.a, blurred.a), uTint.a * t);
}
```

Add to `packages/mobile/pubspec.yaml` under the existing `flutter:` key:

```yaml
  shaders:
    - shaders/scroll_edge_blur.frag
```

Replace the body of `ScrollEdgeEffect` with a `StatefulWidget` that:
- loads `ui.FragmentProgram.fromAsset('shaders/scroll_edge_blur.frag')` once, in `initState`, into a nullable field
- while it is null, renders the Step 3 variant A tree
- once loaded, renders:

```dart
    final shader = _program!.fragmentShader()
      ..setFloat(0, size.width * dpr)
      ..setFloat(1, size.height * dpr)
      ..setFloat(2, 18 * dpr)
      ..setFloat(3, widget.edge == ScrollEdge.top ? 1 : 0)
      ..setFloat(4, bg.r)
      ..setFloat(5, bg.g)
      ..setFloat(6, bg.b)
      ..setFloat(7, 0.55);
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRect(child: BackdropFilter(filter: ui.ImageFilter.shader(shader), child: const SizedBox.expand())),
      ),
    );
```

Here `size` is from a `LayoutBuilder` (`Size(constraints.maxWidth, widget.height)`), `dpr = MediaQuery.devicePixelRatioOf(context)`, and `bg = context.skin.bgBase`. Re-run the Step 4 capture into `/tmp/edge_b` and apply the same two criteria. Keep whichever of A or B meets them with the lower `top_mad`. Delete the other variant's code, shader file and pubspec entry.

- [ ] **Step 6: Verify and commit**

Run: `cd packages/mobile && flutter test && flutter analyze`
Expected: PASS, and `No issues found!`

```bash
git add -A packages/mobile/lib/core/widgets/glass packages/mobile/test/core/widgets/glass packages/mobile/shaders packages/mobile/pubspec.yaml
git commit -m "feat(mobile): ScrollEdgeEffect soft blur-and-fade under glass bars

Variant kept: <A or B>, top_mad <value>.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: `GlassSheetChrome` and `showGlassSheet`

**Files:**
- Create: `packages/mobile/lib/core/widgets/glass/glass_sheet.dart`
- Modify: `packages/mobile/lib/core/widgets/glass/lab/glass_lab_screen.dart` (sheet scene)
- Test: `packages/mobile/test/core/widgets/glass/glass_sheet_test.dart`

**Interfaces:**
- Consumes: `showExpressiveSheet` (`package:expressive_sheet`), `GlassSurface`, `GlassStyle`, `GlassMetrics`.
- Produces:
  - `sealed class GlassSheetLogic`:
    - `static bool isFloating({required double sheetHeight, required double screenHeight})`: true when `sheetHeight < screenHeight * GlassMetrics.floatingSheetMaxFraction`
    - `static double cornerRadius()`: `GlassMetrics.displayCornerRadius - GlassMetrics.sheetInset`
  - `GlassSheetChrome({required Widget child})`, with `static const Key floatingKey` and `static const Key anchoredKey`
  - `Future<T?> showGlassSheet<T>({required BuildContext context, required WidgetBuilder builder})`
- Behaviour:
  - **Floating** (partial height): inset `GlassMetrics.sheetInset` on the sides and bottom, rendered as a `GlassSurface(kind: rect, radius: cornerRadius(), size: shortest side)` in its own layer, with a grabber.
  - **Anchored** (≥ 0.9 of screen height): opaque `skin.bgSurface`, flush to the edges, with the top corners at `cornerRadius()`.

- [ ] **Step 1: Write the failing test**

`packages/mobile/test/core/widgets/glass/glass_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_sheet.dart';

Widget _host(double childHeight) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(402, 874)),
        child: SkinScope(
          skin: const LightSkin(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassSheetChrome(child: SizedBox(height: childHeight, child: const Text('Sheet'))),
          ),
        ),
      ),
    );

void main() {
  test('floats below 90% of the screen and anchors above', () {
    expect(GlassSheetLogic.isFloating(sheetHeight: 437, screenHeight: 874), isTrue);
    expect(GlassSheetLogic.isFloating(sheetHeight: 800, screenHeight: 874), isFalse);
  });

  testWidgets('a half-height sheet floats as glass', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(400));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.floatingKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsNothing);
  });

  testWidgets('a full-height sheet anchors opaque', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(820));
    await tester.pump();
    expect(find.byKey(GlassSheetChrome.anchoredKey), findsOneWidget);
    expect(find.byKey(GlassSheetChrome.floatingKey), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_sheet_test.dart`
Expected: FAIL (`glass_sheet.dart` not found).

- [ ] **Step 3: Implement**

`packages/mobile/lib/core/widgets/glass/glass_sheet.dart`:

```dart
import 'package:expressive_sheet/expressive_sheet.dart';
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';

sealed class GlassSheetLogic {
  static bool isFloating({required double sheetHeight, required double screenHeight}) =>
      sheetHeight < screenHeight * GlassMetrics.floatingSheetMaxFraction;

  static double cornerRadius() => GlassMetrics.displayCornerRadius - GlassMetrics.sheetInset;
}

class GlassSheetChrome extends StatelessWidget {
  const GlassSheetChrome({super.key, required this.child});

  static const Key floatingKey = ValueKey('glass-sheet-floating');
  static const Key anchoredKey = ValueKey('glass-sheet-anchored');

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final screen = MediaQuery.sizeOf(context);
    final grabber = Center(
      child: Container(
        width: 36,
        height: 5,
        margin: const EdgeInsets.only(top: 6, bottom: 10),
        decoration: BoxDecoration(
          color: skin.borderStrong,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
        ),
      ),
    );
    final body = Column(mainAxisSize: MainAxisSize.min, children: [grabber, child]);
    return _MeasuredSheet(
      builder: (height) {
        if (height == null || GlassSheetLogic.isFloating(sheetHeight: height, screenHeight: screen.height)) {
          return Padding(
            key: floatingKey,
            padding: const EdgeInsets.fromLTRB(GlassMetrics.sheetInset, 0, GlassMetrics.sheetInset, GlassMetrics.sheetInset),
            child: GlassSurface(
              kind: GlassShapeKind.rect,
              radius: GlassSheetLogic.cornerRadius(),
              size: screen.shortestSide,
              child: body,
            ),
          );
        }
        return DecoratedBox(
          key: anchoredKey,
          decoration: ShapeDecoration(
            color: skin.bgSurface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(GlassSheetLogic.cornerRadius())),
            ),
          ),
          child: SafeArea(top: false, child: body),
        );
      },
    );
  }
}

class _MeasuredSheet extends StatefulWidget {
  const _MeasuredSheet({required this.builder});

  final Widget Function(double? height) builder;

  @override
  State<_MeasuredSheet> createState() => _MeasuredSheetState();
}

class _MeasuredSheetState extends State<_MeasuredSheet> {
  double? _height;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return widget.builder(_height);
          },
        ),
      ),
    );
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_height == null || (h - _height!).abs() > 0.5) setState(() => _height = h);
  }
}

Future<T?> showGlassSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  return showExpressiveSheet<T>(
    context: context,
    barrierColor: const Color(0x00000000),
    builder: (context) => GlassSheetChrome(child: builder(context)),
  );
}
```

`_MeasuredSheet` measures the sheet's own rendered height, which includes the inset. The anchored branch triggers when that height reaches 90% of the screen. `package:expressive_sheet/expressive_sheet.dart` exports `showExpressiveSheet` (verified: `packages/expressive_sheet/lib/expressive_sheet.dart:4`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/mobile && flutter test test/core/widgets/glass/glass_sheet_test.dart && flutter analyze`
Expected: PASS, and `No issues found!`

- [ ] **Step 5: The sheet scene in the lab**

The app-level `SkinScope` in `main.dart` sits above `MaterialApp` and follows the user's saved theme (`SkinCubit`). The lab instead follows the simulator appearance through its own `SkinScope` inside `GlassLabScreen`. A sheet route is pushed onto the app `Navigator`, outside the lab's `SkinScope`, so the lab must wrap the sheet in the same brightness-based skin itself. It therefore calls `showExpressiveSheet` directly, not `showGlassSheet`.

Convert `GlassLabScreen` to a `StatefulWidget` and add imports for:
- `package:expressive_sheet/expressive_sheet.dart`
- `package:operator_mobile/core/widgets/glass/glass_sheet.dart`
- `package:operator_mobile/core/app_themes/text_style/app_text_style.dart`

In its state, add:

```dart
  @override
  void initState() {
    super.initState();
    if (widget.scene != GlassLabScene.sheet) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      final skin = dark ? const DarkSkin() : const LightSkin();
      showExpressiveSheet<void>(
        context: context,
        barrierColor: const Color(0x00000000),
        builder: (_) => SkinScope(
          skin: skin,
          child: GlassSheetChrome(
            child: SizedBox(
              height: 380,
              child: Center(
                child: Text('Sheet', style: AppTextStyle.style16SemiBold.copyWith(color: skin.textPrimary)),
              ),
            ),
          ),
        ),
      );
    });
  }
```

Then tune the `SizedBox(height: 380)` until the lab sheet's top edge matches the native `.medium` detent's top edge in `compare_light_sheet.png`.

Run: `cd packages/mobile && SCENES=sheet tool/glass_reference/capture.sh`
Expected: completes. In `compare_light_sheet.png`, the lab sheet floats inset over the scene like the native one.

- [ ] **Step 6: Commit**

```bash
git add packages/mobile/lib/core/widgets/glass packages/mobile/lib/core/app_routes packages/mobile/test/core/widgets/glass
git commit -m "feat(mobile): GlassSheetChrome floating inset glass, opaque when full height

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Tune against native and get sign-off

**Files:**
- Modify: `packages/mobile/lib/core/widgets/glass/glass_style.dart`
- Modify: `packages/mobile/lib/core/widgets/glass/glass_metrics.dart`
- Modify (only if needed): `packages/mobile/packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag`, logging any change in `FORK.md`
- Create: `docs/superpowers/specs/2026-09-23-mobile-liquid-glass-signoff.md`

**Interfaces:**
- Consumes: everything above.
- Produces: tuned constants, plus a sign-off note with the final capture metrics.

This task is a measured loop. Change one group of constants, capture, and compare. Keep a change only if the zoom images look closer **and** `top_mad`/`bottom_mad` do not rise.

- [ ] **Step 1: Geometry first**

Run: `cd packages/mobile && tool/glass_reference/capture.sh`
Open every `build/captures/compare_*_zoom.png`. For each element, measure its edges in the native vs lab halves of the zoom image: tab bar top, bottom, left and right; back circle centre; Edit capsule bounds; Run capsule bounds. Use pixel positions from the image, where 3 px = 1pt, with a Python crop if needed. Adjust `GlassMetrics` (`tabBarBottomInset`, `tabBarHeight`, `tabBarSideInset`, `toolbarTopGap`, `toolbarSideInset`, `primaryButtonInset`, `displayCornerRadius`, `sheetInset`) until every edge is within 1pt (3 px). After every edit, re-run `flutter test test/core/widgets/glass`; tests that pin a constant must still pass.

- [ ] **Step 2: Material next**

With geometry locked, compare tint, blur, rim and shadow in light then dark. Tune `GlassStyle.resolve` one parameter group at a time, in this order:
1. tint alpha (`regular`)
2. `blur` lerp range
3. `saturation`
4. `thicknessFor` range and `refractiveIndex` (lens band width and bend)
5. `lightIntensity`, `fillRatio` and `lightAngle` (rim)
6. `chromaticAberration`
7. `shadows`

Record the metrics after each group. Stop when a further change no longer lowers the metrics and the zoom images show no difference you can name.

- [ ] **Step 3: Write the sign-off note**

`docs/superpowers/specs/2026-09-23-mobile-liquid-glass-signoff.md` contains:
- the final `capture.sh` metric lines for light/dark × rest/sheet
- the final `GlassMetrics` and `GlassStyle` values
- any remaining visible differences, each named with the element and theme
- the device and runtime (iPhone 17 Pro, iOS 26.5)

- [ ] **Step 4: Verify and commit**

Run: `cd packages/mobile && flutter analyze && flutter test`
Expected: `No issues found!`, and all tests pass.

```bash
git add packages/mobile docs/superpowers/specs/2026-09-23-mobile-liquid-glass-signoff.md
git commit -m "feat(mobile): tune glass against native iOS 26 reference

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand the images to the user for sign-off**

Send the four `compare_*.png` and four `compare_*_zoom.png` images to the user with `SendUserFile`, along with the sign-off note. The project is done only when the user signs off on the images. If they name a difference, return to Step 2 for that element.
