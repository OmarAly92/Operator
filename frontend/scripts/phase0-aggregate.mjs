import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PLATFORMS = Object.freeze(["darwin", "win32", "linux"]);

async function findFile(root, basename) {
	const matches = [];
	async function visit(directory) {
		for (const entry of await readdir(directory, { withFileTypes: true })) {
			const target = path.join(directory, entry.name);
			if (entry.isDirectory()) await visit(target);
			else if (entry.isFile() && entry.name === basename) matches.push(target);
		}
	}
	await visit(root);
	if (matches.length !== 1) throw new Error(`expected exactly one ${basename}, found ${matches.length}`);
	return matches[0];
}

function sameJson(left, right) {
	return JSON.stringify(left) === JSON.stringify(right);
}

export async function aggregatePhase0Evidence(inputRoot, context) {
	if (!/^[0-9a-f]{40}$/.test(context.sourceCommit ?? "")) throw new Error("aggregate source commit is invalid");
	if (!context.repository || !context.runId || !Number.isInteger(context.attempt) || context.attempt < 1) {
		throw new Error("aggregate workflow context is invalid");
	}
	const platforms = {};
	let identity;
	let updaterSigning;
	for (const platform of PLATFORMS) {
		const file = await findFile(inputRoot, `phase0-platform-${platform}.json`);
		const bytes = await readFile(file);
		let summary;
		try {
			summary = JSON.parse(bytes);
		} catch {
			throw new Error(`platform summary contains invalid JSON: ${platform}`);
		}
		if (summary?.schemaVersion !== 1 || summary.platform !== platform || summary.sourceCommit !== context.sourceCommit || !summary.evidence) {
			throw new Error(`platform summary provenance is invalid: ${platform}`);
		}
		if (identity && !sameJson(identity, summary.identity)) throw new Error(`platform identity evidence disagrees on ${platform}`);
		if (updaterSigning && !sameJson(updaterSigning, summary.updaterSigning)) throw new Error(`platform updater evidence disagrees on ${platform}`);
		identity ??= summary.identity;
		updaterSigning ??= summary.updaterSigning;
		platforms[platform] = {
			...summary.evidence,
			provenance: {
				sourceCommit: context.sourceCommit,
				artifactSha256: createHash("sha256").update(bytes).digest("hex"),
			},
		};
	}
	const updaterFile = await findFile(inputRoot, "updater-signing-evidence.json");
	let retainedUpdater;
	try {
		retainedUpdater = JSON.parse(await readFile(updaterFile, "utf8"));
	} catch {
		throw new Error("retained updater evidence contains invalid JSON");
	}
	if (!sameJson(updaterSigning, retainedUpdater)) throw new Error("platform updater evidence disagrees with retained signer evidence");
	return {
		schemaVersion: 1,
		provenance: {
			kind: "phase0-ci-aggregate",
			sourceCommit: context.sourceCommit,
			generatedAt: new Date(context.now ?? Date.now()).toISOString(),
			workflowRun: { repository: context.repository, runId: context.runId, attempt: context.attempt },
		},
		platforms,
		identity,
		updaterSigning: retainedUpdater,
	};
}

function parseArgs(argv) {
	const args = {};
	for (let index = 0; index < argv.length; index += 2) {
		const flag = argv[index];
		const value = argv[index + 1];
		if (flag === "--input") args.input = value;
		else if (flag === "--output") args.output = value;
		else throw new Error(`unknown or incomplete flag: ${flag ?? ""}`);
	}
	if (!args.input || !args.output) throw new Error("--input and --output are required");
	return args;
}

async function main() {
	const args = parseArgs(process.argv.slice(2));
	const evidence = await aggregatePhase0Evidence(path.resolve(args.input), {
		sourceCommit: process.env.GITHUB_SHA,
		repository: process.env.GITHUB_REPOSITORY,
		runId: process.env.GITHUB_RUN_ID,
		attempt: Number(process.env.GITHUB_RUN_ATTEMPT),
	});
	await writeFile(path.resolve(args.output), `${JSON.stringify(evidence, null, "\t")}\n`, "utf8");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
