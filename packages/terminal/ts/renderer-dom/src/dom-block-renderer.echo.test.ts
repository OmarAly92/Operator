import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, type TerminalCore, type TerminalLimits } from "@operator/terminal-core";
import { DomBlockRenderer } from "./index";
import { font, theme, loadedCore, feed, flushRepaint, stubRowLayout } from "./renderer-harness";

beforeAll(async () => {
	await loadedCore();
});

afterEach(() => {
	vi.restoreAllMocks();
});

function mountRenderer(limits?: TerminalLimits): {
	core: TerminalCore;
	host: HTMLElement;
	renderer: DomBlockRenderer;
	feed: (text: string) => Promise<void>;
	enterAltScreen: () => Promise<void>;
	leaveAltScreen: () => Promise<void>;
} {
	stubRowLayout();
	const core = createTerminalCore({ columns: 16, scrollback: 100, ...(limits ? { limits } : {}) });
	const host = document.createElement("div");
	const renderer = new DomBlockRenderer();
	renderer.mount(host, core);
	renderer.setTheme(theme);
	renderer.setFont(font);
	const feedInto = async (text: string): Promise<void> => {
		feed(core, text);
		await flushRepaint();
	};
	return {
		core,
		host,
		renderer,
		feed: feedInto,
		enterAltScreen: () => feedInto("\u001b[?1049h"),
		leaveAltScreen: () => feedInto("\u001b[?1049l"),
	};
}

const printable = (text: string) => ({ text, ctrlKey: false, altKey: false, metaKey: false, isComposing: false });

describe("predictive echo", () => {
	it("paints nothing when the host set no threshold", () => {
		const { renderer, host } = mountRenderer();
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		expect(renderer.predictionCount()).toBe(0);
	});

	it("paints one dim glyph at the cursor once armed", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		const painted = host.querySelectorAll(".terminal-prediction");
		expect(painted).toHaveLength(1);
		expect(painted[0]!.textContent).toBe("a");
	});

	it("paints nothing when the measured RTT is below the threshold", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 7);
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("removes the glyph when real output confirms it", async () => {
		const { renderer, host, feed } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		await feed("a");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("predictionsClear removes every painted glyph", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		renderer.predictionsClear();
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("measures the round trip from a noted send to the next output the core reports", async () => {
		const { renderer, feed } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteSend(performance.now() - 200);
		await feed("x");
		expect(renderer.predictKey(printable("a"), performance.now())).toBe(true);
	});

	it("takes no sample from output that no send is waiting on", async () => {
		const { renderer, feed } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 0 });
		await feed("x");
		expect(renderer.predictKey(printable("a"), performance.now())).toBe(false);
	});

	it("setPredictiveEcho(null) disarms and clears", () => {
		const { renderer, host } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		renderer.setPredictiveEcho(null);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		expect(renderer.predictKey(printable("b"), 1100)).toBe(false);
	});

	it("reconciles a confirmed prediction before registering the next one, so a keystroke landing between real output and the next paint does not drift a column right", async () => {
		const { renderer, host, core } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		await flushRepaint();
		renderer.predictKey(printable("a"), performance.now());
		feed(core, "a");
		renderer.predictKey(printable("b"), performance.now());
		expect(renderer.predictionCount()).toBe(1);
		const painted = host.querySelectorAll(".terminal-prediction");
		expect(painted).toHaveLength(1);
		expect(painted[0]!.textContent).toBe("b");
	});
});

describe("predictive echo on the alternate screen", () => {
	it("paints at the alt cursor when the alt surface is showing", async () => {
		const { renderer, host, enterAltScreen } = mountRenderer();
		await enterAltScreen();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("paints in whichever surface is showing, never both at once", async () => {
		const { renderer, host, enterAltScreen, leaveAltScreen } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		await enterAltScreen();
		renderer.predictKey(printable("a"), 1000);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
		await leaveAltScreen();
		renderer.predictionsClear();
		renderer.predictKey(printable("b"), 1100);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("drops predictions when the alt screen redraws the whole frame", async () => {
		const { renderer, host, enterAltScreen, feed } = mountRenderer();
		await enterAltScreen();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		renderer.predictKey(printable("a"), performance.now());
		await feed("\u001b[?25h");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
		await feed("\u001b[H\u001b[2J\r\n\r\nprompt> ");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("anchors block-surface predictions at the block cursor after leaving the alt screen, not a stale hidden alt cursor", async () => {
		const { renderer, host, enterAltScreen, leaveAltScreen } = mountRenderer();
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
		await enterAltScreen();
		await leaveAltScreen();

		const staleAltCursor = host.querySelector("[data-terminal-cursor]");
		expect(staleAltCursor).not.toBeNull();
		expect(staleAltCursor?.closest("[hidden]")).not.toBeNull();

		const zeroRect = { x: 0, y: 0, left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0, toJSON: () => ({}) } as DOMRect;
		vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
			if (this.hasAttribute("data-terminal-cursor-cell")) {
				return { x: 0, y: 0, left: 42, top: 24, right: 62, bottom: 44, width: 20, height: 20, toJSON: () => ({}) } as DOMRect;
			}
			if (this.hasAttribute("data-terminal-cursor")) {
				return { x: 0, y: 0, left: 999, top: 999, right: 1019, bottom: 1019, width: 20, height: 20, toJSON: () => ({}) } as DOMRect;
			}
			return zeroRect;
		});

		renderer.predictKey(printable("b"), performance.now());
		const painted = host.querySelector<HTMLElement>(".terminal-prediction");
		expect(painted).not.toBeNull();
		expect(painted!.style.left).toBe("42px");
		expect(painted!.style.top).toBe("24px");
	});
});

describe("predictive echo against real output", () => {
	const armed = (renderer: DomBlockRenderer) => {
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteRoundTrip(0, 107);
	};
	const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

	it("expires an unconfirmed prediction on its own when no further output arrives", async () => {
		const { renderer, host, feed } = mountRenderer();
		await feed("> ");
		armed(renderer);
		renderer.predictKey(printable("a"), performance.now() - 490);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(1);
		await wait(60);
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
	});

	it("confirms an echoed keystroke after scrollback has been trimmed", async () => {
		const { renderer, core, feed } = mountRenderer({ rows: 20, bytes: 1 << 20 });
		let lines = "";
		for (let index = 0; index < 100; index += 1) lines += `line ${index}\r\n`;
		await feed(`${lines}> `);
		expect(core.snapshot().firstStableRow).toBeGreaterThan(0);
		armed(renderer);
		renderer.predictKey(printable("a"), performance.now());
		await feed("a");
		expect(renderer.predictionCount()).toBe(0);
		expect(renderer.predictKey(printable("b"), performance.now())).toBe(true);
	});

	it("confirms a keystroke typed after a wide character on the same line", async () => {
		const { renderer, feed } = mountRenderer();
		await feed("> \u4e16");
		armed(renderer);
		renderer.predictKey(printable("a"), performance.now());
		await feed("a");
		expect(renderer.predictionCount()).toBe(0);
		expect(renderer.predictKey(printable("b"), performance.now())).toBe(true);
	});

	it("drops a prediction the echo contradicts instead of leaving it beside the real text", async () => {
		const { renderer, host, feed } = mountRenderer();
		await feed("> ");
		armed(renderer);
		renderer.predictKey(printable("a"), performance.now());
		await feed("*");
		expect(host.querySelectorAll(".terminal-prediction")).toHaveLength(0);
		expect(renderer.predictKey(printable("b"), performance.now())).toBe(false);
	});

	it("does not take a frame that returns the cursor to the prompt as the keystroke's echo", async () => {
		const { renderer, feed } = mountRenderer();
		await feed("> ");
		renderer.setPredictiveEcho({ thresholdMs: 30 });
		renderer.noteSend(performance.now());
		await feed("\u001b7\u001b[1;10H*\u001b8");
		await wait(50);
		await feed("a");
		expect(renderer.predictKey(printable("b"), performance.now())).toBe(true);
	});
});
