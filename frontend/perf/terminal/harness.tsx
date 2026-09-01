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
	alternateScreen?: boolean;
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
	name: "first-paint" | "workload" | "input-echo" | "resize" | "reconnect" | "renderer-recovery" | "disposal" | "scroll";
	timestamp: number;
	bytes?: number;
};

type TerminalBenchmarkHarnessProps = {
	configuration: TerminalHarnessConfiguration;
	mode?: "workload" | "disposal";
	disposalBytes?: number;
	disposalSettleMs?: number;
	scenarioName?: string;
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
const scrollResponseMarker = "__OPERATOR_SCROLL_RESPONSE__";
const scrollResponseMarkerBytes = new TextEncoder().encode(scrollResponseMarker);

const acknowledgementMarks: Record<TerminalAcknowledgement["name"], string> = {
	"first-paint": "operator:terminal-first-paint",
	workload: "operator:terminal-ready",
	"input-echo": "operator:terminal-input-echo",
	resize: "operator:terminal-resize",
	reconnect: "operator:terminal-reconnect",
	"renderer-recovery": "operator:terminal-renderer-recovery",
	disposal: "operator:terminal-disposed",
	scroll: "operator:terminal-scroll-echo",
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

function markerMatcher(markerBytes = workloadMarkerBytes): (bytes: Uint8Array) => boolean {
	let matchedBytes = 0;
	return (bytes) => {
		let completed = false;
		for (const byte of bytes) {
			if (byte === markerBytes[matchedBytes]) {
				matchedBytes += 1;
				if (matchedBytes === markerBytes.length) {
					completed = true;
					matchedBytes = 0;
				}
			} else {
				matchedBytes = byte === markerBytes[0] ? 1 : 0;
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

const sgrWheelUpReport = "\x1b[<64;1;1M";

function scenarioRequiresAlternateScreenResponder(scenarioName?: string): boolean {
	if (!scenarioName) return false;
	const scenarioConfig = (scenarios as Record<string, TerminalScenario | undefined>)[scenarioName];
	return scenarioConfig?.alternateScreen === true;
}

function alternateScreenResponderScript(): string {
	if (navigator.userAgent.includes("Windows")) {
		return `[Console]::Out.Write([char]27 + '[?1049h' + [char]27 + '[?1006h' + [char]27 + '[?1000h'); $i=0; while($true){ $b=[Console]::In.Read(); if ($b -lt 0) { break }; if ($b -ne 77) { continue }; $i++; [Console]::Out.Write([char]27 + '[H' + [char]27 + '[2K${scrollResponseMarker} ' + $i + [char]13 + [char]10) }\r`;
	}
	return `( saved=$(stty -g); cleanup(){ stty "$saved"; printf '\\033[?1000l\\033[?1006l\\033[?1049l'; }; trap 'exit 0' HUP INT TERM; trap cleanup EXIT; stty -echo -icanon min 1 time 0; printf '\\033[?1049h\\033[?1006h\\033[?1000h'; i=0; while chunk=$(dd bs=32 count=1 2>/dev/null); do case "$chunk" in *M*) ;; *) continue ;; esac; i=$((i+1)); printf '\\033[H\\033[2K${scrollResponseMarker} %d\\r\\n' "$i"; done )\r`;
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
	mode = "workload",
	disposalBytes = 2_097_152,
	disposalSettleMs = 200,
	scenarioName,
	createMux = defaultCreateMux,
	onAcknowledgement,
	onRendererKind,
}: TerminalBenchmarkHarnessProps) {
	const startAlternateScreenResponder = scenarioRequiresAlternateScreenResponder(scenarioName);
	const [terminal, setTerminal] = useState<AttachableTerminal | null>(null);
	const [rendererKind, setRendererKind] = useState<TerminalRendererKind | undefined>();
	const [attachmentGeneration, setAttachmentGeneration] = useState(0);
	// Disposal-retention mode: each "operator:terminal-benchmark-disposal" event
	// mounts a fresh XtermTerminal, feeds it synthetic output, then unmounts it so
	// the outer probe can sample retained memory after every disposal ack.
	const [disposalCycle, setDisposalCycle] = useState<{ id: number } | null>(null);
	const disposalCycleIdRef = useRef(0);
	const disposalBytesRef = useRef(disposalBytes);
	disposalBytesRef.current = disposalBytes;
	const disposalSettleMsRef = useRef(disposalSettleMs);
	disposalSettleMsRef.current = disposalSettleMs;
	const muxRef = useRef<TerminalMux | null>(null);
	const requestedWorkloadsRef = useRef(0);
	const pendingWorkloadsRef = useRef(0);
	const workloadByteWindowRef = useRef(false);
	const accumulatedWorkloadBytesRef = useRef(0);
	const lastPrimaryBytesRef = useRef<number | undefined>(undefined);
	const inputEchoPendingRef = useRef(0);
	const scrollPendingRef = useRef(0);
	const scrollPaintPendingRef = useRef(0);
	const responderStartedRef = useRef(false);
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
				return;
			}
			if (scrollPaintPendingRef.current > 0) {
				scrollPaintPendingRef.current -= 1;
				acknowledge("scroll", event.timestamp);
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
		if (mode !== "disposal") return undefined;
		const startDisposalCycle = () => {
			disposalCycleIdRef.current += 1;
			setDisposalCycle({ id: disposalCycleIdRef.current });
		};
		window.addEventListener("operator:terminal-benchmark-disposal", startDisposalCycle);
		return () => window.removeEventListener("operator:terminal-benchmark-disposal", startDisposalCycle);
	}, [mode]);

	useEffect(() => {
		if (mode !== "disposal" || !terminal) return undefined;
		let cancelled = false;
		const timers: ReturnType<typeof setTimeout>[] = [];
		const runCycle = async () => {
			const chunkSize = 65_536;
			const line = "\x1b[38;5;46mheap-probe\x1b[0m 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz\r\n";
			const lineBytes = new TextEncoder().encode(line);
			for (let offset = 0; offset < disposalBytesRef.current; offset += chunkSize) {
				if (cancelled) return;
				const chunk = new Uint8Array(Math.min(chunkSize, disposalBytesRef.current - offset));
				for (let index = 0; index < chunk.byteLength; index += lineBytes.length) {
					chunk.set(lineBytes.subarray(0, Math.min(lineBytes.length, chunk.byteLength - index)), index);
				}
				await new Promise<void>((resolve) => terminal.write(chunk, resolve));
			}
			if (cancelled) return;
			timers.push(setTimeout(() => {
				if (cancelled) return;
				setTerminal(null);
				setDisposalCycle(null);
			}, disposalSettleMsRef.current));
		};
		void runCycle();
		return () => {
			cancelled = true;
			for (const timer of timers) clearTimeout(timer);
		};
	}, [mode, terminal]);

	useEffect(() => {
		if (!terminal || mode === "disposal") return undefined;
		const mux = createMux(muxUrlFromApiBase(configuration.daemonBaseUrl));
		const seesWorkloadMarker = markerMatcher();
		const seesScrollResponse = markerMatcher(scrollResponseMarkerBytes);
		const reconnecting = attachmentGeneration > 0;
		let socketOpened = false;
		let socketClosed = false;
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
				if (scrollPendingRef.current > 0 && seesScrollResponse(bytes)) {
					scrollPendingRef.current -= 1;
					terminal.write(bytes, () => {
						scrollPaintPendingRef.current += 1;
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
				if (state === "open") socketOpened = true;
				if (state === "closed") {
					socketClosed = true;
					setAttachmentGeneration((generation) => generation + 1);
				}
			}),
		];
		mux.open(configuration.terminalId, configuration.columns, configuration.rows);
		if (startAlternateScreenResponder && !responderStartedRef.current) {
			responderStartedRef.current = true;
			mux.sendInput(configuration.terminalId, alternateScreenResponderScript());
		}
		return () => {
			if (muxRef.current === mux) muxRef.current = null;
			for (const unsubscribe of subscriptions) unsubscribe();
			if (startAlternateScreenResponder && responderStartedRef.current) {
				mux.sendInput(configuration.terminalId, "\x03");
				// A dropped socket discards the queued interrupt, so the responder
				// outlives this mux; leaving the flag set keeps the next attachment
				// from feeding it the script a second time.
				responderStartedRef.current = socketOpened && socketClosed;
			}
			mux.close(configuration.terminalId);
			mux.dispose();
		};
	}, [acknowledge, attachmentGeneration, configuration, createMux, mode, startAlternateScreenResponder, terminal]);

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
		const sendScrollProbe = () => {
			const mux = muxRef.current;
			if (!mux || !terminal) return;
			scrollPendingRef.current += 1;
			mux.sendInput(configuration.terminalId, sgrWheelUpReport);
		};
		const forceDisconnect = () => {
			const mux = muxRef.current;
			if (!mux) return;
			mux.dispose();
		};
		window.addEventListener("operator:terminal-benchmark-run", runWorkload);
		window.addEventListener("operator:terminal-benchmark-input", sendInputProbe);
		window.addEventListener("operator:terminal-benchmark-scroll", sendScrollProbe);
		window.addEventListener("operator:terminal-benchmark-reconnect", forceDisconnect);
		return () => {
			window.removeEventListener("operator:terminal-benchmark-run", runWorkload);
			window.removeEventListener("operator:terminal-benchmark-input", sendInputProbe);
			window.removeEventListener("operator:terminal-benchmark-scroll", sendScrollProbe);
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
			{mode === "disposal" ? (
				disposalCycle ? (
					<XtermTerminal
						columns={configuration.columns}
						geometryMode="fixed"
						key={`disposal-cycle-${disposalCycle.id}`}
						onReady={setTerminal}
						onRendererKind={rendererChanged}
						onTimestamp={onTimestamp}
						rows={configuration.rows}
						scrollback={configuration.scrollback}
						theme="dark"
					/>
				) : null
			) : (
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
			)}
		</div>
	);
}
