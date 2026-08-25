import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const EXPECTED_ALLOWLIST = Object.freeze(["app://renderer", "tauri://localhost", "http://tauri.localhost"]);
const READY_PATH = "/readyz";

export function corsProbeTargets() {
	return Object.freeze([
		{ origin: "app://renderer", expectGranted: true },
		{ origin: "tauri://localhost", expectGranted: true },
		{ origin: "http://tauri.localhost", expectGranted: true },
		{ origin: "null", expectGranted: false },
		{ origin: "*", expectGranted: false },
		{ origin: "https://evil.example", expectGranted: false },
		{ origin: "http://tauri.localhost.evil.example", expectGranted: false },
		{ origin: "https://tauri.localhost", expectGranted: false },
		{ origin: "http://localhost:5173", expectGranted: false },
	]);
}

function loopbackBaseUrl(rawUrl) {
	const url = new URL(rawUrl);
	if (!["http:", "https:"].includes(url.protocol) || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
		throw new Error(`cors probe target must be a loopback HTTP(S) origin: ${rawUrl}`);
	}
	url.pathname = "/";
	url.search = "";
	url.hash = "";
	return url.toString();
}

async function probeOrigin(baseUrl, target, fetchImpl) {
	const requestUrl = new URL(READY_PATH, baseUrl).toString();
	let response;
	try {
		response = await fetchImpl(requestUrl, {
			headers: { origin: target.origin },
			signal: AbortSignal.timeout(10_000),
		});
	} catch (error) {
		throw new Error(`cors probe for ${target.origin} could not reach the daemon: ${error instanceof Error ? error.message : String(error)}`);
	}
	const allowOrigin = response.headers.get("access-control-allow-origin");
	const vary = response.headers.get("vary") ?? "";
	await response.arrayBuffer().catch(() => undefined);
	return {
		origin: target.origin,
		status: response.status,
		allowOrigin,
		vary,
	};
}

function assertObservationMatchesContract(target, observation, failures) {
	if (observation.vary.split(",").map((value) => value.trim().toLowerCase()).includes("origin") === false) {
		failures.push(`${target.origin}: response is missing the required Vary: Origin cache guard`);
	}
	const expectedStatus = target.expectGranted ? 200 : 403;
	if (observation.status !== expectedStatus) {
		failures.push(`${target.origin}: observed status ${observation.status} but the committed CORS boundary requires ${expectedStatus}`);
	}
	if (target.expectGranted) {
		if (observation.allowOrigin !== target.origin) {
			failures.push(`${target.origin}: expected an exact access-control-allow-origin echo, received ${JSON.stringify(observation.allowOrigin)}`);
		}
	} else if (observation.allowOrigin !== null) {
		failures.push(`${target.origin}: rejected origins must never receive an access-control-allow-origin header, received ${JSON.stringify(observation.allowOrigin)}`);
	}
}

export async function runCorsProbe({ baseUrl, targets = corsProbeTargets(), allowlist = EXPECTED_ALLOWLIST, fetchImpl = fetch }) {
	const resolvedBase = loopbackBaseUrl(baseUrl);
	const observations = [];
	for (const target of targets) {
		observations.push(await probeOrigin(resolvedBase, target, fetchImpl));
	}
	const failures = [];
	for (let index = 0; index < targets.length; index += 1) {
		assertObservationMatchesContract(targets[index], observations[index], failures);
	}
	const grantedOrigins = observations.filter((entry) => entry.allowOrigin !== null).map((entry) => entry.origin).sort();
	const exactAllowlist = JSON.stringify(grantedOrigins) === JSON.stringify([...allowlist].sort());
	if (!exactAllowlist) {
		failures.push(`observed granted origins [${grantedOrigins.join(", ")}] are not exactly the configured allowlist`);
	}
	if (failures.length > 0) {
		throw new Error(`cors evidence refused: ${failures.join("; ")}`);
	}
	return {
		schemaVersion: 1,
		passed: true,
		exactAllowlist: true,
		allowlist: [...allowlist],
		probes: observations.map((entry) => ({
			origin: entry.origin,
			allowed: entry.allowOrigin !== null,
			status: entry.status,
			allowOrigin: entry.allowOrigin,
			varyIncludesOrigin: entry.vary.split(",").map((value) => value.trim().toLowerCase()).includes("origin"),
		})),
	};
}

function parseArgs(argv) {
	const args = {};
	for (let index = 0; index < argv.length; index += 2) {
		const flag = argv[index];
		const value = argv[index + 1];
		if (!flag?.startsWith("--") || value === undefined) throw new Error(`invalid argument: ${flag ?? ""}`);
		args[flag.slice(2)] = value;
	}
	return args;
}

async function main() {
	if (process.argv.includes("--help")) {
		process.stdout.write("Usage: node scripts/phase0-cors-probe.mjs --url <loopback daemon base url> --output <cors-evidence.json>\n");
		return;
	}
	const args = parseArgs(process.argv.slice(2));
	if (!args.url || !args.output) throw new Error("--url and --output are required");
	const evidence = await runCorsProbe({ baseUrl: args.url });
	await mkdirFor(path.resolve(args.output));
	await writeFile(path.resolve(args.output), `${JSON.stringify(evidence, null, "\t")}\n`, "utf8");
	process.stdout.write(`cors evidence written: ${path.resolve(args.output)} (${evidence.probes.length} probes)\n`);
}

async function mkdirFor(filePath) {
	const { mkdir } = await import("node:fs/promises");
	await mkdir(path.dirname(filePath), { recursive: true });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
