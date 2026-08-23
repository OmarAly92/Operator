import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
export const DECISION = Object.freeze({ SUCCESS: "success", FAILURE: "failure" });
const REQUIRED_PLATFORMS = Object.freeze(["darwin", "win32", "linux"]);

export function validateMigrationExercise(exercise) {
  if (!exercise || exercise.kind !== "electron-to-tauri" || exercise.runner !== "native-installed-update") {
    throw new Error("native migration exercise is missing");
  }
  for (const field of ["legacyVersion", "targetVersion"]) {
    if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(exercise[field] ?? "")) throw new Error(`migration exercise ${field} is invalid`);
  }
  for (const field of ["legacyArtifactSha256", "targetArtifactSha256"]) {
    if (!/^[0-9a-f]{64}$/.test(exercise[field] ?? "")) throw new Error(`migration exercise ${field} is invalid`);
  }
  if (!Number.isFinite(Date.parse(exercise.observedAt ?? ""))) throw new Error("migration exercise timestamp is invalid");
  if (exercise.launchedLegacy !== true || exercise.updateRequested !== true || exercise.updaterExitCode !== 0 || exercise.launchedTarget !== true || exercise.identityPreserved !== true || exercise.statePreserved !== true) {
    throw new Error("native migration exercise did not observe every required transition");
  }
  return { valid: true };
}

export function validateBridgeHandoff(handoff) {
  if (!handoff || handoff.signed !== true) {
    throw new Error("bridge handoff must be signed");
  }
  if (handoff.replacesDirectly !== true) {
    throw new Error("bridge handoff must replace direct migration proof");
  }
  if (handoff.signatureValid !== true || handoff.exerciseObserved !== true || !/^[0-9a-f]{64}$/.test(handoff.artifactSha256 ?? "") || !/^[0-9a-f]{64}$/.test(handoff.targetArtifactSha256 ?? "")) {
    throw new Error("bridge handoff must retain a valid signature, artifact digest, and observed exercise");
  }
  return { valid: true };
}

export function evaluateLegacyUpdate(migrations) {
  const reasons = [];
  let bridgeRequired = false;

  if (!migrations || typeof migrations !== "object" || Array.isArray(migrations)) {
    return { success: false, bridgeRequired: false, reasons: ["missing migration evidence"] };
  }

  for (const platform of REQUIRED_PLATFORMS) {
    if (!migrations[platform]) {
      reasons.push(`missing platform migration evidence: ${platform}`);
    }
  }

  for (const platform of REQUIRED_PLATFORMS) {
    const data = migrations[platform];
    if (!data) continue;
    if (data.directSuccess === true) {
      try {
        validateMigrationExercise(data.exercise);
      } catch (error) {
        reasons.push(`direct migration exercise invalid on ${platform}: ${error.message}`);
      }
      continue;
    }
    if (data.bridgeRequired === true && data.bridgeProven === true) {
      bridgeRequired = true;
      try {
        validateBridgeHandoff(data.handoff);
      } catch (error) {
        reasons.push(`bridge handoff invalid on ${platform}: ${error.message}`);
        continue;
      }
      reasons.push(`bridge handoff required on ${platform} and proven as mandatory rollout work`);
      continue;
    }
    if (data.directSuccess === false && data.bridgeRequired === true && data.bridgeProven !== true) {
      reasons.push(`direct migration failed on ${platform} and bridge handoff not proven`);
      continue;
    }
    reasons.push(`direct migration failed on ${platform}`);
  }

  const success = reasons.filter((r) => !r.includes("bridge handoff required")).length === 0;
  return { success, bridgeRequired, reasons };
}

async function readObservation(observationsDir, name, reasons) {
  try {
    const raw = await readFile(path.join(observationsDir, name), "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error?.code === "ENOENT") reasons.push(`${name} is missing`);
    else reasons.push(`${name} contains invalid JSON`);
    return undefined;
  }
}

function observationTimestamp(observation, name) {
  const value = observation?.launchedAt ?? observation?.requestedAt;
  if (!Number.isFinite(Date.parse(value ?? ""))) throw new Error(`observation ${name} timestamp is invalid`);
  return Date.parse(value);
}

export async function recordMigrationEvidence({ observationsDir, resultsDir, platform, electronArtifactPath, tauriArtifactPath }) {
  const reasons = [];
  const [legacyLaunch, updateRequest, targetLaunch, versions, statePreservation] = await Promise.all([
    readObservation(observationsDir, "legacy-launch.json", reasons),
    readObservation(observationsDir, "update-request.json", reasons),
    readObservation(observationsDir, "target-launch.json", reasons),
    readObservation(observationsDir, "versions.json", reasons),
    readObservation(observationsDir, "state-preservation.json", reasons),
  ]);
  const digestFile = async (filePath, label) => {
    try {
      return createHash("sha256").update(await readFile(filePath)).digest("hex");
    } catch {
      throw new Error(`${label} fixture artifact is missing so migration evidence cannot be compiled`);
    }
  };
  const legacyArtifactSha256 = await digestFile(electronArtifactPath, "electron legacy fixture");
  const targetArtifactSha256 = await digestFile(tauriArtifactPath, "tauri target fixture");

  let observedAtMs = Number.NEGATIVE_INFINITY;
  for (const [observation, name] of [[legacyLaunch, "legacy-launch.json"], [targetLaunch, "target-launch.json"], [updateRequest, "update-request.json"]]) {
    if (!observation) continue;
    observedAtMs = Math.max(observedAtMs, observationTimestamp(observation, name));
  }

  let launchedLegacy = false;
  let launchedTarget = false;
  if (legacyLaunch) {
    if (legacyLaunch.readyObserved === true) launchedLegacy = true;
    else reasons.push("legacy launch did not observe daemon readiness");
  }
  if (targetLaunch) {
    if (targetLaunch.readyObserved === true) launchedTarget = true;
    else reasons.push("target launch did not observe daemon readiness");
  }

  let updateRequested = false;
  if (updateRequest) {
    if (updateRequest.exitCode === 0) updateRequested = true;
    else reasons.push(`update request failed with updaterExitCode ${String(updateRequest.exitCode)}`);
  }

  let identityPreserved = false;
  let statePreserved = false;
  if (statePreservation) {
    identityPreserved = typeof statePreservation.identityBefore === "string" && statePreservation.identityBefore === statePreservation.identityAfter;
    statePreserved = /^[0-9a-f]{64}$/.test(statePreservation.stateDigestBefore ?? "") && statePreservation.stateDigestBefore === statePreservation.stateDigestAfter;
    if (!identityPreserved) reasons.push("application identity changed across the handoff");
    if (!statePreserved) reasons.push("operator state changed across the handoff");
  }

  if (versions) {
    for (const [field, value] of Object.entries(versions)) {
      if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(String(value ?? ""))) reasons.push(`observed ${field} is not a release semantic version`);
    }
  }

  const complete =
    legacyLaunch !== undefined &&
    updateRequest !== undefined &&
    targetLaunch !== undefined &&
    versions !== undefined &&
    statePreservation !== undefined &&
    reasons.length === 0 &&
    launchedLegacy &&
    updateRequested &&
    launchedTarget &&
    identityPreserved &&
    statePreserved;

  const exercise = {
    kind: "electron-to-tauri",
    runner: "native-installed-update",
    legacyVersion: String(versions?.legacyVersion ?? ""),
    targetVersion: String(versions?.targetVersion ?? ""),
    legacyArtifactSha256,
    targetArtifactSha256,
    launchedLegacy,
    updateRequested,
    updaterExitCode: Number(updateRequest?.exitCode ?? 1),
    launchedTarget,
    identityPreserved,
    statePreserved,
    observedAt: new Date(Number.isFinite(observedAtMs) ? observedAtMs : 0).toISOString(),
  };

  const record = complete
    ? {
        directSuccess: true,
        success: true,
        bridgeRequired: false,
        bridgeProven: false,
        migrationObserved: true,
        exercise,
      }
    : {
        directSuccess: false,
        success: false,
        bridgeRequired: false,
        bridgeProven: false,
        migrationObserved: false,
        reasons,
      };
  await mkdir(resultsDir, { recursive: true });
  await writeFile(path.join(resultsDir, "legacy-update-evidence.json"), `${JSON.stringify({ schemaVersion: 1, [platform]: record }, null, "\t")}\n`, "utf8");
  return { complete: record.success === true, reasons };
}

export async function loadMigrationEvidence(resultsDir) {
  const evidencePath = path.join(resultsDir, "legacy-update-evidence.json");
  let raw;
  try {
    raw = await readFile(evidencePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") throw new Error(`missing migration evidence: ${evidencePath}`);
    throw error;
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("migration evidence contains invalid JSON");
  }
  return parsed;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "--results") {
      args.results = argv[i + 1];
      i += 1;
    } else if (flag === "--record") {
      args.record = true;
    } else if (flag === "--observations") {
      args.observations = argv[i + 1];
      i += 1;
    } else if (flag === "--platform") {
      args.platform = argv[i + 1];
      i += 1;
    } else if (flag === "--electron-artifact") {
      args.electronArtifact = argv[i + 1];
      i += 1;
    } else if (flag === "--tauri-artifact") {
      args.tauriArtifact = argv[i + 1];
      i += 1;
    } else if (flag === "--help" || flag === "-h") {
      args.help = true;
    } else if (flag.startsWith("--")) {
      throw new Error(`unknown flag: ${flag}`);
    }
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write("Usage: node scripts/phase0-legacy-update.mjs --results <dir>\n");
    process.stdout.write("       node scripts/phase0-legacy-update.mjs --record --observations <dir> --results <dir> --platform <p> --electron-artifact <f> --tauri-artifact <f>\n");
    return;
  }
  if (args.record) {
    if (!args.results || !args.observations || !args.platform || !args.electronArtifact || !args.tauriArtifact) {
      throw new Error("--record requires --observations --results --platform --electron-artifact and --tauri-artifact");
    }
    const outcome = await recordMigrationEvidence({
      observationsDir: path.resolve(args.observations),
      resultsDir: path.resolve(args.results),
      platform: args.platform,
      electronArtifactPath: path.resolve(args.electronArtifact),
      tauriArtifactPath: path.resolve(args.tauriArtifact),
    });
    process.stdout.write(`migration exercise recorded: ${outcome.complete ? "complete" : "incomplete"}\n`);
    for (const reason of outcome.reasons) process.stdout.write(`${reason}\n`);
    if (!outcome.complete) process.exitCode = 1;
    return;
  }
  if (!args.results) {
    throw new Error("--results <dir> is required");
  }
  const migrations = await loadMigrationEvidence(args.results);
  const result = evaluateLegacyUpdate(migrations);
  process.stdout.write(`${result.success ? "success" : "failure"}\n`);
  for (const reason of result.reasons) {
    process.stdout.write(`${reason}\n`);
  }
  if (!result.success) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
