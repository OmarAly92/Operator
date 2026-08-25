import { createRoot } from "react-dom/client";
import { I18nextProvider } from "react-i18next";
import "@xterm/xterm/css/xterm.css";
import "../../src/renderer/styles.css";
import { appI18n } from "../../src/renderer/i18n";
import { SkinProvider } from "../../src/renderer/theme/skin-context";
import {
	TerminalBenchmarkHarness,
	terminalHarnessConfiguration,
	type TerminalAcknowledgement,
} from "./harness";
import { nativeTerminalRuntimeIdentity } from "./runtime";

type ReporterMessage =
	| TerminalAcknowledgement
	| { name: "workload-start"; timestamp: number }
	| { name: "disposal-baseline"; timestamp: number }
	| { name: "renderer"; rendererKind: "webgl" | "canvas"; webviewRuntimeVersion: string; displayScale: number };

type ScenarioDriver = {
	eventName:
		| "operator:terminal-benchmark-run"
		| "operator:terminal-benchmark-input"
		| "operator:terminal-benchmark-reconnect"
		| "operator:terminal-benchmark-disposal";
	ackName: TerminalAcknowledgement["name"];
	detail?: (iteration: number) => WorkloadRequestDetail;
};

type WorkloadRequestDetail = {
	scenario: "vtebench" | "large-output" | "cpu-time" | "active-memory";
	iteration: number;
};

const scenarioDrivers: Record<string, ScenarioDriver> = {
	vtebench: { eventName: "operator:terminal-benchmark-run", ackName: "workload", detail: (iteration) => ({ scenario: "vtebench", iteration }) },
	"large-output": { eventName: "operator:terminal-benchmark-run", ackName: "workload", detail: (iteration) => ({ scenario: "large-output", iteration }) },
	"cpu-time": { eventName: "operator:terminal-benchmark-run", ackName: "workload", detail: (iteration) => ({ scenario: "cpu-time", iteration }) },
	"active-memory": { eventName: "operator:terminal-benchmark-run", ackName: "workload", detail: (iteration) => ({ scenario: "active-memory", iteration }) },
	"input-latency": { eventName: "operator:terminal-benchmark-input", ackName: "input-echo" },
	reconnect: { eventName: "operator:terminal-benchmark-reconnect", ackName: "reconnect" },
	disposal: { eventName: "operator:terminal-benchmark-disposal", ackName: "disposal" },
};

function reporterUrl(parameters: URLSearchParams): string | undefined {
	const rawUrl = parameters.get("reportUrl");
	if (!rawUrl) return undefined;
	const url = new URL(rawUrl);
	if (url.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
		throw new Error("terminal benchmark reporter must use loopback HTTP");
	}
	return url.toString();
}

function reporter(url: string | undefined) {
	return (message: ReporterMessage) => {
		if (!url) return;
		void fetch(url, {
			body: JSON.stringify(message),
			headers: { "content-type": "text/plain;charset=UTF-8" },
			keepalive: true,
			method: "POST",
		});
	};
}

function scenarioController(
	parameters: URLSearchParams,
	report: (message: ReporterMessage) => void,
	onComplete: () => void,
) {
	const scenario = parameters.get("scenario");
	if (!scenario) return (_acknowledgement: TerminalAcknowledgement) => undefined;
	const driver = scenarioDrivers[scenario];
	if (!driver) throw new Error("unsupported terminal benchmark scenario");
	const warmups = Number(parameters.get("warmups"));
	const samples = Number(parameters.get("samples"));
	const fixedWorkloads = Number(parameters.get("fixedWorkloads") ?? "1");
	if (!Number.isInteger(warmups) || warmups < 0 || !Number.isInteger(samples) || samples < 1 || !Number.isInteger(fixedWorkloads) || fixedWorkloads < 1) {
		throw new Error("terminal benchmark requires valid warmups samples and fixedWorkloads");
	}
	const totalIterations = warmups + samples * fixedWorkloads;
	let iteration = 0;
	let started = false;
	const runIteration = () => {
		requestAnimationFrame(() => {
			const timestamp = performance.now();
			report({ name: "workload-start", timestamp });
			window.dispatchEvent(new CustomEvent(driver.eventName, { detail: driver.detail?.(iteration) }));
		});
	};
	if (scenario === "disposal") {
		// No base terminal mounts in disposal mode, so there is no first-paint ack
		// to start from. Announce the baseline, then begin cycling after a fixed
		// delay so the outer probe can sample pre-cycles memory.
		report({ name: "disposal-baseline", timestamp: performance.now() });
		setTimeout(runIteration, Math.max(0, Number(parameters.get("disposalStartMs") ?? 3000)));
	}
	return (acknowledgement: TerminalAcknowledgement) => {
		report(acknowledgement);
		if (acknowledgement.name === "first-paint" && !started) {
			started = true;
			runIteration();
			return;
		}
		if (acknowledgement.name !== driver.ackName) return;
		iteration += 1;
		if (iteration < totalIterations) {
			runIteration();
		} else {
			requestAnimationFrame(onComplete);
		}
	};
}

async function renderHarness() {
	const parameters = new URLSearchParams(window.location.search);
	const report = reporter(reporterUrl(parameters));
	const webviewRuntimeVersion = await nativeTerminalRuntimeIdentity();
	const root = createRoot(document.getElementById("root") as HTMLElement);
	const onAcknowledgement = scenarioController(parameters, report, () => root.unmount());
	root.render(
		<I18nextProvider i18n={appI18n}>
			<SkinProvider>
				<TerminalBenchmarkHarness
					configuration={terminalHarnessConfiguration(window.location.search)}
					disposalBytes={Number(parameters.get("disposalBytes") ?? 2_097_152)}
					mode={parameters.get("scenario") === "disposal" ? "disposal" : "workload"}
					onAcknowledgement={onAcknowledgement}
					onRendererKind={(rendererKind) => {
						report({
							displayScale: window.devicePixelRatio,
							name: "renderer",
							rendererKind,
							webviewRuntimeVersion,
						});
					}}
				/>
			</SkinProvider>
		</I18nextProvider>,
	);
}

function renderFailure(error: unknown) {
	const root = document.getElementById("root") as HTMLElement;
	root.setAttribute("role", "alert");
	root.textContent = error instanceof Error ? error.message : String(error);
}

void renderHarness().catch(renderFailure);
