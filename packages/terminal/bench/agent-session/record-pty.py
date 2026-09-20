#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import pty
import select
import signal
import struct
import sys
import termios
import tty


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def main():
    parser = argparse.ArgumentParser(description="record a pty session in the agent-session fixture layout")
    parser.add_argument("--out", required=True, help="fixture directory to create")
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=40)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command:
        parser.error("command is required")
    os.makedirs(args.out, exist_ok=True)
    recording = open(os.path.join(args.out, "recording"), "wb")
    sizes = [{"offset": 0, "cols": args.cols, "rows": args.rows}]
    written = 0

    def write_sizes():
        with open(os.path.join(args.out, "size.json"), "w") as handle:
            json.dump(sizes, handle)

    write_sizes()
    pid, master = pty.fork()
    if pid == 0:
        os.execvp(args.command[0], args.command)
    set_winsize(master, args.cols, args.rows)
    state = {"cols": args.cols, "rows": args.rows}

    def on_winch(_signum, _frame):
        try:
            packed = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\0" * 8)
        except OSError:
            return
        rows, cols, _, _ = struct.unpack("HHHH", packed)
        if cols == 0 or rows == 0 or (cols, rows) == (state["cols"], state["rows"]):
            return
        state["cols"], state["rows"] = cols, rows
        set_winsize(master, cols, rows)
        sizes.append({"offset": written, "cols": cols, "rows": rows})
        write_sizes()

    signal.signal(signal.SIGWINCH, on_winch)
    stdin = sys.stdin.fileno()
    saved = termios.tcgetattr(stdin)
    tty.setraw(stdin)
    try:
        while True:
            ready, _, _ = select.select([master, stdin], [], [])
            if master in ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                recording.write(data)
                recording.flush()
                written += len(data)
                os.write(sys.stdout.fileno(), data)
            if stdin in ready:
                data = os.read(stdin, 65536)
                if not data:
                    break
                os.write(master, data)
    finally:
        termios.tcsetattr(stdin, termios.TCSADRAIN, saved)
        recording.close()
        write_sizes()
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    sys.exit(main())
