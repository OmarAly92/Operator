import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { runEphemeralSigningFlow, verifyFixture } from "./phase0-updater-signing.mjs";

test("updater signing uses the pinned Tauri minisign signer and retains public verification material", async () => {
	const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), "operator-tauri-updater-signing-"));
	try {
		const fixturePath = path.join(temporaryRoot, "Operator.tar.gz");
		const outputDir = path.join(temporaryRoot, "output");
		await writeFile(fixturePath, "tauri updater fixture");
		const evidence = await runEphemeralSigningFlow({
			tmpDir: temporaryRoot,
			fixturePath,
			outputDir,
			gitRoot: path.resolve(new URL("../../", import.meta.url).pathname),
		});
		assert.equal(evidence.format, "tauri-minisign");
		assert.equal(evidence.signer, "@tauri-apps/cli@2.11.4");
		assert.equal(evidence.signatureValid, true);
		assert.match(evidence.publicKeyFingerprint, /^[0-9a-f]{64}$/);
		const signature = await readFile(path.join(outputDir, "fixture.sig"), "utf8");
		const publicKey = await readFile(path.join(outputDir, "public.key"), "utf8");
		assert.match(Buffer.from(signature.trim(), "base64").toString("utf8"), /^untrusted comment:/);
		assert.match(Buffer.from(publicKey.trim(), "base64").toString("utf8"), /^untrusted comment:/);
		const retainedFixture = await readFile(path.join(outputDir, "fixture.tar"), "utf8");
		assert.equal(retainedFixture, "tauri updater fixture");
		const reverified = await verifyFixture({
			fixturePath: path.join(outputDir, "fixture.tar"),
			signaturePath: path.join(outputDir, "fixture.sig"),
			publicKeyPath: path.join(outputDir, "public.key"),
		});
		assert.equal(reverified, true);
		await writeFile(fixturePath, "tampered updater fixture");
		await assert.rejects(verifyFixture({
			fixturePath,
			signaturePath: path.join(outputDir, "fixture.sig"),
			publicKeyPath: path.join(outputDir, "public.key"),
		}), /signature is invalid/);
		await assert.rejects(readFile(path.join(outputDir, "private.key")), /ENOENT/);
	} finally {
		await rm(temporaryRoot, { recursive: true, force: true });
	}
});
