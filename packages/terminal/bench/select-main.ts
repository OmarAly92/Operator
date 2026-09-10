import { createElement } from "react";
import { createRoot } from "react-dom/client";
import {
	TerminalSurface,
	createTerminalCore,
	initTerminalCoreFromUrl,
	warpDarkTheme,
	type FontConfig,
	type HostCapabilities,
} from "@operator/terminal-react";

declare global {
	interface Window {
		__gate: {
			startSpinner(): void;
			stopSpinner(): void;
			copied: string[];
			tickCount: number;
		};
		__gateReady: boolean;
	}
}

const root = document.getElementById("root");
if (!root) throw new Error("select gate root is missing");

window.__gateReady = false;

await initTerminalCoreFromUrl();

const core = createTerminalCore({ columns: 100, scrollback: 2000, rows: 50 });

const copied: string[] = [];
const host: HostCapabilities = {
	writeClipboard: async (text: string) => {
		copied.push(text);
	},
	readClipboard: async () => "",
	openLink: async () => undefined,
};

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.3,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

function band(index: number): string {
	return (
		"\x1b]133;A\x07\x1b]133;C\x07" +
		`\x1b[48;5;237m\x1b[38;5;231m> operator run task-${index} --apply\x1b[0m\r\n` +
		`Thinking through step ${index} of the plan...\r\n` +
		`Edited file src/module-${index}.ts (+${index} -${index})\r\n` +
		"\x1b]133;D;0\x07"
	);
}

let transcript = "";
for (let index = 1; index <= 40; index += 1) transcript += band(index);
core.feed(new TextEncoder().encode(transcript));

let spinnerHandle: number | null = null;
let tickCount = 0;

function startSpinner(): void {
	if (spinnerHandle !== null) return;
	spinnerHandle = window.setInterval(() => {
		tickCount += 1;
		core.feed(new TextEncoder().encode(`\x1b[2K\r✻ Baking for ${tickCount}s`));
	}, 50);
}

function stopSpinner(): void {
	if (spinnerHandle !== null) {
		window.clearInterval(spinnerHandle);
		spinnerHandle = null;
	}
}

window.__gate = {
	startSpinner,
	stopSpinner,
	copied,
	get tickCount() {
		return tickCount;
	},
};

function App() {
	return createElement(TerminalSurface, {
		core,
		theme: warpDarkTheme,
		font,
		altScreenActive: false,
		host,
		onSend: () => undefined,
		onSendRaw: () => undefined,
		onPaint: () => {
			window.__gateReady = true;
		},
	});
}

createRoot(root).render(createElement(App));
