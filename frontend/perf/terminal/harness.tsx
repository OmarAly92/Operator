import { useCallback, useEffect, useRef, useState } from "react";
import scenarios from "../scenarios.json";
import {
	XtermTerminal,
	type TerminalRendererKind,
	type XtermTerminalTimestamp,
} from "../../src/renderer/components/XtermTerminal";
import type { AttachableTerminal } from "../../src/renderer/hooks/useTerminalSession";
import { createTerminalMux, muxUrlFromApiBase, type TerminalMux } from "../../src/renderer/lib/terminal-mux";

type TerminalScenario = {
	columns: number;
	rows: number;
	scrollback: number;
	outputBytes?: number;
	workloadIterations?: number;
};

export type TerminalHarnessConfiguration = {
	daemonBaseUrl: string;
	sessionId: string;
	terminalId: string;
	columns: number;
	rows: number;
	scrollback: number;
};

export type TerminalAcknowledgement = {
	name: "first-paint" | "workload" | "input-echo" | "resize" | "reconnect" | "renderer-recovery" | "disposal";
	timestamp: number;
	bytes?: number;
};

type TerminalBenchmarkHarnessProps = {
	configuration: TerminalHarnessConfiguration;
	createMux?: (url: string) => TerminalMux;
	onAcknowledgement?: (acknowledgement: TerminalAcknowledgement) => void;
	onRendererKind?: (kind: TerminalRendererKind) => void;
};

type WorkloadRequest = {
	scenario: "vtebench" | "large-output" | "cpu-time" | "active-memory";
	iteration: number;
};

const workloadMarker = "__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__";
const workloadMarkerBytes = new TextEncoder().encode(workloadMarker);

const acknowledgementMarks: Record<TerminalAcknowledgement["name"], string> = {
	"first-paint": "operator:terminal-first-paint",
	workload: "operator:terminal-ready",
	"input-echo": "operator:terminal-input-echo",
	resize: "operator:terminal-resize",
	reconnect: "operator:terminal-reconnect",
	"renderer-recovery": "operator:terminal-renderer-recovery",
	disposal: "operator:terminal-disposed",
};

const defaultCreateMux = (url: string) => createTerminalMux(url);

function benchmarkGeometry(): Pick<TerminalHarnessConfiguration, "columns" | "rows" | "scrollback"> {
	const vtebench = scenarios.vtebench as TerminalScenario;
	const largeOutput = scenarios["large-output"] as TerminalScenario;
	if (
		vtebench.columns !== largeOutput.columns ||
		vtebench.rows !== largeOutput.rows ||
		vtebench.scrollback !== largeOutput.scrollback
	) {
		throw new Error("terminal benchmark scenarios must share one fixed grid");
	}
	return { columns: vtebench.columns, rows: vtebench.rows, scrollback: vtebench.scrollback };
}

function loopbackDaemonBaseUrl(rawUrl: string): string {
	const url = new URL(rawUrl);
	const loopbackHosts = new Set(["127.0.0.1", "localhost", "[::1]"]);
	if (!["http:", "https:"].includes(url.protocol) || !loopbackHosts.has(url.hostname) || url.username || url.password) {
		throw new Error("terminal benchmark daemon URL must use a loopback HTTP(S) origin");
	}
	url.pathname = "/";
	url.search = "";
	url.hash = "";
	return url.toString();
}

function requiredIdentifier(parameters: URLSearchParams, name: "sessionId" | "terminalId"): string {
	const identifier = parameters.get(name)?.trim();
	if (!identifier) throw new Error(`terminal benchmark requires ${name}`);
	return identifier;
}

export function terminalHarnessConfiguration(search: string): TerminalHarnessConfiguration {
	const parameters = new URLSearchParams(search);
	const daemonBaseUrl = parameters.get("daemonBaseUrl");
	if (!daemonBaseUrl) throw new Error("terminal benchmark requires daemonBaseUrl");
	return {
		daemonBaseUrl: loopbackDaemonBaseUrl(daemonBaseUrl),
		sessionId: requiredIdentifier(parameters, "sessionId"),
		terminalId: requiredIdentifier(parameters, "terminalId"),
		...benchmarkGeometry(),
	};
}

function markerMatcher(): (bytes: Uint8Array) => boolean {
	let matchedBytes = 0;
	return (bytes) => {
		let completed = false;
		for (const byte of bytes) {
			if (byte === workloadMarkerBytes[matchedBytes]) {
				matchedBytes += 1;
				if (matchedBytes === workloadMarkerBytes.length) {
					completed = true;
					matchedBytes = 0;
				}
			} else {
				matchedBytes = byte === workloadMarkerBytes[0] ? 1 : 0;
			}
		}
		return completed;
	};
}

function fixedComputeWorkload(request: WorkloadRequest): string {
	const scenarioConfig = scenarios[request.scenario] as TerminalScenario | undefined;
	const iterations = scenarioConfig?.workloadIterations ?? 100_000;
	if (!Number.isInteger(iterations) || iterations < 1) throw new Error(`${request.scenario} requires a positive workloadIterations count`);
	const windows = navigator.userAgent.includes("Windows");
	const markerCommand = windows
		? `[Console]::Out.Write(([char]95).ToString() + [char]95 + 'OPERATOR_TERMINAL_WORKLOAD_COMPLETE' + [char]95 + [char]95)`
		: `printf '\\137\\137OPERATOR_TERMINAL_WORKLOAD_COMPLETE\\137\\137'`;
	if (windows) return `for($i=0;$i -lt ${iterations};$i++){}; if ($?) { ${markerCommand} }`;
	return `i=0; while [ "$i" -lt ${iterations} ]; do i=$((i+1)); done && ${markerCommand}`;
}

function workloadInput(request: WorkloadRequest): string {
	if (!Number.isInteger(request.iteration) || request.iteration < 0) throw new Error("invalid terminal benchmark iteration");
	const windows = navigator.userAgent.includes("Windows");
	const markerCommand = windows
		? `[Console]::Out.Write(([char]95).ToString() + [char]95 + 'OPERATOR_TERMINAL_WORKLOAD_COMPLETE' + [char]95 + [char]95)`
		: `printf '\\137\\137OPERATOR_TERMINAL_WORKLOAD_COMPLETE\\137\\137'`;
	if (request.scenario === "vtebench") return windows ? `vtebench; if ($?) { ${markerCommand} }\r` : `vtebench && ${markerCommand}\r`;
	if (request.scenario === "large-output") {
		const outputBytes = (scenarios["large-output"] as TerminalScenario).outputBytes;
		if (!outputBytes) throw new Error("large-output scenario requires outputBytes");
		const outputCommand = windows
			? `[Console]::Out.Write(-join ('x' * ${outputBytes}))`
			: `LC_ALL=C head -c ${outputBytes} /dev/zero | tr '\\0' x`;
		return windows ? `${outputCommand}; if ($?) { ${markerCommand} }\r` : `${outputCommand} && ${markerCommand}\r`;
	}
	if (request.scenario === "cpu-time" || request.scenario === "active-memory") {
		return `${fixedComputeWorkload(request)}\r`;
	}
	throw new Error("unsupported terminal benchmark workload");
}

function useAcknowledgements(onAcknowledgement?: (acknowledgement: TerminalAcknowledgement) => void) {
	const callbackRef = useRef(onAcknowledgement);
	callbackRef.current = onAcknowledgement;
	return useCallback((name: TerminalAcknowledgement["name"], timestamp = performance.now(), bytes?: number) => {
		performance.mark(acknowledgementMarks[name]);
		callbackRef.current?.({ name, timestamp, ...(typeof bytes === "number" ? { bytes } : {}) });
	}, []);
}

declare global {
	interface Window {
		__operatorTerminalBenchmark?: {
			takeLastPrimaryBytes: () => number | undefined;
		};
	}
}

export function TerminalBenchmarkHarness({
	configuration,
	createMux = defaultCreateMux,
	onAcknowledgement,
	onRendererKind,
}: TerminalBenchmarkHarnessProps) {
	const [terminal, setTerminal] = useState<AttachableTerminal | null>(null);
	const [rendererKind, setRendererKind] = useState<TerminalRendererKind | undefined>();
	const [attachmentGeneration, setAttachmentGeneration] = useState(0);
	const muxRef = useRef<TerminalMux | null>(null);
	const requestedWorkloadsRef = useRef(0);
	const pendingWorkloadsRef = useRef(0);
	const workloadByteWindowRef = useRef(false);
	const accumulatedWorkloadBytesRef = useRef(0);
	const lastPrimaryBytesRef = useRef<number | undefined>(undefined);
	const inputEchoPendingRef = useRef(0);
	const firstPaintRef = useRef(false);
	const acknowledge = useAcknowledgements(onAcknowledgement);

	const onTimestamp = useCallback((event: XtermTerminalTimestamp) => {
		if (event.kind === "render") {
			if (!firstPaintRef.current) {
				firstPaintRef.current = true;
				acknowledge("first-paint", event.timestamp);
			}
			if (pendingWorkloadsRef.current > 0) {
				pendingWorkloadsRef.current -= 1;
				const observedBytes = lastPrimaryBytesRef.current;
				lastPrimaryBytesRef.current = undefined;
				acknowledge("workload", event.timestamp, typeof observedBytes === "number" ? observedBytes : undefined);
				return;
			}
			if (inputEchoPendingRef.current > 0) {
				inputEchoPendingRef.current -= 1;
				acknowledge("input-echo", event.timestamp);
			}
			return;
		}
		if (event.kind === "resize") acknowledge("resize", event.timestamp);
		if (event.kind === "renderer-recovery") acknowledge("renderer-recovery", event.timestamp);
		if (event.kind === "disposal") acknowledge("disposal", event.timestamp);
	}, [acknowledge]);
	const rendererChanged = useCallback((kind: TerminalRendererKind) => {
		setRendererKind(kind);
		onRendererKind?.(kind);
	}, [onRendererKind]);

	useEffect(() => {
		window.__operatorTerminalBenchmark = {
			takeLastPrimaryBytes: () => {
				const observed = lastPrimaryBytesRef.current;
				lastPrimaryBytesRef.current = undefined;
				return observed;
			},
		};
		return () => {
			delete window.__operatorTerminalBenchmark;
		};
	}, []);

	useEffect(() => {
		if (!terminal) return undefined;
		const mux = createMux(muxUrlFromApiBase(configuration.daemonBaseUrl));
		const seesWorkloadMarker = markerMatcher();
		const reconnecting = attachmentGeneration > 0;
		muxRef.current = mux;
		const subscriptions = [
			mux.onData(configuration.terminalId, (bytes) => {
				if (requestedWorkloadsRef.current > 0 && seesWorkloadMarker(bytes)) {
					requestedWorkloadsRef.current -= 1;
					if (workloadByteWindowRef.current) {
						accumulatedWorkloadBytesRef.current += bytes.byteLength;
						lastPrimaryBytesRef.current = accumulatedWorkloadBytesRef.current;
						workloadByteWindowRef.current = false;
						accumulatedWorkloadBytesRef.current = 0;
					}
					terminal.write(bytes, () => {
						pendingWorkloadsRef.current += 1;
					});
					return;
				}
				if (workloadByteWindowRef.current) accumulatedWorkloadBytesRef.current += bytes.byteLength;
				terminal.write(bytes);
			}),
			mux.onOpened(configuration.terminalId, () => {
				if (reconnecting) acknowledge("reconnect");
			}),
			mux.onConnectionChange((state) => {
				if (state === "closed") setAttachmentGeneration((generation) => generation + 1);
			}),
		];
		mux.open(configuration.terminalId, configuration.columns, configuration.rows);
		return () => {
			if (muxRef.current === mux) muxRef.current = null;
			for (const unsubscribe of subscriptions) unsubscribe();
			mux.close(configuration.terminalId);
			mux.dispose();
		};
	}, [acknowledge, attachmentGeneration, configuration, createMux, terminal]);

	useEffect(() => {
		const runWorkload = (event: Event) => {
			const request = (event as CustomEvent<WorkloadRequest>).detail;
			const mux = muxRef.current;
			if (!mux || !terminal) return;
			if (terminal.cols !== configuration.columns || terminal.rows !== configuration.rows) {
				throw new Error(
					`terminal benchmark grid drifted from ${configuration.columns}x${configuration.rows} to ${terminal.cols}x${terminal.rows}`,
				);
			}
			const input = workloadInput(request);
			workloadByteWindowRef.current = true;
			accumulatedWorkloadBytesRef.current = 0;
			requestedWorkloadsRef.current += 1;
			mux.sendInput(configuration.terminalId, input);
		};
		const sendInputProbe = () => {
			const mux = muxRef.current;
			if (!mux || !terminal) return;
			inputEchoPendingRef.current += 1;
			mux.sendInput(configuration.terminalId, "x");
		};
		const forceDisconnect = () => {
			const mux = muxRef.current;
			if (!mux) return;
			mux.dispose();
		};
		window.addEventListener("operator:terminal-benchmark-run", runWorkload);
		window.addEventListener("operator:terminal-benchmark-input", sendInputProbe);
		window.addEventListener("operator:terminal-benchmark-reconnect", forceDisconnect);
		return () => {
			window.removeEventListener("operator:terminal-benchmark-run", runWorkload);
			window.removeEventListener("operator:terminal-benchmark-input", sendInputProbe);
			window.removeEventListener("operator:terminal-benchmark-reconnect", forceDisconnect);
		};
	}, [configuration.columns, configuration.rows, configuration.terminalId, terminal]);

	return (
		<div
			aria-label={`Terminal benchmark for ${configuration.sessionId}`}
			data-terminal-renderer-kind={rendererKind}
			data-testid="terminal-benchmark-root"
			style={{ height: "100vh", width: "100vw" }}
		>
			<XtermTerminal
				columns={configuration.columns}
				geometryMode="fixed"
				onReady={setTerminal}
				onRendererKind={rendererChanged}
				onTimestamp={onTimestamp}
				rows={configuration.rows}
				scrollback={configuration.scrollback}
				theme="dark"
			/>
		</div>
	);
}
