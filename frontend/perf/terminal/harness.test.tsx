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

type FakeCore = {
	columns: number;
	rows: number;
	scrollback: number;
	fed: Uint8Array[];
	disposed: boolean;
	feed: (bytes: Uint8Array) => void;
	dispose: () => void;
};

type FakeRenderer = {
	host: HTMLElement;
	paintListeners: Set<() => void>;
	disposed: boolean;
};

const terminalState = vi.hoisted(() => ({
	wasmInits: 0,
	lastCore: null as FakeCore | null,
	lastRenderer: null as FakeRenderer | null,
}));

vi.mock("@operator/terminal-core/browser", () => ({
	initTerminalCoreFromUrl: vi.fn(async () => {
		terminalState.wasmInits += 1;
	}),
}));

vi.mock("@operator/terminal-core", () => ({
	createTerminalCore: vi.fn((options: { columns: number; rows: number; scrollback: number }) => {
		const core: FakeCore = {
			columns: options.columns,
			rows: options.rows,
			scrollback: options.scrollback,
			fed: [],
			disposed: false,
			feed(bytes: Uint8Array) {
				core.fed.push(bytes);
			},
			dispose() {
				core.disposed = true;
			},
		};
		terminalState.lastCore = core;
		return core;
	}),
}));

vi.mock("@operator/terminal-renderer-dom", () => ({
	warpDarkTheme: { name: "warp-dark" },
	DomBlockRenderer: class FakeDomBlockRenderer {
		host: HTMLElement | null = null;
		paintListeners = new Set<() => void>();
		disposed = false;

		mount(host: HTMLElement) {
			this.host = host;
			const marker = document.createElement("div");
			marker.setAttribute("data-testid", "terminal-block-list");
			host.appendChild(marker);
			terminalState.lastRenderer = this as unknown as FakeRenderer;
		}
		setTheme() {}
		setFont() {}
		onPaint(listener: () => void) {
			this.paintListeners.add(listener);
			return () => this.paintListeners.delete(listener);
		}
		dispose() {
			this.disposed = true;
			this.paintListeners.clear();
		}
	},
}));

function emitPaint(timestamp: number) {
	vi.spyOn(performance, "now").mockReturnValue(timestamp);
	for (const listener of [...(terminalState.lastRenderer?.paintListeners ?? [])]) listener();
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
		terminalState.wasmInits = 0;
		terminalState.lastCore = null;
		terminalState.lastRenderer = null;
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
			durations: { durations: [15, 30], observedBytes: [null, null] },
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

	it("mounts the real production renderer on the live mux boundary", async () => {
		const mux = fakeMux();

		renderHarness(mux);

		const root = await screen.findByLabelText("Terminal benchmark for session-1");
		expect(root).toHaveAttribute("data-terminal-renderer-kind", "dom");
		await waitFor(() => expect(root.querySelector('[data-testid="terminal-block-list"]')).toBeInTheDocument());
		await waitFor(() => expect(mux.open).toHaveBeenCalledWith("terminal-1", 120, 40));
		expect(terminalState.lastCore).toMatchObject({ columns: 120, rows: 40, scrollback: 5000 });
	});

	it("acknowledges a workload only once its marker paints, carrying the observed byte count", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		renderHarness(mux, acknowledgements);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());

		act(runLargeOutput);
		act(() => mux.emitData(new TextEncoder().encode("secret terminal output__OPERATOR_TERMINAL_WORKLOAD_")));
		act(() => mux.emitData(new TextEncoder().encode("COMPLETE__")));

		expect(acknowledgements.some(({ name }) => name === "workload")).toBe(false);
		act(() => emitPaint(300));
		const workloadAcknowledgement = acknowledgements.find(({ name }) => name === "workload");
		expect(workloadAcknowledgement).toMatchObject({ name: "workload", timestamp: 300 });
		expect(acknowledgements.every((acknowledgement) => {
			const keys = Object.keys(acknowledgement).sort().join(",");
			if (keys === "name,timestamp") return true;
			return acknowledgement.name === "workload" && keys === "bytes,name,timestamp" && typeof acknowledgement.bytes === "number";
		})).toBe(true);
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
			expect(input).toContain("if ($?)");
			expect(input).not.toContain("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__");
		} finally {
			Object.defineProperty(navigator, "userAgent", { configurable: true, value: defaultUserAgent });
		}
	});

	it("emits no success marker after a POSIX workload failure", async () => {
		const defaultUserAgent = navigator.userAgent;
		Object.defineProperty(navigator, "userAgent", { configurable: true, value: "Linux" });
		const mux = fakeMux();
		try {
			renderHarness(mux);
			await waitFor(() => expect(mux.open).toHaveBeenCalled());
			window.dispatchEvent(new CustomEvent("operator:terminal-benchmark-run", {
				detail: { scenario: "vtebench", iteration: 0 },
			}));
			const input = vi.mocked(mux.sendInput).mock.calls[0]?.[1];
			expect(input).toContain("vtebench && printf");
			expect(input).not.toContain("vtebench; printf");
		} finally {
			Object.defineProperty(navigator, "userAgent", { configurable: true, value: defaultUserAgent });
		}
	});

	it("drives cpu-time and active-memory workloads through the real shell on both platforms", async () => {
		const cases = [
			{ scenario: "cpu-time", posixLoop: 'while [ "$i" -lt 200000 ]', windowsLoop: "-lt 200000" },
			{ scenario: "active-memory", posixLoop: 'while [ "$i" -lt 50000 ]', windowsLoop: "-lt 50000" },
		] as const;
		const defaultUserAgent = navigator.userAgent;
		try {
			for (const { scenario, posixLoop, windowsLoop } of cases) {
				Object.defineProperty(navigator, "userAgent", { configurable: true, value: "Macintosh" });
				const posixMux = fakeMux();
				const posixView = renderHarness(posixMux);
				await waitFor(() => expect(posixMux.open).toHaveBeenCalled());
				act(() => {
					window.dispatchEvent(new CustomEvent("operator:terminal-benchmark-run", { detail: { scenario, iteration: 0 } }));
				});
				const posixInput = vi.mocked(posixMux.sendInput).mock.calls[0]?.[1] as string;
				expect(posixInput).toContain(posixLoop);
				expect(posixInput).toContain("\\137\\137OPERATOR");
				expect(posixInput).toContain("&&");
				expect(posixInput.endsWith("\r")).toBe(true);
				posixView.unmount();

				Object.defineProperty(navigator, "userAgent", { configurable: true, value: "Windows" });
				const windowsMux = fakeMux();
				const windowsView = renderHarness(windowsMux);
				await waitFor(() => expect(windowsMux.open).toHaveBeenCalled());
				act(() => {
					window.dispatchEvent(new CustomEvent("operator:terminal-benchmark-run", { detail: { scenario, iteration: 0 } }));
				});
				const windowsInput = vi.mocked(windowsMux.sendInput).mock.calls[0]?.[1] as string;
				expect(windowsInput).toContain(windowsLoop);
				expect(windowsInput).toContain("if ($?)");
				expect(windowsInput).not.toContain("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__");
				windowsView.unmount();
			}
		} finally {
			Object.defineProperty(navigator, "userAgent", { configurable: true, value: defaultUserAgent });
		}
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

	// The test above emits "closed" straight onto the mux, which is what the
	// harness listens for — but the real forced disconnect goes through
	// dispose(), and the real dispose() clears its connection listeners before
	// closing the socket, so that transition never arrives. Driving the actual
	// benchmark event (as the runner does) is the only way to catch a reconnect
	// that never re-attaches; fakeMux's dispose is silent for the same reason.
	it("re-attaches after the benchmark's forced disconnect", async () => {
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

		act(() => {
			window.dispatchEvent(new Event("operator:terminal-benchmark-reconnect"));
		});

		await waitFor(() => expect(createMux).toHaveBeenCalledTimes(2));
		expect(createMux.mock.results[0].value.dispose).toHaveBeenCalled();
		expect(createMux.mock.results[1].value.open).toHaveBeenCalledWith("terminal-1", 120, 40);
		act(() => createMux.mock.results[1].value.emitOpened());
		expect(acknowledgements.some(({ name }) => name === "reconnect")).toBe(true);
	});

	it("closes the attachment and disposes the production renderer", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		const view = renderHarness(mux, acknowledgements);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());
		const renderer = terminalState.lastRenderer;
		const core = terminalState.lastCore;

		view.unmount();

		expect(mux.close).toHaveBeenCalledWith("terminal-1");
		expect(mux.dispose).toHaveBeenCalledTimes(1);
		expect(renderer?.disposed).toBe(true);
		expect(core?.disposed).toBe(true);
		expect(acknowledgements.some(({ name }) => name === "disposal")).toBe(true);
	});
});

it("main.tsx resolves every callable identifier from its own declarations its imports or known globals", async () => {
	const { readFileSync } = await import("node:fs");
	const { dirname, join } = await import("node:path");
	const { fileURLToPath } = await import("node:url");
	const here = dirname(fileURLToPath(import.meta.url));
	const mainSource = readFileSync(join(here, "main.tsx"), "utf8");

	const harnessModule = await import("./harness");
	for (const match of mainSource.matchAll(/import\s*\{([^}]+)\}\s*from\s*"\.\/harness";?/g)) {
		for (const rawSpecifier of match[1].split(",")) {
			const specifier = rawSpecifier.trim();
			if (!specifier || specifier.startsWith("type ")) continue;
			const name = specifier.split(/\s+as\s+/)[0];
			if (!name) continue;
			expect(harnessModule).toHaveProperty(name);
		}
	}

	const declared = new Set<string>();
	for (const match of mainSource.matchAll(/(?:function|const|let|var)\s+([A-Za-z_$][\w$]*)/g)) declared.add(match[1]);
	for (const match of mainSource.matchAll(/import\s+(\w+)(?:\s*,)?[^;]*from/g)) declared.add(match[1]);
	for (const match of mainSource.matchAll(/\*\s+as\s+(\w+)/g)) declared.add(match[1]);
	for (const match of mainSource.matchAll(/import\s*\{([^}]+)\}\s*from/g)) {
		for (const specifier of match[1].split(",")) {
			const name = specifier.trim().replace(/^type\s+/, "").split(/\s+as\s+/)[0];
			if (name && !name.startsWith('"')) declared.add(name);
		}
	}

	const knownGlobals = new Set([
		"if", "for", "while", "switch", "catch", "return", "function", "typeof", "new", "await",
		"window", "document", "performance", "fetch", "requestAnimationFrame", "CustomEvent",
		"URLSearchParams", "URL", "Error", "TypeError", "Number", "String", "Boolean", "Array",
		"Object", "JSON", "Math", "Promise", "console", "undefined", "setTimeout", "clearTimeout",
	]);
	for (const match of mainSource.matchAll(/(?<![\w$.{])([A-Za-z_$][\w$]*)\s*\(/g)) {
		const callee = match[1];
		if (knownGlobals.has(callee)) continue;
		expect(declared.has(callee)).toBe(true);
	}
});
