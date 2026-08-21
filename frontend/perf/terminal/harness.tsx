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
	name: "first-paint" | "workload" | "resize" | "reconnect" | "renderer-recovery" | "disposal";
	timestamp: number;
};

type TerminalBenchmarkHarnessProps = {
	configuration: TerminalHarnessConfiguration;
	createMux?: (url: string) => TerminalMux;
	onAcknowledgement?: (acknowledgement: TerminalAcknowledgement) => void;
	onRendererKind?: (kind: TerminalRendererKind) => void;
};

type WorkloadRequest = {
	scenario: "vtebench" | "large-output";
	iteration: number;
};

const workloadMarker = "__OPERATOR_TERMINAL_WORKLOAD_COMPLETE__";
const workloadMarkerBytes = new TextEncoder().encode(workloadMarker);

const acknowledgementMarks: Record<TerminalAcknowledgement["name"], string> = {
	"first-paint": "operator:terminal-first-paint",
	workload: "operator:terminal-ready",
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

function workloadInput(request: WorkloadRequest): string {
	if (!Number.isInteger(request.iteration) || request.iteration < 0) throw new Error("invalid terminal benchmark iteration");
	const windows = navigator.userAgent.includes("Windows");
	const markerCommand = windows
		? `[Console]::Out.Write(([char]95).ToString() + [char]95 + 'OPERATOR_TERMINAL_WORKLOAD_COMPLETE' + [char]95 + [char]95)`
		: `printf '\\137\\137OPERATOR_TERMINAL_WORKLOAD_COMPLETE\\137\\137'`;
	if (request.scenario === "vtebench") return `vtebench; ${markerCommand}\r`;
	if (request.scenario === "large-output") {
		const outputBytes = (scenarios["large-output"] as TerminalScenario).outputBytes;
		if (!outputBytes) throw new Error("large-output scenario requires outputBytes");
		const outputCommand = windows
			? `[Console]::Out.Write(-join ('x' * ${outputBytes}))`
			: `LC_ALL=C head -c ${outputBytes} /dev/zero | tr '\\0' x`;
		return `${outputCommand}; ${markerCommand}\r`;
	}
	throw new Error("unsupported terminal benchmark workload");
}

function useAcknowledgements(onAcknowledgement?: (acknowledgement: TerminalAcknowledgement) => void) {
	const callbackRef = useRef(onAcknowledgement);
	callbackRef.current = onAcknowledgement;
	return useCallback((name: TerminalAcknowledgement["name"], timestamp = performance.now()) => {
		performance.mark(acknowledgementMarks[name]);
		callbackRef.current?.({ name, timestamp });
	}, []);
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
				acknowledge("workload", event.timestamp);
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
		if (!terminal) return undefined;
		const mux = createMux(muxUrlFromApiBase(configuration.daemonBaseUrl));
		const seesWorkloadMarker = markerMatcher();
		const reconnecting = attachmentGeneration > 0;
		muxRef.current = mux;
		const subscriptions = [
			mux.onData(configuration.terminalId, (bytes) => {
				if (seesWorkloadMarker(bytes) && requestedWorkloadsRef.current > 0) {
					requestedWorkloadsRef.current -= 1;
					terminal.write(bytes, () => {
						pendingWorkloadsRef.current += 1;
					});
					return;
				}
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
			requestedWorkloadsRef.current += 1;
			mux.sendInput(configuration.terminalId, input);
		};
		window.addEventListener("operator:terminal-benchmark-run", runWorkload);
		return () => window.removeEventListener("operator:terminal-benchmark-run", runWorkload);
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
