import { runBenchmarks, type ScenarioName } from "./harness";

declare global {
	interface Window {
		__operatorBenchmarkReport: (result: unknown) => Promise<void>;
	}
}

const knownScenarios = new Set<ScenarioName>([
	"vtebench",
	"large-output",
	"input-latency",
]);

async function main() {
	const host = document.getElementById("terminal");
	if (!host) throw new Error("benchmark host is missing");
	const requested = new URLSearchParams(location.search).get("scenarios")?.split(",") ?? [];
	if (requested.length === 0 || requested.some((name) => !knownScenarios.has(name as ScenarioName))) {
		throw new Error("invalid benchmark scenarios");
	}
	const result = await runBenchmarks(host, requested as ScenarioName[]);
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
