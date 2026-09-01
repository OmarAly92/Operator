import { runBenchmarks, type RendererName, type ScenarioName } from "./harness";

declare global {
	interface Window {
		__operatorBenchmarkReport: (result: unknown) => Promise<void>;
	}
}

const knownScenarios = new Set<ScenarioName>([
	"vtebench",
	"large-output",
	"input-latency",
	"input-latency-owned",
	"find-500k",
]);

const knownRenderers = new Set<RendererName>([
	"xterm",
	"dom",
]);

async function main() {
	const host = document.getElementById("terminal");
	if (!host) throw new Error("benchmark host is missing");
	const params = new URLSearchParams(location.search);
	const renderer = params.get("renderer") ?? "xterm";
	if (!knownRenderers.has(renderer as RendererName)) {
		throw new Error(`invalid benchmark renderer: ${renderer}`);
	}
	const requested = params.get("scenarios")?.split(",") ?? [];
	if (requested.length === 0 || requested.some((name) => !knownScenarios.has(name as ScenarioName))) {
		throw new Error("invalid benchmark scenarios");
	}
	const result = await runBenchmarks(host, renderer as RendererName, requested as ScenarioName[]);
	await window.__operatorBenchmarkReport({
		...result,
		displayScale: window.devicePixelRatio,
	});
}

try {
	await main();
} catch (error) {
	await window.__operatorBenchmarkReport({
		error: error instanceof Error ? error.message : String(error),
	});
}
