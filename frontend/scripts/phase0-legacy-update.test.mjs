import assert from "node:assert/strict";
import test from "node:test";
import {
  evaluateLegacyUpdate,
  recordMigrationEvidence,
  validateBridgeHandoff,
  validateMigrationExercise,
  DECISION as LEGACY_DECISION,
} from "./phase0-legacy-update.mjs";

function validMigrations() {
  const exercise = {
    kind: "electron-to-tauri",
    runner: "native-installed-update",
    legacyVersion: "0.10.0",
    targetVersion: "0.10.3",
    legacyArtifactSha256: "ab".repeat(32),
    targetArtifactSha256: "cd".repeat(32),
    launchedLegacy: true,
    updateRequested: true,
    updaterExitCode: 0,
    launchedTarget: true,
    identityPreserved: true,
    statePreserved: true,
    observedAt: "2026-08-22T00:00:00.000Z",
  };
  return {
    darwin: { directSuccess: true, bridgeRequired: false, bridgeProven: false, exercise: { ...exercise } },
    win32: { directSuccess: true, bridgeRequired: false, bridgeProven: false, exercise: { ...exercise } },
    linux: { directSuccess: true, bridgeRequired: false, bridgeProven: false, exercise: { ...exercise } },
  };
}

test("direct migration on all platforms succeeds", () => {
  const result = evaluateLegacyUpdate(validMigrations());
  assert.equal(result.success, true);
  assert.equal(result.bridgeRequired, false);
});

test("directSuccess without an observed native migration exercise fails closed", () => {
  const migrations = validMigrations();
  delete migrations.darwin.exercise;
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, false);
  assert.match(result.reasons.join(" "), /exercise/);
});

test("failed direct migration without bridge produces failure", () => {
  const migrations = validMigrations();
  migrations.darwin.directSuccess = false;
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, false);
  assert.match(result.reasons.join(" "), /direct migration/);
});

test("failed direct migration with proven bridge still succeeds but records rollout work", () => {
  const migrations = validMigrations();
  migrations.win32.directSuccess = false;
  migrations.win32.bridgeRequired = true;
  migrations.win32.bridgeProven = true;
  migrations.win32.handoff = {
    signed: true,
    signatureValid: true,
    replacesDirectly: true,
    exerciseObserved: true,
    artifactSha256: "ef".repeat(32),
    targetArtifactSha256: "cd".repeat(32),
  };
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, true);
  assert.equal(result.bridgeRequired, true);
  assert.match(result.reasons.join(" "), /bridge/);
});

test("failed direct migration with unproven bridge fails", () => {
  const migrations = validMigrations();
  migrations.linux.directSuccess = false;
  migrations.linux.bridgeRequired = true;
  migrations.linux.bridgeProven = false;
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, false);
});

test("missing platform evidence fails", () => {
  const migrations = validMigrations();
  delete migrations.win32;
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, false);
  assert.match(result.reasons.join(" "), /missing platform/);
});

test("validateBridgeHandoff rejects unsigned bridge", () => {
  assert.throws(() => validateBridgeHandoff({ signed: false, replacesDirectly: true }), /signed/);
});

test("validateBridgeHandoff rejects missing replacement proof", () => {
  assert.throws(() => validateBridgeHandoff({ signed: true, replacesDirectly: false }), /replace/);
});

test("validateBridgeHandoff accepts signed handoff", () => {
  const result = validateBridgeHandoff({
    signed: true,
    signatureValid: true,
    replacesDirectly: true,
    exerciseObserved: true,
    artifactSha256: "ef".repeat(32),
    targetArtifactSha256: "cd".repeat(32),
  });
  assert.equal(result.valid, true);
});

test("evaluateLegacyUpdate rejects invalid handoff even when bridgeProven true", () => {
  const migrations = validMigrations();
  migrations.darwin.directSuccess = false;
  migrations.darwin.bridgeRequired = true;
  migrations.darwin.bridgeProven = true;
  migrations.darwin.handoff = { signed: false, replacesDirectly: true };
  const result = evaluateLegacyUpdate(migrations);
  assert.equal(result.success, false);
  assert.match(result.reasons.join(" "), /bridge handoff invalid/);
});

const { createHash } = await import("node:crypto");
const fsPromises = await import("node:fs/promises");
const os = await import("node:os");
const pathModule = await import("node:path");

async function seedExerciseFixtures(root, options = {}) {
	await fsPromises.writeFile(pathModule.join(root, "legacy-app.tar"), "legacy app bytes");
	await fsPromises.writeFile(pathModule.join(root, "tauri-bundle.tar"), "tauri bundle bytes");
	const observationsDir = pathModule.join(root, "observations");
	await fsPromises.mkdir(observationsDir, { recursive: true });
	const writeObservation = async (name, payload) => {
		await fsPromises.writeFile(pathModule.join(observationsDir, name), `${JSON.stringify(payload, null, "\t")}\n`);
	};
	await writeObservation("legacy-launch.json", { launchedAt: "2026-08-22T00:00:00.000Z", readyObserved: true });
	if (!options.dropUpdateRequest) {
		await writeObservation("update-request.json", { requestedAt: "2026-08-22T00:01:00.000Z", exitCode: options.updateExitCode ?? 0 });
	}
	await writeObservation("target-launch.json", { launchedAt: "2026-08-22T00:02:00.000Z", readyObserved: true });
	await writeObservation("versions.json", { legacyVersion: "0.10.3", targetVersion: "1.0.0" });
	await writeObservation("state-preservation.json", {
		identityBefore: "dev.operator.desktop",
		identityAfter: options.identityChanged ? "com.example.other" : "dev.operator.desktop",
		stateDigestBefore: createHash("sha256").update("state").digest("hex"),
		stateDigestAfter: options.stateDrift ? createHash("sha256").update("other-state").digest("hex") : createHash("sha256").update("state").digest("hex"),
	});
	return observationsDir;
}

test("record compiles validated observations into migration evidence bound to fixture bytes", async () => {
	const root = await fsPromises.mkdtemp(pathModule.join(os.tmpdir(), "operator-legacy-record-"));
	try {
		const observationsDir = await seedExerciseFixtures(root);
		const resultsDir = pathModule.join(root, "results");
		const outcome = await recordMigrationEvidence({
			observationsDir,
			resultsDir,
			platform: "linux",
			electronArtifactPath: pathModule.join(root, "legacy-app.tar"),
			tauriArtifactPath: pathModule.join(root, "tauri-bundle.tar"),
		});
		assert.equal(outcome.complete, true);
		const evidence = JSON.parse(await fsPromises.readFile(pathModule.join(resultsDir, "legacy-update-evidence.json"), "utf8"));
		const expectedLegacyDigest = createHash("sha256").update("legacy app bytes").digest("hex");
		const expectedTargetDigest = createHash("sha256").update("tauri bundle bytes").digest("hex");
		assert.equal(evidence.linux.exercise.legacyArtifactSha256, expectedLegacyDigest);
		assert.equal(evidence.linux.exercise.targetArtifactSha256, expectedTargetDigest);
		assert.equal(validateMigrationExercise(evidence.linux.exercise).valid, true);

		const driftedRoot = await fsPromises.mkdtemp(pathModule.join(os.tmpdir(), "operator-legacy-record-drift-"));
		try {
			await fsPromises.copyFile(pathModule.join(root, "legacy-app.tar"), pathModule.join(driftedRoot, "legacy-app.tar"));
			const driftObservations = await seedExerciseFixtures(driftedRoot, { dropUpdateRequest: true });
			const drifted = await recordMigrationEvidence({
				observationsDir: driftObservations,
				resultsDir: pathModule.join(driftedRoot, "results"),
				platform: "linux",
				electronArtifactPath: pathModule.join(driftedRoot, "legacy-app.tar"),
				tauriArtifactPath: pathModule.join(driftedRoot, "tauri-bundle.tar"),
			});
			assert.equal(drifted.complete, false);
			assert.match(drifted.reasons.join(" "), /update-request\.json/);
			const driftedEvidence = JSON.parse(await fsPromises.readFile(pathModule.join(driftedRoot, "results", "legacy-update-evidence.json"), "utf8"));
			assert.equal(driftedEvidence.linux.success, false);
		} finally {
			await fsPromises.rm(driftedRoot, { recursive: true, force: true });
		}
	} finally {
		await fsPromises.rm(root, { recursive: true, force: true });
	}
});

test("record fails closed when observed transitions contradict each other or the artifacts vanish", async () => {
	const root = await fsPromises.mkdtemp(pathModule.join(os.tmpdir(), "operator-legacy-record-invalid-"));
	try {
		const observationsDir = await seedExerciseFixtures(root, { updateExitCode: 3 });
		const missingArtifact = async () => recordMigrationEvidence({
			observationsDir,
			resultsDir: pathModule.join(root, "results-a"),
			platform: "linux",
			electronArtifactPath: pathModule.join(root, "missing.tar"),
			tauriArtifactPath: pathModule.join(root, "tauri-bundle.tar"),
		});
		await assert.rejects(missingArtifact, /artifact/);
		const resultsDir = pathModule.join(root, "results-b");
		const outcome = await recordMigrationEvidence({
			observationsDir,
			resultsDir,
			platform: "linux",
			electronArtifactPath: pathModule.join(root, "legacy-app.tar"),
			tauriArtifactPath: pathModule.join(root, "tauri-bundle.tar"),
		});
		assert.equal(outcome.complete, false);
		assert.match(outcome.reasons.join(" "), /exit code 3|updaterExitCode/);
	} finally {
		await fsPromises.rm(root, { recursive: true, force: true });
	}
});
