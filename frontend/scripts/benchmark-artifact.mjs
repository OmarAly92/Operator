import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
	benchmarkResultPath,
	collectGitMetadata,
	collectHostMetadata,
	createBenchmarkResult,
	parseNamedArguments,
	writeBenchmarkResult,
} from "./benchmark-result.mjs";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));

export function parseArtifactArguments(argv, env = process.env) {
	const namedArguments = parseNamedArguments(argv);
	if (namedArguments.shell !== "electron") throw new Error("Task 2 supports only electron artifact measurements");
	if (Object.keys(namedArguments).some((key) => key !== "shell")) throw new Error("unknown artifact benchmark argument");
	if (!env.OPERATOR_BENCH_SIGNED_ARTIFACT) throw new Error("OPERATOR_BENCH_SIGNED_ARTIFACT must name the native signed download artifact");
	if (!env.OPERATOR_BENCH_INSTALLED_APP) throw new Error("OPERATOR_BENCH_INSTALLED_APP must name the installed application");
	return {
		shell: namedArguments.shell,
		signedArtifact: env.OPERATOR_BENCH_SIGNED_ARTIFACT,
		installedApp: env.OPERATOR_BENCH_INSTALLED_APP,
		managedBrowser: env.OPERATOR_BENCH_MANAGED_BROWSER,
	};
}

export async function measurePathBytes(targetPath) {
	const metadata = await lstat(targetPath);
	if (metadata.isSymbolicLink()) return 0;
	if (metadata.isFile()) return metadata.size;
	if (!metadata.isDirectory()) return 0;
	const entries = await readdir(targetPath);
	const sizes = await Promise.all(entries.map((entry) => measurePathBytes(path.join(targetPath, entry))));
	return sizes.reduce((total, size) => total + size, 0);
}

async function artifactRendererMetadata(env) {
	const electronPackage = JSON.parse(await readFile(new URL("../node_modules/electron/package.json", import.meta.url), "utf8"));
	const configuredScale = Number(env.OPERATOR_BENCH_DISPLAY_SCALE);
	return {
		webviewRuntimeVersion: env.OPERATOR_BENCH_WEBVIEW_RUNTIME_VERSION || `Electron ${electronPackage.version}`,
		rendererKind: env.OPERATOR_BENCH_RENDERER_KIND || "chromium",
		displayScale: Number.isFinite(configuredScale) && configuredScale > 0 ? configuredScale : 1,
	};
}

export async function runArtifactBenchmark(argv = process.argv.slice(2), env = process.env) {
	const options = parseArtifactArguments(argv, env);
	const measurements = [
		{ scenario: "base-signed-download", artifactKind: "primary-signed-update", target: options.signedArtifact },
		{ scenario: "base-installed-footprint", artifactKind: "installed-application", target: options.installedApp },
	];
	if (options.managedBrowser) {
		measurements.push({
			scenario: "managed-browser-footprint",
			artifactKind: "post-browser-install",
			target: options.managedBrowser,
		});
	}
	const git = await collectGitMetadata();
	const host = collectHostMetadata();
	const renderer = await artifactRendererMetadata(env);
	const benchmarkResults = [];
	for (const measurement of measurements) {
		const bytes = await measurePathBytes(measurement.target);
		const benchmarkResult = createBenchmarkResult({
			shell: options.shell,
			scenario: measurement.scenario,
			buildProfile: env.OPERATOR_BENCH_BUILD_PROFILE || "local-artifact",
			git,
			host,
			renderer,
			scenarioConfiguration: {
				artifactKind: measurement.artifactKind,
				accounting: "recursive-regular-file-bytes",
				baseContents: ["go-daemon", "agent-browser", "node-22.23.2-acp-runtime"],
			},
			warmups: 0,
			samples: [bytes],
			unit: "bytes",
		});
		const outputPath = benchmarkResultPath({
			shell: options.shell,
			scenario: measurement.scenario,
			variant: env.OPERATOR_BENCH_VARIANT,
		});
		await writeBenchmarkResult(outputPath, benchmarkResult);
		process.stdout.write(`${path.relative(frontendRoot, outputPath)}\n`);
		benchmarkResults.push(benchmarkResult);
	}
	return benchmarkResults;
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("OPERATOR_BENCH_SIGNED_ARTIFACT=... OPERATOR_BENCH_INSTALLED_APP=... node scripts/benchmark-artifact.mjs --shell electron\n");
		return;
	}
	await runArtifactBenchmark();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
