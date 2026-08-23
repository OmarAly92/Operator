import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { aggregatePhase0Evidence } from "./phase0-aggregate.mjs";

const sourceCommit = "8311fc6004cefc1146dc1ac2b13413cb801c835b";
const identity = { identifier: "dev.operator.desktop", productName: "Operator", executable: "operator", aliasesPreserved: true };
const updaterSigning = { valid: true, signatureValid: true, privateKeyLeaked: false, format: "tauri-minisign", signer: "@tauri-apps/cli@2.11.4", publicKeyFingerprint: "ab".repeat(32), signatureSha256: "ef".repeat(32) };

async function writeSummaries(root, override = {}, actualUpdater = updaterSigning) {
	for (const platform of ["darwin", "win32", "linux"]) {
		const directory = path.join(root, platform);
		await mkdir(directory, { recursive: true });
		await writeFile(path.join(directory, `phase0-platform-${platform}.json`), JSON.stringify({
			schemaVersion: 1,
			platform,
			sourceCommit: override[platform]?.sourceCommit ?? sourceCommit,
			identity,
			updaterSigning,
			evidence: { marker: platform },
		}));
	}
	const updaterDirectory = path.join(root, "updater-signing");
	await mkdir(updaterDirectory, { recursive: true });
	await writeFile(path.join(updaterDirectory, "updater-signing-evidence.json"), JSON.stringify(actualUpdater));
}

test("aggregator binds every platform summary to the workflow commit and its artifact digest", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-aggregate-"));
	try {
		await writeSummaries(root);
		const evidence = await aggregatePhase0Evidence(root, {
			sourceCommit,
			repository: "OmarAly92/operator",
			runId: "123",
			attempt: 1,
			now: 0,
		});
		assert.equal(evidence.provenance.sourceCommit, sourceCommit);
		for (const platform of ["darwin", "win32", "linux"]) {
			assert.equal(evidence.platforms[platform].provenance.sourceCommit, sourceCommit);
			assert.match(evidence.platforms[platform].provenance.artifactSha256, /^[0-9a-f]{64}$/);
		}
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("aggregator rejects platform updater claims that disagree with the retained signer evidence", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-aggregate-updater-"));
	try {
		await writeSummaries(root, {}, { ...updaterSigning, publicKeyFingerprint: "cd".repeat(32) });
		await assert.rejects(
			aggregatePhase0Evidence(root, { sourceCommit, repository: "OmarAly92/operator", runId: "123", attempt: 1 }),
			/updater evidence disagrees/,
		);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});

test("aggregator rejects a platform summary from another commit", async () => {
	const root = await mkdtemp(path.join(os.tmpdir(), "operator-phase0-aggregate-mismatch-"));
	try {
		await writeSummaries(root, { win32: { sourceCommit: "751744d15340c3d65166023f8c358f9a2438af78" } });
		await assert.rejects(
			aggregatePhase0Evidence(root, { sourceCommit, repository: "OmarAly92/operator", runId: "123", attempt: 1 }),
			/provenance is invalid: win32/,
		);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
});
