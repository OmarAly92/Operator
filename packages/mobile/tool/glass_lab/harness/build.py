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
