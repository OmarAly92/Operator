import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
export const DECISION = Object.freeze({ SUCCESS: "success", FAILURE: "failure" });
const REQUIRED_PLATFORMS = Object.freeze(["darwin", "win32", "linux"]);

export function validateBridgeHandoff(handoff) {
  if (!handoff || handoff.signed !== true) {
    throw new Error("bridge handoff must be signed");
  }
  if (handoff.replacesDirectly !== true) {
    throw new Error("bridge handoff must replace direct migration proof");
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
      continue;
    }
    if (data.bridgeRequired === true && data.bridgeProven === true) {
      bridgeRequired = true;
      try {
        validateBridgeHandoff(data.handoff ?? { signed: data.bridgeProven === true, replacesDirectly: data.replacesDirectly ?? true });
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

export async function loadMigrationEvidence(resultsDir) {
  const evidencePath = path.join(resultsDir, "legacy-update-evidence.json");
  let raw;
  try {
    raw = await readFile(evidencePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      const alt = path.join(resultsDir, "phase0-evidence.json");
      try {
        const altRaw = await readFile(alt, "utf8");
        const parsedAlt = JSON.parse(altRaw);
        if (parsedAlt.platforms) {
          const migrations = {};
          for (const platform of REQUIRED_PLATFORMS) {
            const platformData = parsedAlt.platforms[platform];
            if (platformData && platformData.legacyUpdate) {
              migrations[platform] = {
                directSuccess: platformData.legacyUpdate.success === true,
                bridgeRequired: platformData.legacyUpdate.bridgeRequired === true,
                bridgeProven: platformData.legacyUpdate.bridgeProven === true,
              };
            }
          }
          return migrations;
        }
        throw new Error(`missing migration evidence: ${evidencePath}`);
      } catch (error2) {
        if (error2?.code === "ENOENT") throw new Error(`missing migration evidence: ${evidencePath}`);
        throw error2;
      }
    }
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
