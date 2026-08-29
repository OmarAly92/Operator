import scenarios from "./scenarios.json";
import {
	INPUT_BYTE,
	WORKLOAD_METADATA,
	chunkBytes,
	createLargeOutput,
	createVtebench,
} from "./workloads.mjs";
import { XtermBenchmarkRenderer } from "./adapters/xterm";
import { DomBenchmarkRenderer } from "./adapters/dom";

export interface Geometry {
	columns: number;
	rows: number;
	scrollback: number;
}

export type RendererKind = "webgl" | "canvas";
export type RendererName = "xterm" | "dom";
export type ScenarioName = keyof typeof scenarios;

export interface BenchmarkRenderer {
	readonly kind: RendererKind;
	readonly version: string;
	mount(host: HTMLElement, geometry: Geometry): Promise<void>;
	write(bytes: Uint8Array): Promise<void>;
	onInput(listener: (data: string) => void): () => void;
	waitForPaint(): Promise<number>;
	dispatchPrintableKey(data: string): void;
	dispose(): void;
}

type ScenarioResult = {
	configuration: (typeof scenarios)[ScenarioName];
	samples: number[];
	median: number;
	p95: number;
	unit: string;
	workload: string;
	seed?: number;
	workloadDigest: string;
};

const clearBytes = new TextEncoder().encode("\x1bc");

function summary(samples: number[]) {
	const sorted = [...samples].sort((left, right) => left - right);
	const middle = Math.floor(sorted.length / 2);
	return {
		median: sorted.length % 2 === 0
			? (sorted[middle - 1] + sorted[middle]) / 2
			: sorted[middle],
		p95: sorted[Math.ceil(sorted.length * 0.95) - 1],
	};
}

async function digest(bytes: Uint8Array): Promise<string> {
	const hash = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
	return [...new Uint8Array(hash)]
		.map((byte) => byte.toString(16).padStart(2, "0"))
		.join("");
}

async function clear(renderer: BenchmarkRenderer): Promise<void> {
	await renderer.write(clearBytes);
	await renderer.waitForPaint();
}

async function writeWorkload(renderer: BenchmarkRenderer, bytes: Uint8Array): Promise<number> {
	const startedAt = performance.now();
	for (const chunk of chunkBytes(bytes)) await renderer.write(chunk);
	await renderer.waitForPaint();
	return performance.now() - startedAt;
}

async function inputLatency(renderer: BenchmarkRenderer): Promise<number> {
	return new Promise((resolve, reject) => {
		let startedAt = 0;
		const unsubscribe = renderer.onInput((data) => {
			unsubscribe();
			if (data !== "x") {
				reject(new Error(`unexpected xterm input: ${JSON.stringify(data)}`));
				return;
			}
			void renderer.write(INPUT_BYTE)
				.then(() => renderer.waitForPaint())
				.then((paintedAt) => resolve(paintedAt - startedAt), reject);
		});
		startedAt = performance.now();
		renderer.dispatchPrintableKey("x");
	});
}

async function runScenario(
	host: HTMLElement,
	rendererName: RendererName,
	name: ScenarioName,
	invocationKinds: Set<RendererKind>,
): Promise<{ result: ScenarioResult; rendererVersion: string; rendererKind: RendererKind }> {
	const configuration = scenarios[name];
	const renderer = rendererName === "xterm"
		? new XtermBenchmarkRenderer()
		: new DomBenchmarkRenderer();
	await renderer.mount(host, configuration);
	const workload = name === "vtebench"
		? createVtebench(scenarios.vtebench.seed)
		: name === "large-output"
			? createLargeOutput()
			: INPUT_BYTE;
	const metadata = WORKLOAD_METADATA[name];
	if (await digest(workload) !== metadata.workloadDigest) {
		renderer.dispose();
		throw new Error(`${name} workload digest does not match its generator`);
	}
	const measure = async () => {
		await clear(renderer);
		const before = renderer.kind;
		const duration = name === "input-latency"
			? await inputLatency(renderer)
			: await writeWorkload(renderer, workload);
		const after = renderer.kind;
		invocationKinds.add(before);
		invocationKinds.add(after);
		if (invocationKinds.size !== 1) {
			throw new Error("renderer kind changed during the benchmark; rerun the invocation");
		}
		if (!Number.isFinite(duration) || duration <= 0) throw new Error(`${name} produced an invalid duration`);
		if (name === "vtebench") return 1000 / duration;
		if (name === "large-output") return workload.byteLength * 1000 / duration;
		return duration;
	};

	try {
		for (let index = 0; index < configuration.warmups; index += 1) await measure();
		const samples: number[] = [];
		for (let index = 0; index < configuration.samples; index += 1) samples.push(await measure());
		const { median, p95 } = summary(samples);
		return {
			result: {
				configuration,
				samples,
				median,
				p95,
				unit: configuration.unit,
				...metadata,
			},
			rendererVersion: renderer.version,
			rendererKind: renderer.kind,
		};
	} finally {
		renderer.dispose();
		host.replaceChildren();
	}
}

export async function runBenchmarks(host: HTMLElement, rendererName: RendererName, names: ScenarioName[]) {
	const invocationKinds = new Set<RendererKind>();
	const measured: Partial<Record<ScenarioName, ScenarioResult>> = {};
	let rendererVersion = "";
	let rendererKind: RendererKind | undefined;
	for (const name of names) {
		const scenario = await runScenario(host, rendererName, name, invocationKinds);
		measured[name] = scenario.result;
		rendererVersion = scenario.rendererVersion;
		rendererKind = scenario.rendererKind;
	}
	if (!rendererKind || invocationKinds.size !== 1) throw new Error("benchmark did not preserve one renderer kind");
	return {
		renderer: rendererName,
		rendererVersion,
		rendererKind,
		scenarios: measured,
	};
}
