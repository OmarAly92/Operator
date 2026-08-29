import { createTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import rendererDomPackage from "../../ts/renderer-dom/package.json" with { type: "json" };

import type { BenchmarkRenderer, Geometry, RendererKind } from "../harness";

/**
 * The package's own renderer under the benchmark harness.
 *
 * `write` and `waitForPaint` deliberately mirror the xterm adapter's
 * semantics. xterm resolves `write` only once the bytes have been processed
 * and reports a real paint through `onRender`; timing this renderer on
 * `core.feed` alone would compare WASM parsing against xterm's parse-plus-
 * render and report a speedup that is an artifact of the harness.
 */
export class DomBenchmarkRenderer implements BenchmarkRenderer {
	readonly version = String((rendererDomPackage as { version?: string }).version ?? "");
	private core: TerminalCore | undefined;
	private renderer: DomBlockRenderer | undefined;
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
	}

	write(bytes: Uint8Array): Promise<void> {
		this.assertReady();
		const renderer = this.renderer as DomBlockRenderer;
		return new Promise((resolve, reject) => {
			const off = renderer.onPaint(() => {
				off();
				resolve();
			});
			try {
				(this.core as TerminalCore).feed(bytes);
			} catch (error) {
				off();
				reject(error);
			}
		});
	}

	onInput(_listener: (data: string) => void): () => void {
		return () => {};
	}

	waitForPaint(): Promise<number> {
		this.assertReady();
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

	dispatchPrintableKey(_data: string): void {
		this.assertReady();
		// This renderer has no input path until Phase 2 adds the editor, so
		// there is nothing here that could be timed. Returning quietly would
		// let the input-latency scenario report the harness's own overhead as
		// a latency number and feed it to the perf gate.
		throw new Error(
			"the DOM renderer has no input path until Phase 2; input-latency is not measurable for it",
		);
	}

	dispose(): void {
		try {
			this.renderer?.dispose();
		} catch {}
		try {
			this.core?.dispose();
		} catch {}
		this.core = undefined;
		this.renderer = undefined;
	}

	get kind(): RendererKind {
		this.assertReady();
		return this.rendererKind;
	}

	private assertReady(): void {
		if (this.failure) throw this.failure;
		if (!this.core || !this.renderer) throw new Error("dom renderer is not mounted");
	}
}
