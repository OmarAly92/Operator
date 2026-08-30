import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
	createTerminalCore,
	initTerminalCore,
	type FontConfig,
	type TerminalCore,
	type TerminalTheme,
} from "@operator/terminal-core";
import { TerminalSurface, warpDarkTheme } from "./index";

const wasmPath = join(
	dirname(fileURLToPath(import.meta.url)),
	"..",
	"..",
	"core",
	"wasm",
	"vt_core_bg.wasm",
);

const font: FontConfig = {
	family: "ui-monospace, monospace",
	sizePx: 14,
	lineHeight: 1.2,
	weight: 400,
	letterSpacingPx: 0,
	ligatures: false,
};

const theme: TerminalTheme = warpDarkTheme;
const ignoreSend = () => undefined;
const ignoreRaw = () => undefined;

async function loadWasm(): Promise<void> {
	const bytes = await readFile(wasmPath);
	const wasmBytes = bytes.buffer.slice(
		bytes.byteOffset,
		bytes.byteOffset + bytes.byteLength,
	) as ArrayBuffer;
	await initTerminalCore(wasmBytes);
}

function feed(core: TerminalCore, text: string): void {
	core.feed(new TextEncoder().encode(text));
}

function flushRepaint(): Promise<void> {
	return new Promise((resolve) => {
		requestAnimationFrame(() => resolve());
	});
}

function renderSurface(
	overrides: {
		onGeometry?: (columns: number, rows: number) => void;
		onSend?: (text: string) => void;
		onSendRaw?: (data: string) => void;
	} = {},
) {
	const core = createTerminalCore({ columns: 16, scrollback: 100 });
	const result = render(
		<TerminalSurface
			core={core}
			theme={theme}
			font={font}
			altScreenActive={false}
			onSend={overrides.onSend ?? ignoreSend}
			onSendRaw={overrides.onSendRaw ?? ignoreRaw}
			onGeometry={overrides.onGeometry}
		/>,
	);
	const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
	return { core, host, ...result };
}

function setHostSize(host: HTMLElement, width: number, height: number): void {
	Object.defineProperty(host, "clientWidth", { value: width, configurable: true });
	Object.defineProperty(host, "clientHeight", { value: height, configurable: true });
	host.dispatchEvent(new Event("resize"));
}

describe("TerminalSurface", () => {
	beforeAll(loadWasm);
	afterEach(() => {
		cleanup();
	});
	afterAll(() => undefined);

	it("mounts a synthetic block, repaints on feed, and stops touching the host after unmount", async () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "first");
		const { container, unmount } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={ignoreRaw} />,
		);

		const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
		expect(host).not.toBeNull();
		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(1);
		expect(host.textContent).toBe("first");

		act(() => {
			feed(core, " second");
		});
		await flushRepaint();
		expect(host.textContent).toBe("first second");

		const root = container.firstElementChild as HTMLElement;
		unmount();
		expect(root.parentNode).toBeNull();

		feed(core, " third");
		expect(host.querySelectorAll('[data-terminal-block-id="0:0"]')).toHaveLength(0);
	});

	it("applies a className passthrough and exposes theme + font CSS variables", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "alpha");
		render(
			<TerminalSurface
				className="pane"
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
		expect(host.classList.contains("pane")).toBe(true);
		const block = host.querySelector('[data-terminal-block-id="0:0"]') as HTMLElement;
		const styleAttr = block.getAttribute("style") ?? "";
		expect(styleAttr).toContain("--terminal-foreground:");
		expect(styleAttr).toContain("--terminal-font-family:");
	});

	it("shows the alt-screen surface instead of the block list when active", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive
				altScreenSurface={<div data-testid="raw-surface" />}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		expect(screen.getByTestId("raw-surface")).toBeVisible();
		expect(screen.getByTestId("terminal-block-list")).not.toBeVisible();
	});

	it("returns to the block list when the alt screen exits", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { rerender } = render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive
				altScreenSurface={<div data-testid="raw-surface" />}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		rerender(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				altScreenSurface={<div data-testid="raw-surface" />}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		expect(screen.getByTestId("terminal-block-list")).toBeVisible();
	});

	it("keeps the block list mounted while the alt screen is active", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive
				altScreenSurface={<div data-testid="raw-surface" />}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		expect(screen.getByTestId("terminal-block-list")).toBeInTheDocument();
	});

	it("falls back to the block list when no alt-screen surface is supplied", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive onSend={ignoreSend} onSendRaw={ignoreRaw} />);
		expect(screen.getByTestId("terminal-block-list")).toBeVisible();
	});

	it("mounts the editor below the block list and hides both in the alt screen", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container, rerender } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={ignoreRaw} />,
		);
		const blockList = screen.getByTestId("terminal-block-list");
		const editor = container.querySelector<HTMLElement>(".terminal-editor");
		expect(editor).not.toBeNull();
		expect(blockList.compareDocumentPosition(editor!) & Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
		rerender(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive
				altScreenSurface={<div data-testid="raw-surface" />}
				onSend={ignoreSend}
				onSendRaw={ignoreRaw}
			/>,
		);
		expect(editor).not.toBeVisible();
	});

	it("sends bare submitted text through onSend", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "\x1b]7000;v=1;input-ready=1\x07");
		const onSend = vi.fn();
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} />,
		);
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		for (const key of "make test") fireEvent.keyDown(editor, { key });
		fireEvent.keyDown(editor, { key: "Enter" });
		expect(onSend).toHaveBeenCalledWith("make test");
		expect(onSend.mock.calls[0]?.[0]).not.toContain("\x1b");
		expect(onSend.mock.calls[0]?.[0]).not.toContain("\n");
	});

	it("prefills rerun without submitting", async () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "\x1b]133;A\x07\x1b]7000;v=1;cmd=git%20status\x07\x1b]133;C\x07ok\n\x1b]133;D;0\x07\x1b]7000;v=1;input-ready=1\x07");
		const onSend = vi.fn();
		const host = {
			writeClipboard: vi.fn().mockResolvedValue(undefined),
			readClipboard: vi.fn().mockResolvedValue(""),
			openLink: vi.fn().mockResolvedValue(undefined),
		};
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} host={host} />,
		);
		await flushRepaint();
		fireEvent.click(container.querySelector<HTMLButtonElement>("[data-action='rerun']")!);
		expect(container.querySelector(".terminal-editor-line")?.textContent).toContain("git status");
		expect(onSend).not.toHaveBeenCalled();
	});

	it("resizes the core to the measured geometry", () => {
		const { core, host } = renderSurface();
		const resize = vi.spyOn(core, "resize");
		setHostSize(host, 1000, 500);
		expect(resize).toHaveBeenCalled();
		const [columns, rows] = resize.mock.calls.at(-1)!;
		expect(columns).toBeGreaterThan(0);
		expect(rows).toBeGreaterThan(0);
	});

	it("does not resize when the measured geometry has not changed", () => {
		const { core, host } = renderSurface();
		setHostSize(host, 1000, 500);
		const resize = vi.spyOn(core, "resize");
		setHostSize(host, 1000, 500);
		expect(resize).not.toHaveBeenCalled();
	});

	it("hides the editor while the alternate screen is active", () => {
		const { container, core } = renderSurface();
		expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(false);
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(true);
	});

	it("sends alternate-screen keystrokes raw and never as a submitted line", () => {
		const onSend = vi.fn();
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSend, onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "a", bubbles: true }));
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
		expect(onSend).not.toHaveBeenCalled();
		expect(onSendRaw).toHaveBeenNthCalledWith(1, "a");
		expect(onSendRaw).toHaveBeenNthCalledWith(2, "\r");
	});

	it("encodes arrows as CSI while application cursor keys are off", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }));
		expect(onSendRaw).toHaveBeenCalledWith("\x1b[A");
	});

	it("encodes arrows as SS3 once the program sets application cursor keys", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[?1h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }));
		expect(onSendRaw).toHaveBeenCalledWith("\x1bOA");
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }));
		expect(onSendRaw).toHaveBeenCalledWith("\x1bOB");
	});

	it("sends the whole recorded agent-cli frame's worth of state through correctly", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h\x1b[22;0;0t\x1b[?1h\x1b=\x1b[H\x1b[2J");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true }));
		expect(onSendRaw).toHaveBeenCalledWith("\x1bOD");
	});

	it("turns the wheel into arrow keys instead of scrolling nothing", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw).toHaveBeenCalled();
		expect(onSendRaw.mock.calls.at(-1)![0]).toMatch(/^(\x1bOB|\x1b\[B)+$/);
	});

	it("does not turn the wheel into keys outside the alternate screen", () => {
		const onSendRaw = vi.fn();
		const { container } = renderSurface({ onSendRaw });
		const surface = container.querySelector(".terminal-host") as HTMLElement;
		surface.dispatchEvent(new WheelEvent("wheel", { deltaY: 120, bubbles: true, cancelable: true }));
		expect(onSendRaw).not.toHaveBeenCalled();
	});

	it("takes focus when the alternate screen opens and gives it back on leave", () => {
		const { container, core } = renderSurface();
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		expect(document.activeElement).toBe(container.querySelector(".terminal-host"));
		act(() => {
			feed(core, "\x1b[?1049l");
		});
		expect(container.querySelector(".terminal-editor-host")?.hasAttribute("hidden")).toBe(false);
	});

	it("returns to the block list when the program leaves the alternate screen", async () => {
		const { container, core } = renderSurface();
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		await flushRepaint();
		expect(container.querySelector("[data-terminal-alt-surface]")).not.toBeNull();
		act(() => {
			feed(core, "\x1b[?1049l");
		});
		await flushRepaint();
		const surface = container.querySelector("[data-terminal-alt-surface]") as HTMLElement | null;
		expect(surface === null || surface.hidden).toBe(true);
	});
});
