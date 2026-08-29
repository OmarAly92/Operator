import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { act, cleanup, render, screen } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
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
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} />,
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
			/>,
		);
		rerender(
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				altScreenSurface={<div data-testid="raw-surface" />}
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
			/>,
		);
		expect(screen.getByTestId("terminal-block-list")).toBeInTheDocument();
	});

	it("falls back to the block list when no alt-screen surface is supplied", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive />);
		expect(screen.getByTestId("terminal-block-list")).toBeVisible();
	});
});
