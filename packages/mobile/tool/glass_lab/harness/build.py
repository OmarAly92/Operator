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
