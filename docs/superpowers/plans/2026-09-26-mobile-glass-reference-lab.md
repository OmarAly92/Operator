# Mobile Glass Reference Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal.** Build the instrument every later glass project is measured with:
- a native iOS 27 SwiftUI catalog of every iPhone Liquid Glass component;
- an XCUITest driver that plays identical touches on any app;
- a Python harness that records native and Operator's Flutter glass lab and compares them numerically;
- a committed baseline report.

**Architecture.**
- `packages/mobile/tool/glass_lab/` holds four parts:
  - a generated Xcode project with two targets, the GlassLab app and the GlassLabDriver UI test runner;
  - a scene manifest (`scenes.json`);
  - a backdrop generator;
  - the harness (`harness/`).
- Operator's debug-only `/glass-lab` route gets a registry keyed by the same scene ids. It reads its scene from a launch file, because Dart cannot see launch variables on iOS.
- Still images are compared from lossless driver screenshots. Motion is compared from `simctl` recordings at their real frame timestamps. Motion pass limits account for the native-vs-native noise floor.

**Tech stack.** Swift/SwiftUI (iOS 27 SDK, Xcode 27), XCTest UI testing, Python 3 (Pillow, numpy, stdlib `unittest`), ffmpeg, Flutter 3.44.5 / Dart.

**Spec.** `docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-design.md`. Read its "Prototype findings" section first. Research inputs are in `docs/superpowers/specs/research/2026-09-26-liquid-glass/`.

**Where the code comes from.** Every code block in this plan was run on the iOS 27 simulator in a prototype before the plan was written:
- the native catalog compiled;
- the driver drove GlassLab, Operator and Reminders;
- the harness tests passed;
- a native and Flutter smoke run produced a report.

Transcribe the code exactly, then run the verification steps. If a verification step fails, fix the cause, and note what changed in the task report.

## Global Constraints

- **Paths and git**
  - Work only in the worktree `/Users/omaraly/development/AI/Operator-glass-lab`, on branch `feat/mobile-glass-lab`. Never touch `/Users/omaraly/development/AI/Operator`, the shared `development` checkout.
  - Paths below are relative to `packages/mobile/` unless they start with `docs/`, which is relative to the repository root.
  - Every commit message ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `frontend/package-lock.json`. Never stash.
- **Code**
  - No code comments in any new or changed code (Swift, Dart, Python, shell). Keep upstream comments that already exist.
- **Simulator and tools**
  - Simulator: "iPhone 17 Pro (iOS 27)", runtime `com.apple.CoreSimulator.SimRuntime.iOS-27-0`, UDID `708879DD-8B2A-4547-863F-F49EE1474D8B` on this machine. Code finds it by name and runtime, never by UDID.
  - Python may use the standard library, Pillow and numpy only. No `pip install`, and no downloads of any kind.
- **Gates**
  - Flutter gates: `flutter analyze` must print "No issues found!", and `flutter test` must be green. Run both from `packages/mobile`.
  - Harness gate: `python3 -m unittest discover tool/glass_lab/harness/tests`, run from `packages/mobile`.
- **Operator on the simulator**
  - Operator is used only through its debug glass lab route. Never pair, never enter a password, and never touch the user's real sessions or desktops.
  - When a system prompt appears, the only acceptable answers are "Don't Allow" or "Not Now".

## Review Focus

1. **iOS 27 control labels the steps depend on** ("Close", "Search", "BackButton", "Increment", "Decrement", "Cancel", "Sort By", "Sonnet", "Run", "Agents") can differ from the manifest. Expected: every native scene completes its steps. When an element is not found, the driver prints the whole accessibility tree to `driver.log`; fix the step in `scenes.json` from that tree. Task 5 Step 7 pins this by running every native scene.
2. **A leftover `Documents/glass_lab/launch.json` in Operator's container** would make every later debug launch open the lab. Expected: the harness removes it after every drive, even when the driver fails, and the app deletes it as it starts. Pinned by `test_record.py` in Task 5 and `glass_lab_launch_test.dart` in Task 6.
3. **First-run system prompts and overlays inside recordings.** These include Operator's notification prompt, the keyboard's "Quickly Change Keyboards" tip, and Apple apps' welcome screens. Expected: none of them appears in a baseline filmstrip. The driver dismisses springboard alerts with the privacy-preserving button, and `prepare` handles the rest. Task 8 Step 4 pins this by inspecting filmstrips.
4. **An accessibility mode left on after a crashed run.** Expected: `run_cases` always restores all three modes to off. Task 5 Step 8 pins this by interrupting a Reduce Motion run and reading the defaults back.
5. **A Flutter frame stall read as a spring difference.** Expected: the report lists Flutter frame gaps over 25 ms beside the motion measures. Pinned by `EventTests.test_reports_gaps_inside_motion_only` in Task 4.

---

## File map

| Path | Responsibility |
|---|---|
| `tool/glass_lab/native/gen_project.py` | Writes `GlassLab.xcodeproj`: synchronized folders, two targets, shared scheme |
| `tool/glass_lab/native/GlassLab.xcodeproj/` | Generated, committed |
| `tool/glass_lab/native/GlassLab/GlassLabApp.swift` | App entry, scene host, catalog index |
| `tool/glass_lab/native/GlassLab/Lab.swift` | Launch variables, backdrops, ready marker, shared views |
| `tool/glass_lab/native/GlassLab/SceneRegistry.swift` | Id → scene view map |
| `tool/glass_lab/native/GlassLab/{Material,Navigation,Presentation,Control}Scenes.swift` | The catalog, one file per group |
| `tool/glass_lab/native/GlassLabDriver/DriverTests.swift` | The one UI test: launch, settle, screenshot, play steps, screenshot |
| `tool/glass_lab/native/GlassLabDriver/Step.swift` | Step JSON decoding and playback |
| `tool/glass_lab/scenes.json` | Scene manifest |
| `tool/glass_lab/noise.json` | Native-vs-native motion noise floor, written by `lab.py repeat` |
| `tool/glass_lab/backdrops/generate.py` | Deterministic backdrops |
| `tool/glass_lab/harness/manifest.py` | Load, validate and select scenes |
| `tool/glass_lab/harness/metrics.py` | Image loading, glass boxes, static comparison, thresholds |
| `tool/glass_lab/harness/springfit.py` | Spring step response, fit, curve features |
| `tool/glass_lab/harness/align.py` | Frame sequences, events, stalls, series, moving extent |
| `tool/glass_lab/harness/analyze.py` | Per-case analysis: window, region, motion comparison, checks |
| `tool/glass_lab/harness/report.py` | HTML report and Markdown summary |
| `tool/glass_lab/harness/sim.py` | Simulator device, appearance, accessibility, containers |
| `tool/glass_lab/harness/build.py` | Build and install both apps, generate backdrops |
| `tool/glass_lab/harness/record.py` | Launch file, driver runs, recording, capture of one case |
| `tool/glass_lab/harness/lab.py` | CLI |
| `tool/glass_lab/harness/tests/*.py` | unittest suites |
| `tool/glass_lab/README.md` | How to use the lab |
| `lib/core/widgets/glass/lab/glass_lab_launch.dart` | Launch file parsing, lab folder |
| `lib/core/widgets/glass/lab/glass_lab_marker.dart` | Semantics identifiers for the driver |
| `lib/core/widgets/glass/lab/glass_lab_backdrop.dart` | Backdrop images from the lab folder |
| `lib/core/widgets/glass/lab/glass_lab_registry.dart` | Id → scene builder, missing placeholder |
| `lib/core/widgets/glass/lab/glass_lab_screen.dart` | Lab route screen |
| `lib/core/widgets/glass/lab/scenes/*.dart` | Flutter scenes for components Operator already has |
| `docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-baseline.md` | Committed baseline summary |

Deleted: `tool/glass_reference/`, `lib/core/widgets/glass/lab/glass_lab_scene.dart`, `test/core/widgets/glass/lab/glass_lab_scene_test.dart`.

---

### Task 1: Native app shell, project generator and driver

**Files:**
- Create: `tool/glass_lab/native/gen_project.py`
- Create: `tool/glass_lab/native/GlassLab/GlassLabApp.swift`, `Lab.swift`, `SceneRegistry.swift`, `MaterialScenes.swift`
- Create: `tool/glass_lab/native/GlassLabDriver/DriverTests.swift`, `Step.swift`
- Generate: `tool/glass_lab/native/GlassLab.xcodeproj/`
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - App bundle id `dev.operator.glasslab`. Launch variables `GLASS_LAB_SCENE`, `GLASS_LAB_BACKDROP`, `GLASS_LAB_BARE`.
  - Accessibility id `scene.ready`. Backdrops are read from `<app data container>/Documents/glass_lab/<id>.png`.
  - Driver test `GlassLabDriver/DriverTests/testScene`. It reads the runner variables `GLASS_TARGET`, `GLASS_SCENE`, `GLASS_STEPS` (JSON list), `GLASS_BACKDROP`, `GLASS_BARE`, `GLASS_SETTLE` and `GLASS_OUT`, each passed through `xcodebuild` with a `TEST_RUNNER_` prefix. It writes `ready.png`, `settled.png` and `timing.json` (`{start, done, missing}`) into `GLASS_OUT`.
  - `SceneRegistry.all: [String: () -> AnyView]`, and `MaterialScenes.all` with the same type.

- [ ] **Step 1: Write the project generator**

Create `tool/glass_lab/native/gen_project.py`:

```python
import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE / "GlassLab.xcodeproj"


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


APP = oid("target.app")
DRIVER = oid("target.driver")
ROOT = oid("project")
MAIN = oid("group.main")
PRODUCTS = oid("group.products")
APP_DIR = oid("sync.app")
DRIVER_DIR = oid("sync.driver")
APP_PRODUCT = oid("product.app")
DRIVER_PRODUCT = oid("product.driver")
PROXY = oid("proxy.app")
DEPENDENCY = oid("dependency.app")


def phase(kind, name):
    return oid(f"phase.{kind}.{name}")


def config(name, kind):
    return oid(f"config.{name}.{kind}")


def config_list(name):
    return oid(f"configlist.{name}")


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Manual",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "27.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
RELEASE = {
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}
APP_SETTINGS = {
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.operator.glasslab",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
}
DRIVER_SETTINGS = {
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.operator.glasslab.driver",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "TEST_TARGET_NAME": "GlassLab",
}


def settings_block(values, indent):
    pad = "\t" * indent
    return "\n".join(f"{pad}{k} = {v};" for k, v in sorted(values.items()))


def build_configuration(ident, name, values):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{settings_block(values, 4)}\n\t\t\t}};\n"
        f"\t\t\tname = {name};\n"
        f"\t\t}};\n"
    )


def configuration_list(ident, debug, release):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n\t\t\t\t{debug},\n\t\t\t\t{release},\n\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};\n"
    )


def empty_phase(ident, isa):
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = {isa};\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )


def native_target(ident, name, group, product, product_type, dependencies):
    deps = "".join(f"\t\t\t\t{d},\n" for d in dependencies)
    return (
        f"\t\t{ident} = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {config_list(name)};\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{phase('sources', name)},\n"
        f"\t\t\t\t{phase('frameworks', name)},\n"
        f"\t\t\t\t{phase('resources', name)},\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n\t\t\t);\n"
        f"\t\t\tdependencies = (\n{deps}\t\t\t);\n"
        f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{group},\n\t\t\t);\n"
        f"\t\t\tname = {name};\n"
        f"\t\t\tpackageProductDependencies = (\n\t\t\t);\n"
        f"\t\t\tproductName = {name};\n"
        f"\t\t\tproductReference = {product};\n"
        f'\t\t\tproductType = "{product_type}";\n'
        f"\t\t}};\n"
    )


def pbxproj():
    objects = []
    objects.append(
        f"\t\t{PROXY} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {ROOT};\n"
        f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {APP};\n\t\t\tremoteInfo = GlassLab;\n\t\t}};\n"
    )
    objects.append(
        f"\t\t{APP_PRODUCT} = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = GlassLab.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )
    objects.append(
        f"\t\t{DRIVER_PRODUCT} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
        f"includeInIndex = 0; path = GlassLabDriver.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )
    for ident, path in ((APP_DIR, "GlassLab"), (DRIVER_DIR, "GlassLabDriver")):
        objects.append(
            f"\t\t{ident} = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
            f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
        )
    for name in ("GlassLab", "GlassLabDriver"):
        objects.append(empty_phase(phase("frameworks", name), "PBXFrameworksBuildPhase"))
        objects.append(empty_phase(phase("resources", name), "PBXResourcesBuildPhase"))
        objects.append(empty_phase(phase("sources", name), "PBXSourcesBuildPhase"))
    objects.append(
        f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_DIR},\n"
        f"\t\t\t\t{DRIVER_DIR},\n\t\t\t\t{PRODUCTS},\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
    )
    objects.append(
        f"\t\t{PRODUCTS} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_PRODUCT},\n"
        f"\t\t\t\t{DRIVER_PRODUCT},\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
    )
    objects.append(
        native_target(APP, "GlassLab", APP_DIR, APP_PRODUCT, "com.apple.product-type.application", [])
    )
    objects.append(
        native_target(
            DRIVER,
            "GlassLabDriver",
            DRIVER_DIR,
            DRIVER_PRODUCT,
            "com.apple.product-type.bundle.ui-testing",
            [DEPENDENCY],
        )
    )
    objects.append(
        f"\t\t{ROOT} = {{\n"
        f"\t\t\tisa = PBXProject;\n"
        f"\t\t\tattributes = {{\n"
        f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        f"\t\t\t\tLastSwiftUpdateCheck = 2700;\n"
        f"\t\t\t\tLastUpgradeCheck = 2700;\n"
        f"\t\t\t\tTargetAttributes = {{\n"
        f"\t\t\t\t\t{APP} = {{\n\t\t\t\t\t\tCreatedWithXcodeVersion = 27.0;\n\t\t\t\t\t}};\n"
        f"\t\t\t\t\t{DRIVER} = {{\n\t\t\t\t\t\tCreatedWithXcodeVersion = 27.0;\n"
        f"\t\t\t\t\t\tTestTargetID = {APP};\n\t\t\t\t\t}};\n"
        f"\t\t\t\t}};\n"
        f"\t\t\t}};\n"
        f"\t\t\tbuildConfigurationList = {config_list('project')};\n"
        f"\t\t\tdevelopmentRegion = en;\n"
        f"\t\t\thasScannedForEncodings = 0;\n"
        f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {MAIN};\n"
        f"\t\t\tminimizedProjectReferenceProxies = 1;\n"
        f"\t\t\tpreferredProjectObjectVersion = 77;\n"
        f"\t\t\tproductRefGroup = {PRODUCTS};\n"
        f'\t\t\tprojectDirPath = "";\n'
        f'\t\t\tprojectRoot = "";\n'
        f"\t\t\ttargets = (\n\t\t\t\t{APP},\n\t\t\t\t{DRIVER},\n\t\t\t);\n"
        f"\t\t}};\n"
    )
    objects.append(
        f"\t\t{DEPENDENCY} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {APP};\n"
        f"\t\t\ttargetProxy = {PROXY};\n\t\t}};\n"
    )
    for name, extra in (("project", {}), ("GlassLab", APP_SETTINGS), ("GlassLabDriver", DRIVER_SETTINGS)):
        base = COMMON if name == "project" else {}
        objects.append(build_configuration(config(name, "debug"), "Debug", {**base, **(DEBUG if name == "project" else {}), **extra}))
        objects.append(build_configuration(config(name, "release"), "Release", {**base, **(RELEASE if name == "project" else {}), **extra}))
        objects.append(configuration_list(config_list(name), config(name, "debug"), config(name, "release")))
    body = "".join(objects)
    return (
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n"
        f"\tobjects = {{\n{body}\t}};\n\trootObject = {ROOT};\n}}\n"
    )


def buildable(ident, product, name):
    return (
        f'            <BuildableReference\n'
        f'               BuildableIdentifier = "primary"\n'
        f'               BlueprintIdentifier = "{ident}"\n'
        f'               BuildableName = "{product}"\n'
        f'               BlueprintName = "{name}"\n'
        f'               ReferencedContainer = "container:GlassLab.xcodeproj">\n'
        f'            </BuildableReference>\n'
    )


def scheme():
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Scheme LastUpgradeVersion = "2700" version = "1.7">\n'
        '   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">\n'
        '      <BuildActionEntries>\n'
        '         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">\n'
        + buildable(APP, "GlassLab.app", "GlassLab")
        + '         </BuildActionEntry>\n'
        '      </BuildActionEntries>\n'
        '   </BuildAction>\n'
        '   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv = "YES">\n'
        '      <Testables>\n'
        '         <TestableReference skipped = "NO">\n'
        + buildable(DRIVER, "GlassLabDriver.xctest", "GlassLabDriver")
        + '         </TestableReference>\n'
        '      </Testables>\n'
        '   </TestAction>\n'
        '   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">\n'
        '      <BuildableProductRunnable runnableDebuggingMode = "0">\n'
        + buildable(APP, "GlassLab.app", "GlassLab")
        + '      </BuildableProductRunnable>\n'
        '   </LaunchAction>\n'
        '</Scheme>\n'
    )


def main(project=PROJECT):
    project = Path(project)
    (project / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
    (project / "project.pbxproj").write_text(pbxproj())
    (project / "xcshareddata" / "xcschemes" / "GlassLab.xcscheme").write_text(scheme())


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else PROJECT)
```

- [ ] **Step 2: Write the app shell**

Create `tool/glass_lab/native/GlassLab/GlassLabApp.swift`:

```swift
import SwiftUI

@main
struct GlassLabApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        if let id = Lab.sceneID {
            SceneHost(id: id)
        } else {
            CatalogIndex()
        }
    }
}

struct SceneHost: View {
    let id: String

    var body: some View {
        Group {
            if Lab.bare {
                Backdrop()
            } else if let make = SceneRegistry.all[id] {
                make()
            } else {
                ZStack {
                    Backdrop()
                    Text("unknown scene: \(id)").font(.headline).padding().background(.white)
                }
            }
        }
        .overlay(alignment: .topLeading) { ReadyMarker() }
    }
}

struct CatalogIndex: View {
    @State private var selected: String?

    var body: some View {
        NavigationStack {
            List(SceneRegistry.ids, id: \.self) { id in
                NavigationLink(id, value: id)
            }
            .navigationTitle("Glass Lab")
            .navigationDestination(for: String.self) { id in
                SceneHost(id: id).toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}
```

Create `tool/glass_lab/native/GlassLab/Lab.swift`:

```swift
import SwiftUI
import UIKit

enum Lab {
    static let environment = ProcessInfo.processInfo.environment
    static let sceneID = environment["GLASS_LAB_SCENE"]
    static let bare = environment["GLASS_LAB_BARE"] == "1"
    static let backdropID = environment["GLASS_LAB_BACKDROP"] ?? "stripes"
    static let accent = Color(red: 0x1A / 255, green: 0xCB / 255, blue: 0x64 / 255)

    static func image(_ id: String) -> UIImage? {
        let documents = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/glass_lab")
        return UIImage(contentsOfFile: documents.appendingPathComponent("\(id).png").path)
    }
}

struct ReadyMarker: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("scene.ready")
    }
}

struct Backdrop: View {
    var id: String = Lab.backdropID

    var body: some View {
        if id == "scroll" {
            ScrollBackdrop()
        } else if id == "none" {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        } else if let image = Lab.image(id) {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
        } else {
            Color.gray.ignoresSafeArea()
        }
    }
}

struct ScrollBackdrop: View {
    var body: some View {
        ScrollView {
            if let image = Lab.image("scroll") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
            }
        }
        .accessibilityIdentifier("scroll.content")
        .ignoresSafeArea()
    }
}

struct GlassBlock: View {
    let width: CGFloat
    let height: CGFloat
    var glass: Glass = .regular

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .glassEffect(glass)
    }
}

struct Card: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text("feat/branch").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LabButton: View {
    let title: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
```

Create `tool/glass_lab/native/GlassLab/SceneRegistry.swift`, material-only for now; Task 2 widens it:

```swift
import SwiftUI

enum SceneRegistry {
    static let all: [String: () -> AnyView] = MaterialScenes.all

    static let ids: [String] = all.keys.sorted()
}
```

- [ ] **Step 3: Write the material scenes**

Create `tool/glass_lab/native/GlassLab/MaterialScenes.swift`:

```swift
import SwiftUI

enum MaterialScenes {
    static let all: [String: () -> AnyView] = [
        "material.regular": { AnyView(RegularScene()) },
        "material.clear": { AnyView(ClearScene()) },
        "material.tinted": { AnyView(TintedScene()) },
        "material.interactive": { AnyView(InteractiveScene()) },
        "material.flip": { AnyView(FlipScene()) },
        "material.materialize": { AnyView(MaterializeScene()) },
        "material.merge": { AnyView(MergeScene()) },
        "material.union": { AnyView(UnionScene()) },
        "material.morph": { AnyView(MorphScene()) },
        "material.shapes": { AnyView(ShapesScene()) },
        "material.edge.soft": { AnyView(EdgeScene(style: .soft)) },
        "material.edge.hard": { AnyView(EdgeScene(style: .hard)) },
        "material.edge.automatic": { AnyView(EdgeScene(style: .automatic)) },
        "material.content": { AnyView(ContentMaterialsScene()) },
    ]
}

struct RegularScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                GlassBlock(width: 150, height: 44)
                GlassBlock(width: 250, height: 88)
                GlassBlock(width: 360, height: 200)
            }
        }
    }
}

struct ClearScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 64) {
                GlassBlock(width: 250, height: 88, glass: .clear)
                ZStack {
                    Capsule().fill(.black.opacity(0.35)).frame(width: 250, height: 88)
                    GlassBlock(width: 250, height: 88, glass: .clear)
                }
            }
        }
    }
}

struct TintedScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                GlassBlock(width: 250, height: 88, glass: .regular.tint(Lab.accent))
                Button {} label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(Lab.accent)
                    .accessibilityIdentifier("tinted.run")
            }
        }
    }
}

struct InteractiveScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            GlassBlock(width: 250, height: 88, glass: .regular.interactive())
                .accessibilityElement()
                .accessibilityIdentifier("glass")
        }
    }
}

struct FlipScene: View {
    var body: some View {
        ZStack {
            ScrollBackdrop()
            VStack {
                GlassBlock(width: 150, height: 44).padding(.top, 180)
                Spacer()
                GlassBlock(width: 360, height: 200).padding(.bottom, 180)
            }
            .allowsHitTesting(false)
        }
    }
}

struct MaterializeScene: View {
    @State private var shown = true

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer {
                if shown {
                    GlassBlock(width: 250, height: 88).glassEffectTransition(.materialize)
                }
            }
            VStack {
                Spacer()
                LabButton(title: "Toggle", id: "toggle") {
                    withAnimation { shown.toggle() }
                }
                .padding(.bottom, 120)
            }
        }
    }
}

struct MergeScene: View {
    @State private var merged = false

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer(spacing: 40) {
                HStack(spacing: merged ? 0 : 80) {
                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    LabButton(title: "Merge", id: "merge") { withAnimation { merged = true } }
                    LabButton(title: "Split", id: "split") { withAnimation { merged = false } }
                }
                .padding(.bottom, 120)
            }
        }
    }
}

struct UnionScene: View {
    @Namespace private var namespace
    private let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill"]

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer {
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Image(systemName: symbols[index])
                            .font(.system(size: 24))
                            .frame(width: 64, height: 64)
                            .glassEffect()
                            .glassEffectUnion(id: index < 2 ? "first" : "second", namespace: namespace)
                    }
                }
            }
        }
    }
}

struct MorphScene: View {
    @Namespace private var namespace
    @State private var expanded = false
    private let badges = ["star.fill", "heart.fill", "bolt.fill"]

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 16) {
                    if expanded {
                        ForEach(badges, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 22))
                                .frame(width: 56, height: 56)
                                .glassEffect()
                                .glassEffectID(symbol, in: namespace)
                        }
                    }
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "xmark" : "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectID("toggle", in: namespace)
                    .accessibilityIdentifier("morph")
                }
            }
        }
    }
}

struct ShapesScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 40) {
                Color.clear.frame(width: 250, height: 60).glassEffect(.regular, in: .capsule)
                Color.clear.frame(width: 250, height: 88).glassEffect(.regular, in: .rect(cornerRadius: 16))
                Color.clear
                    .frame(width: 300, height: 180)
                    .overlay {
                        Color.clear
                            .glassEffect(.regular, in: ConcentricRectangle())
                            .padding(12)
                    }
                    .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .containerShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            }
        }
    }
}

struct EdgeScene: View {
    let style: ScrollEdgeEffectStyle

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = Lab.image("scroll") {
                    Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
                }
            }
            .accessibilityIdentifier("scroll.content")
            .scrollEdgeEffectStyle(style, for: .all)
            .navigationTitle("Edge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} }
            }
        }
    }
}

struct ContentMaterialsScene: View {
    private let materials: [(String, Material)] = [
        ("Ultra thin", .ultraThinMaterial),
        ("Thin", .thinMaterial),
        ("Regular", .regularMaterial),
        ("Thick", .thickMaterial),
    ]

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 16) {
                ForEach(materials, id: \.0) { name, material in
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 340, height: 80)
                        .background(material, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }
}
```

- [ ] **Step 4: Write the driver**

Create `tool/glass_lab/native/GlassLabDriver/Step.swift`:

```swift
import Foundation
import XCTest

enum Target {
    case point(CGFloat, CGFloat)
    case element(String, dx: CGFloat, dy: CGFloat)

    init(json: Any) throws {
        if let pair = json as? [Double], pair.count == 2 {
            self = .point(CGFloat(pair[0]), CGFloat(pair[1]))
        } else if let name = json as? String {
            self = .element(name, dx: 0, dy: 0)
        } else if let object = json as? [String: Any], let name = object["element"] as? String {
            self = .element(name, dx: CGFloat(object["dx"] as? Double ?? 0), dy: CGFloat(object["dy"] as? Double ?? 0))
        } else {
            throw StepError.malformed("target \(json)")
        }
    }
}

enum Step {
    case wait(Double)
    case tap(Target)
    case doubleTap(Target)
    case press(Target, duration: Double)
    case pressDrag(from: Target, to: Target, pressDuration: Double, velocity: Double?, hold: Double)

    static func decode(_ text: String) throws -> [Step] {
        let raw = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let list = raw as? [[String: Any]] else { throw StepError.malformed("steps must be a list of objects") }
        return try list.map(Step.init(json:))
    }

    init(json: [String: Any]) throws {
        guard json.count == 1, let (kind, value) = json.first else { throw StepError.malformed("step \(json)") }
        switch kind {
        case "wait":
            guard let seconds = value as? Double else { throw StepError.malformed("wait \(value)") }
            self = .wait(seconds)
        case "tap":
            self = .tap(try Target(json: value))
        case "doubleTap":
            self = .doubleTap(try Target(json: value))
        case "press":
            guard let object = value as? [String: Any], let at = object["at"], let duration = object["duration"] as? Double else {
                throw StepError.malformed("press \(value)")
            }
            self = .press(try Target(json: at), duration: duration)
        case "pressDrag":
            guard let object = value as? [String: Any], let from = object["from"], let to = object["to"] else {
                throw StepError.malformed("pressDrag \(value)")
            }
            self = .pressDrag(
                from: try Target(json: from),
                to: try Target(json: to),
                pressDuration: object["pressDuration"] as? Double ?? 0.05,
                velocity: object["velocity"] as? Double,
                hold: object["hold"] as? Double ?? 0
            )
        default:
            throw StepError.malformed("unknown step \(kind)")
        }
    }
}

enum StepError: Error, CustomStringConvertible {
    case malformed(String)
    case missingElement(String, String)

    var description: String {
        switch self {
        case .malformed(let detail): return "malformed step: \(detail)"
        case .missingElement(let name, let tree): return "element \(name) not found\n\(tree)"
        }
    }
}

struct StepPlayer {
    let app: XCUIApplication

    func coordinate(_ target: Target) throws -> XCUICoordinate {
        switch target {
        case .point(let x, let y):
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        case .element(let name, let dx, let dy):
            let element = app.descendants(matching: .any)[name].firstMatch
            guard element.waitForExistence(timeout: 5) else { throw StepError.missingElement(name, app.debugDescription) }
            return element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: dx, dy: dy))
        }
    }

    func play(_ step: Step) throws {
        switch step {
        case .wait(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .tap(let target):
            try coordinate(target).tap()
        case .doubleTap(let target):
            try coordinate(target).doubleTap()
        case .press(let target, let duration):
            try coordinate(target).press(forDuration: duration)
        case .pressDrag(let from, let to, let pressDuration, let velocity, let hold):
            let start = try coordinate(from)
            let end = try coordinate(to)
            let speed = velocity.map { XCUIGestureVelocity(CGFloat($0)) } ?? .default
            start.press(forDuration: pressDuration, thenDragTo: end, withVelocity: speed, thenHoldForDuration: hold)
        }
    }
}
```

Create `tool/glass_lab/native/GlassLabDriver/DriverTests.swift`:

```swift
import XCTest

final class DriverTests: XCTestCase {
    func testScene() throws {
        let environment = ProcessInfo.processInfo.environment
        let target = try XCTUnwrap(environment["GLASS_TARGET"], "GLASS_TARGET missing")
        let scene = environment["GLASS_SCENE"] ?? ""
        let steps = try Step.decode(environment["GLASS_STEPS"] ?? "[]")
        let settle = Double(environment["GLASS_SETTLE"] ?? "") ?? 1.5
        let out = environment["GLASS_OUT"].map { URL(fileURLWithPath: $0) }
        let app = XCUIApplication(bundleIdentifier: target)
        if !scene.isEmpty {
            app.launchEnvironment["GLASS_LAB_SCENE"] = scene
            app.launchEnvironment["GLASS_LAB_BACKDROP"] = environment["GLASS_BACKDROP"] ?? "stripes"
            app.launchEnvironment["GLASS_LAB_BARE"] = environment["GLASS_BARE"] ?? "0"
        }
        app.launch()
        dismissSystemPrompts()
        if scene.isEmpty {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        } else {
            let ready = app.descendants(matching: .any)["scene.ready"]
            XCTAssertTrue(ready.waitForExistence(timeout: 20), "scene.ready never appeared\n\(app.debugDescription)")
        }
        Thread.sleep(forTimeInterval: settle)
        let missing = !scene.isEmpty && app.descendants(matching: .any)["scene.missing"].exists
        try out.map { try XCUIScreen.main.screenshot().pngRepresentation.write(to: $0.appendingPathComponent("ready.png")) }
        let start = Date().timeIntervalSince1970
        let player = StepPlayer(app: app)
        for step in missing ? [] : steps {
            try player.play(step)
        }
        let done = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: settle)
        if let out {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent("settled.png"))
            let timing: [String: Any] = ["start": start, "done": done, "missing": missing]
            try JSONSerialization.data(withJSONObject: timing).write(to: out.appendingPathComponent("timing.json"))
        }
    }

    private func dismissSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let choice = ["Don’t Allow", "Don't Allow", "Not Now"].lazy.map { alert.buttons[$0] }.first { $0.exists }
            guard let choice else { return }
            choice.tap()
        }
    }
}
```

- [ ] **Step 5: Generate the project and ignore Xcode user state**

Run: `python3 tool/glass_lab/native/gen_project.py`
Expected: `tool/glass_lab/native/GlassLab.xcodeproj/project.pbxproj` and `.../xcshareddata/xcschemes/GlassLab.xcscheme` exist.

Append to `.gitignore` (the one in `packages/mobile`), after the `tool/glass_reference/build/` line:

```
tool/glass_lab/**/__pycache__/
tool/glass_lab/native/GlassLab.xcodeproj/xcuserdata/
tool/glass_lab/native/GlassLab.xcodeproj/project.xcworkspace/
```

- [ ] **Step 6: Build app and driver for iOS 27**

Run:
```bash
xcodebuild build-for-testing -project tool/glass_lab/native/GlassLab.xcodeproj -scheme GlassLab -destination "platform=iOS Simulator,name=iPhone 17 Pro (iOS 27),OS=27.0" -derivedDataPath build/glass_lab/native 2>&1 | grep -E "error:|TEST BUILD"
```
Expected: `** TEST BUILD SUCCEEDED **`. If the simulator does not exist yet, create and boot it first:

```bash
xcrun simctl create "iPhone 17 Pro (iOS 27)" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0
```

- [ ] **Step 7: Smoke-drive a scene**

Run:
```bash
UDID=$(xcrun simctl list devices "iOS 27.0" | grep "iPhone 17 Pro (iOS 27)" | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" build/glass_lab/native/Build/Products/Debug-iphonesimulator/GlassLab.app
mkdir -p build/glass_lab/smoke
TEST_RUNNER_GLASS_TARGET=dev.operator.glasslab TEST_RUNNER_GLASS_SCENE=material.interactive TEST_RUNNER_GLASS_BACKDROP=stripes TEST_RUNNER_GLASS_OUT="$PWD/build/glass_lab/smoke" TEST_RUNNER_GLASS_STEPS='[{"wait":0.5},{"press":{"at":"glass","duration":1.0}},{"wait":0.5}]' xcodebuild test-without-building -project tool/glass_lab/native/GlassLab.xcodeproj -scheme GlassLab -destination "id=$UDID" -derivedDataPath build/glass_lab/native -only-testing:GlassLabDriver/DriverTests/testScene 2>&1 | grep -E "passed|failed|error"
ls build/glass_lab/smoke
```
Expected: `Test Case '-[GlassLabDriver.DriverTests testScene]' passed`, and `ready.png settled.png timing.json` listed. The backdrop is grey at this point, because Task 5's `prepare` copies the real ones.

- [ ] **Step 8: Commit**

```bash
git add .gitignore tool/glass_lab/native
git commit -m "feat(mobile): glass lab native shell, material scenes and XCUITest driver

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Native navigation, presentation and control scenes

**Files:**
- Create: `tool/glass_lab/native/GlassLab/NavigationScenes.swift`, `PresentationScenes.swift`, `ControlScenes.swift`
- Modify: `tool/glass_lab/native/GlassLab/SceneRegistry.swift`

**Interfaces:**
- Consumes: `Backdrop`, `ScrollBackdrop`, `GlassBlock`, `Card`, `LabButton` and `Lab.accent` from `Lab.swift`.
- Produces:
  - `NavigationScenes.all`, `PresentationScenes.all` and `ControlScenes.all`, each `[String: () -> AnyView]`.
  - The accessibility ids the steps use: `sheet.top`, `zoom.source`, `sheet.present`, `sheet.close`, `popover.source`, `menu.button`, `card`, `card.N`, `alert.show`, `confirm.show`, `row.N`, `nav.bell`, `nav.tray`, `btn.glass`, `btn.prominent`, `toggle.off`, `toggle.on`, `slider.default`, `segmented`, `picker`, `datepicker`, `field.text`, `field.search`, `form`, `glass`, `toggle`, `merge`, `split`, `morph`, `tinted.run`, `scroll.content`.

- [ ] **Step 1: Write the navigation scenes**

Create `tool/glass_lab/native/GlassLab/NavigationScenes.swift`:

```swift
import SwiftUI

enum NavigationScenes {
    static let all: [String: () -> AnyView] = [
        "tabbar.rest": { AnyView(LabTabView()) },
        "tabbar.press": { AnyView(LabTabView()) },
        "tabbar.drag": { AnyView(LabTabView()) },
        "tabbar.badge": { AnyView(LabTabView(badge: true)) },
        "tabbar.prominent": { AnyView(LabTabView(prominent: true)) },
        "tabbar.minimize": { AnyView(LabTabView(scrolls: true, minimizes: true)) },
        "tabbar.accessory": { AnyView(LabTabView(scrolls: true, minimizes: true, accessory: true)) },
        "tabbar.search": { AnyView(LabTabView()) },
        "navbar.inline": { AnyView(InlineNavScene()) },
        "navbar.large": { AnyView(LargeTitleScene()) },
        "navbar.groups": { AnyView(GroupsScene()) },
        "navbar.minimize": { AnyView(LargeTitleScene(minimizes: true)) },
        "navbar.push": { AnyView(PushScene()) },
        "navbar.badge": { AnyView(BadgeNavScene()) },
        "toolbar.bottom": { AnyView(BottomToolbarScene()) },
        "search.bottom": { AnyView(SearchScene()) },
        "search.minimized": { AnyView(SearchScene(minimized: true)) },
        "search.scopes": { AnyView(SearchScene(scoped: true)) },
    ]
}

enum LabTab: Hashable {
    case agents, prs, settings, run, search
}

struct LabTabView: View {
    var badge = false
    var prominent = false
    var scrolls = false
    var minimizes = false
    var accessory = false
    @State private var selection: LabTab = .agents
    @State private var query = ""

    var body: some View {
        TabView(selection: $selection) {
            Tab("Agents", systemImage: "square.stack.3d.up", value: .agents) { page }
            Tab("PRs", systemImage: "arrow.triangle.merge", value: .prs) { page }
                .badge(badge ? 3 : 0)
            Tab("Settings", systemImage: "gearshape", value: .settings) { page }
            if prominent {
                Tab("Run", systemImage: "play.fill", value: .run, role: .prominent) { page }
            }
            Tab(value: .search, role: .search) {
                NavigationStack { Backdrop().searchable(text: $query) }
            }
        }
        .tint(Lab.accent)
        .tabBarMinimizeBehavior(minimizes ? .onScrollDown : .automatic)
        .tabViewBottomAccessory(isEnabled: accessory) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                Text("Agent working")
                Spacer()
                Image(systemName: "stop.fill")
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var page: some View {
        if scrolls {
            ScrollBackdrop()
        } else {
            Backdrop()
        }
    }
}

struct DetailPage: View {
    let title: String

    var body: some View {
        Backdrop()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct InlineNavScene: View {
    @State private var path = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Backdrop()
                .navigationTitle("Sessions")
                .navigationDestination(for: Int.self) { _ in
                    Backdrop()
                        .navigationTitle("Agents")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {} label: { Image(systemName: "bell") }
                                Button {} label: { Image(systemName: "ellipsis") }
                            }
                        }
                }
        }
    }
}

struct LargeTitleScene: View {
    var minimizes = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = Lab.image("scroll") {
                    Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
                }
            }
            .accessibilityIdentifier("scroll.content")
            .navigationTitle("Agents")
            .navigationSubtitle("3 running")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "plus") }
                }
            }
            .toolbarMinimizationBehavior(minimizes ? .onScrollDown : .automatic, for: .navigationBar)
        }
    }
}

struct GroupsScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") {} }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "bell") }.accessibilityIdentifier("nav.bell")
                        Button {} label: { Image(systemName: "tray") }.accessibilityIdentifier("nav.tray")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {}.buttonStyle(.glassProminent).tint(Lab.accent)
                    }
                }
        }
    }
}

struct PushScene: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                VStack(spacing: 12) {
                    ForEach(1...3, id: \.self) { index in
                        NavigationLink(value: index) { Card(title: "Session \(index)") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("row.\(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "bell") }
                }
            }
            .navigationDestination(for: Int.self) { index in
                Backdrop()
                    .navigationTitle("Session \(index)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Image(systemName: "bell") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Image(systemName: "square.and.arrow.up") }
                        }
                    }
            }
        }
    }
}

struct BadgeNavScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "bell") }
                            .badge(3)
                    }
                }
        }
    }
}

struct BottomToolbarScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Files")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {} label: { Image(systemName: "trash") }
                        Button {} label: { Image(systemName: "folder") }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {} label: { Image(systemName: "square.and.pencil") }
                    }
                }
        }
    }
}

struct SearchScene: View {
    var minimized = false
    var scoped = false
    @State private var query = ""
    @State private var scope = 0

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query)
                .searchToolbarBehavior(minimized ? .minimize : .automatic)
                .searchScopes($scope, activation: .onSearchPresentation) {
                    if scoped {
                        Text("All").tag(0)
                        Text("Running").tag(1)
                        Text("Done").tag(2)
                    }
                }
        }
    }
}
```

- [ ] **Step 2: Write the presentation scenes**

Create `tool/glass_lab/native/GlassLab/PresentationScenes.swift`:

```swift
import SwiftUI

enum PresentationScenes {
    static let all: [String: () -> AnyView] = [
        "sheet.detents": { AnyView(DetentSheetScene()) },
        "sheet.scroll": { AnyView(ScrollSheetScene()) },
        "sheet.zoom": { AnyView(ZoomSheetScene()) },
        "sheet.crossfade": { AnyView(CrossFadeSheetScene()) },
        "popover.bar": { AnyView(PopoverScene()) },
        "menu.bar": { AnyView(MenuScene()) },
        "menu.submenu": { AnyView(MenuScene()) },
        "menu.pressdrag": { AnyView(MenuScene()) },
        "contextmenu.card": { AnyView(ContextMenuScene()) },
        "alert.two": { AnyView(AlertScene(actions: 2)) },
        "alert.three": { AnyView(AlertScene(actions: 3)) },
        "confirm.source": { AnyView(ConfirmScene()) },
        "push.zoom": { AnyView(PushZoomScene()) },
    ]
}

struct SheetBody: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .accessibilityIdentifier("sheet.top")
            Spacer()
        }
    }
}

struct DetentSheetScene: View {
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        Backdrop()
            .sheet(isPresented: .constant(true)) {
                SheetBody(title: "Sheet")
                    .presentationDetents([.height(120), .medium, .large], selection: $detent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    .interactiveDismissDisabled()
            }
    }
}

struct ScrollSheetScene: View {
    var body: some View {
        Backdrop()
            .sheet(isPresented: .constant(true)) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(1...30, id: \.self) { index in
                            Card(title: "Row \(index)")
                        }
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("sheet.scroll")
                .presentationDetents([.large])
                .interactiveDismissDisabled()
            }
    }
}

struct ZoomSheetScene: View {
    @Namespace private var namespace
    @State private var shown = false

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shown = true } label: { Image(systemName: "plus") }
                            .accessibilityIdentifier("zoom.source")
                    }
                    .matchedTransitionSource(id: "source", in: namespace)
                }
                .sheet(isPresented: $shown) {
                    SheetBody(title: "New agent")
                        .presentationDetents([.medium])
                        .navigationTransition(.zoom(sourceID: "source", in: namespace))
                }
        }
    }
}

struct CrossFadeSheetScene: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Present", id: "sheet.present") { shown = true }
        }
        .sheet(isPresented: $shown) {
            VStack {
                SheetBody(title: "Cross fade")
                LabButton(title: "Close", id: "sheet.close") { shown = false }
                Spacer()
            }
            .presentationDetents([.medium])
            .navigationTransition(.crossFade)
        }
    }
}

struct PopoverScene: View {
    @State private var shown = false

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shown = true } label: { Image(systemName: "info.circle") }
                            .accessibilityIdentifier("popover.source")
                            .popover(isPresented: $shown) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Session 1").font(.headline)
                                    Text("Running for 12 minutes").font(.subheadline)
                                }
                                .padding(20)
                                .presentationCompactAdaptation(.popover)
                            }
                    }
                }
        }
    }
}

struct MenuScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Reminders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Show List Info", systemImage: "info.circle") {}
                            Button("Select Reminders", systemImage: "checkmark.circle") {}
                            Menu("Sort By", systemImage: "arrow.up.arrow.down") {
                                Button("Manual") {}
                                Button("Due Date") {}
                                Button("Title") {}
                            }
                            Button("Show Completed", systemImage: "eye") {}
                            Button("Print", systemImage: "printer") {}
                            Button("Delete List", systemImage: "trash", role: .destructive) {}
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityIdentifier("menu.button")
                    }
                }
        }
    }
}

struct ContextMenuScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            Card(title: "Session 1")
                .padding(.horizontal, 16)
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {}
                    Button("Share", systemImage: "square.and.arrow.up") {}
                    Button("Kill", systemImage: "xmark.octagon", role: .destructive) {}
                }
                .accessibilityIdentifier("card")
        }
    }
}

struct AlertScene: View {
    let actions: Int
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Show", id: "alert.show") { shown = true }
        }
        .alert("Kill session?", isPresented: $shown) {
            if actions == 3 {
                Button("Keep running") {}
            }
            Button("Kill", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent stops and its terminal closes.")
        }
    }
}

struct ConfirmScene: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Delete", id: "confirm.show") { shown = true }
                .confirmationDialog("Delete session?", isPresented: $shown, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}

struct PushZoomScene: View {
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        NavigationLink(value: index) { Card(title: "Session \(index + 1)") }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: index, in: namespace)
                            .accessibilityIdentifier("card.\(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { index in
                Backdrop()
                    .navigationTitle("Session \(index + 1)")
                    .navigationTransition(.zoom(sourceID: index, in: namespace))
            }
        }
    }
}
```

- [ ] **Step 3: Write the control scenes**

Create `tool/glass_lab/native/GlassLab/ControlScenes.swift`:

```swift
import SwiftUI
import UIKit

enum ControlScenes {
    static let all: [String: () -> AnyView] = [
        "button.styles": { AnyView(ButtonStylesScene()) },
        "button.press": { AnyView(ButtonPressScene()) },
        "toggle": { AnyView(ToggleScene()) },
        "slider": { AnyView(SliderScene()) },
        "segmented": { AnyView(SegmentedScene()) },
        "stepper": { AnyView(StepperScene()) },
        "picker.menu": { AnyView(MenuPickerScene()) },
        "datepicker.compact": { AnyView(DatePickerScene(style: .compact)) },
        "datepicker.inline": { AnyView(DatePickerScene(style: .inline)) },
        "datepicker.wheel": { AnyView(DatePickerScene(style: .wheel)) },
        "pagecontrol": { AnyView(PageControlScene()) },
        "textfield": { AnyView(TextFieldScene()) },
        "list.form": { AnyView(FormScene()) },
        "swipe.row": { AnyView(SwipeScene()) },
        "progress": { AnyView(ProgressScene()) },
    ]
}

struct ButtonStylesScene: View {
    private let sizes: [ControlSize] = [.small, .regular, .large, .extraLarge]

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                ForEach(sizes, id: \.self) { size in
                    HStack(spacing: 12) {
                        Button("Glass") {}.buttonStyle(.glass)
                        Button("Prominent") {}.buttonStyle(.glassProminent).tint(Lab.accent)
                        Button("Clear") {}.buttonStyle(.glass(.clear))
                    }
                    .controlSize(size)
                }
                HStack(spacing: 16) {
                    Button {} label: { Image(systemName: "plus") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    Button {} label: { Image(systemName: "play.fill") }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Lab.accent)
                    Button {} label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass(.clear))
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                }
            }
        }
    }
}

struct ButtonPressScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 60) {
                Button("Glass button") {}
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityIdentifier("btn.glass")
                Button("Prominent button") {}
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Lab.accent)
                    .accessibilityIdentifier("btn.prominent")
            }
        }
    }
}

struct ToggleScene: View {
    @State private var off = false
    @State private var on = true

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 60) {
                Toggle("Off", isOn: $off).labelsHidden().accessibilityIdentifier("toggle.off")
                Toggle("On", isOn: $on).labelsHidden().accessibilityIdentifier("toggle.on")
            }
        }
    }
}

struct SliderScene: View {
    @State private var plain = 0.5
    @State private var stepped = 5.0
    @State private var neutral = 0.0
    @State private var thumbless = 0.4

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                Slider(value: $plain) { Text("Default") }
                    .labelsHidden()
                    .accessibilityIdentifier("slider.default")
                Slider(value: $stepped, in: 0...10, step: 1) { Text("Stepped") }
                    .labelsHidden()
                Slider(value: $neutral, in: -1...1, neutralValue: 0) { Text("Neutral") }
                    .labelsHidden()
                Slider(value: $thumbless) { Text("Thumbless") }
                    .labelsHidden()
                    .sliderThumbVisibility(.hidden)
            }
            .frame(width: 300)
        }
    }
}

struct SegmentedScene: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            Backdrop()
            Picker("Filter", selection: $selection) {
                Text("All").tag(0)
                Text("Running").tag(1)
                Text("Done").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .accessibilityIdentifier("segmented")
        }
    }
}

struct StepperScene: View {
    @State private var value = 3

    var body: some View {
        ZStack {
            Backdrop()
            Stepper("Agents: \(value)", value: $value, in: 0...10)
                .frame(width: 300)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct MenuPickerScene: View {
    @State private var model = "Opus"

    var body: some View {
        ZStack {
            Backdrop()
            Picker("Model", selection: $model) {
                Text("Opus").tag("Opus")
                Text("Sonnet").tag("Sonnet")
                Text("Haiku").tag("Haiku")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("picker")
        }
    }
}

enum LabDatePickerStyle {
    case compact, inline, wheel
}

struct DatePickerScene: View {
    let style: LabDatePickerStyle
    @State private var date = Date(timeIntervalSince1970: 1_790_000_000)

    var body: some View {
        ZStack {
            Backdrop()
            picker.accessibilityIdentifier("datepicker")
        }
    }

    @ViewBuilder private var picker: some View {
        switch style {
        case .compact:
            DatePicker("Due", selection: $date).datePickerStyle(.compact).labelsHidden()
        case .inline:
            DatePicker("Due", selection: $date).datePickerStyle(.graphical).frame(width: 360)
        case .wheel:
            DatePicker("Due", selection: $date).datePickerStyle(.wheel).labelsHidden()
        }
    }
}

struct PageControlView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = 5
        control.currentPage = 1
        control.backgroundStyle = .prominent
        return control
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {}
}

struct PageControlScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            PageControlView().fixedSize()
        }
    }
}

struct TextFieldScene: View {
    @State private var text = ""
    @State private var search = ""

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 32) {
                TextField("Message", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field.text")
                TextField("Search", text: $search)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect()
                    .accessibilityIdentifier("field.search")
            }
            .frame(width: 320)
        }
    }
}

struct FormScene: View {
    @State private var alerts = true
    @State private var sounds = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Desktop", value: "127.0.0.1")
                    LabeledContent("Status", value: "Connected")
                }
                Section("Phone alerts") {
                    Toggle("Alerts", isOn: $alerts)
                    Toggle("Sounds", isOn: $sounds)
                }
                Section {
                    Button("Remove desktop", role: .destructive) {}
                }
            }
            .accessibilityIdentifier("form")
            .navigationTitle("Settings")
        }
    }
}

struct SwipeScene: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(1...6, id: \.self) { index in
                    Text("Session \(index)")
                        .swipeActions {
                            Button("Kill", role: .destructive) {}
                            Button("Pin") {}.tint(.orange)
                        }
                        .accessibilityIdentifier("row.\(index)")
                }
            }
            .navigationTitle("Sessions")
        }
    }
}

struct ProgressScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 40) {
                ProgressView(value: 0.6).frame(width: 300)
                ProgressView().controlSize(.large)
                Slider(value: .constant(0.3)) { Text("Progress") }
                    .labelsHidden()
                    .sliderThumbVisibility(.hidden)
                    .frame(width: 300)
            }
        }
    }
}
```

- [ ] **Step 4: Register every group**

Replace `tool/glass_lab/native/GlassLab/SceneRegistry.swift` with:

```swift
import SwiftUI

enum SceneRegistry {
    static let all: [String: () -> AnyView] = MaterialScenes.all
        .merging(NavigationScenes.all) { first, _ in first }
        .merging(PresentationScenes.all) { first, _ in first }
        .merging(ControlScenes.all) { first, _ in first }

    static let ids: [String] = all.keys.sorted()
}
```

- [ ] **Step 5: Build**

Run the Task 1 Step 6 build command again.
Expected: `** TEST BUILD SUCCEEDED **`. The synchronized folders pick up the new files, so there is no need to regenerate the project.

- [ ] **Step 6: Browse the catalog**

Install as in Task 1 Step 7, then launch with no scene: `xcrun simctl launch "$UDID" dev.operator.glasslab`. Take `xcrun simctl io "$UDID" screenshot build/glass_lab/smoke/index.png`.
Expected: a "Glass Lab" list of 60 scene ids.

- [ ] **Step 7: Commit**

```bash
git add tool/glass_lab/native
git commit -m "feat(mobile): glass lab native navigation, presentation and control scenes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Scene manifest, backdrop generator and generated-file checks

**Files:**
- Create: `tool/glass_lab/scenes.json`
- Create: `tool/glass_lab/backdrops/generate.py`
- Create: `tool/glass_lab/harness/manifest.py`
- Test: `tool/glass_lab/harness/tests/test_manifest.py`, `tool/glass_lab/harness/tests/test_generated.py`

**Interfaces:**
- Consumes: the native scene ids from Tasks 1–2, parsed from the `"id": { AnyView` lines in `*Scenes.swift`.
- Produces:
  - `manifest.LAB: Path` (the `tool/glass_lab` folder) and `manifest.MANIFEST: Path`.
  - Constants `manifest.BACKDROPS`, `GROUPS`, `APPEARANCES` and `STEP_KINDS`.
  - The frozen dataclass `manifest.Scene` with fields `id, group, title, inventory, app, backdrops, appearances, steps, regions, track, prepare`, and properties `native_only` and `rest`.
  - Functions `manifest.validate(raw) -> list[str]`, `manifest.parse(raw) -> list[Scene]`, `manifest.load(path=MANIFEST) -> list[Scene]` and `manifest.select(scenes, selector) -> list[Scene]`. `select` accepts an id, a group, an id prefix, or `all`, and raises `ValueError` when nothing matches.
  - The `backdrops/generate.py` CLI: `generate.py <out dir>` writes `stripes, photo, white, black, text, scroll` PNGs.

- [ ] **Step 1: Write the failing manifest tests**

Create `tool/glass_lab/harness/tests/test_manifest.py`:

```python
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import manifest

REGISTERED = re.compile(r'^\s*"([a-z0-9.]+)": \{ AnyView', re.M)


def valid_scene(**changes):
    entry = {
        "id": "menu.bar",
        "group": "presentations",
        "title": "Menu",
        "inventory": "4.6",
        "app": "lab",
        "backdrops": ["stripes"],
        "appearances": ["dark"],
        "steps": [{"wait": 0.5}, {"tap": "menu.button"}, {"tap": [100, 700]}],
    }
    entry.update(changes)
    return entry


class ValidationTests(unittest.TestCase):
    def test_accepts_a_valid_scene(self):
        self.assertEqual(manifest.validate([valid_scene()]), [])

    def test_rejects_duplicate_ids(self):
        errors = manifest.validate([valid_scene(), valid_scene()])
        self.assertTrue(any("duplicate" in e for e in errors))

    def test_rejects_unknown_backdrop_and_step(self):
        errors = manifest.validate([valid_scene(backdrops=["sunset"], steps=[{"swipe": [1, 2]}])])
        self.assertTrue(any("backdrop sunset" in e for e in errors))
        self.assertTrue(any("unknown step swipe" in e for e in errors))

    def test_rejects_bad_targets(self):
        errors = manifest.validate([valid_scene(steps=[{"tap": [1]}, {"pressDrag": {"from": "a"}}])])
        self.assertEqual(len(errors), 2)

    def test_only_apple_scenes_target_other_apps(self):
        errors = manifest.validate([valid_scene(app="com.apple.Maps")])
        self.assertTrue(any("only apple scenes" in e for e in errors))

    def test_rest_means_waits_only(self):
        rest = manifest.parse([valid_scene(steps=[{"wait": 1.0}])])[0]
        moving = manifest.parse([valid_scene()])[0]
        self.assertTrue(rest.rest)
        self.assertFalse(moving.rest)

    def test_select_by_id_group_and_prefix(self):
        scenes = manifest.parse([valid_scene(), valid_scene(id="menu.submenu"), valid_scene(id="toggle", group="controls")])
        self.assertEqual([s.id for s in manifest.select(scenes, "menu")], ["menu.bar", "menu.submenu"])
        self.assertEqual([s.id for s in manifest.select(scenes, "controls")], ["toggle"])
        self.assertEqual(len(manifest.select(scenes, "all")), 3)
        with self.assertRaises(ValueError):
            manifest.select(scenes, "nothing")


class RealManifestTests(unittest.TestCase):
    def test_real_manifest_is_valid(self):
        self.assertEqual(manifest.validate(json.loads(manifest.MANIFEST.read_text())), [])

    def test_lab_ids_match_the_native_registry(self):
        swift = "".join(path.read_text() for path in (manifest.LAB / "native" / "GlassLab").glob("*Scenes.swift"))
        registered = set(REGISTERED.findall(swift))
        lab = {scene.id for scene in manifest.load() if not scene.native_only}
        self.assertEqual(lab, registered)


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: an error, `ModuleNotFoundError: No module named 'manifest'`.

- [ ] **Step 2: Implement the manifest module**

Create `tool/glass_lab/harness/manifest.py`:

```python
import json
from dataclasses import dataclass, field
from pathlib import Path

LAB = Path(__file__).resolve().parents[1]
MANIFEST = LAB / "scenes.json"
GROUPS = ("material", "navigation", "presentations", "controls", "apple")
BACKDROPS = ("stripes", "photo", "white", "black", "text", "scroll", "none")
APPEARANCES = ("light", "dark")
STEP_KINDS = ("wait", "tap", "doubleTap", "press", "pressDrag")
FIELDS = ("id", "group", "title", "inventory", "app", "backdrops", "appearances", "steps")


@dataclass(frozen=True)
class Scene:
    id: str
    group: str
    title: str
    inventory: str
    app: str
    backdrops: tuple
    appearances: tuple
    steps: tuple
    regions: dict = field(default_factory=dict)
    track: str | None = None
    prepare: tuple = ()

    @property
    def native_only(self):
        return self.app != "lab"

    @property
    def rest(self):
        return all("wait" in step for step in self.steps)


def _target_errors(where, value):
    if isinstance(value, str) and value:
        return []
    if isinstance(value, list) and len(value) == 2 and all(isinstance(v, (int, float)) for v in value):
        return []
    if isinstance(value, dict) and isinstance(value.get("element"), str):
        extra = set(value) - {"element", "dx", "dy"}
        return [f"{where}: unknown target keys {sorted(extra)}"] if extra else []
    return [f"{where}: bad target {value!r}"]


def _step_errors(where, step):
    if not isinstance(step, dict) or len(step) != 1:
        return [f"{where}: a step is an object with exactly one key"]
    kind, value = next(iter(step.items()))
    if kind not in STEP_KINDS:
        return [f"{where}: unknown step {kind}"]
    if kind == "wait":
        return [] if isinstance(value, (int, float)) and value >= 0 else [f"{where}: wait needs seconds"]
    if kind in ("tap", "doubleTap"):
        return _target_errors(where, value)
    if kind == "press":
        if not isinstance(value, dict) or "at" not in value or not isinstance(value.get("duration"), (int, float)):
            return [f"{where}: press needs at and duration"]
        return _target_errors(where, value["at"])
    if not isinstance(value, dict) or "from" not in value or "to" not in value:
        return [f"{where}: pressDrag needs from and to"]
    extra = set(value) - {"from", "to", "pressDuration", "velocity", "hold"}
    errors = [f"{where}: unknown pressDrag keys {sorted(extra)}"] if extra else []
    return errors + _target_errors(where, value["from"]) + _target_errors(where, value["to"])


def validate(raw):
    errors = []
    if not isinstance(raw, list):
        return ["manifest must be a list"]
    seen = set()
    for index, entry in enumerate(raw):
        where = f"scene {index}"
        if not isinstance(entry, dict):
            errors.append(f"{where}: not an object")
            continue
        where = f"scene {entry.get('id', index)}"
        errors += [f"{where}: missing {name}" for name in FIELDS if name not in entry]
        if entry.get("id") in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(entry.get("id"))
        if entry.get("group") not in GROUPS:
            errors.append(f"{where}: unknown group {entry.get('group')}")
        errors += [f"{where}: unknown backdrop {b}" for b in entry.get("backdrops", []) if b not in BACKDROPS]
        if not entry.get("backdrops"):
            errors.append(f"{where}: needs at least one backdrop")
        errors += [f"{where}: unknown appearance {a}" for a in entry.get("appearances", []) if a not in APPEARANCES]
        for number, step in enumerate(entry.get("steps", [])):
            errors += _step_errors(f"{where} step {number}", step)
        for number, step in enumerate(entry.get("prepare", [])):
            errors += _step_errors(f"{where} prepare {number}", step)
        regions = entry.get("regions", {})
        for name, rect in regions.items():
            if not (isinstance(rect, list) and len(rect) == 4 and all(isinstance(v, (int, float)) for v in rect)):
                errors.append(f"{where}: region {name} must be [x, y, w, h]")
        if entry.get("track") is not None and entry["track"] not in regions:
            errors.append(f"{where}: track names an unknown region")
        if entry.get("app") != "lab" and entry.get("group") != "apple":
            errors.append(f"{where}: only apple scenes may target another app")
    return errors


def parse(raw):
    errors = validate(raw)
    if errors:
        raise ValueError("\n".join(errors))
    return [
        Scene(
            id=entry["id"],
            group=entry["group"],
            title=entry["title"],
            inventory=entry["inventory"],
            app=entry["app"],
            backdrops=tuple(entry["backdrops"]),
            appearances=tuple(entry["appearances"]),
            steps=tuple(entry["steps"]),
            regions=dict(entry.get("regions", {})),
            track=entry.get("track"),
            prepare=tuple(entry.get("prepare", [])),
        )
        for entry in raw
    ]


def load(path=MANIFEST):
    return parse(json.loads(Path(path).read_text()))


def select(scenes, selector):
    if selector == "all":
        return list(scenes)
    chosen = [s for s in scenes if s.id == selector or s.group == selector or s.id.startswith(selector + ".")]
    if not chosen:
        raise ValueError(f"no scene matches {selector}")
    return chosen
```

- [ ] **Step 3: Write the manifest**

Create `tool/glass_lab/scenes.json` with exactly this content, one scene per line:

```json
[
  {
    "id": "material.regular",
    "group": "material",
    "title": "Regular glass at three sizes",
    "inventory": "2.1",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo",
      "white",
      "black",
      "text"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "material.clear",
    "group": "material",
    "title": "Clear glass with and without the dimming layer",
    "inventory": "2.2",
    "app": "lab",
    "backdrops": [
      "photo",
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "material.tinted",
    "group": "material",
    "title": "Tinted glass and a prominent button",
    "inventory": "2.4",
    "app": "lab",
    "backdrops": [
      "stripes",
      "white",
      "black"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "material.interactive",
    "group": "material",
    "title": "Interactive glass press and drag",
    "inventory": "2.5",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "press": {
          "at": "glass",
          "duration": 1.0
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": "glass",
          "to": {
            "element": "glass",
            "dx": 60
          },
          "pressDuration": 0.3,
          "velocity": 120,
          "hold": 0.5
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "material.flip",
    "group": "material",
    "title": "Small and large glass over content that turns white then black",
    "inventory": "2.9",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            700
          ],
          "to": [
            201,
            150
          ],
          "pressDuration": 0.05,
          "velocity": 400,
          "hold": 0.5
        }
      },
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            700
          ],
          "to": [
            201,
            150
          ],
          "pressDuration": 0.05,
          "velocity": 400,
          "hold": 0.5
        }
      },
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            700
          ],
          "to": [
            201,
            150
          ],
          "pressDuration": 0.05,
          "velocity": 400,
          "hold": 0.5
        }
      },
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            700
          ],
          "to": [
            201,
            150
          ],
          "pressDuration": 0.05,
          "velocity": 400,
          "hold": 0.5
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "material.materialize",
    "group": "material",
    "title": "Glass materializes in and out",
    "inventory": "2.13",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "toggle"
      },
      {
        "wait": 1.2
      },
      {
        "tap": "toggle"
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "material.merge",
    "group": "material",
    "title": "Two circles merge and split in a container",
    "inventory": "2.14",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "merge"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "split"
      },
      {
        "wait": 1.5
      }
    ]
  },
  {
    "id": "material.union",
    "group": "material",
    "title": "Glass union of four items in two groups",
    "inventory": "2.15",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "material.morph",
    "group": "material",
    "title": "Button morphs into a badge stack",
    "inventory": "2.16",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "morph"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "morph"
      },
      {
        "wait": 1.5
      }
    ]
  },
  {
    "id": "material.shapes",
    "group": "material",
    "title": "Capsule, fixed radius and concentric shapes",
    "inventory": "2.17",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "material.edge.soft",
    "group": "material",
    "title": "Soft scroll edge effect under an inline bar",
    "inventory": "2.19",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "material.edge.hard",
    "group": "material",
    "title": "Hard scroll edge effect under an inline bar",
    "inventory": "2.19",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "material.edge.automatic",
    "group": "material",
    "title": "Automatic scroll edge effect under an inline bar",
    "inventory": "2.19",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "material.content",
    "group": "material",
    "title": "Content layer materials",
    "inventory": "2.22",
    "app": "lab",
    "backdrops": [
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "tabbar.rest",
    "group": "navigation",
    "title": "Tab bar with a search tab",
    "inventory": "3.1",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo",
      "white",
      "black"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "tabbar.press",
    "group": "navigation",
    "title": "Tab bar press and hold",
    "inventory": "3.2",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "press": {
          "at": "PRs",
          "duration": 1.0
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "tabbar.drag",
    "group": "navigation",
    "title": "Tab selection lens dragged across tabs",
    "inventory": "3.2",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": "Agents",
          "to": "Settings",
          "pressDuration": 0.3,
          "velocity": 300,
          "hold": 0.4
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "tabbar.minimize",
    "group": "navigation",
    "title": "Tab bar minimizes on scroll",
    "inventory": "3.3",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            650
          ],
          "to": [
            201,
            250
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": [
            201,
            250
          ],
          "to": [
            201,
            650
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "tabbar.accessory",
    "group": "navigation",
    "title": "Tab bar bottom accessory, expanded then inline",
    "inventory": "3.4",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            650
          ],
          "to": [
            201,
            250
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": [
            201,
            250
          ],
          "to": [
            201,
            650
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "tabbar.search",
    "group": "navigation",
    "title": "Search tab morphs into a field",
    "inventory": "3.5",
    "app": "lab",
    "backdrops": [
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Search"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "Agents"
      },
      {
        "wait": 1.5
      }
    ]
  },
  {
    "id": "tabbar.prominent",
    "group": "navigation",
    "title": "Prominent tab",
    "inventory": "3.6",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Run"
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "tabbar.badge",
    "group": "navigation",
    "title": "Tab badge",
    "inventory": "3.7",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "navbar.inline",
    "group": "navigation",
    "title": "Inline title, back button and trailing group",
    "inventory": "3.10",
    "app": "lab",
    "backdrops": [
      "stripes",
      "white",
      "black"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "navbar.large",
    "group": "navigation",
    "title": "Large title with subtitle scrolling under the bar",
    "inventory": "3.12",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "navbar.groups",
    "group": "navigation",
    "title": "Toolbar groups, spacer and prominent action",
    "inventory": "3.13",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "press": {
          "at": "nav.bell",
          "duration": 0.8
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "navbar.minimize",
    "group": "navigation",
    "title": "Navigation bar minimizes on scroll",
    "inventory": "3.18",
    "app": "lab",
    "backdrops": [
      "scroll"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            650
          ],
          "to": [
            201,
            250
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": [
            201,
            250
          ],
          "to": [
            201,
            650
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "navbar.push",
    "group": "navigation",
    "title": "Toolbar items across push and pop",
    "inventory": "3.16",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "row.1"
      },
      {
        "wait": 1.2
      },
      {
        "tap": "BackButton"
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "navbar.badge",
    "group": "navigation",
    "title": "Badge on a bar button",
    "inventory": "3.17",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "toolbar.bottom",
    "group": "navigation",
    "title": "Bottom toolbar with groups",
    "inventory": "3.15",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "search.bottom",
    "group": "navigation",
    "title": "Bottom search field above the keyboard",
    "inventory": "3.20",
    "app": "lab",
    "backdrops": [
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Search"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "Close"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "search.minimized",
    "group": "navigation",
    "title": "Minimized search button",
    "inventory": "3.20",
    "app": "lab",
    "backdrops": [
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Search"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "Close"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "search.scopes",
    "group": "navigation",
    "title": "Search scopes",
    "inventory": "3.21",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Search"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "sheet.detents",
    "group": "presentations",
    "title": "Sheet moved between its detents",
    "inventory": "4.1",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": "sheet.top",
          "to": [
            201,
            80
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 0.3
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": "sheet.top",
          "to": [
            201,
            850
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 0.3
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "sheet.scroll",
    "group": "presentations",
    "title": "Large sheet with scrolling content",
    "inventory": "4.1",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "sheet.zoom",
    "group": "presentations",
    "title": "Sheet zooms out of a toolbar button",
    "inventory": "4.3",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "zoom.source"
      },
      {
        "wait": 1.5
      },
      {
        "pressDrag": {
          "from": "sheet.top",
          "to": [
            201,
            860
          ],
          "pressDuration": 0.05,
          "velocity": 900,
          "hold": 0.0
        }
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "sheet.crossfade",
    "group": "presentations",
    "title": "Cross-fade sheet presentation",
    "inventory": "4.4",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "sheet.present"
      },
      {
        "wait": 1.2
      },
      {
        "tap": "sheet.close"
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "popover.bar",
    "group": "presentations",
    "title": "Popover from a bar button",
    "inventory": "4.5",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "popover.source"
      },
      {
        "wait": 1.2
      },
      {
        "tap": [
          201,
          700
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "menu.bar",
    "group": "presentations",
    "title": "Menu from a toolbar button",
    "inventory": "4.6",
    "app": "lab",
    "backdrops": [
      "stripes",
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "menu.button"
      },
      {
        "wait": 1.2
      },
      {
        "tap": [
          100,
          700
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "menu.submenu",
    "group": "presentations",
    "title": "Menu with a submenu",
    "inventory": "4.6",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "menu.button"
      },
      {
        "wait": 1.0
      },
      {
        "tap": "Sort By"
      },
      {
        "wait": 1.0
      },
      {
        "tap": [
          100,
          700
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "menu.pressdrag",
    "group": "presentations",
    "title": "Press the menu button and drag onto an item",
    "inventory": "4.6",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": "menu.button",
          "to": [
            300,
            230
          ],
          "pressDuration": 0.4,
          "velocity": 400,
          "hold": 0.3
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "contextmenu.card",
    "group": "presentations",
    "title": "Context menu on a card",
    "inventory": "4.7",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "press": {
          "at": "card",
          "duration": 1.0
        }
      },
      {
        "wait": 1.0
      },
      {
        "tap": [
          201,
          80
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "alert.two",
    "group": "presentations",
    "title": "Alert with two actions",
    "inventory": "4.9",
    "app": "lab",
    "backdrops": [
      "stripes",
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "alert.show"
      },
      {
        "wait": 1.0
      },
      {
        "tap": "Cancel"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "alert.three",
    "group": "presentations",
    "title": "Alert with three actions",
    "inventory": "4.9",
    "app": "lab",
    "backdrops": [
      "stripes",
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "alert.show"
      },
      {
        "wait": 1.0
      },
      {
        "tap": "Cancel"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "confirm.source",
    "group": "presentations",
    "title": "Confirmation dialog anchored to its button",
    "inventory": "4.10",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "confirm.show"
      },
      {
        "wait": 1.0
      },
      {
        "tap": [
          201,
          120
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "push.zoom",
    "group": "presentations",
    "title": "Push with a zoom transition from a card",
    "inventory": "4.11",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "card.0"
      },
      {
        "wait": 1.2
      },
      {
        "pressDrag": {
          "from": [
            1,
            437
          ],
          "to": [
            320,
            437
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.0
        }
      },
      {
        "wait": 1.2
      }
    ]
  },
  {
    "id": "button.styles",
    "group": "controls",
    "title": "Glass button styles, sizes and shapes",
    "inventory": "5.1",
    "app": "lab",
    "backdrops": [
      "stripes",
      "white",
      "black"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "button.press",
    "group": "controls",
    "title": "Glass and prominent button press",
    "inventory": "5.1",
    "app": "lab",
    "backdrops": [
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "press": {
          "at": "btn.glass",
          "duration": 0.8
        }
      },
      {
        "wait": 0.8
      },
      {
        "press": {
          "at": "btn.prominent",
          "duration": 0.8
        }
      },
      {
        "wait": 0.8
      }
    ]
  },
  {
    "id": "toggle",
    "group": "controls",
    "title": "Switch tapped, then its knob dragged",
    "inventory": "5.5",
    "app": "lab",
    "backdrops": [
      "white",
      "black",
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "toggle.off"
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": {
            "element": "toggle.on",
            "dx": 12
          },
          "to": {
            "element": "toggle.on",
            "dx": -18
          },
          "pressDuration": 0.2,
          "velocity": 100,
          "hold": 0.5
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "slider",
    "group": "controls",
    "title": "Slider flicked, then dragged slowly",
    "inventory": "5.6",
    "app": "lab",
    "backdrops": [
      "white",
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": "slider.default",
          "to": {
            "element": "slider.default",
            "dx": 140
          },
          "pressDuration": 0.1,
          "velocity": 1500,
          "hold": 0.0
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": {
            "element": "slider.default",
            "dx": 140
          },
          "to": {
            "element": "slider.default",
            "dx": 60
          },
          "pressDuration": 0.1,
          "velocity": 100,
          "hold": 0.5
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "segmented",
    "group": "controls",
    "title": "Segmented control tapped, then dragged",
    "inventory": "5.7",
    "app": "lab",
    "backdrops": [
      "white",
      "stripes"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": {
          "element": "segmented",
          "dx": 107
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": {
            "element": "segmented",
            "dx": -107
          },
          "to": "segmented",
          "pressDuration": 0.2,
          "velocity": 200,
          "hold": 0.4
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "stepper",
    "group": "controls",
    "title": "Stepper",
    "inventory": "5.8",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "Increment"
      },
      {
        "wait": 0.6
      },
      {
        "tap": "Increment"
      },
      {
        "wait": 0.6
      },
      {
        "tap": "Decrement"
      },
      {
        "wait": 0.8
      }
    ]
  },
  {
    "id": "picker.menu",
    "group": "controls",
    "title": "Menu picker",
    "inventory": "5.9",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "picker"
      },
      {
        "wait": 1.0
      },
      {
        "tap": "Sonnet"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "datepicker.compact",
    "group": "controls",
    "title": "Compact date picker",
    "inventory": "5.9",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "datepicker"
      },
      {
        "wait": 1.2
      },
      {
        "tap": [
          201,
          80
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "datepicker.inline",
    "group": "controls",
    "title": "Inline date picker",
    "inventory": "5.9",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "datepicker.wheel",
    "group": "controls",
    "title": "Wheel date picker",
    "inventory": "5.9",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "pagecontrol",
    "group": "controls",
    "title": "Page control with a platter",
    "inventory": "5.10",
    "app": "lab",
    "backdrops": [
      "photo"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "textfield",
    "group": "controls",
    "title": "Text and search fields",
    "inventory": "5.11",
    "app": "lab",
    "backdrops": [
      "white",
      "black"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "tap": "field.text"
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "list.form",
    "group": "controls",
    "title": "Inset grouped form",
    "inventory": "5.12",
    "app": "lab",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            400
          ],
          "pressDuration": 0.05,
          "velocity": 400,
          "hold": 0.5
        }
      },
      {
        "wait": 0.5
      }
    ]
  },
  {
    "id": "swipe.row",
    "group": "controls",
    "title": "Swipe actions on a row",
    "inventory": "5.14",
    "app": "lab",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": "row.2",
          "to": {
            "element": "row.2",
            "dx": -180
          },
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 0.4
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "progress",
    "group": "controls",
    "title": "Progress views and a thumbless slider",
    "inventory": "5.13",
    "app": "lab",
    "backdrops": [
      "white"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "apple.maps.sheet",
    "group": "apple",
    "title": "Maps sheet dragged to full, then to its smallest detent",
    "inventory": "4.1",
    "app": "com.apple.Maps",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": [
            201,
            497
          ],
          "to": [
            201,
            150
          ],
          "pressDuration": 0.05,
          "velocity": 500,
          "hold": 0.3
        }
      },
      {
        "wait": 1.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            80
          ],
          "to": [
            201,
            800
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.3
        }
      },
      {
        "wait": 1.5
      }
    ],
    "prepare": [
      {
        "wait": 2.0
      },
      {
        "tap": [
          201,
          810
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "apple.photos.search",
    "group": "apple",
    "title": "Photos search tab",
    "inventory": "3.5",
    "app": "com.apple.mobileslideshow",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 1.0
      },
      {
        "tap": "Search"
      },
      {
        "wait": 1.5
      },
      {
        "tap": "Library"
      },
      {
        "wait": 1.5
      }
    ],
    "prepare": [
      {
        "wait": 2.0
      },
      {
        "tap": [
          201,
          809
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "apple.photos.scroll",
    "group": "apple",
    "title": "Photos grid scrolled under the tab bar",
    "inventory": "3.3",
    "app": "com.apple.mobileslideshow",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            650
          ],
          "to": [
            201,
            250
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      },
      {
        "pressDrag": {
          "from": [
            201,
            250
          ],
          "to": [
            201,
            650
          ],
          "pressDuration": 0.05,
          "velocity": 800,
          "hold": 0.2
        }
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "apple.reminders.menu",
    "group": "apple",
    "title": "Reminders list menu",
    "inventory": "4.6",
    "app": "com.apple.reminders",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 1.0
      },
      {
        "tap": [
          363,
          84
        ]
      },
      {
        "wait": 1.2
      },
      {
        "tap": [
          100,
          700
        ]
      },
      {
        "wait": 1.0
      }
    ],
    "prepare": [
      {
        "wait": 2.0
      },
      {
        "tap": [
          201,
          809
        ]
      },
      {
        "wait": 1.0
      }
    ]
  },
  {
    "id": "apple.calendar.toolbar",
    "group": "apple",
    "title": "Calendar grouped toolbar and bottom bar",
    "inventory": "3.13",
    "app": "com.apple.mobilecal",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": []
  },
  {
    "id": "apple.settings.large",
    "group": "apple",
    "title": "Settings large title under the bar",
    "inventory": "3.12",
    "app": "com.apple.Preferences",
    "backdrops": [
      "none"
    ],
    "appearances": [
      "light",
      "dark"
    ],
    "steps": [
      {
        "wait": 0.5
      },
      {
        "pressDrag": {
          "from": [
            201,
            600
          ],
          "to": [
            201,
            300
          ],
          "pressDuration": 0.05,
          "velocity": 600,
          "hold": 1.0
        }
      },
      {
        "wait": 0.5
      }
    ]
  }
]
```

- [ ] **Step 4: Run the manifest tests**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_manifest.py"`
Expected: `OK` for 9 tests. `test_lab_ids_match_the_native_registry` proves the manifest and the native catalog list the same 60 ids.

- [ ] **Step 5: Write the backdrop generator**

Create `tool/glass_lab/backdrops/generate.py`:

```python
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WIDTH = 1206
HEIGHT = 2622
STRIPES = [0xE5484D, 0xE89527, 0xF0B45C, 0x1ACB64, 0x47BFFF, 0x8E6CF0]
WORDS = (
    "agent session branch terminal glass render commit merge review desktop pairing tunnel "
    "prompt model harness spawn build test layer shader spring detent sheet toolbar capsule "
    "lens refraction blur tint shadow scroll edge motion frame pixel native measure"
).split()
FONT = Path(__file__).resolve().parents[3] / "assets/fonts/anthropic_sans/AnthropicSansText-400.otf"


def rgb(value):
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def stripes():
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    band = WIDTH / len(STRIPES)
    for index, color in enumerate(STRIPES):
        draw.rectangle([round(index * band), 0, round((index + 1) * band) - 1, HEIGHT], fill=rgb(color))
    return image


def photo(height=HEIGHT, seed=7):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:height, 0:WIDTH].astype(np.float32)
    top = np.array([40, 70, 140], np.float32)
    bottom = np.array([230, 150, 90], np.float32)
    t = (y / height)[..., None]
    canvas = top * (1 - t) + bottom * t
    for _ in range(14):
        cx, cy = rng.uniform(0, WIDTH), rng.uniform(0, height)
        radius = rng.uniform(140, 520)
        color = rng.uniform(0, 255, 3).astype(np.float32)
        weight = np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2 * radius**2)))[..., None] * rng.uniform(0.5, 0.9)
        canvas = canvas * (1 - weight) + color * weight
    canvas += rng.normal(0, 6, canvas.shape).astype(np.float32)
    image = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(image)
    for index in range(28):
        cx, cy = rng.uniform(0, WIDTH), rng.uniform(0, height)
        w, h = rng.uniform(40, 260), rng.uniform(40, 260)
        color = tuple(int(c) for c in rng.uniform(0, 255, 3))
        box = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
        if index % 2:
            draw.ellipse(box, fill=color)
        else:
            draw.rectangle(box, fill=color)
    return image


def flat(color, height=HEIGHT):
    return Image.new("RGB", (WIDTH, height), color)


def text(height=HEIGHT, seed=11):
    rng = np.random.default_rng(seed)
    image = Image.new("RGB", (WIDTH, height), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), 51)
    margin, line, y = 48, 66, 150
    while y < height - line:
        words, x = [], margin
        while True:
            word = WORDS[rng.integers(len(WORDS))]
            width = draw.textlength(word + " ", font=font)
            if x + width > WIDTH - margin:
                break
            words.append(word)
            x += width
        draw.text((margin, y), " ".join(words), fill=(0, 0, 0), font=font)
        y += line
        if rng.random() < 0.18:
            y += line
    return image


def scroll():
    image = Image.new("RGB", (WIDTH, HEIGHT * 3))
    image.paste(text(), (0, 0))
    image.paste(photo(), (0, HEIGHT))
    image.paste(flat((255, 255, 255), HEIGHT // 2), (0, HEIGHT * 2))
    image.paste(flat((0, 0, 0), HEIGHT - HEIGHT // 2), (0, HEIGHT * 2 + HEIGHT // 2))
    return image


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    backdrops = {
        "stripes": stripes(),
        "photo": photo(),
        "white": flat((255, 255, 255)),
        "black": flat((0, 0, 0)),
        "text": text(),
        "scroll": scroll(),
    }
    for name, image in backdrops.items():
        image.save(out / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent)
```

- [ ] **Step 6: Write the generated-file tests**

Create `tool/glass_lab/harness/tests/test_generated.py`:

```python
import filecmp
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LAB = Path(__file__).resolve().parents[2]


class GeneratedFilesTests(unittest.TestCase):
    def test_committed_project_matches_the_generator(self):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp) / "GlassLab.xcodeproj"
            subprocess.run([sys.executable, str(LAB / "native" / "gen_project.py"), str(out)], check=True)
            committed = LAB / "native" / "GlassLab.xcodeproj"
            for relative in ("project.pbxproj", "xcshareddata/xcschemes/GlassLab.xcscheme"):
                self.assertTrue(filecmp.cmp(out / relative, committed / relative, shallow=False), relative)

    def test_backdrops_are_deterministic(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            for out in (first, second):
                subprocess.run([sys.executable, str(LAB / "backdrops" / "generate.py"), out], check=True)
            names = sorted(p.name for p in Path(first).glob("*.png"))
            self.assertEqual(names, ["black.png", "photo.png", "scroll.png", "stripes.png", "text.png", "white.png"])
            for name in names:
                self.assertTrue(filecmp.cmp(Path(first) / name, Path(second) / name, shallow=False), name)


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_generated.py"`
Expected: `OK` for 2 tests, in about 7 s. It proves the committed Xcode project equals the generator's output, and that two backdrop runs are byte-identical.

- [ ] **Step 7: Commit**

```bash
git add tool/glass_lab/scenes.json tool/glass_lab/backdrops tool/glass_lab/harness
git commit -m "feat(mobile): glass lab scene manifest, backdrop generator and checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Analysis: metrics, springs, events, comparison and report

**Files:**
- Create: `tool/glass_lab/harness/metrics.py`, `springfit.py`, `align.py`, `analyze.py`, `report.py`
- Test: `tool/glass_lab/harness/tests/test_metrics.py`

**Interfaces:**
- Consumes: `manifest.Scene` (Task 3).
- Produces:
  - `metrics`:
    - constants `SCALE = 3`, `SCREEN = (402, 874)` and `THRESHOLDS` (keys `mad luminance rim_rms bbox_pt centre_pt time_ms overshoot_pct response_pct damping`);
    - `load(path) -> float32 HxWx3`, `luma`, `crop(image, rect_pt)` and `mad`;
    - `glass_boxes(frame, bare, threshold=6.0, min_area=40, scale=SCALE) -> [(x, y, w, h) pt]`, largest first;
    - `union(boxes, pad, bounds)`, `rim_profile`, `box_delta`, `centre_delta`;
    - `static_compare(native, flutter, native_bare, flutter_bare, region) -> dict` with keys `mad luminance native_box flutter_box bbox_pt centre_pt rim_rms rim_native rim_flutter pass`.
  - `springfit`: `step_response(t, response, damping)`, `normalize`, `fit(times, values) -> {response, damping, rms} | None`, `features(times, values) -> {peak_ms, overshoot_pct, settle_ms} | None`.
  - `align`:
    - constants `GRID_HZ = 120`, `KEYS` and `SKIP_TOP_POINTS = 72`;
    - `Frames(paths, times)`;
    - `differences`, `events(diffs, times)`, `stalls(diffs, times)`, `row`, `event_series`, `significant`, `resample` and `extent`.
  - `analyze`: `analyze(scene, case_dir, noise=None) -> dict` with `kind` one of `compared`, `missing` or `reference`; `motion_measures(motion) -> {name: (value, limit key)}`; `motion_checks(motion, noise)`.
  - `report`: `build(run_dir, scenes) -> (html path, counts, results)` and `markdown(run_dir, counts, results, scenes) -> str`.

- [ ] **Step 1: Write the failing tests**

Create `tool/glass_lab/harness/tests/test_metrics.py`:

```python
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import align
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


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_metrics.py"`
Expected: an error, `ModuleNotFoundError: No module named 'align'`.

- [ ] **Step 2: Implement metrics**

Create `tool/glass_lab/harness/metrics.py`:

```python
from collections import deque

import numpy as np
from PIL import Image

SCALE = 3
SCREEN = (402, 874)
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


def box_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[0] + a[2] - b[0] - b[2]), abs(a[1] + a[3] - b[1] - b[3])))


def centre_delta(a, b):
    if a is None or b is None:
        return float("inf")
    return float(max(abs(a[0] + a[2] / 2 - b[0] - b[2] / 2), abs(a[1] + a[3] / 2 - b[1] - b[3] / 2)))


def static_compare(native, flutter, native_bare, flutter_bare, region):
    native_region, flutter_region = crop(native, region), crop(flutter, region)
    native_boxes = glass_boxes(native_region, crop(native_bare, region))
    flutter_boxes = glass_boxes(flutter_region, crop(flutter_bare, region))
    offset = lambda boxes: [(b[0] + region[0], b[1] + region[1], b[2], b[3]) for b in boxes]
    native_main = offset(native_boxes)[0] if native_boxes else None
    flutter_main = offset(flutter_boxes)[0] if flutter_boxes else None
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
    result["pass"] = {key: result[key] <= THRESHOLDS[key] for key in ("mad", "luminance", "rim_rms", "bbox_pt", "centre_pt")}
    return result
```

- [ ] **Step 3: Implement spring fitting**

Create `tool/glass_lab/harness/springfit.py`:

```python
import numpy as np

RESPONSES = np.linspace(0.05, 1.5, 146)
DAMPINGS = np.linspace(0.1, 1.2, 111)


def step_response(t, response, damping):
    t = np.asarray(t, dtype=np.float64)
    omega = 2 * np.pi / np.asarray(response, dtype=np.float64)
    zeta = np.asarray(damping, dtype=np.float64)
    under = zeta < 1
    wd = omega * np.sqrt(np.abs(1 - zeta**2))
    safe_wd = np.where(wd == 0, 1e-9, wd)
    decay = np.exp(-zeta * omega * t)
    under_curve = 1 - decay * (np.cos(safe_wd * t) + zeta * omega / safe_wd * np.sin(safe_wd * t))
    critical = 1 - np.exp(-omega * t) * (1 + omega * t)
    r1 = -omega * (zeta - np.sqrt(np.abs(zeta**2 - 1)))
    r2 = -omega * (zeta + np.sqrt(np.abs(zeta**2 - 1)))
    denominator = np.where(r1 == r2, 1e-9, r2 - r1)
    over_curve = 1 - (r2 * np.exp(r1 * t) - r1 * np.exp(r2 * t)) / denominator
    near_critical = np.abs(zeta - 1) < 1e-6
    return np.where(under, under_curve, np.where(near_critical, critical, over_curve))


def normalize(values):
    values = np.asarray(values, dtype=np.float64)
    travel = values[-1] - values[0]
    if abs(travel) < 1e-9:
        return None
    return (values - values[0]) / travel


def fit(times, values):
    normalized = normalize(values)
    if normalized is None:
        return None
    t = np.asarray(times, dtype=np.float64)[None, None, :]
    curves = step_response(t, RESPONSES[:, None, None], DAMPINGS[None, :, None])
    errors = np.sqrt(np.mean((curves - normalized[None, None, :]) ** 2, axis=2))
    i, j = np.unravel_index(np.argmin(errors), errors.shape)
    return {"response": float(RESPONSES[i]), "damping": float(DAMPINGS[j]), "rms": float(errors[i, j])}


def features(times, values):
    normalized = normalize(values)
    if normalized is None:
        return None
    times = np.asarray(times, dtype=np.float64)
    peak = int(np.argmax(normalized))
    outside = np.nonzero(np.abs(normalized - 1) > 0.02)[0]
    settle = times[outside[-1] + 1] if len(outside) and outside[-1] + 1 < len(times) else times[0]
    return {
        "peak_ms": float(times[peak] * 1000),
        "overshoot_pct": float(max(0.0, normalized[peak] - 1) * 100),
        "settle_ms": float(settle * 1000),
    }
```

- [ ] **Step 4: Implement events and series**

Create `tool/glass_lab/harness/align.py`:

```python
import numpy as np

from metrics import glass_boxes, load, luma, mad

GRID_HZ = 120
MOTION_THRESHOLD = 0.5
QUIET_SECONDS = 0.15
HOLD_SECONDS = 0.3
STALL_MS = 25.0
EXTENT_TILE = 8
EXTENT_THRESHOLD = 10.0
SKIP_TOP_POINTS = 72
VIDEO_BOX_THRESHOLD = 12.0
KEYS = ("width", "height", "cx", "cy", "luma")
MIN_EVENT_CHANGE = {"width": 4.0, "height": 4.0, "cx": 4.0, "cy": 4.0, "luma": 1.5}


class Frames:
    def __init__(self, paths, times):
        self.paths = list(paths)
        self.times = list(times)

    def __len__(self):
        return len(self.paths)

    def __getitem__(self, index):
        return load(self.paths[index])

    def __iter__(self):
        return (load(path) for path in self.paths)


def differences(frames):
    values, previous = [0.0], None
    for frame in frames:
        if previous is not None:
            values.append(mad(frame, previous))
        previous = frame
    return values


def events(diffs, times, threshold=MOTION_THRESHOLD, quiet=QUIET_SECONDS):
    found, first, last = [], None, None
    for index, value in enumerate(diffs):
        if value <= threshold:
            continue
        if first is not None and times[index] - times[last] > quiet:
            found.append((first, last))
            first = None
        if first is None:
            first = max(0, index - 1)
        last = index
    if first is not None:
        found.append((first, last))
    return found


def stalls(diffs, times, threshold=MOTION_THRESHOLD, quiet=QUIET_SECONDS):
    gaps = []
    for first, last in events(diffs, times, threshold, quiet):
        for index in range(first + 2, last + 1):
            gap = (times[index] - times[index - 1]) * 1000
            if gap > STALL_MS:
                gaps.append(gap)
    return gaps


def row(frame, bare):
    boxes = glass_boxes(frame, bare, threshold=VIDEO_BOX_THRESHOLD, min_area=20, scale=1)
    box = boxes[0] if boxes else (0, 0, 0, 0)
    return {
        "width": float(box[2]),
        "height": float(box[3]),
        "cx": float(box[0] + box[2] / 2),
        "cy": float(box[1] + box[3] / 2),
        "luma": float(luma(frame).mean()),
    }


def event_series(frames, first, last, bare):
    stop = frames.times[last] + HOLD_SECONDS
    indices = [i for i in range(first, len(frames)) if i <= last or frames.times[i] <= stop]
    origin = max(frames.times[first], frames.times[first + 1] - 1.0 / GRID_HZ) if first + 1 < len(frames) else frames.times[first]
    times = [max(0.0, frames.times[i] - origin) for i in indices]
    rows = [row(frames[i], bare) for i in indices]
    times.append(stop - origin)
    rows.append(dict(rows[-1]))
    return resample(times, rows)


def significant(series):
    return any(np.ptp(series[key]) >= MIN_EVENT_CHANGE[key] for key in KEYS)


def resample(times, rows, hz=GRID_HZ):
    grid = np.arange(0.0, times[-1] + 1e-9, 1.0 / hz)
    return {key: np.interp(grid, times, [r[key] for r in rows]).tolist() for key in KEYS}


def extent(frames, threshold=EXTENT_THRESHOLD, tile=EXTENT_TILE):
    first, peak = None, None
    for frame in frames:
        if first is None:
            first = frame
            height, width = frame.shape[0] // tile * tile, frame.shape[1] // tile * tile
            peak = np.zeros((height // tile, width // tile), dtype=np.float32)
            continue
        difference = np.abs(frame[:height, :width] - first[:height, :width]).mean(axis=2)
        np.maximum(peak, difference.reshape(height // tile, tile, width // tile, tile).mean(axis=(1, 3)), out=peak)
    if peak is None:
        return []
    peak[: SKIP_TOP_POINTS // tile] = 0
    ys, xs = np.nonzero(peak > threshold)
    if len(xs) == 0:
        return []
    return [(int(xs.min() * tile), int(ys.min() * tile), int((xs.max() - xs.min() + 1) * tile), int((ys.max() - ys.min() + 1) * tile))]
```

- [ ] **Step 5: Run the tests**

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_metrics.py"`
Expected: `OK` for 18 tests.

- [ ] **Step 6: Implement case analysis**

Create `tool/glass_lab/harness/analyze.py`:

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


def compare_series(key, a, b):
    times = np.arange(len(a)) / align.GRID_HZ
    entry = {"rms": float(np.sqrt(np.mean((a - b) ** 2))), "native": a.tolist(), "flutter": b.tolist()}
    if abs(a[-1] - a[0]) < MIN_TRAVEL[key] or abs(b[-1] - b[0]) < MIN_TRAVEL[key]:
        return entry
    fa, fb = springfit.features(times, a), springfit.features(times, b)
    if fa and fb:
        entry["peak_ms"] = abs(fa["peak_ms"] - fb["peak_ms"])
        entry["settle_ms"] = abs(fa["settle_ms"] - fb["settle_ms"])
        entry["overshoot_pct"] = abs(fa["overshoot_pct"] - fb["overshoot_pct"])
    sa, sb = springfit.fit(times, a), springfit.fit(times, b)
    if sa and sb and sa["rms"] < 0.15 and sb["rms"] < 0.15:
        entry["native_spring"], entry["flutter_spring"] = sa, sb
        entry["response_pct"] = abs(sa["response"] - sb["response"]) / sa["response"] * 100
        entry["damping"] = abs(sa["damping"] - sb["damping"])
    return entry


def best_lag(a_series, b_series):
    limit = int(MAX_LAG_MS / 1000 * align.GRID_HZ)
    for key in align.KEYS:
        a = np.array(a_series[key])
        if np.ptp(a) < MIN_TRAVEL[key]:
            continue
        b = np.array(b_series[key])
        best, chosen = float("inf"), 0
        for lag in range(-limit, limit + 1):
            x, y = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
            count = min(len(x), len(y))
            if count < 3:
                continue
            error = float(np.mean((x[:count] - y[:count]) ** 2))
            if error < best:
                best, chosen = error, lag
        return chosen
    return 0


def compare_motion(native, flutter):
    result = {"event_count": [len(native["events"]), len(flutter["events"])], "events": []}
    for native_event, flutter_event in zip(native["events"], flutter["events"]):
        a_series, b_series = native_event["series"], flutter_event["series"]
        lag = best_lag(a_series, b_series)
        event = {"lag_ms": lag * 1000 / align.GRID_HZ}
        for key in align.KEYS:
            a, b = np.array(a_series[key]), np.array(b_series[key])
            a, b = (a[lag:], b) if lag >= 0 else (a, b[-lag:])
            count = min(len(a), len(b))
            if count < 3:
                continue
            event[key] = compare_series(key, a[:count], b[:count])
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


def motion_checks(result, noise=None):
    noise = noise or {}
    checks = {"events.count": result["event_count"][0] == result["event_count"][1]}
    for name, (value, limit) in motion_measures(result).items():
        allowed = max(metrics.THRESHOLDS[limit], NOISE_FACTOR * noise.get(name, 0.0))
        checks[name] = value <= allowed
    return checks


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
        )
    checks = {f"{name}.{key}": value for name, stat in result["static"].items() for key, value in stat["pass"].items()}
    if not scene.rest:
        native, flutter = motion(native_dir, region), motion(flutter_dir, region)
        result["motion"] = compare_motion(native, flutter)
        result["native_stalls"] = native["stalls"]
        result["flutter_stalls"] = flutter["stalls"]
        checks.update({f"motion.{k}": v for k, v in motion_checks(result["motion"], noise).items()})
    result["checks"] = checks
    result["pass"] = bool(checks) and all(checks.values())
    return result
```

- [ ] **Step 7: Implement the report**

Create `tool/glass_lab/harness/report.py`:

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


def worst(result):
    checks = result.get("checks") or {}
    failing = [k for k, ok in checks.items() if not ok]
    return ", ".join(failing[:3]) if failing else "—"


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


def markdown(run_dir, counts, results, scenes):
    by_scene = {s.id: s for s in scenes}
    lines = [
        "# Glass lab baseline",
        "",
        f"Run: `{Path(run_dir).name}`. Native iOS 27 (iPhone 17 Pro simulator) against Operator's Flutter glass.",
        "",
        "| Status | Count |",
        "|---|---|",
    ]
    lines += [f"| {key} | {value} |" for key, value in counts.items()]
    lines += ["", "| Scene | Case | Title | Status | Failing measures |", "|---|---|---|---|---|"]
    for _, result in results:
        kind = result.get("kind")
        status = ("pass" if result.get("pass") else "fail") if kind == "compared" else kind
        scene = by_scene.get(result["scene"])
        title = scene.title if scene else ""
        lines.append(f"| {result['scene']} | {result['case']} | {title} | {status} | {worst(result)} |")
    return "\n".join(lines) + "\n"
```

- [ ] **Step 8: Import check and full harness tests**

Run: `cd tool/glass_lab/harness && python3 -c "import analyze, report" && cd ../../.. && python3 -m unittest discover tool/glass_lab/harness/tests`
Expected: no import error, and `OK` for all tests so far.

- [ ] **Step 9: Commit**

```bash
git add tool/glass_lab/harness
git commit -m "feat(mobile): glass lab metrics, spring fitting, motion events and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Simulator control, recording and the lab CLI

**Files:**
- Create: `tool/glass_lab/harness/sim.py`, `build.py`, `record.py`, `lab.py`, `tool/glass_lab/README.md`
- Test: `tool/glass_lab/harness/tests/test_record.py`
- Modify: `tool/glass_lab/scenes.json`, only if Step 7 finds labels that differ on iOS 27

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - The `lab.py` CLI: `build [native|flutter|both]`, `prepare`, `run`, `report`, `summary`, `repeat`, `geometry`, `baseline`.
  - `record.capture(udid, scene, app, backdrop, out_dir)`, which writes `bare/ready.png`, `ready.png`, `settled.png`, `timing.json` (with `video_start`) and `video.mp4` into `out_dir`.
  - `record.write_launch_file(folder, scene, backdrop, bare)` and `record.clear_launch_file(folder)`.
  - `build.FLUTTER_BUNDLE = "dev.operator.operatorMobile"` and `build.NATIVE_BUNDLE = "dev.operator.glasslab"`.
  - Run layout: `build/glass_lab/runs/<YYYYMMDD-HHMMSS>/<scene>/<appearance>-<backdrop>[-<a11y>]/<native|flutter>/`.

- [ ] **Step 1: Write the failing launch-file test**

Create `tool/glass_lab/harness/tests/test_record.py`:

```python
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

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


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_record.py"`
Expected: an error, `ModuleNotFoundError: No module named 'record'` (or `build`).

- [ ] **Step 2: Implement simulator control**

Create `tool/glass_lab/harness/sim.py`:

```python
import json
import shutil
import subprocess
from pathlib import Path

DEVICE_NAME = "iPhone 17 Pro (iOS 27)"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
A11Y_MODES = ("none", "reduce-transparency", "increase-contrast", "reduce-motion")


def run(args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def simctl(*args):
    return run(["xcrun", "simctl", *args]).stdout


def device():
    devices = json.loads(simctl("list", "devices", "-j"))["devices"].get(RUNTIME, [])
    udid = next((d["udid"] for d in devices if d["name"] == DEVICE_NAME), None)
    if udid is None:
        udid = simctl("create", DEVICE_NAME, DEVICE_TYPE, RUNTIME).strip()
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    simctl("bootstatus", udid, "-b")
    return udid


def status_bar(udid):
    simctl("status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4")


def appearance(udid, value):
    simctl("ui", udid, "appearance", value)


def accessibility(udid, mode):
    if mode not in A11Y_MODES:
        raise ValueError(f"unknown accessibility mode {mode}")
    simctl("spawn", udid, "defaults", "write", "com.apple.Accessibility", "ReduceMotionEnabled", "-bool", "true" if mode == "reduce-motion" else "false")
    simctl("spawn", udid, "defaults", "write", "com.apple.Accessibility", "EnhancedBackgroundContrastEnabled", "-bool", "true" if mode == "reduce-transparency" else "false")
    simctl("ui", udid, "increase_contrast", "enabled" if mode == "increase-contrast" else "disabled")


def install(udid, app_path):
    simctl("install", udid, str(app_path))


def container(udid, bundle):
    return Path(simctl("get_app_container", udid, bundle, "data").strip())


def installed(udid, bundle):
    return subprocess.run(["xcrun", "simctl", "get_app_container", udid, bundle], capture_output=True).returncode == 0


def install_backdrops(udid, bundle, source):
    if not installed(udid, bundle):
        print(f"skip {bundle}: not installed, run lab.py build first")
        return False
    target = container(udid, bundle) / "Documents" / "glass_lab"
    target.mkdir(parents=True, exist_ok=True)
    for image in Path(source).glob("*.png"):
        shutil.copy2(image, target / image.name)
    return True


def revoke_location(udid, bundle):
    subprocess.run(["xcrun", "simctl", "privacy", udid, "revoke", "location", bundle], capture_output=True)
```

- [ ] **Step 3: Implement builds**

Create `tool/glass_lab/harness/build.py`:

```python
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
NATIVE_BUNDLE = "dev.operator.glasslab"
FLUTTER_BUNDLE = "dev.operator.operatorMobile"


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


def flutter(udid):
    stream(["flutter", "build", "ios", "--simulator", "--debug", "--config-only"], cwd=MOBILE)
    stream([
        "xcodebuild", "build",
        "-workspace", str(MOBILE / "ios/Runner.xcworkspace"),
        "-scheme", "Runner",
        "-configuration", "Debug",
        "-sdk", "iphonesimulator",
        "-destination", destination(udid),
        "-derivedDataPath", str(FLUTTER_DATA),
        "IPHONEOS_DEPLOYMENT_TARGET=15.0",
    ])
    sim.install(udid, FLUTTER_APP)


def backdrops():
    stream([sys.executable, str(LAB / "backdrops" / "generate.py"), str(BACKDROPS)])
    return BACKDROPS
```

- [ ] **Step 4: Implement recording**

Create `tool/glass_lab/harness/record.py`:

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


def write_launch_file(folder, scene_id, backdrop, bare):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / LAUNCH_FILE).write_text(json.dumps({"scene": scene_id, "backdrop": backdrop, "bare": bare}))


def clear_launch_file(folder):
    (Path(folder) / LAUNCH_FILE).unlink(missing_ok=True)


def drive(udid, target, scene_id, steps, backdrop, bare, out_dir, settle=1.5):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    folder = launch_folder(udid, target) if target == build.FLUTTER_BUNDLE and scene_id else None
    if folder:
        write_launch_file(folder, scene_id, backdrop, bare)
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
        ],
        env=env,
        capture_output=True,
        text=True,
    )


def target_for(scene, app):
    if scene.native_only:
        return scene.app
    return build.NATIVE_BUNDLE if app == "native" else build.FLUTTER_BUNDLE


def capture(udid, scene, app, backdrop, out_dir):
    out_dir = Path(out_dir)
    target = target_for(scene, app)
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

Run: `python3 -m unittest discover tool/glass_lab/harness/tests -p "test_record.py"`
Expected: `OK`.

- [ ] **Step 5: Implement the CLI and README**

Create `tool/glass_lab/harness/lab.py`:

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
import manifest
import metrics
import record
import report
import sim

RUNS = build.OUT / "runs"
RUN_NAME = re.compile(r"\d{8}-\d{6}")
NOISE = manifest.LAB / "noise.json"
REPEAT_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar")
BASELINE_A11Y_SCENES = ("material.regular", "tabbar.rest", "tabbar.drag", "menu.bar", "sheet.detents")


def cmd_build(args):
    udid = sim.device()
    if args.target in ("native", "both"):
        build.native(udid)
    if args.target in ("flutter", "both"):
        build.flutter(udid)
    print(f"built for {udid}")


def cmd_prepare(args):
    udid = sim.device()
    sim.status_bar(udid)
    source = build.backdrops()
    for bundle in (build.NATIVE_BUNDLE, build.FLUTTER_BUNDLE):
        sim.install_backdrops(udid, bundle, source)
    for scene in manifest.load():
        if scene.native_only:
            sim.revoke_location(udid, scene.app)
            if scene.prepare:
                record.prepare_apple(udid, scene, build.OUT / "prepare" / scene.id)
    print(f"prepared {udid}")


def case_name(appearance, backdrop, a11y):
    return f"{appearance}-{backdrop}" + ("" if a11y == "none" else f"-{a11y}")


def run_cases(udid, scenes, apps, appearances, backdrop, a11y, run_dir):
    sim.accessibility(udid, a11y)
    try:
        for scene in scenes:
            backdrops = [backdrop] if backdrop else list(scene.backdrops)
            for appearance in [a for a in scene.appearances if a in appearances]:
                sim.appearance(udid, appearance)
                for chosen in backdrops:
                    case_dir = run_dir / scene.id / case_name(appearance, chosen, a11y)
                    for app in ["native"] if scene.native_only else apps:
                        print(f"{scene.id} {case_dir.name} {app}", flush=True)
                        try:
                            record.capture(udid, scene, app, chosen, case_dir / app)
                        except RuntimeError as error:
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
    udid = sim.device()
    scenes = manifest.select(manifest.load(), args.scene)
    run_dir = new_run_dir()
    run_cases(udid, scenes, apps_for(args.app), appearances_for(args.appearance), args.backdrop, args.a11y, run_dir)
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
    run_cases(udid, scenes, ["native", "flutter"], ["light", "dark"], None, "none", run_dir)
    chosen = [s for s in scenes if s.id in BASELINE_A11Y_SCENES]
    for mode in ("reduce-transparency", "increase-contrast", "reduce-motion"):
        run_cases(udid, chosen, ["native", "flutter"], ["dark"], None, mode, run_dir)
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
    NOISE.write_text(json.dumps(noise, indent=2, sort_keys=True) + "\n")
    print(NOISE)


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
    b.add_argument("target", nargs="?", default="both", choices=("native", "flutter", "both"))
    b.set_defaults(func=cmd_build)
    commands.add_parser("prepare").set_defaults(func=cmd_prepare)
    r = commands.add_parser("run")
    r.add_argument("scene")
    r.add_argument("--app", default="both", choices=("native", "flutter", "both"))
    r.add_argument("--appearance", default="both", choices=("light", "dark", "both"))
    r.add_argument("--backdrop", choices=manifest.BACKDROPS)
    r.add_argument("--a11y", default="none", choices=sim.A11Y_MODES)
    r.set_defaults(func=cmd_run)
    p = commands.add_parser("report")
    p.add_argument("run_dir", nargs="?")
    p.set_defaults(func=cmd_report)
    commands.add_parser("baseline").set_defaults(func=cmd_baseline)
    m = commands.add_parser("summary")
    m.add_argument("out")
    m.add_argument("run_dir", nargs="?")
    m.set_defaults(func=cmd_summary)
    t = commands.add_parser("repeat")
    t.add_argument("scene", nargs="?", default="default")
    t.add_argument("--times", type=int, default=3)
    t.set_defaults(func=cmd_repeat)
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

Create `tool/glass_lab/README.md`:

````markdown
# Glass lab

This lab measures Operator's Flutter glass against native iOS 27 Liquid Glass.

It has three parts:
- a native SwiftUI catalog (`native/GlassLab`);
- an XCUITest driver that plays identical touches on any app (`native/GlassLabDriver`);
- a Python harness that records both apps and compares them (`harness/`).

The spec is `docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-design.md`.

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
````

- [ ] **Step 6: Build and prepare**

Run:
```bash
python3 tool/glass_lab/harness/lab.py build native
python3 tool/glass_lab/harness/lab.py prepare
```
Expected:
- `built for <udid>`, then `skip dev.operator.operatorMobile: not installed, run lab.py build first` (Operator is built in Task 7), then `prepared <udid>`.
- `build/glass_lab/backdrops/` holds six PNGs.

- [ ] **Step 7: Every native scene completes**

Run: `python3 tool/glass_lab/harness/lab.py run all --app native --appearance dark`. It takes about 60 minutes; run it in the background and wait.
Expected: no `failed:` lines. For each failure, open the case's `native/driver.log`. The driver prints the app's accessibility tree when an element is missing. Correct the step target in `scenes.json` to the label or identifier the tree shows, and rerun only that scene with `lab.py run <scene> --app native --appearance dark`. The `apple.*` scenes may need their `prepare` taps corrected the same way, using a screenshot of each Apple app after `prepare`. After any edit to `scenes.json`, rerun `python3 -m unittest discover tool/glass_lab/harness/tests`.

- [ ] **Step 8: Accessibility modes are restored after a crash**

Run the following. It interrupts `lab.py` mid-run with SIGINT, the same signal Ctrl-C sends.
```bash
python3 tool/glass_lab/harness/lab.py run material.regular --app native --appearance dark --a11y reduce-motion & PID=$!
sleep 25; kill -INT $PID; wait $PID
UDID=$(xcrun simctl list devices "iOS 27.0" | grep "iPhone 17 Pro (iOS 27)" | grep -oE "[0-9A-F-]{36}")
xcrun simctl spawn "$UDID" defaults read com.apple.Accessibility ReduceMotionEnabled
```
Expected: `0`, because `run_cases` restores all modes in `finally`.

- [ ] **Step 9: Report on the native run**

Run: `python3 tool/glass_lab/harness/lab.py report`
Expected: a path to `report.html`. Its counts show every lab scene as `missing` (Operator is not built yet) and every `apple.*` scene as `reference`, with `error: 0`.

- [ ] **Step 10: Commit**

```bash
git add tool/glass_lab
git commit -m "feat(mobile): glass lab simulator control, recording and CLI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Operator's Flutter glass lab

**Files:**
- Create: `lib/core/widgets/glass/lab/glass_lab_launch.dart`, `glass_lab_marker.dart`, `glass_lab_registry.dart`
- Create: `lib/core/widgets/glass/lab/scenes/lab_scene_parts.dart`, `lab_material_scenes.dart`, `lab_navigation_scenes.dart`, `lab_presentation_scenes.dart`, `lab_control_scenes.dart`
- Replace: `lib/core/widgets/glass/lab/glass_lab_backdrop.dart`, `lib/core/widgets/glass/lab/glass_lab_screen.dart`
- Delete: `lib/core/widgets/glass/lab/glass_lab_scene.dart`, `test/core/widgets/glass/lab/glass_lab_scene_test.dart`
- Modify: `lib/main.dart`, `lib/core/app_routes/app_router.dart`, `pubspec.yaml`, `pubspec.lock`
- Test: `test/core/widgets/glass/lab/glass_lab_launch_test.dart`, `test/core/widgets/glass/lab/glass_lab_registry_test.dart`

**Interfaces:**
- Consumes: `tool/glass_lab/scenes.json` (Task 3), plus existing widgets: `GlassSurface`, `GlassButton`, `GlassTabBar`, `GlassTabItem`, `GlobalAppbar.sub`, `ScrollEdgeEffect`, `showAppSheet`, `AppSheetPage`, `AppSheetDetent`, `SkinScope`, `DarkSkin`, `LightSkin` and `AppTextStyle`.
- Produces:
  - `GlassLabLaunch(scene, backdrop, bare)`, with `fromJson`, `consume(Directory)`, `load()`, and the statics `directory` and `current`.
  - `GlassLabRegistry.scenes: Map<String, Widget Function(GlassLabLaunch)>` and `GlassLabRegistry.build(launch)`.
  - `GlassLabScreen(launch:)` and `GlassLabMarker(id, child:)`.
  - Semantics identifiers `scene.ready`, `scene.missing`, `scroll.content`, `sheet.top`, `glass`, `btn.glass` and `btn.prominent`.
  - Tab bar semantics labels `Agents`, `PRs`, `Settings` and `Search` (from `GlassTabBar`'s existing `Semantics(label:)`).

- [ ] **Step 1: Write the failing tests**

Delete `test/core/widgets/glass/lab/glass_lab_scene_test.dart`.

Create `test/core/widgets/glass/lab/glass_lab_launch_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';

void main() {
  test('reads scene, backdrop and bare mode', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'menu.bar', 'backdrop': 'photo', 'bare': true});
    expect(launch?.scene, 'menu.bar');
    expect(launch?.backdrop, 'photo');
    expect(launch?.bare, isTrue);
  });

  test('defaults the backdrop and bare mode', () {
    final launch = GlassLabLaunch.fromJson({'scene': 'tabbar.rest', 'backdrop': ''});
    expect(launch?.backdrop, GlassLabLaunch.defaultBackdrop);
    expect(launch?.bare, isFalse);
  });

  test('returns null without a scene', () {
    expect(GlassLabLaunch.fromJson(const <String, dynamic>{}), isNull);
    expect(GlassLabLaunch.fromJson({'scene': ''}), isNull);
    expect(GlassLabLaunch.fromJson('tabbar.rest'), isNull);
  });

  test('consume reads the launch file once and deletes it', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('{"scene": "toggle", "backdrop": "white"}');
    expect(GlassLabLaunch.consume(directory)?.scene, 'toggle');
    expect(File('${directory.path}/${GlassLabLaunch.launchFile}').existsSync(), isFalse);
    expect(GlassLabLaunch.consume(directory), isNull);
  });

  test('consume ignores and deletes a malformed file', () {
    final directory = Directory.systemTemp.createTempSync('glass_lab');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/${GlassLabLaunch.launchFile}').writeAsStringSync('not json');
    expect(GlassLabLaunch.consume(directory), isNull);
    expect(File('${directory.path}/${GlassLabLaunch.launchFile}').existsSync(), isFalse);
  });
}
```

Create `test/core/widgets/glass/lab/glass_lab_registry_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_registry.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_screen.dart';

List<String> labSceneIds() {
  final raw = jsonDecode(File('tool/glass_lab/scenes.json').readAsStringSync()) as List<dynamic>;
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      if (entry['app'] == 'lab') entry['id'] as String,
  ];
}

Future<void> pumpLab(WidgetTester tester, GlassLabLaunch launch) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp(home: GlassLabScreen(launch: launch)),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1206, 2622);
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  test('every registered scene is in the manifest', () {
    expect(labSceneIds(), containsAll(GlassLabRegistry.scenes.keys));
  });

  testWidgets('every manifest scene renders its scene or the missing placeholder', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final id in labSceneIds()) {
      await pumpLab(tester, GlassLabLaunch(scene: id));
      final missing = GlassLabRegistry.scenes.containsKey(id) ? findsNothing : findsOneWidget;
      expect(find.bySemanticsIdentifier('scene.missing'), missing, reason: id);
      expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget, reason: id);
      expect(tester.takeException(), isNull, reason: id);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
    semantics.dispose();
  });

  testWidgets('bare mode renders only the backdrop', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLab(tester, const GlassLabLaunch(scene: 'tabbar.rest', bare: true));
    expect(find.bySemanticsLabel('Agents'), findsNothing);
    expect(find.bySemanticsIdentifier('scene.ready'), findsOneWidget);
    semantics.dispose();
  });
}
```

Run: `flutter test test/core/widgets/glass/lab/`
Expected: compilation errors, because `glass_lab_launch.dart` and `glass_lab_registry.dart` do not exist.

- [ ] **Step 2: Make `path_provider` a direct dependency**

In `pubspec.yaml`, under `dependencies:`, add a line after `drift_flutter: ^0.3.0`:

```yaml
  path_provider: ^2.1.6
```

Run: `flutter pub get`
Expected: `pubspec.lock` changes only `path_provider`'s `dependency: transitive` to `dependency: "direct main"`. Its version, 2.1.6, is unchanged.

- [ ] **Step 3: Write the launch file, marker, backdrop, registry and screen**

Create `lib/core/widgets/glass/lab/glass_lab_launch.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class GlassLabLaunch {
  const GlassLabLaunch({required this.scene, this.backdrop = defaultBackdrop, this.bare = false});

  static const String defaultBackdrop = 'stripes';
  static const String launchFile = 'launch.json';
  static Directory directory = Directory('');
  static GlassLabLaunch? current;

  final String scene;
  final String backdrop;
  final bool bare;

  static GlassLabLaunch? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final scene = json['scene'];
    if (scene is! String || scene.isEmpty) return null;
    final backdrop = json['backdrop'];
    return GlassLabLaunch(
      scene: scene,
      backdrop: backdrop is String && backdrop.isNotEmpty ? backdrop : defaultBackdrop,
      bare: json['bare'] == true,
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

Create `lib/core/widgets/glass/lab/glass_lab_marker.dart`:

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

Replace `lib/core/widgets/glass/lab/glass_lab_backdrop.dart` with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';

class GlassLabBackdrop extends StatelessWidget {
  const GlassLabBackdrop({super.key, required this.id});

  static const Color missingColor = Color(0xFF808080);

  final String id;

  static File file(String id) => File('${GlassLabLaunch.directory.path}/$id.png');

  @override
  Widget build(BuildContext context) {
    if (id == 'none') return ColoredBox(color: context.skin.bgBase, child: const SizedBox.expand());
    if (id == 'scroll') return const GlassLabScrollBackdrop();
    return SizedBox.expand(
      child: Image.file(
        file(id),
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) => const ColoredBox(color: missingColor),
      ),
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

Create `lib/core/widgets/glass/lab/glass_lab_registry.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_control_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_material_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_navigation_scenes.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_presentation_scenes.dart';

typedef GlassLabSceneBuilder = Widget Function(GlassLabLaunch launch);

sealed class GlassLabRegistry {
  static final Map<String, GlassLabSceneBuilder> scenes = {
    ...LabMaterialScenes.scenes,
    ...LabNavigationScenes.scenes,
    ...LabPresentationScenes.scenes,
    ...LabControlScenes.scenes,
  };

  static Widget build(GlassLabLaunch launch) {
    if (launch.bare) return GlassLabBackdrop(id: launch.backdrop);
    final builder = scenes[launch.scene];
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
                child: Text(
                  'missing: ${launch.scene}',
                  style: AppTextStyle.style15SemiBold.copyWith(color: const Color(0xFF000000)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

Replace `lib/core/widgets/glass/lab/glass_lab_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_registry.dart';

class GlassLabScreen extends StatelessWidget {
  const GlassLabScreen({super.key, required this.launch});

  final GlassLabLaunch launch;

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return SkinScope(
      skin: dark ? const DarkSkin() : const LightSkin(),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(child: GlassLabRegistry.build(launch)),
            const Positioned(left: 0, top: 0, child: GlassLabReady()),
          ],
        ),
      ),
    );
  }
}
```

Delete `lib/core/widgets/glass/lab/glass_lab_scene.dart`.

- [ ] **Step 4: Write the scenes Operator can already render**

Create `lib/core/widgets/glass/lab/scenes/lab_scene_parts.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/glass_surface.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';

class LabCentered extends StatelessWidget {
  const LabCentered({super.key, required this.backdrop, required this.children, this.gap = 48});

  final String backdrop;
  final List<Widget> children;
  final double gap;

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
      ],
    );
  }
}

class LabBlock extends StatelessWidget {
  const LabBlock({
    super.key,
    required this.width,
    required this.height,
    this.variant = GlassVariant.regular,
    this.pressable = false,
  });

  final double width;
  final double height;
  final GlassVariant variant;
  final bool pressable;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GlassSurface(
        kind: GlassShapeKind.capsule,
        size: height,
        variant: variant,
        pressable: pressable,
        child: const SizedBox.expand(),
      ),
    );
  }
}
```

Create `lib/core/widgets/glass/lab/scenes/lab_material_scenes.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_style.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_scene_parts.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

sealed class LabMaterialScenes {
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
        LabBlock(width: 250, height: 88, variant: GlassVariant.clear),
        _DimmedClear(),
      ],
    ),
    'material.tinted': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: [
        const LabBlock(width: 250, height: 88, variant: GlassVariant.prominent),
        GlassButton.label(label: 'Run', icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
      ],
    ),
    'material.interactive': (launch) => LabCentered(
      backdrop: launch.backdrop,
      children: const [GlassLabMarker('glass', child: LabBlock(width: 250, height: 88, pressable: true))],
    ),
    'material.edge.soft': (launch) => const _EdgeScene(),
    'material.edge.hard': (launch) => const _EdgeScene(),
    'material.edge.automatic': (launch) => const _EdgeScene(),
  };
}

class _DimmedClear extends StatelessWidget {
  const _DimmedClear();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        SizedBox(
          width: 250,
          height: 88,
          child: DecoratedBox(
            decoration: ShapeDecoration(color: Color(0x59000000), shape: StadiumBorder()),
          ),
        ),
        LabBlock(width: 250, height: 88, variant: GlassVariant.clear),
      ],
    );
  }
}

class _EdgeScene extends StatelessWidget {
  const _EdgeScene();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: GlobalAppbar.sub(
        titleText: 'Edge',
        actions: [GlassButton.label(label: 'Edit', onPressed: () {})],
      ),
      body: const Stack(
        children: [
          Positioned.fill(child: GlassLabScrollBackdrop()),
          Positioned(left: 0, right: 0, top: 0, child: ScrollEdgeEffect(edge: ScrollEdge.top, height: 140)),
        ],
      ),
    );
  }
}
```

Create `lib/core/widgets/glass/lab/scenes/lab_navigation_scenes.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

sealed class LabNavigationScenes {
  static const Rect nativeTabBar = Rect.fromLTWH(20, 791, 362, 62);

  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'tabbar.rest': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'tabbar.press': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'tabbar.drag': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'navbar.inline': (launch) => _InlineNavScene(backdrop: launch.backdrop),
  };
}

class _TabBarScene extends StatefulWidget {
  const _TabBarScene({required this.backdrop});

  final String backdrop;

  @override
  State<_TabBarScene> createState() => _TabBarSceneState();
}

class _TabBarSceneState extends State<_TabBarScene> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: widget.backdrop)),
        Positioned.fromRect(
          rect: LabNavigationScenes.nativeTabBar,
          child: GlassTabBar(
            items: const [
              GlassTabItem(icon: Icons.layers, label: 'Agents'),
              GlassTabItem(icon: Icons.call_merge, label: 'PRs'),
              GlassTabItem(icon: Icons.settings, label: 'Settings'),
              GlassTabItem(icon: Icons.search, label: 'Search'),
            ],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
        ),
      ],
    );
  }
}

class _InlineNavScene extends StatelessWidget {
  const _InlineNavScene({required this.backdrop});

  final String backdrop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: GlobalAppbar.sub(
        titleText: 'Agents',
        actions: [
          GlassButton.icon(icon: Icons.notifications_none_rounded, onPressed: () {}),
          GlassButton.icon(icon: Icons.more_horiz_rounded, onPressed: () {}),
        ],
      ),
      body: GlassLabBackdrop(id: backdrop),
    );
  }
}
```

Create `lib/core/widgets/glass/lab/scenes/lab_presentation_scenes.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';

sealed class LabPresentationScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'sheet.detents': (launch) => _SheetScene(backdrop: launch.backdrop),
  };
}

class _SheetScene extends StatefulWidget {
  const _SheetScene({required this.backdrop});

  final String backdrop;

  @override
  State<_SheetScene> createState() => _SheetSceneState();
}

class _SheetSceneState extends State<_SheetScene> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    if (!mounted) return;
    final skin = context.skin;
    unawaited(
      showAppSheet<void>(
        context: context,
        detent: AppSheetDetent.medium,
        page: AppSheetPage(
          title: 'Sheet',
          rows: (context, _) => const [GlassLabMarker('sheet.top', child: SizedBox(height: 56))],
        ),
        scope: (_, sheet) => SkinScope(skin: skin, child: sheet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GlassLabBackdrop(id: widget.backdrop);
}
```

Create `lib/core/widgets/glass/lab/scenes/lab_control_scenes.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_marker.dart';
import 'package:operator_mobile/core/widgets/glass/lab/scenes/lab_scene_parts.dart';

sealed class LabControlScenes {
  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'button.styles': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 18,
      children: [
        for (final compact in [true, true, false, false])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassButton.label(label: 'Glass', compact: compact, onPressed: () {}),
              const SizedBox(width: 12),
              GlassButton.label(label: 'Prominent', compact: compact, prominent: true, onPressed: () {}),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassButton.icon(icon: Icons.add_rounded, onPressed: () {}),
            const SizedBox(width: 16),
            GlassButton.icon(icon: Icons.play_arrow_rounded, prominent: true, onPressed: () {}),
          ],
        ),
      ],
    ),
    'button.press': (launch) => LabCentered(
      backdrop: launch.backdrop,
      gap: 60,
      children: [
        GlassLabMarker('btn.glass', child: GlassButton.label(label: 'Glass button', onPressed: () {})),
        GlassLabMarker('btn.prominent', child: GlassButton.label(label: 'Prominent button', prominent: true, onPressed: () {})),
      ],
    ),
  };
}
```

- [ ] **Step 5: Wire the launch into the app**

In `lib/main.dart`, replace the import
`import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_scene.dart';`
with
`import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';`
Then replace:

```dart
  final labScene = kDebugMode ? GlassLabScene.fromEnvironment() : null;
  final initialRoute = labScene != null
```

with:

```dart
  final labLaunch = kDebugMode ? await GlassLabLaunch.load() : null;
  final initialRoute = labLaunch != null
```

In `lib/core/app_routes/app_router.dart`, make the same import replacement. Then replace

```dart
          builder: (_) => GlassLabScreen(scene: GlassLabScene.fromEnvironment() ?? GlassLabScene.rest),
```

with:

```dart
          builder: (_) => GlassLabScreen(
            launch: GlassLabLaunch.current ?? const GlassLabLaunch(scene: 'tabbar.rest'),
          ),
```

- [ ] **Step 6: Run the gates**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/core/widgets/glass/lab/`
Expected: `All tests passed!` for 8 tests.

Run: `flutter test`
Expected: the full suite is green.

- [ ] **Step 7: Commit**

```bash
git add lib test pubspec.yaml pubspec.lock
git commit -m "feat(mobile): glass lab route reads its scene from a launch file and renders every manifest id

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Flutter scenes through the harness, placed like native

**Files:**
- Modify: `lib/core/widgets/glass/lab/scenes/*.dart`, only for placement
- Modify: `tool/glass_lab/scenes.json`, only if a Flutter-side label differs

**Interfaces:**
- Consumes: Tasks 5 and 6.
- Produces: a run in which every Flutter scene that exists has its glass box centre within 1 pt of native. The spec's "Done" item 3 lists those scenes.

- [ ] **Step 1: Build Operator and prepare**

Run:
```bash
python3 tool/glass_lab/harness/lab.py build flutter
python3 tool/glass_lab/harness/lab.py prepare
```
Expected: `built for <udid>`, and `prepared <udid>` with no `skip` line.

- [ ] **Step 2: Record the implemented scenes in both apps**

Run:
```bash
for scene in tabbar.rest tabbar.press tabbar.drag button.press button.styles sheet.detents navbar.inline material.regular material.tinted material.clear material.interactive material.edge.soft; do python3 tool/glass_lab/harness/lab.py run $scene --appearance dark; done
```
Expected: no `failed:` lines.

The first Flutter launch on a fresh simulator shows Operator's notification prompt, which the driver dismisses with "Don't Allow". If a Flutter case fails to find an element, read its `flutter/driver.log` tree:
- Give the Flutter scene the same semantics identifier through `GlassLabMarker`, or the same label.
- Never change the native catalog to suit Flutter.

- [ ] **Step 3: Report and read centres**

`lab.py run` makes one run directory per invocation. Report each of them:

```bash
for run in $(ls -d build/glass_lab/runs/2* | tail -12); do python3 tool/glass_lab/harness/lab.py report "$run" >/dev/null; done
python3 - <<'EOF'
import glob, json
for path in sorted(glob.glob("build/glass_lab/runs/2*/*/*/result.json"))[-40:]:
    result = json.load(open(path))
    for name, stat in (result.get("static") or {}).items():
        print(result["scene"], result["case"], name, "centre", round(stat["centre_pt"], 1), stat["native_box"], stat["flutter_box"])
EOF
```
Expected: for each scene listed in spec "Done" item 3, `centre` ≤ 1.0 in both `ready` and `settled`.

- [ ] **Step 4: Fix placement where the scene controls it**

For any listed scene whose centre is off by more than 1 pt, change only the Flutter scene's placement. Examples: `LabCentered` gap values, the `Positioned` rect, or safe-area handling. Run `python3 tool/glass_lab/harness/lab.py geometry <scene>` for the native boxes. Do not change `GlassTabBar`, `GlassButton`, `GlobalAppbar`, `AppSheet` or `GlassSurface`.

Two kinds of difference come from how a component draws, not from where the scene puts it:
- the nav bar's internal item spacing;
- a larger box caused by shadow spread.

For those, write one line per scene into the task report, naming the component and the measured delta. The baseline carries them forward. Rerun Steps 2–3 for changed scenes, then run `flutter analyze` and `flutter test test/core/widgets/glass/lab/`.

- [ ] **Step 5: Placeholders run cleanly**

Run: `python3 tool/glass_lab/harness/lab.py run menu.bar --appearance dark && python3 tool/glass_lab/harness/lab.py report`
Expected: `menu.bar` is counted as `missing`, and its `flutter/timing.json` has `"missing": true` (the driver skipped the steps).

- [ ] **Step 6: Commit**

```bash
git add lib tool/glass_lab
git commit -m "feat(mobile): glass lab Flutter scenes placed like native

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Noise floor, Apple references, baseline and cleanup

**Files:**
- Create: `tool/glass_lab/noise.json` (written by `lab.py repeat`)
- Create: `docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-baseline.md` (written by `lab.py summary`)
- Delete: `tool/glass_reference/`
- Modify: `.gitignore`, `tool/glass_lab/scenes.json` (only Apple `prepare` steps, if needed)

**Interfaces:**
- Consumes: everything above.
- Produces: the committed noise floor and baseline summary, which are the backlog for projects 2–4.

- [ ] **Step 1: Measure the noise floor**

Run: `python3 tool/glass_lab/harness/lab.py repeat`. It takes about 25 minutes.
Expected: for each of `material.regular`, `tabbar.rest`, `tabbar.drag` and `menu.bar`, a line `static mad 0.00` (any value ≤ 1.0 passes) and a motion noise map. `tool/glass_lab/noise.json` is written. If any scene prints `static repeatability FAILED`, stop and investigate before continuing: the rig is not trustworthy.

- [ ] **Step 2: Check the primary events against the one-frame target**

Read `noise.json`. For `menu.bar`, `event0.width.peak_ms` and `event0.width.settle_ms` are expected at ≤ 17. Record the values in the task report either way; the spec reports this target rather than enforcing it.

- [ ] **Step 3: Apple app references**

Run: `python3 tool/glass_lab/harness/lab.py run apple --appearance dark`
Expected: six `reference` cases. Look at each case's `native/ready.png`. If an Apple app is still on a welcome or permission screen, fix that scene's `prepare` taps in `scenes.json`, run `lab.py prepare`, and repeat the run.

- [ ] **Step 4: Run the baseline**

Run: `python3 tool/glass_lab/harness/lab.py baseline`. It takes about four hours; run it in the background.
Expected: ends by printing the report path and the counts, with `error: 0`.

Open `report.html` and scan every filmstrip for system overlays, such as a keyboard tip or a permission alert. For each one, add a dismissal to `prepare` (or a `prepare` list on that scene), then rerun that scene with `lab.py run <scene>` and `lab.py report <that run>`.

- [ ] **Step 5: Write the baseline summary**

Run: `python3 tool/glass_lab/harness/lab.py summary ../../docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-baseline.md`
Expected: the file exists, starting with "# Glass lab baseline". It has one row per case: scene, case, title, status and failing measures.

- [ ] **Step 6: Remove the old reference tool**

Delete `tool/glass_reference/` and remove the `tool/glass_reference/build/` line from `.gitignore`. Check with `grep -rn "glass_reference" lib test tool .gitignore ../../docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-design.md`. Expected: no hits outside the spec's own text.

- [ ] **Step 7: Final gates**

Run:
```bash
python3 -m unittest discover tool/glass_lab/harness/tests
flutter analyze
flutter test
```
Expected: `OK`, `No issues found!`, and all tests passed.

- [ ] **Step 8: Commit**

```bash
git add -A tool .gitignore ../../docs/superpowers/specs/2026-09-26-mobile-glass-reference-lab-baseline.md
git commit -m "feat(mobile): glass lab noise floor and iOS 27 baseline; retire glass_reference

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
