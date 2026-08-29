import { CanvasAddon } from "@xterm/addon-canvas";
import { WebglAddon } from "@xterm/addon-webgl";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";

import type { BenchmarkRenderer, Geometry, RendererKind } from "../harness";

export class XtermBenchmarkRenderer implements BenchmarkRenderer {
	readonly version = "5.5.0";
	private terminal: Terminal | undefined;
	private webgl: WebglAddon | undefined;
	private canvas: CanvasAddon | undefined;
	private contextLossSubscription: { dispose(): void } | undefined;
	private failure: Error | undefined;
	private rendererKind: RendererKind | undefined;

	get kind(): RendererKind {
		this.assertReady();
		return this.rendererKind as RendererKind;
	}

	async mount(host: HTMLElement, geometry: Geometry): Promise<void> {
		const terminal = new Terminal({
			cols: geometry.columns,
			rows: geometry.rows,
			scrollback: geometry.scrollback,
			fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
			fontSize: 12,
		});
		terminal.open(host);
		this.terminal = terminal;
		let webgl: WebglAddon | undefined;
		try {
			webgl = new WebglAddon();
			terminal.loadAddon(webgl);
			this.webgl = webgl;
			this.rendererKind = "webgl";
			this.contextLossSubscription = webgl.onContextLoss(() => this.recoverCanvas());
		} catch {
			try {
				webgl?.dispose();
			} catch {}
			this.recoverCanvas();
		}
	}

	write(bytes: Uint8Array): Promise<void> {
		this.assertReady();
		return new Promise((resolve) => {
			(this.terminal as Terminal).write(bytes, resolve);
		});
	}

	onInput(listener: (data: string) => void): () => void {
		this.assertReady();
		const subscription = (this.terminal as Terminal).onData(listener);
		return () => subscription.dispose();
	}

	waitForPaint(): Promise<number> {
		this.assertReady();
		return new Promise((resolve, reject) => {
			const terminal = this.terminal as Terminal;
			const timeout = window.setTimeout(() => {
				subscription.dispose();
				reject(new Error("xterm did not paint within 10 seconds"));
			}, 10000);
			const subscription = terminal.onRender(() => {
				subscription.dispose();
				requestAnimationFrame((timestamp) => {
					window.clearTimeout(timeout);
					resolve(timestamp);
				});
			});
			terminal.refresh(0, terminal.rows - 1);
		});
	}

	dispatchPrintableKey(data: string): void {
		this.assertReady();
		(this.terminal as Terminal).input(data, true);
	}

	dispose(): void {
		this.contextLossSubscription?.dispose();
		try {
			this.webgl?.dispose();
		} catch {}
		try {
			this.canvas?.dispose();
		} catch {}
		this.terminal?.dispose();
		this.contextLossSubscription = undefined;
		this.webgl = undefined;
		this.canvas = undefined;
		this.terminal = undefined;
		this.rendererKind = undefined;
	}

	private recoverCanvas(): void {
		if (!this.terminal || this.canvas) return;
		try {
			this.contextLossSubscription?.dispose();
			this.contextLossSubscription = undefined;
			try {
				this.webgl?.dispose();
			} catch {}
			this.webgl = undefined;
			const canvas = new CanvasAddon();
			this.terminal.loadAddon(canvas);
			this.canvas = canvas;
			this.rendererKind = "canvas";
		} catch (error) {
			this.failure = error instanceof Error ? error : new Error(String(error));
		}
	}

	private assertReady(): void {
		if (this.failure) throw this.failure;
		if (!this.terminal || !this.rendererKind) throw new Error("xterm renderer is not mounted");
	}
}
