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
});
