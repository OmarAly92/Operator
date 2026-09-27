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
