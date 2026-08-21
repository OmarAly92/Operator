import { act, render, screen, waitFor } from "@testing-library/react";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { useEffect } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AttachableTerminal } from "../../src/renderer/hooks/useTerminalSession";
import type { TerminalMux } from "../../src/renderer/lib/terminal-mux";
import {
	TerminalBenchmarkHarness,
	terminalHarnessConfiguration,
	type TerminalAcknowledgement,
} from "./harness";

const terminalState = vi.hoisted(() => ({
	props: null as null | Record<string, unknown>,
}));
const defaultUserAgent = navigator.userAgent;

vi.mock("../../src/renderer/components/XtermTerminal", () => ({
	XtermTerminal: (props: Record<string, unknown>) => {
		terminalState.props = props;
		useEffect(() => {
			(props.onRendererKind as ((kind: "webgl") => void) | undefined)?.("webgl");
			(props.onTimestamp as ((event: { kind: string; timestamp: number }) => void) | undefined)?.({
				kind: "render",
				timestamp: 100,
			});
			(props.onReady as ((terminal: AttachableTerminal) => void) | undefined)?.(fakeTerminal);
			return () => {
				(props.onTimestamp as ((event: { kind: string; timestamp: number }) => void) | undefined)?.({
					kind: "disposal",
					timestamp: 600,
				});
			};
		}, []);
		return <div data-testid="production-xterm" />;
	},
}));

const fakeTerminal: AttachableTerminal = {
	cols: 120,
	rows: 40,
	write: vi.fn((_bytes: Uint8Array, done?: () => void) => {
		done?.();
		(terminalState.props?.onTimestamp as ((event: { kind: string; timestamp: number }) => void) | undefined)?.({
			kind: "render",
			timestamp: 300,
		});
	}),
	writeln: vi.fn(),
	showLatestOutput: vi.fn(),
	prepareForActivation: vi.fn().mockResolvedValue(undefined),
	onUserInput: vi.fn(() => ({ dispose: vi.fn() })),
	onResize: vi.fn(() => ({ dispose: vi.fn() })),
};

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

describe("terminal benchmark harness", () => {
	beforeEach(() => {
		terminalState.props = null;
		vi.mocked(fakeTerminal.write).mockClear();
		Object.defineProperty(navigator, "userAgent", { configurable: true, value: defaultUserAgent });
	});

	it.each([
		"https://operator.dev",
		"http://127.0.0.1.evil.example:4317",
		"ftp://127.0.0.1:4317",
	])("refuses a non-loopback daemon URL: %s", (daemonBaseUrl) => {
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

	it("mounts the production xterm on the real mux contract", async () => {
		const mux = fakeMux();
		const createMux = vi.fn(() => mux);

		render(<TerminalBenchmarkHarness configuration={configuration()} createMux={createMux} />);

		expect(screen.getByTestId("production-xterm")).toBeInTheDocument();
		await waitFor(() => expect(mux.open).toHaveBeenCalledWith("terminal-1", 120, 40));
		expect(createMux).toHaveBeenCalledWith("ws://127.0.0.1:4317/mux");
		expect(terminalState.props).toMatchObject({ columns: 120, rows: 40, scrollback: 5000 });
	});

	it("builds the fixed Windows output workload without echoing the completion marker", async () => {
		Object.defineProperty(navigator, "userAgent", { configurable: true, value: "Windows" });
		const mux = fakeMux();
		render(<TerminalBenchmarkHarness configuration={configuration()} createMux={() => mux} />);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());

		act(() => {
			window.dispatchEvent(
				new CustomEvent("operator:terminal-benchmark-run", {
					detail: { scenario: "large-output", iteration: 0 },
				}),
			);
		});

		const input = vi.mocked(mux.sendInput).mock.calls[0]?.[1];
		expect(input).toContain("[Console]::Out.Write(-join ('x' * 16777216))");
		expect(input).not.toContain("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__");
	});

	it("reports renderer and timestamp-only workload acknowledgements", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		render(
			<TerminalBenchmarkHarness
				configuration={configuration()}
				createMux={() => mux}
				onAcknowledgement={(acknowledgement) => acknowledgements.push(acknowledgement)}
			/>,
		);

		await waitFor(() => expect(screen.getByTestId("terminal-benchmark-root")).toHaveAttribute("data-terminal-renderer-kind", "webgl"));
		act(() => mux.emitData(new TextEncoder().encode("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__")));
		expect(acknowledgements.some((acknowledgement) => acknowledgement.name === "workload")).toBe(false);
		act(() => {
			window.dispatchEvent(
				new CustomEvent("operator:terminal-benchmark-run", {
					detail: { scenario: "large-output", iteration: 0 },
				}),
			);
		});
		expect(mux.sendInput).toHaveBeenCalledTimes(1);
		expect(vi.mocked(mux.sendInput).mock.calls[0]?.[1]).not.toContain("__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__");
		act(() => {
			mux.emitData(new TextEncoder().encode("secret terminal output__OPERATOR_TERMINAL_WORKLOAD_"));
		});

		expect(acknowledgements).toContainEqual({ name: "first-paint", timestamp: 100 });
		expect(acknowledgements.some((acknowledgement) => acknowledgement.name === "workload")).toBe(false);
		act(() => mux.emitData(new TextEncoder().encode("COMPLETE__")));
		expect(acknowledgements).toContainEqual({ name: "workload", timestamp: 300 });
		act(() => {
			(terminalState.props?.onTimestamp as (event: { kind: string; timestamp: number }) => void)({
				kind: "resize",
				timestamp: 400,
			});
			(terminalState.props?.onTimestamp as (event: { kind: string; timestamp: number }) => void)({
				kind: "renderer-recovery",
				timestamp: 500,
			});
		});
		expect(acknowledgements).toContainEqual({ name: "resize", timestamp: 400 });
		expect(acknowledgements).toContainEqual({ name: "renderer-recovery", timestamp: 500 });
		expect(acknowledgements.every((acknowledgement) => Object.keys(acknowledgement).sort().join(",") === "name,timestamp")).toBe(true);
		expect(JSON.stringify(acknowledgements)).not.toContain("secret terminal output");
	});

	it("reopens the fixed grid and timestamps a successful reconnect", async () => {
		const muxes = [fakeMux(), fakeMux()];
		const acknowledgements: TerminalAcknowledgement[] = [];
		const createMux = vi.fn(() => muxes.shift()!);
		render(
			<TerminalBenchmarkHarness
				configuration={configuration()}
				createMux={createMux}
				onAcknowledgement={(acknowledgement) => acknowledgements.push(acknowledgement)}
			/>,
		);

		await waitFor(() => expect(createMux).toHaveBeenCalledTimes(1));
		act(() => createMux.mock.results[0].value.emitConnection("closed"));
		await waitFor(() => expect(createMux).toHaveBeenCalledTimes(2));
		expect(createMux.mock.results[1].value.open).toHaveBeenCalledWith("terminal-1", 120, 40);
		act(() => createMux.mock.results[1].value.emitOpened());

		expect(acknowledgements.some((acknowledgement) => acknowledgement.name === "reconnect")).toBe(true);
	});

	it("closes the terminal attachment and reports disposal on unmount", async () => {
		const mux = fakeMux();
		const acknowledgements: TerminalAcknowledgement[] = [];
		const view = render(
			<TerminalBenchmarkHarness
				configuration={configuration()}
				createMux={() => mux}
				onAcknowledgement={(acknowledgement) => acknowledgements.push(acknowledgement)}
			/>,
		);
		await waitFor(() => expect(mux.open).toHaveBeenCalled());

		view.unmount();

		expect(mux.close).toHaveBeenCalledWith("terminal-1");
		expect(mux.dispose).toHaveBeenCalledTimes(1);
		expect(acknowledgements).toContainEqual({ name: "disposal", timestamp: 600 });
	});
});
