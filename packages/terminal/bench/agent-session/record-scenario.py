#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

ESCAPE = re.compile(rb"\x1b\[[0-9;?>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x1b[=>78DEHMNOZc]")
FORWARD = re.compile(rb"\x1b\[([0-9]*)C")
COLUMN = re.compile(rb"\x1b\[[0-9;]*[GH]")
QUERY = re.compile(rb"\x1b\[(>0?q|0?c|\?([0-9;]*)\$p|\?([0-9;]*)([hl]))")
TRACKED = {1, 25, 1000, 1002, 1003, 1004, 1006, 1049, 2004, 2048}
IDENTITY = b"Operator"


def plain(data):
    spaced = COLUMN.sub(b" ", FORWARD.sub(lambda match: b" " * int(match.group(1) or b"1"), data))
    return ESCAPE.sub(b"", spaced).replace(b"\r", b"\n").decode("utf-8", "replace")


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


class Session:
    def __init__(self, command, cols, rows):
        self.started = time.monotonic()
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.execvp(command[0], command)
        set_winsize(self.master, cols, rows)
        self.recording = bytearray()
        self.timing = []
        self.sizes = [{"offset": 0, "cols": cols, "rows": rows}]
        self.inputs = []
        self.intervals = []
        self.current = {"from": 0, "state": "working"}
        self.last_output_ms = 0
        self.since = 0
        self.modes = {25}
        self.closed = False

    def answer(self, data):
        replies = bytearray()
        for match in QUERY.finditer(data):
            if match.group(4):
                for mode in (int(part) for part in match.group(3).split(b";") if part):
                    if match.group(4) == b"h":
                        self.modes.add(mode)
                    else:
                        self.modes.discard(mode)
            elif match.group(1).endswith(b"q"):
                replies += b"\x1bP>|" + IDENTITY + b"\x1b\\"
            elif match.group(1).endswith(b"c"):
                replies += b"\x1b[?62;22c"
            else:
                for mode in (int(part) for part in match.group(2).split(b";") if part):
                    status = 0 if mode not in TRACKED and mode != 2026 else (1 if mode in self.modes and mode != 2026 else 2)
                    replies += b"\x1b[?%d;%d$y" % (mode, status)
        if replies:
            os.write(self.master, bytes(replies))

    def now(self):
        return int((time.monotonic() - self.started) * 1000)

    def pump(self, seconds):
        deadline = time.monotonic() + seconds
        while not self.closed:
            left = deadline - time.monotonic()
            if left <= 0:
                return
            ready, _, _ = select.select([self.master], [], [], left)
            if not ready:
                return
            try:
                data = os.read(self.master, 65536)
            except OSError:
                data = b""
            if not data:
                self.closed = True
                return
            at = self.now()
            self.timing.append([len(self.recording), at])
            self.recording.extend(data)
            self.last_output_ms = at
            self.answer(data)
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()

    def write(self, text):
        self.since = len(self.recording)
        os.write(self.master, text.encode("utf-8"))
        self.inputs.append(self.now())

    def begin(self, at, state, question=None):
        self.current["to"] = at
        if self.current["to"] > self.current["from"]:
            self.intervals.append(self.current)
        self.current = {"from": at, "state": state}
        if question:
            self.current["question"] = question

    def matches(self, regex, raw, window):
        return regex.search(window) if raw else regex.search(plain(window))

    def arrival(self, regex, raw, since):
        ends = [entry[0] for entry in self.timing[1:]] + [len(self.recording)]
        for (_, at), end in zip(self.timing, ends):
            if end > since and self.matches(regex, raw, bytes(self.recording[since:end])):
                return max(at, self.current["from"])
        return self.now()

    def expect(self, pattern, raw, timeout):
        regex = re.compile(pattern.encode("utf-8") if raw else pattern)
        since = self.since
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not self.closed:
            window = bytes(self.recording[since:])
            if self.matches(regex, raw, window):
                self.since = len(self.recording)
                return self.arrival(regex, raw, since)
            self.pump(0.05)
        tail = plain(bytes(self.recording[-4000:]))
        raise SystemExit(f"expect {pattern!r} timed out after {timeout}s; screen text:\n{tail}")

    def expect_quiet(self, seconds, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and not self.closed:
            self.pump(0.25)
            if self.now() - self.last_output_ms >= seconds * 1000:
                return self.last_output_ms
        raise SystemExit(f"expect_quiet {seconds}s timed out after {timeout}s")

    def stop(self):
        for signum in (signal.SIGHUP, signal.SIGTERM, signal.SIGKILL):
            try:
                os.kill(self.pid, signum)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                try:
                    pid, _ = os.waitpid(self.pid, os.WNOHANG)
                except ChildProcessError:
                    return
                if pid:
                    return
                if self.closed:
                    time.sleep(0.05)
                else:
                    self.pump(0.05)
        os.close(self.master)
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass

    def resize(self, cols, rows):
        set_winsize(self.master, cols, rows)
        self.sizes.append({"offset": len(self.recording), "cols": cols, "rows": rows})
        self.inputs.append(self.now())
        os.kill(self.pid, signal.SIGWINCH)


def run(session, steps):
    for step in steps:
        kind = step["type"]
        if kind == "text":
            session.write(step["text"])
            session.pump(step.get("settle", 0.6))
        elif kind == "submit":
            session.write("\r")
            session.begin(session.now(), "working")
            session.pump(0.2)
        elif kind == "answer":
            session.write(step["keys"])
            session.begin(session.now(), "working")
            session.pump(0.2)
        elif kind == "expect":
            at = session.expect(step["pattern"], step.get("raw", False), step.get("timeout", 300))
            session.begin(at, step["state"], step.get("question"))
        elif kind == "expect_quiet":
            at = session.expect_quiet(step["seconds"], step.get("timeout", 900))
            session.begin(at, step["state"])
        elif kind == "wait":
            session.pump(step["seconds"])
        elif kind == "resize":
            session.resize(step["cols"], step["rows"])
            session.pump(0.2)
        else:
            raise SystemExit(f"unknown step type {kind!r}")


def main():
    parser = argparse.ArgumentParser(description="record an agent scenario with timing and ground truth")
    parser.add_argument("--out", required=True)
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = [part for part in args.command if part != "--"]
    if not command:
        parser.error("command is required")
    with open(args.scenario) as handle:
        scenario = json.load(handle)
    session = Session(command, args.cols, args.rows)
    finished = False
    try:
        run(session, scenario["steps"])
        session.pump(scenario.get("tail_seconds", 2))
        finished = True
    finally:
        end = max(session.now(), session.last_output_ms + 1)
        session.begin(end, session.current["state"])
        length, reads = len(session.recording), len(session.timing)
        session.stop()
        if not finished:
            with open(args.out.rstrip("/") + ".failed.recording", "wb") as handle:
                handle.write(bytes(session.recording))
    del session.recording[length:]
    del session.timing[reads:]
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "recording"), "wb") as handle:
        handle.write(bytes(session.recording))
    with open(os.path.join(args.out, "size.json"), "w") as handle:
        json.dump(session.sizes, handle)
    with open(os.path.join(args.out, "timing.json"), "w") as handle:
        json.dump(session.timing, handle)
    truth = {
        "harness": scenario["harness"],
        "agentVersion": scenario.get("agentVersion", ""),
        "command": command,
        "intervals": session.intervals,
        "inputs": session.inputs,
    }
    with open(os.path.join(args.out, "truth.json"), "w") as handle:
        json.dump(truth, handle, indent=1, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    main()
