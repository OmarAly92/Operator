import { act, render, screen, waitFor } from "@testing-library/react";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { TerminalMux } from "../../src/renderer/lib/terminal-mux";
import { SkinProvider } from "../../src/renderer/theme/skin-context";
import {
	TerminalBenchmarkHarness,
	terminalHarnessConfiguration,
	type TerminalAcknowledgement,
} from "./harness";

type RenderListener = () => void;

const xtermState = vi.hoisted(() => ({
	contextLoss: undefined as (() => void) | undefined,
	fitColumns: 120,
	fitRows: 40,
	lastTerminal: null as null | {
		cols: number;
		rows: number;
		written: Uint8Array[];
		writeCallbacks: Array<() => void>;
		renderListeners: Set<RenderListener>;
		disposed: boolean;
	},
}));

vi.mock("@xterm/xterm", () => ({
	Terminal: class FakeTerminal {
		cols: number;
		rows: number;
		written: Uint8Array[] = [];
		writeCallbacks: Array<() => void> = [];
		renderListeners = new Set<RenderListener>();
		disposed = false;
		options: Record<string, unknown>;
		modes = { bracketedPasteMode: false, mouseTrackingMode: "none" };
		buffer = { active: { type: "normal" } };
		unicode = { activeVersion: "" };
		_core = {
			element: { classList: { add: vi.fn(), remove: vi.fn() } },
			viewport: { scrollBarWidth: 15 },
			_selectionService: { enable: vi.fn(), shouldForceSelection: () => false },
		};

		constructor(options: Record<string, unknown>) {
			this.options = options;
			this.cols = options.cols as number;
			this.rows = options.rows as number;
			xtermState.lastTerminal = this;
		}

		loadAddon(addon: { activate?: (terminal: FakeTerminal) => void }) {
			addon.activate?.(this);
		}
		open(host: HTMLElement) {
			const terminal = document.createElement("div");
			terminal.className = "xterm";
			host.appendChild(terminal);
		}
		write(bytes: Uint8Array, done?: () => void) {
			this.written.push(bytes);
			if (done) this.writeCallbacks.push(done);
		}
		writeln() {}
		refresh() {}
		focus() {}
		clear() {}
		selectAll() {}
		hasSelection() {
			return false;
		}
		getSelection() {
			return "";
		}
		scrollLines() {}
		scrollToBottom() {}
		attachCustomKeyEventHandler() {}
		attachCustomWheelEventHandler() {}
		onData() {
			return { dispose: () => undefined };
		}
		onKey() {
			return { dispose: () => undefined };
		}
		onSelectionChange() {
			return { dispose: () => undefined };
		}
		onResize() {
			return { dispose: () => undefined };
		}
		onRender(listener: RenderListener) {
			this.renderListeners.add(listener);
			return { dispose: () => this.renderListeners.delete(listener) };
		}
		dispose() {
			this.disposed = true;
		}
	},
}));

vi.mock("@xterm/addon-fit", () => ({
	FitAddon: class FakeFitAddon {
		terminal?: { cols: number; rows: number };
		activate(terminal: { cols: number; rows: number }) {
			this.terminal = terminal;
		}
		fit() {
			if (!this.terminal) return;
			this.terminal.cols = xtermState.fitColumns;
			this.terminal.rows = xtermState.fitRows;
		}
		proposeDimensions() {
			return this.terminal ? { cols: this.terminal.cols, rows: this.terminal.rows } : undefined;
		}
	},
}));

vi.mock("@xterm/addon-search", () => ({ SearchAddon: class FakeSearchAddon {} }));
vi.mock("@xterm/addon-unicode11", () => ({ Unicode11Addon: class FakeUnicode11Addon {} }));
vi.mock("@xterm/addon-web-links", () => ({ WebLinksAddon: class FakeWebLinksAddon {} }));
vi.mock("@xterm/addon-canvas", () => ({ CanvasAddon: class FakeCanvasAddon {} }));
vi.mock("@xterm/addon-webgl", () => ({
	WebglAddon: class FakeWebglAddon {
		onContextLoss(listener: () => void) {
			xtermState.contextLoss = listener;
		}
		dispose() {}
	},
}));

function emitRender(timestamp: number) {
	vi.spyOn(performance, "now").mockReturnValue(timestamp);
	for (const listener of [...(xtermState.lastTerminal?.renderListeners ?? [])]) listener();
}

function completeWrite() {
	xtermState.lastTerminal?.writeCallbacks.shift()?.();
}

function fakeMux(): TerminalMux & {
	emitConnection: (state: "open" | "closed") => void;
	emitData: (bytes: Uint8Array) => void;
	emitOpened: () => void;
} {
	let dataListener: ((bytes: Uint8Array) => void) | undefined;
	let openedListener: (() => void) | undefined;
	let connectionListener: ((state: "open" | "closed") => void) | undefined;
	return {
		open: vi.fn(),
		sendInput: vi.fn(),
		resize: vi.fn(),
		close: vi.fn(),
		onData: vi.fn((_id, listener) => {
			dataListener = listener;
			return vi.fn();
		}),
		onExit: vi.fn(() => vi.fn()),
		onOpened: vi.fn((_id, listener) => {
			openedListener = listener;
			return vi.fn();
		}),
		onError: vi.fn(() => vi.fn()),
		onConnectionChange: vi.fn((listener) => {
			connectionListener = listener;
			return vi.fn();
		}),
		dispose: vi.fn(),
		emitConnection: (state) => connectionListener?.(state),
		emitData: (bytes) => dataListener?.(bytes),
		emitOpened: () => openedListener?.(),
	};
}

function configuration() {
	return terminalHarnessConfiguration(
		"?daemonBaseUrl=http%3A%2F%2F127.0.0.1%3A4317&sessionId=session-1&terminalId=terminal-1",
	);
}

function renderHarness(
	mux: ReturnType<typeof fakeMux>,
	acknowledgements: TerminalAcknowledgement[] = [],
) {
	return render(
		<SkinProvider>
			<TerminalBenchmarkHarness
				configuration={configuration()}
				createMux={() => mux}
				onAcknowledgement={(acknowledgement) => acknowledgements.push(acknowledgement)}
			/>
		</SkinProvider>,
	);
}

function runLargeOutput() {
	window.dispatchEvent(
		new CustomEvent("operator:terminal-benchmark-run", {
			detail: { scenario: "large-output", iteration: 0 },
		}),
	);
}

describe("terminal benchmark harness", () => {
	beforeEach(() => {
		xtermState.contextLoss = undefined;
		xtermState.fitColumns = 120;
		xtermState.fitRows = 40;
		xtermState.lastTerminal = null;
		vi.restoreAllMocks();
	});

	it.each([
		["IPv4", "http://127.0.0.1:4317", "http://127.0.0.1:4317/"],
		["localhost", "https://localhost:4317/path?secret=value", "https://localhost:4317/"],
		["IPv6", "http://[::1]:4317/path", "http://[::1]:4317/"],
	])("accepts an exact loopback %s daemon URL", (_label, daemonBaseUrl, expected) => {
		const query = new URLSearchParams({ daemonBaseUrl, sessionId: "session-1", terminalId: "terminal-1" });

		expect(terminalHarnessConfiguration(`?${query}`).daemonBaseUrl).toBe(expected);
	});

	it.each([
		"https://operator.dev",
		"http://127.0.0.1.evil.example:4317",
		"ftp://127.0.0.1:4317",
		"http://user@127.0.0.1:4317",
		"http://user:password@localhost:4317",
	])("refuses an unsafe daemon URL: %s", (daemonBaseUrl) => {
		const query = new URLSearchParams({ daemonBaseUrl, sessionId: "session-1", terminalId: "terminal-1" });

		expect(() => terminalHarnessConfiguration(`?${query}`)).toThrow(/loopback HTTP\(S\)/);
	});

	it("accepts both target webview shells in the benchmark driver", () => {
		const moduleUrl = pathToFileURL(path.resolve(process.cwd(), "scripts/benchmark-terminal.mjs")).href;
		const script = `const { parseTerminalArguments } = await import(${JSON.stringify(moduleUrl)}); process.stdout.write(JSON.stringify([parseTerminalArguments(["--shell", "electron", "--scenario", "vtebench"]), parseTerminalArguments(["--shell", "tauri", "--scenario", "large-output"])]));`;
		const stdout = execFileSync(process.execPath, ["--input-type=module", "--eval", script], { encoding: "utf8" });

		expect(JSON.parse(stdout)).toEqual([
			{ shell: "electron", scenario: "vtebench" },
			{ shell: "tauri", scenario: "large-output" },
		]);
	});

	it("validates Tauri daemon URLs before launching the native harness", () => {
		const moduleUrl = pathToFileURL(path.resolve(process.cwd(), "scripts/benchmark-terminal.mjs")).href;
		const script = `const { tauriDaemonUrl } = await import(${JSON.stringify(moduleUrl)}); const urls = ["http://127.0.0.1:4317/path", "https://localhost:4317/path", "http://[::1]:4317/path", "http://127.0.0.1.evil.example:4317", "http://user@127.0.0.1:4317", "http://user:password@localhost:4317", "file://127.0.0.1/path"]; process.stdout.write(JSON.stringify(urls.map((url) => { try { return tauriDaemonUrl({OPERATOR_BENCH_DAEMON_URL:url}); } catch { return "rejected"; } })));`;
		const stdout = execFileSync(process.execPath, ["--input-type=module", "--eval", script], { encoding: "utf8" });

		expect(JSON.parse(stdout)).toEqual([
			"http://127.0.0.1:4317/",
			"https://localhost:4317/",
			"http://[::1]:4317/",
			"rejected",
			"rejected",
			"rejected",
			"rejected",
		]);
	});

	it("keeps Tauri evidence non-binding and derives durations from timestamp-only messages", () => {
		const moduleUrl = pathToFileURL(path.resolve(process.cwd(), "scripts/benchmark-terminal.mjs")).href;
		const script = `const module = await import(${JSON.stringify(moduleUrl)}); let rejected = false; try { module.terminalAcknowledgementDurations([{name:"workload-start",timestamp:1,content:"forbidden"},{name:"workload",timestamp:2}]); } catch { rejected = true; } process.stdout.write(JSON.stringify({profile:module.tauriTerminalEvidenceProfile({}),durations:module.terminalAcknowledgementDurations([{name:"workload",timestamp:25},{name:"workload-start",timestamp:10},{name:"workload",timestamp:70},{name:"workload-start",timestamp:40}]),rejected}));`;
		const stdout = execFileSync(process.execPath, ["--input-type=module", "--eval", script], { encoding: "utf8" });

		expect(JSON.parse(stdout)).toEqual({
			profile: {
				buildProfile: "local-tauri-webview-non-binding",
				evidenceScope: "non-binding",
				runtimeAttestation: "tauri-dev-webview",
			},
			durations: [15, 30],
			rejected: true,
		});
	});

	it("uses the shared terminal scenario geometry", () => {
		expect(configuration()).toEqual({
			daemonBaseUrl: "http://127.0.0.1:4317/",
			sessionId: "session-1",
			terminalId: "terminal-1",
			columns: 120,
			rows: 40,
			scrollback: 5000,
		});
	});

	it("mounts the real production terminal on the live mux boundary", async () => {
		const mux = fakeMux();

		renderHarness(mux);

		const root = await screen.findByLabelText("Terminal benchmark for session-1");
		expect(root.querySelector(".xterm")).toBeInTheDocument();
		await waitFor(() => expect(mux.open).toHaveBeenCalledWith("terminal-1", 120, 40));
	});

	it("does not arm workload completion until the marker write finishes", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		renderHarness(mux, acknowledgements);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());

		act(() => mux.emitData(new TextEncoder().encode("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__")));
		act(runLargeOutput);
		act(() => mux.emitData(new TextEncoder().encode("secret terminal output__OPERATOR_TERMINAL_WORKLOAD_")));
		act(() => mux.emitData(new TextEncoder().encode("COMPLETE__")));
		act(() => emitRender(200));

		expect(acknowledgements.some(({ name }) => name === "workload")).toBe(false);
		act(completeWrite);
		act(() => emitRender(300));
		expect(acknowledgements).toContainEqual({ name: "workload", timestamp: 300 });
		expect(acknowledgements.every((acknowledgement) => Object.keys(acknowledgement).sort().join(",") === "name,timestamp")).toBe(true);
		expect(JSON.stringify(acknowledgements)).not.toContain("secret terminal output");
	});

	it("builds the fixed Windows output workload without echoing the completion marker", async () => {
		const defaultUserAgent = navigator.userAgent;
		Object.defineProperty(navigator, "userAgent", { configurable: true, value: "Windows" });
		const mux = fakeMux();
		try {
			renderHarness(mux);
			await waitFor(() => expect(mux.open).toHaveBeenCalled());

			act(runLargeOutput);

			const input = vi.mocked(mux.sendInput).mock.calls[0]?.[1];
			expect(input).toContain("[Console]::Out.Write(-join ('x' * 16777216))");
			expect(input).not.toContain("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__");
		} finally {
			Object.defineProperty(navigator, "userAgent", { configurable: true, value: defaultUserAgent });
		}
	});

	it("keeps FitAddon from changing the benchmark grid", async () => {
		vi.useFakeTimers();
		vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) =>
			window.setTimeout(() => callback(performance.now()), 0),
		);
		vi.stubGlobal("cancelAnimationFrame", (id: number) => window.clearTimeout(id));
		xtermState.fitColumns = 80;
		xtermState.fitRows = 24;
		try {
			renderHarness(fakeMux());
			await act(async () => vi.advanceTimersByTime(130));

			expect(xtermState.lastTerminal).toMatchObject({ cols: 120, rows: 40 });
		} finally {
			vi.useRealTimers();
			vi.unstubAllGlobals();
		}
	});

	it("fails closed when the live grid drifts before a sample", async () => {
		const mux = fakeMux();
		renderHarness(mux);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());
		xtermState.lastTerminal!.cols = 119;
		let browserError: Error | undefined;
		const captureError = (event: ErrorEvent) => {
			event.preventDefault();
			browserError = event.error as Error;
		};
		window.addEventListener("error", captureError);

		act(runLargeOutput);

		window.removeEventListener("error", captureError);
		expect(browserError?.message).toMatch(/grid drifted from 120x40/);
		expect(mux.sendInput).not.toHaveBeenCalled();
	});

	it("acknowledges canvas recovery only after its first recovered frame", async () => {
		const acknowledgements: TerminalAcknowledgement[] = [];
		renderHarness(fakeMux(), acknowledgements);
		await waitFor(() => expect(screen.getByTestId("terminal-benchmark-root")).toHaveAttribute("data-terminal-renderer-kind", "webgl"));

		act(() => xtermState.contextLoss?.());

		expect(screen.getByTestId("terminal-benchmark-root")).toHaveAttribute("data-terminal-renderer-kind", "canvas");
		expect(acknowledgements.some(({ name }) => name === "renderer-recovery")).toBe(false);
		act(() => emitRender(500));
		expect(acknowledgements).toContainEqual({ name: "renderer-recovery", timestamp: 500 });
	});

	it("reopens the fixed grid and timestamps a successful reconnect", async () => {
		const muxes = [fakeMux(), fakeMux()];
		const acknowledgements: TerminalAcknowledgement[] = [];
		const createMux = vi.fn(() => muxes.shift()!);
		render(
			<SkinProvider>
				<TerminalBenchmarkHarness
					configuration={configuration()}
					createMux={createMux}
					onAcknowledgement={(acknowledgement) => acknowledgements.push(acknowledgement)}
				/>
			</SkinProvider>,
		);

		await waitFor(() => expect(createMux).toHaveBeenCalledTimes(1));
		act(() => createMux.mock.results[0].value.emitConnection("closed"));
		await waitFor(() => expect(createMux).toHaveBeenCalledTimes(2));
		expect(createMux.mock.results[1].value.open).toHaveBeenCalledWith("terminal-1", 120, 40);
		act(() => createMux.mock.results[1].value.emitOpened());

		expect(acknowledgements.some(({ name }) => name === "reconnect")).toBe(true);
	});

	it("closes the attachment and disposes the production terminal", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		const view = renderHarness(mux, acknowledgements);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());

		view.unmount();

		expect(mux.close).toHaveBeenCalledWith("terminal-1");
		expect(mux.dispose).toHaveBeenCalledTimes(1);
		expect(xtermState.lastTerminal?.disposed).toBe(true);
		expect(acknowledgements.some(({ name }) => name === "disposal")).toBe(true);
	});
});
