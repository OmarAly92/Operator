import { createTerminalCore, decodeBlocks } from "@operator/terminal-core";
import { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";

declare global {
	interface Window {
		__terminalScrollReady: boolean;
		__terminalScrollBlockCount: number;
	}
}

const host = document.getElementById("terminal");
if (!host) throw new Error("scroll host is missing");

await initTerminalCoreFromUrl();
const core = createTerminalCore({ columns: 80, scrollback: 100000 });
const renderer = new DomBlockRenderer();
renderer.mount(host, core);

const blocks: string[] = [];
for (let index = 0; index < 50000; index += 1) {
	blocks.push(`\x1b]133;A\x07\x1b]133;C\x07row ${index}\n\x1b]133;D;0\x07`);
}

await new Promise<void>((resolve, reject) => {
	const timeout = window.setTimeout(() => {
		off();
		reject(new Error("initial 50,000-block paint timed out"));
	}, 30000);
	const off = renderer.onPaint(() => {
		off();
		window.clearTimeout(timeout);
		resolve();
	});
	core.feed(new TextEncoder().encode(blocks.join("")));
});

window.__terminalScrollBlockCount = decodeBlocks(core.snapshot()).length;
window.__terminalScrollReady = true;
