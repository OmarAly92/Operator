import { cpSync, existsSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { runInPty } from "./pty.mjs";

const coreDist = fileURLToPath(new URL("../ts/core/dist/index.js", import.meta.url));
const coreWasm = fileURLToPath(new URL("../ts/core/wasm/vt_core_bg.wasm", import.meta.url));

export const coreSkip = existsSync(coreDist) && existsSync(coreWasm)
	? false
	: "the terminal core is not built (npm run build)";

export async function feedCore(stream, { columns = 120, rows = 40 } = {}) {
	const core = await import(coreDist);
	const bytes = readFileSync(coreWasm);
	await core.initTerminalCore(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
	const terminal = core.createTerminalCore({ columns, rows, limits: { rows: 10_000, bytes: 1 << 24 } });
	terminal.feed(Buffer.from(stream, "latin1"));
	const blocks = core.decodeBlocks(terminal.snapshot()).map((block) => ({
		command: block.command,
		cwd: block.cwd,
		state: block.state,
		output: terminal.readBlockOutput(block.id),
	}));
	terminal.dispose?.();
	return blocks;
}

export function productionSession(shell, steps, { settleMs = 800 } = {}) {
	const manifest = JSON.parse(readFileSync(new URL("../protocol/recipes.json", import.meta.url), "utf8"));
	const name = manifest.shells[shell].script;
	const home = realpathSync(mkdtempSync(join(tmpdir(), `opr-${shell}-home-`)));
	const script = join(home, name);
	cpSync(fileURLToPath(new URL(`./${name}`, import.meta.url)), script);
	const scriptDir = fileURLToPath(new URL(`./${name}.d`, import.meta.url));
	if (existsSync(scriptDir)) cpSync(scriptDir, `${script}.d`, { recursive: true });
	const command = manifest.shells[shell].argv
		.map((argument) => argument.replaceAll("{{script}}", JSON.stringify(script)))
		.map((argument) => `'${argument.replaceAll("'", "'\\''")}'`)
		.join(" ");
	try {
		const stream = runInPty(command, steps, {
			settleMs,
			env: {
				HOME: home,
				XDG_CONFIG_HOME: join(home, ".config"),
				OPERATOR_TERMINAL_ID: "t",
				OPERATOR_TERMINAL_SUPPRESS_PROMPT: "1",
				OPERATOR_TERMINAL_INTEGRATION: "auto",
				BASH_SILENCE_DEPRECATION_WARNING: "1",
			},
		});
		return { stream, home };
	} finally {
		rmSync(home, { recursive: true, force: true });
	}
}

export const ABORTED_PROMPTS_SESSION = [
	"printf x",
	"echo one",
	{ keys: "C-c", enter: false },
	{ keys: "", enter: true },
	"echo two",
];

export async function abortedPromptsSession(shell) {
	const { stream } = productionSession(shell, ABORTED_PROMPTS_SESSION);
	const blocks = await feedCore(stream);
	const first = blocks.findIndex((block) => block.command !== "");
	return { stream, blocks: first < 0 ? [] : blocks.slice(first) };
}

export function commandOutputs(blocks) {
	return blocks.filter((block) => block.command !== "").map((block) => [block.command, block.output]);
}
