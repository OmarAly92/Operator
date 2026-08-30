import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const outDir = join(root, "protocol", "alt-vectors");

function tmux(...args) {
	return execFileSync("tmux", args, { encoding: "utf8" });
}

function sleep(ms) {
	execFileSync("sleep", [String(ms / 1000)]);
}

export function capture({ name, command, rows, cols, keys = [], settleMs = 700 }) {
	const session = `optcap-${name}-${process.pid}`;
	const rawPath = join("/tmp", `${session}.raw`);
	rmSync(rawPath, { force: true });
	mkdirSync(outDir, { recursive: true });
	try {
		tmux("new-session", "-d", "-s", session, "-x", String(cols), "-y", String(rows), command);
		tmux("pipe-pane", "-t", session, "-o", `cat >> ${rawPath}`);
		sleep(settleMs);
		for (const key of keys) {
			tmux("send-keys", "-t", session, key);
			sleep(300);
		}
		sleep(settleMs);
		const expectedRows = tmux("capture-pane", "-t", session, "-p").replace(/\n$/, "").split("\n");
		const input = readFileSync(rawPath);
		writeFileSync(
			join(outDir, `${name}.json`),
			`${JSON.stringify(
				{ name, rows, cols, command, keys, inputBase64: input.toString("base64"), expectedRows },
				null,
				"\t",
			)}\n`,
		);
		return expectedRows;
	} finally {
		try {
			tmux("kill-session", "-t", session);
		} catch {}
		rmSync(rawPath, { force: true });
	}
}

const cases = [
	{ name: "less-page", command: "less /usr/share/dict/words", rows: 20, cols: 60, keys: ["Space", "Space"] },
	{ name: "vim-open", command: "vim -u NONE -N /etc/hosts", rows: 20, cols: 60, keys: ["G"] },
	{ name: "htop-frame", command: "htop -d 600", rows: 24, cols: 80, keys: [], settleMs: 2500 },
	{ name: "less-back", command: "less /usr/share/dict/words", rows: 20, cols: 60, keys: ["Space", "Space", "b", "y", "y"] },
];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	for (const testCase of cases) {
		try {
			capture(testCase);
			console.log(`recorded ${testCase.name}`);
		} catch (error) {
			console.error(`skipped ${testCase.name}: ${error.message}`);
		}
	}
}
