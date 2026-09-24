import { act, cleanup, render } from "@testing-library/react";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { createTerminalCore, type HostCapabilities } from "@operator/terminal-core";
import { LineEditor } from "@operator/terminal-editor";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import { TerminalSurface } from "./index";
import {
	feed,
	flushRepaint,
	font,
	ignoreRaw,
	ignoreSend,
	loadWasm,
	renderSurface,
	theme,
} from "./surface-harness";

describe("TerminalSurface", () => {
	beforeAll(loadWasm);
	afterEach(() => {
		cleanup();
	});
	afterAll(() => undefined);

	it("forwards the features prop to the renderer and puts the core in grapheme mode by default", () => {
		const setFeatures = vi.spyOn(DomBlockRenderer.prototype, "setFeatures");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { rerender } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
		);
		expect(setFeatures).toHaveBeenLastCalledWith({});
		expect(core.graphemeClusters()).toBe(true);
		rerender(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} features={{ attributes: "warp" }} />,
		);
		expect(setFeatures).toHaveBeenLastCalledWith({ attributes: "warp" });
		rerender(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} features={{ graphemes: false, widthCache: false }} />,
		);
		expect(core.graphemeClusters()).toBe(false);
		setFeatures.mockRestore();
	});

	it("keeps the features on a renderer the surface rebuilds for a new onSend", () => {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const setFeatures = vi.spyOn(DomBlockRenderer.prototype, "setFeatures");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const surfaceWith = (onSend: () => void) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={onSend} onSendRaw={ignoreRaw} features={{ attributes: "warp" }} />
		);
		const { rerender } = render(surfaceWith(() => undefined));
		const first = mount.mock.contexts.at(-1);
		setFeatures.mockClear();
		rerender(surfaceWith(() => undefined));
		const rebuilt = mount.mock.contexts.at(-1);
		expect(rebuilt).not.toBe(first);
		expect(setFeatures).toHaveBeenLastCalledWith({ attributes: "warp" });
		expect(setFeatures.mock.contexts.at(-1)).toBe(rebuilt);
		mount.mockRestore();
		setFeatures.mockRestore();
	});

	it("forwards onBlockFinished from the renderer", () => {
		const onBlockFinished = vi.fn();
		const listen = vi.spyOn(DomBlockRenderer.prototype, "onBlockFinished");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} onBlockFinished={onBlockFinished} />,
		);
		expect(listen).toHaveBeenCalledTimes(1);
		const listener = listen.mock.calls[0]![0] as (event: unknown) => void;
		listener({ id: "0:1", exitCode: 0, durationMs: 5, visible: true });
		expect(onBlockFinished).toHaveBeenCalledWith({ id: "0:1", exitCode: 0, durationMs: 5, visible: true });
		listen.mockRestore();
	});

	it("tells the renderer when focus enters and leaves the surface", () => {
		const setFocused = vi.spyOn(DomBlockRenderer.prototype, "setFocused");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const { container } = render(
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} onSend={() => undefined} onSendRaw={() => undefined} />,
		);
		const editor = container.querySelector<HTMLElement>(".terminal-editor")!;
		act(() => editor.focus());
		expect(setFocused).toHaveBeenLastCalledWith(true);
		act(() => editor.blur());
		expect(setFocused).toHaveBeenLastCalledWith(false);
		setFocused.mockRestore();
	});

	it("hands the host's visibility to the renderer", () => {
		const spy = vi.spyOn(DomBlockRenderer.prototype, "setVisible");
		const { setVisible } = renderSurface({ visible: false });
		expect(spy).toHaveBeenLastCalledWith(false);
		setVisible(true);
		expect(spy).toHaveBeenLastCalledWith(true);
		setVisible(undefined);
		expect(spy).toHaveBeenLastCalledWith(null);
		spy.mockRestore();
	});

	it("hands the host's visibility to the line editor", () => {
		const spy = vi.spyOn(LineEditor.prototype, "setVisible");
		const { setVisible } = renderSurface({ visible: false });
		expect(spy).toHaveBeenLastCalledWith(false);
		setVisible(true);
		expect(spy).toHaveBeenLastCalledWith(true);
		setVisible(undefined);
		expect(spy).toHaveBeenLastCalledWith(true);
		spy.mockRestore();
	});

	it("mounts a fresh renderer and editor already hidden when the mount effect reruns while parked", () => {
		const rendererSpy = vi.spyOn(DomBlockRenderer.prototype, "setVisible");
		const editorSpy = vi.spyOn(LineEditor.prototype, "setVisible");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const surfaceWith = (onSend: () => void) => (
			<TerminalSurface
				core={core}
				theme={theme}
				font={font}
				altScreenActive={false}
				onSend={onSend}
				onSendRaw={ignoreRaw}
				visible={false}
			/>
		);
		const { rerender } = render(surfaceWith(() => undefined));
		rendererSpy.mockClear();
		editorSpy.mockClear();
		const repaint = vi.spyOn(DomBlockRenderer.prototype as unknown as { repaint(): void }, "repaint");
		rerender(surfaceWith(() => undefined));
		expect(rendererSpy).toHaveBeenLastCalledWith(false);
		expect(editorSpy).toHaveBeenLastCalledWith(false);
		expect(repaint).not.toHaveBeenCalled();
		repaint.mockRestore();
		rendererSpy.mockRestore();
		editorSpy.mockRestore();
	});

	async function mountAltSurface(extra: Partial<HostCapabilities>) {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const host: HostCapabilities = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, ...extra };
		const result = renderSurface({ host });
		const renderer = mount.mock.contexts[0] as DomBlockRenderer;
		mount.mockRestore();
		act(() => {
			feed(result.core, "\x1b[?1049h");
		});
		await flushRepaint();
		const surface = result.host;
		const typeKey = (key: string, modifiers: KeyboardEventInit = {}) => {
			act(() => {
				surface.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, ...modifiers }));
			});
		};
		return { renderer, surface, typeKey, core: result.core, unmountSurface: result.unmount };
	}

	it("predicts a printable keystroke on the alternate screen when the host set a threshold", async () => {
		const { renderer, surface, typeKey } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
		renderer.noteRoundTrip(0, 107);
		typeKey("a");
		expect(renderer.predictionCount()).toBe(1);
		expect(surface.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("predicts nothing when the host set no threshold", async () => {
		const { renderer, typeKey } = await mountAltSurface({});
		renderer.noteRoundTrip(0, 107);
		typeKey("a");
		expect(renderer.predictionCount()).toBe(0);
	});

	it("does not predict the copy chord or a control key", async () => {
		const { renderer, typeKey } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
		renderer.noteRoundTrip(0, 107);
		typeKey("c", { metaKey: true });
		typeKey("c", { ctrlKey: true, shiftKey: true });
		typeKey("Enter");
		expect(renderer.predictionCount()).toBe(0);
	});

	it("clears predictions when the pane tears down", async () => {
		const { renderer, typeKey, unmountSurface } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
		renderer.noteRoundTrip(0, 107);
		typeKey("a");
		expect(renderer.predictionCount()).toBe(1);
		unmountSurface();
		expect(renderer.predictionCount()).toBe(0);
	});

	it("arms from the round trip between a keystroke and the output it produces", async () => {
		const { renderer, typeKey, core } = await mountAltSurface({ predictiveEcho: { thresholdMs: 30 } });
		const now = vi.spyOn(performance, "now").mockReturnValue(1000);
		typeKey("a");
		expect(renderer.predictionCount()).toBe(0);
		now.mockReturnValue(1107);
		act(() => {
			feed(core, "a");
		});
		now.mockReturnValue(1120);
		typeKey("b");
		now.mockRestore();
		expect(renderer.predictionCount()).toBe(1);
	});

	async function mountPrimarySurface(extra: Partial<HostCapabilities>) {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const onSendRaw = vi.fn();
		const host: HostCapabilities = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, ...extra };
		const result = renderSurface({ host, onSendRaw });
		const renderer = mount.mock.contexts[0] as DomBlockRenderer;
		mount.mockRestore();
		act(() => {
			feed(result.core, "> ");
		});
		await flushRepaint();
		const editor = result.host.parentElement!.querySelector<HTMLElement>(".terminal-editor")!;
		const typeKey = (key: string, modifiers: KeyboardEventInit = {}) => {
			act(() => {
				editor.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true, ...modifiers }));
			});
		};
		return { renderer, surface: result.host, typeKey, core: result.core, onSendRaw };
	}

	it("predicts a keystroke the line editor passes through to a child on the primary screen", async () => {
		const { renderer, surface, typeKey, core, onSendRaw } = await mountPrimarySurface({ predictiveEcho: { thresholdMs: 30 } });
		expect(core.snapshot().altScreen).toBeNull();
		renderer.noteRoundTrip(0, 107);
		typeKey("a");
		expect(onSendRaw).toHaveBeenCalledWith("a");
		expect(renderer.predictionCount()).toBe(1);
		expect(surface.querySelectorAll(".terminal-prediction")).toHaveLength(1);
	});

	it("does not predict on the primary screen while the line editor owns the line", async () => {
		const { renderer, typeKey, core, onSendRaw } = await mountPrimarySurface({ predictiveEcho: { thresholdMs: 30 } });
		act(() => {
			feed(core, "\x1b]7000;v=1;input-ready=1\x07");
		});
		await flushRepaint();
		renderer.noteRoundTrip(0, 107);
		typeKey("a");
		expect(onSendRaw).not.toHaveBeenCalled();
		expect(renderer.predictionCount()).toBe(0);
	});

	it("keeps Claude Code on the primary screen, so the primary path is the one that must predict", async () => {
		const recording = await readFile(join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "bench", "agent-session", "fixtures", "claude-spinner-10s", "recording"));
		const core = createTerminalCore({ columns: 120, scrollback: 1000 });
		core.feed(new Uint8Array(recording));
		expect(core.snapshot().altScreen).toBeNull();
	});

	it("passes the host's predictive-echo threshold to the renderer and null when there is none", () => {
		const setPredictiveEcho = vi.spyOn(DomBlockRenderer.prototype, "setPredictiveEcho");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const base = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {} };
		const { rerender } = render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} host={base} onSend={ignoreSend} onSendRaw={ignoreRaw} />);
		expect(setPredictiveEcho).toHaveBeenLastCalledWith(null);
		rerender(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} host={{ ...base, predictiveEcho: { thresholdMs: 30 } }} onSend={ignoreSend} onSendRaw={ignoreRaw} />);
		expect(setPredictiveEcho).toHaveBeenLastCalledWith({ thresholdMs: 30 });
		setPredictiveEcho.mockRestore();
	});

	it("keeps the predictive-echo threshold on a renderer the surface rebuilds", () => {
		const setPredictiveEcho = vi.spyOn(DomBlockRenderer.prototype, "setPredictiveEcho");
		const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, predictiveEcho: { thresholdMs: 30 } };
		const { rebuild } = renderSurface({ host });
		setPredictiveEcho.mockClear();
		rebuild();
		expect(setPredictiveEcho).toHaveBeenLastCalledWith({ thresholdMs: 30 });
		setPredictiveEcho.mockRestore();
	});

	it("passes the host's secret patterns to the renderer and nothing when there are none", () => {
		const setSecretPatterns = vi.spyOn(DomBlockRenderer.prototype, "setSecretPatterns");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, secretPatterns: [{ source: "x" }] };
		render(<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} host={host} onSend={() => undefined} onSendRaw={() => undefined} />);
		expect(setSecretPatterns).toHaveBeenLastCalledWith([{ source: "x" }]);
		setSecretPatterns.mockRestore();
	});

	it("keeps the secret patterns on a renderer the surface rebuilds for a new onSend", () => {
		const mount = vi.spyOn(DomBlockRenderer.prototype, "mount");
		const setSecretPatterns = vi.spyOn(DomBlockRenderer.prototype, "setSecretPatterns");
		const core = createTerminalCore({ columns: 16, scrollback: 100 });
		const host = { writeClipboard: async () => {}, readClipboard: async () => "", openLink: async () => {}, secretPatterns: [{ source: "x" }] };
		const surfaceWith = (onSend: () => void) => (
			<TerminalSurface core={core} theme={theme} font={font} altScreenActive={false} host={host} onSend={onSend} onSendRaw={ignoreRaw} />
		);
		const { rerender } = render(surfaceWith(() => undefined));
		const first = mount.mock.contexts.at(-1);
		setSecretPatterns.mockClear();
		rerender(surfaceWith(() => undefined));
		const rebuilt = mount.mock.contexts.at(-1);
		expect(rebuilt).not.toBe(first);
		expect(setSecretPatterns).toHaveBeenLastCalledWith([{ source: "x" }]);
		expect(setSecretPatterns.mock.contexts.at(-1)).toBe(rebuilt);
		mount.mockRestore();
		setSecretPatterns.mockRestore();
	});
});
