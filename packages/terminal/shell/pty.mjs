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

export function runInPty(command, input, options = {}) {
	return runInPtySegments(command, input, options).join("");
}

export function runInPtySegments(command, input, { settleMs = 1000, env = {} } = {}) {
	const dir = mkdtempSync(join(tmpdir(), "opr-pty-"));
	const raw = join(dir, "pane.raw");
	const session = `opr_pty_${process.pid}_${Math.random().toString(36).slice(2, 8)}`;
	const tmux = (...args) => execFileSync("tmux", args, { encoding: "latin1" });
	try {
		const environment = Object.entries(env).flatMap(([name, value]) => ["-e", `${name}=${value}`]);
		tmux("new-session", "-d", "-s", session, "-x", "120", "-y", "40", ...environment, command);
		tmux("pipe-pane", "-t", session, "-o", `cat >> ${raw}`);
		sleep(settleMs);
		const cuts = [];
		for (const item of input) {
			const { keys, enter = true, waitMs = settleMs, resize, cut = false } =
				typeof item === "string" ? { keys: item } : item;
			if (resize || cut) {
				cuts.push(readFileSync(raw, "latin1").length);
			}
			if (resize) {
				tmux("resize-window", "-t", session, "-x", String(resize[0]), "-y", String(resize[1]));
			} else {
				tmux("send-keys", "-t", session, keys, ...(enter ? ["Enter"] : []));
			}
			sleep(waitMs);
		}
		const all = readFileSync(raw, "latin1");
		return [0, ...cuts].map((start, index) => all.slice(start, cuts[index] ?? all.length));
	} finally {
		try {
			tmux("kill-session", "-t", session);
		} catch {}
		rmSync(dir, { recursive: true, force: true });
	}
}

export function parseOscRecords(raw, chunks = [raw]) {
	let pending = "";
	const records = [];
	for (const chunk of chunks) {
		pending += chunk;
		while (true) {
			const start = pending.indexOf("\x1b]");
			if (start < 0) {
				pending = pending.endsWith("\x1b") ? "\x1b" : "";
				break;
			}
			if (start > 0) {
				pending = pending.slice(start);
			}
			const bel = pending.indexOf("\x07", 2);
			const st = pending.indexOf("\x1b\\", 2);
			if (bel < 0 && st < 0) {
				break;
			}
			const end = bel < 0 ? st : st < 0 ? bel : Math.min(bel, st);
			const terminator = end === bel ? "BEL" : "ST";
			const width = terminator === "BEL" ? 1 : 2;
			const rawRecord = pending.slice(0, end + width);
			const payload = pending.slice(2, end);
			if (payload.startsWith("133;") || payload.startsWith("7000;")) {
				records.push({ raw: rawRecord, payload, terminator });
			}
			pending = pending.slice(end + width);
		}
	}
	return records;
}

export function splitEveryByte(raw) {
	return Array.from(raw);
}

function sleep(ms) {
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
