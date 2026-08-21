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

type ReporterMessage =
	| TerminalAcknowledgement
	| { name: "workload-start"; timestamp: number }
	| { name: "renderer"; rendererKind: "webgl" | "canvas"; webviewRuntimeVersion: string; displayScale: number };

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

function workloadController(
	parameters: URLSearchParams,
	report: (message: ReporterMessage) => void,
	onComplete: () => void,
) {
	const scenario = parameters.get("scenario");
	if (!scenario) return (_acknowledgement: TerminalAcknowledgement) => undefined;
	if (scenario !== "vtebench" && scenario !== "large-output") throw new Error("unsupported terminal benchmark workload");
	const warmups = Number(parameters.get("warmups"));
	const samples = Number(parameters.get("samples"));
	if (!Number.isInteger(warmups) || warmups < 0 || !Number.isInteger(samples) || samples < 1) {
		throw new Error("terminal benchmark requires valid warmups and samples");
	}
	let iteration = 0;
	let started = false;
	const run = () => {
		const timestamp = performance.now();
		report({ name: "workload-start", timestamp });
		window.dispatchEvent(new CustomEvent("operator:terminal-benchmark-run", { detail: { scenario, iteration } }));
	};
	return (acknowledgement: TerminalAcknowledgement) => {
		report(acknowledgement);
		if (acknowledgement.name === "first-paint" && !started) {
			started = true;
			requestAnimationFrame(run);
		}
		if (acknowledgement.name !== "workload") return;
		iteration += 1;
		if (iteration < warmups + samples) {
			requestAnimationFrame(run);
		} else {
			requestAnimationFrame(onComplete);
		}
	};
}

function renderHarness() {
	const parameters = new URLSearchParams(window.location.search);
	const report = reporter(reporterUrl(parameters));
	const root = createRoot(document.getElementById("root") as HTMLElement);
	const onAcknowledgement = workloadController(parameters, report, () => root.unmount());
	root.render(
		<I18nextProvider i18n={appI18n}>
			<SkinProvider>
				<TerminalBenchmarkHarness
					configuration={terminalHarnessConfiguration(window.location.search)}
					onAcknowledgement={onAcknowledgement}
					onRendererKind={(rendererKind) => {
						report({
							displayScale: window.devicePixelRatio,
							name: "renderer",
							rendererKind,
							webviewRuntimeVersion: navigator.userAgent,
						});
					}}
				/>
			</SkinProvider>
		</I18nextProvider>,
	);
}

try {
	renderHarness();
} catch (error) {
	const root = document.getElementById("root") as HTMLElement;
	root.setAttribute("role", "alert");
	root.textContent = error instanceof Error ? error.message : String(error);
}
