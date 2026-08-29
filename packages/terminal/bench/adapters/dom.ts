import { createTerminalCore, type TerminalCore } from "@operator/terminal-core";
import { initTerminalCoreFromUrl } from "@operator/terminal-core/browser";
import { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import rendererDomPackage from "../../ts/renderer-dom/package.json" with { type: "json" };

import type { BenchmarkRenderer, Geometry, RendererKind } from "../harness";

export class DomBenchmarkRenderer implements BenchmarkRenderer {
	readonly version = String((rendererDomPackage as { version?: string }).version ?? "");
	private core: TerminalCore | undefined;
	private renderer: DomBlockRenderer | undefined;
	private failure: Error | undefined;
	private readonly rendererKind: RendererKind = "canvas";

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
		return new Promise((resolve) => {
			requestAnimationFrame((timestamp) => {
				resolve(timestamp);
			});
		});
	}

	dispatchPrintableKey(_data: string): void {
		this.assertReady();
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
