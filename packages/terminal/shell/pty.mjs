import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export function haveTmux() {
	try {
		execFileSync("tmux", ["-V"], { stdio: "ignore" });
		return true;
	} catch {
		return false;
	}
}

export function runInPty(command, keys, { settleMs = 1000 } = {}) {
	const dir = mkdtempSync(join(tmpdir(), "opr-pty-"));
	const raw = join(dir, "pane.raw");
	const session = `opr_pty_${process.pid}_${Math.random().toString(36).slice(2, 8)}`;
	const tmux = (...args) => execFileSync("tmux", args, { encoding: "latin1" });
	try {
		tmux("new-session", "-d", "-s", session, "-x", "120", "-y", "40", command);
		tmux("pipe-pane", "-t", session, "-o", `cat >> ${raw}`);
		sleep(settleMs);
		for (const line of keys) {
			tmux("send-keys", "-t", session, line, "Enter");
			sleep(settleMs);
		}
		return readFileSync(raw, "latin1");
	} finally {
		try {
			tmux("kill-session", "-t", session);
		} catch {}
		rmSync(dir, { recursive: true, force: true });
	}
}

function sleep(ms) {
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
