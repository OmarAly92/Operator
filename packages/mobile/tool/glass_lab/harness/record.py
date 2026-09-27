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
            "-collect-test-diagnostics", "never",
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
