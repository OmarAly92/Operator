import { createTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
import { LineEditor } from "@operator/terminal-editor";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import rendererDomPackage from "../../ts/renderer-dom/package.json" with { type: "json" };

import type { BenchmarkRenderer, Geometry, RendererKind } from "../harness";

/**
 * The package's own renderer under the benchmark harness.
 *
 * `write` and `waitForPaint` deliberately mirror the xterm adapter's
 * semantics: `write` resolves when the bytes are parsed, and `waitForPaint`
 * resolves on a real paint. Resolving `waitForPaint` on a bare animation
 * frame, as the first version did, reports a frame that fires whether or not
 * anything rendered -- which is how this renderer came to look 54x faster
 * than xterm.
 */
export class DomBenchmarkRenderer implements BenchmarkRenderer {
	readonly version = String((rendererDomPackage as { version?: string }).version ?? "");
	private core: TerminalCore | undefined;
	private renderer: DomBlockRenderer | undefined;
	private editor: LineEditor | undefined;
	private editorRoot: HTMLElement | undefined;
	private editorPaintPending = false;
	private failure: Error | undefined;
	private readonly rendererKind: RendererKind = "dom";

	async mount(host: HTMLElement, geometry: Geometry): Promise<void> {
		try {
			await initTerminalCoreFromUrl();
		} catch (error) {
			this.failure = error instanceof Error ? error : new Error(String(error));
			throw this.failure;
		}
		const core = createTerminalCore({ columns: geometry.columns, scrollback: geometry.scrollback });
		this.core = core;
		const renderer = new DomBlockRenderer();
		renderer.mount(host, core);
		this.renderer = renderer;
		const editor = new LineEditor();
		editor.mount(host, core, { send: () => undefined, sendRaw: () => undefined });
		this.editor = editor;
		this.editorRoot = host.querySelector<HTMLElement>(".terminal-editor") ?? undefined;
		core.feed(new TextEncoder().encode("\x1b]7000;v=1;input-ready=1\x07"));
	}

	write(bytes: Uint8Array): Promise<void> {
		this.assertReady();
		// Mirrors xterm's `terminal.write(bytes, cb)`, whose callback fires
		// when the bytes have been parsed -- not when they have been painted.
		// `core.feed` parses synchronously in WASM, so this is the same point
		// in the pipeline. The paint is measured once at the end of the
		// workload by `waitForPaint`, exactly as it is for xterm.
		return new Promise((resolve, reject) => {
			try {
				(this.core as TerminalCore).feed(bytes);
				resolve();
			} catch (error) {
				reject(error);
			}
		});
	}

	onInput(_listener: (data: string) => void): () => void {
		return () => {};
	}

	waitForPaint(): Promise<number> {
		this.assertReady();
		if (this.editorPaintPending) {
			this.editorPaintPending = false;
			return new Promise((resolve) => requestAnimationFrame(resolve));
		}
		const renderer = this.renderer as DomBlockRenderer;
		return new Promise((resolve, reject) => {
			const timeout = window.setTimeout(() => {
				off();
				reject(new Error("dom renderer did not paint within 10 seconds"));
			}, 10000);
			const off = renderer.onPaint(() => {
				off();
				requestAnimationFrame((timestamp) => {
					window.clearTimeout(timeout);
					resolve(timestamp);
				});
			});
		});
	}

	dispatchPrintableKey(data: string): void {
		this.assertReady();
		this.editorPaintPending = true;
		this.editorRoot?.dispatchEvent(new KeyboardEvent("keydown", { key: data, bubbles: true }));
	}

	dispose(): void {
		try {
			this.editor?.dispose();
		} catch {}
		try {
			this.renderer?.dispose();
		} catch {}
		try {
			this.core?.dispose();
		} catch {}
		this.core = undefined;
		this.renderer = undefined;
		this.editor = undefined;
		this.editorRoot = undefined;
		this.editorPaintPending = false;
	}

	get kind(): RendererKind {
		this.assertReady();
		return this.rendererKind;
	}

	private assertReady(): void {
		if (this.failure) throw this.failure;
		if (!this.core || !this.renderer || !this.editor || !this.editorRoot) {
			throw new Error("dom renderer is not mounted");
		}
	}
}
