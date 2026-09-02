import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore } from "@operator/terminal-core";
import { DomBlockRenderer, terminalStyles } from "@operator/terminal-renderer-dom";
import { TerminalSurface } from "./index";
import {
	feed,
	flushRepaint,
	font,
	ignoreRaw,
	ignoreSend,
	loadWasm,
	renderSurface,
	setHostSize,
	theme,
} from "./surface-harness";

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

	it("leaves the block list unfocusable in the normal buffer, and focusable only in the alt screen", () => {
		// The host carries tabindex only when its alt-screen keydown handler is
		// bound. With tabindex in the normal buffer a click lands focus on the
		// block list instead of the editor, where nothing handles keys: typing
		// does nothing, arrows scroll the list, and the first keypress paints a
		// focus ring around the whole terminal.
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={ignoreRaw} />,
		);
		const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
		expect(host.hasAttribute("tabindex")).toBe(false);

		act(() => {
			feed(core, "\x1b[?1049h");
		});
		expect(host.getAttribute("tabindex")).toBe("0");
	});

	it("puts focus in the editor when the block list is clicked", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={ignoreRaw} />,
		);
		const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		const composition = editor.querySelector("textarea")!;
		expect(document.activeElement).not.toBe(composition);

		fireEvent.click(host);
		expect(document.activeElement).toBe(composition);
	});

	it("does not steal focus into the editor while text is selected in the block list", () => {
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		feed(core, "selectable output");
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={ignoreSend} onSendRaw={ignoreRaw} />,
		);
		const host = screen.getByTestId("terminal-block-list").parentElement as HTMLElement;
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		const selection = document.getSelection()!;
		selection.removeAllRanges();
		const range = document.createRange();
		range.selectNodeContents(host);
		selection.addRange(range);

		fireEvent.click(host);
		expect(document.activeElement).not.toBe(editor);
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

	it("leaves the whole horizontal inset to the block, the way Warp does", () => {
		// Warp's BlockPadding (warp/app/src/terminal/mod.rs) carries padding_top,
		// command_padding_top, middle and bottom and has no horizontal field -- but
		// that does not mean Warp runs flush to the edge, which is what an earlier
		// reading of this concluded. The inset lives one level up, in the terminal
		// view: app/src/terminal/view.rs, PADDING_LEFT = 16. .terminal-block carries
		// that 16px, so the surface must add nothing or the content lands at 20.
		const { surface } = renderSurface();
		expect(surface).toHaveClass("terminal-surface");
		expect(terminalStyles).toContain("--terminal-padding-x: 0px;");
		expect(terminalStyles).toContain("--terminal-padding-y: 0px;");
	});

	it("sizes the grid to the space inside the block padding, not the whole host", () => {
		// The rows are laid out inside .terminal-block, which reserves 16px each
		// side and 2.1 lines top and bottom. Measuring columns against the host's
		// full width tells the shell it has more columns than a row can show, so
		// every full-width line overflows and the pane grows a horizontal
		// scrollbar while appearing narrower than it is.
		const measure = vi.spyOn(DomBlockRenderer.prototype, "measure").mockReturnValue({ cellWidth: 8, cellHeight: 16 });
		const { core, host } = renderSurface();
		const resize = vi.spyOn(core, "resize");
		setHostSize(host, 816, 416);
		expect(resize).toHaveBeenLastCalledWith(98, 23);
		measure.mockRestore();
	});

	it("resizes from the host box, not the surface around it", () => {
		// Geometry follows the host the renderer measures, less the block's inset:
		// (808 - 32) / 8 = 97 columns, (408 - 2.1 * 16) / 16 = 23 rows.
		const measure = vi.spyOn(DomBlockRenderer.prototype, "measure").mockReturnValue({ cellWidth: 8, cellHeight: 16 });
		const { core, host, surface } = renderSurface();
		Object.defineProperty(surface, "clientWidth", { value: 808, configurable: true });
		Object.defineProperty(surface, "clientHeight", { value: 408, configurable: true });
		const resize = vi.spyOn(core, "resize");
		setHostSize(host, 808, 408);
		expect(host.clientWidth).toBe(808);
		expect(resize).toHaveBeenLastCalledWith(97, 23);
		measure.mockRestore();
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


	it("takes focus when the alternate screen opens and gives it back on leave", () => {
		const { container, core } = renderSurface();
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const host = container.querySelector(".terminal-host") as HTMLElement;
		expect(document.activeElement).toBe(host.querySelector("textarea"));
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

	it("sends composed text once and swallows the composing keydown", () => {
		const onSendRaw = vi.fn();
		const { container, core } = renderSurface({ onSendRaw });
		act(() => {
			feed(core, "\x1b[?1049h");
		});
		const host = container.querySelector(".terminal-host") as HTMLElement;
		const textarea = host.querySelector("textarea");
		expect(textarea).not.toBeNull();
		host.dispatchEvent(new KeyboardEvent("keydown", { key: "Process", keyCode: 229, bubbles: true }));
		expect(onSendRaw).not.toHaveBeenCalled();
		textarea!.dispatchEvent(new CompositionEvent("compositionend", { data: "日本" }));
		expect(onSendRaw).toHaveBeenCalledExactlyOnceWith("日本");
	});
});
