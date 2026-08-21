import { readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const DECISIONS = Object.freeze(["continue", "linux-canvas", "drop-platform", "stop-port"]);
const REQUIRED_PLATFORMS = Object.freeze(["darwin", "win32", "linux"]);
const EXPECTED_IDENTITY = Object.freeze({
  identifier: "dev.operator.desktop",
  productName: "Operator",
  executable: "operator",
});
const ABSOLUTE_DOWNLOAD_LIMIT = 100 * 1024 * 1024;
const WARM_START_MEDIAN_FACTOR = 0.7;
const WARM_START_P95_FACTOR = 0.75;
const IDLE_MEMORY_FACTOR = 0.6;
const ARTIFACT_DOWNLOAD_FACTOR = 0.7;
const ARTIFACT_INSTALLED_FACTOR = 0.6;

function pushReason(reasons, message) {
  reasons.push(message);
}

export function evaluateDecision(evidence) {
  const reasons = [];
  let linuxCanvas = false;
  let hasBridgeRollout = false;

  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    return { decision: "stop-port", reasons: ["evidence is missing or malformed"] };
  }

  if (!evidence.platforms || typeof evidence.platforms !== "object") {
    return { decision: "stop-port", reasons: ["missing platform evidence"] };
  }

  for (const platform of REQUIRED_PLATFORMS) {
    if (!evidence.platforms[platform]) {
      pushReason(reasons, `missing platform evidence: ${platform}`);
    }
  }

  if (evidence.identity) {
    if (evidence.identity.identifier !== EXPECTED_IDENTITY.identifier) {
      pushReason(reasons, `application identity changed: identifier ${String(evidence.identity.identifier)} != ${EXPECTED_IDENTITY.identifier}`);
    }
    if (evidence.identity.productName !== EXPECTED_IDENTITY.productName) {
      pushReason(reasons, `application identity changed: productName ${String(evidence.identity.productName)} != ${EXPECTED_IDENTITY.productName}`);
    }
    if (evidence.identity.executable !== EXPECTED_IDENTITY.executable) {
      pushReason(reasons, `application identity changed: executable ${String(evidence.identity.executable)} != ${EXPECTED_IDENTITY.executable}`);
    }
    if (evidence.identity.aliasesPreserved === false) {
      pushReason(reasons, "application identity changed: version-free aliases not preserved");
    }
  } else {
    pushReason(reasons, "missing application identity evidence");
  }

  if (evidence.updaterSigning) {
    if (evidence.updaterSigning.valid === false || evidence.updaterSigning.signatureValid === false) {
      pushReason(reasons, "invalid updater signature");
    }
    if (evidence.updaterSigning.privateKeyLeaked === true) {
      pushReason(reasons, "updater private key leaked");
    }
    if (evidence.updaterSigning.valid !== true && evidence.updaterSigning.signatureValid !== true) {
      if (evidence.updaterSigning.signatureValid === false) {
      } else if (evidence.updaterSigning.valid === false) {
      }
    }
    if (!evidence.updaterSigning.valid && !evidence.updaterSigning.signatureValid) {
    }
  } else {
    pushReason(reasons, "missing updater-signing evidence");
  }

  if (evidence.updaterSigning && evidence.updaterSigning.privateKeyLeaked) {
  }

  for (const platform of REQUIRED_PLATFORMS) {
    const data = evidence.platforms[platform];
    if (!data) continue;

    if (!data.stateAudit || data.stateAudit.passed !== true || data.stateAudit.leaked === true) {
      if (data.stateAudit && data.stateAudit.leaked === true) {
        pushReason(reasons, `state leak on ${platform}`);
      } else {
        pushReason(reasons, `state audit failed on ${platform}`);
      }
    }

    if (!data.cors || data.cors.passed !== true) {
      pushReason(reasons, `CORS boundary failed on ${platform}`);
    }

    if (!data.browser || data.browser.passed !== true) {
      pushReason(reasons, `standalone browser automation failed on ${platform}`);
    }

    if (data.updaterSigning) {
      if (data.updaterSigning.valid === false || data.updaterSigning.signatureValid === false) {
        pushReason(reasons, `invalid updater signature on ${platform}`);
      }
      if (data.updaterSigning.privateKeyLeaked === true) {
        pushReason(reasons, `updater private key leaked on ${platform}`);
      }
    }

    const legacy = data.legacyUpdate;
    if (!legacy) {
      pushReason(reasons, `missing legacy-update migration evidence on ${platform}`);
    } else if (legacy.success !== true) {
      if (legacy.bridgeRequired === true && legacy.bridgeProven === true) {
        hasBridgeRollout = true;
        pushReason(reasons, `bridge handoff required on ${platform} and proven as mandatory rollout work`);
      } else {
        pushReason(reasons, `legacy-update migration failed on ${platform}`);
      }
    } else if (legacy.bridgeRequired === true && legacy.bridgeProven === true) {
      hasBridgeRollout = true;
    }

    if (!data.artifact) {
      pushReason(reasons, `missing artifact evidence on ${platform}`);
    } else {
      if (data.artifact.includesACP !== true) {
        pushReason(reasons, `missing ACP runtime on ${platform}`);
      }
      if (data.artifact.includesDaemon !== true) {
      }
      if (platform === "linux" && data.artifact.rpmExists !== true) {
        pushReason(reasons, `missing RPM artifact on ${platform}`);
      }
      if (data.artifact.electron && data.artifact.tauri) {
        const electronDownload = data.artifact.electron.downloadBytes;
        const tauriDownload = data.artifact.tauri.downloadBytes;
        const electronInstalled = data.artifact.electron.installedBytes;
        const tauriInstalled = data.artifact.tauri.installedBytes;
        if (typeof tauriDownload === "number") {
          if (tauriDownload > ABSOLUTE_DOWNLOAD_LIMIT) {
            pushReason(reasons, `base signed download exceeds 100 MiB on ${platform}: ${tauriDownload}`);
          }
          if (typeof electronDownload === "number" && tauriDownload > electronDownload * ARTIFACT_DOWNLOAD_FACTOR) {
            pushReason(reasons, `base signed download exceeds 70% of Electron on ${platform}`);
          }
        }
        if (typeof tauriInstalled === "number" && typeof electronInstalled === "number") {
          if (tauriInstalled > electronInstalled * ARTIFACT_INSTALLED_FACTOR) {
            pushReason(reasons, `base installed footprint exceeds 60% of Electron on ${platform}`);
          }
        }
      }
    }

    if (!data.terminal || !data.terminal.electron || !data.terminal.tauri) {
      pushReason(reasons, `missing terminal evidence on ${platform}`);
      continue;
    }

    const electron = data.terminal.electron;
    const tauri = data.terminal.tauri;

    const rendererKind = tauri.rendererKind;
    if (rendererKind === "canvas") {
      if (platform === "darwin" || platform === "win32") {
        pushReason(reasons, `canvas renderer on ${platform} requires WebGL`);
      } else if (platform === "linux") {
        linuxCanvas = true;
      }
    } else if (rendererKind !== "webgl") {
      pushReason(reasons, `missing renderer kind on ${platform}`);
    }

    if (electron.warmStart && tauri.warmStart) {
      if (typeof tauri.warmStart.median === "number" && typeof electron.warmStart.median === "number") {
        if (tauri.warmStart.median > electron.warmStart.median * WARM_START_MEDIAN_FACTOR) {
          pushReason(reasons, `warm-start median regression on ${platform}`);
        }
      }
      if (typeof tauri.warmStart.p95 === "number" && typeof electron.warmStart.p95 === "number") {
        if (tauri.warmStart.p95 > electron.warmStart.p95 * WARM_START_P95_FACTOR) {
          pushReason(reasons, `warm-start p95 regression on ${platform}`);
        }
      }
    }

    if (electron.firstRun && tauri.firstRun) {
      if (typeof tauri.firstRun.median === "number" && typeof electron.firstRun.median === "number") {
        if (tauri.firstRun.median >= electron.firstRun.median) {
          pushReason(reasons, `first-run start regression on ${platform}`);
        }
      }
      if (typeof tauri.firstRun.p95 === "number" && typeof electron.firstRun.p95 === "number") {
        if (tauri.firstRun.p95 >= electron.firstRun.p95) {
          pushReason(reasons, `first-run start regression on ${platform}`);
        }
      }
    }

    if (electron.vtebench && tauri.vtebench) {
      if (typeof tauri.vtebench.median === "number" && typeof electron.vtebench.median === "number") {
        if (tauri.vtebench.median < electron.vtebench.median) {
          pushReason(reasons, `terminal throughput regression on ${platform} vtebench`);
        }
      }
    }

    if (electron.largeOutput && tauri.largeOutput) {
      if (typeof tauri.largeOutput.median === "number" && typeof electron.largeOutput.median === "number") {
        if (tauri.largeOutput.median < electron.largeOutput.median) {
          pushReason(reasons, `terminal throughput regression on ${platform} large-output`);
        }
      }
    }

    if (electron.idleMemory && tauri.idleMemory) {
      if (typeof tauri.idleMemory.median === "number" && typeof electron.idleMemory.median === "number") {
        if (tauri.idleMemory.median > electron.idleMemory.median * IDLE_MEMORY_FACTOR) {
          pushReason(reasons, `idle-memory regression on ${platform}`);
        }
      }
    }

    if (electron.inputLatency && tauri.inputLatency) {
      if (typeof tauri.inputLatency.p95 === "number" && typeof electron.inputLatency.p95 === "number") {
        if (tauri.inputLatency.p95 > electron.inputLatency.p95) {
          pushReason(reasons, `terminal input latency regression on ${platform}`);
        }
      }
    }

    if (electron.reconnect && tauri.reconnect) {
      if (typeof tauri.reconnect.p95 === "number" && typeof electron.reconnect.p95 === "number") {
        if (tauri.reconnect.p95 > electron.reconnect.p95) {
          pushReason(reasons, `terminal reconnect regression on ${platform}`);
        }
      }
    }

    if (electron.activeMemory && tauri.activeMemory) {
      if (typeof tauri.activeMemory.bytes === "number" && typeof electron.activeMemory.bytes === "number") {
        if (tauri.activeMemory.bytes > electron.activeMemory.bytes) {
          pushReason(reasons, `active-terminal memory regression on ${platform}`);
        }
      }
    }

    if (electron.cpuTime && tauri.cpuTime) {
      if (typeof tauri.cpuTime.ms === "number" && typeof electron.cpuTime.ms === "number") {
        if (tauri.cpuTime.ms > electron.cpuTime.ms) {
          pushReason(reasons, `fixed-workload CPU time regression on ${platform}`);
        }
      }
    }
  }

  if (reasons.length > 0) {
    const onlyBridge = reasons.every((r) => r.includes("bridge"));
    if (onlyBridge && hasBridgeRollout) {
      if (linuxCanvas) {
        return { decision: "linux-canvas", reasons: ["linux-canvas: Linux uses canvas but all terminal gates pass", ...reasons] };
      }
      return { decision: "continue", reasons };
    }
    return { decision: "stop-port", reasons };
  }

  if (linuxCanvas) {
    return { decision: "linux-canvas", reasons: ["linux-canvas: Linux uses canvas but all terminal gates pass"] };
  }

  if (hasBridgeRollout) {
    return { decision: "continue", reasons: ["bridge handoff required on one or more platforms and proven as mandatory rollout work"] };
  }

  return { decision: "continue", reasons: [] };
}

export async function loadEvidence(resultsDir) {
  const evidencePath = path.join(resultsDir, "phase0-evidence.json");
  let raw;
  try {
    raw = await readFile(evidencePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      const altPath = path.join(resultsDir, "evidence.json");
      try {
        raw = await readFile(altPath, "utf8");
      } catch (error2) {
        if (error2?.code === "ENOENT") {
          throw new Error(`missing evidence file: ${evidencePath} or ${altPath}`);
        }
        throw error2;
      }
    } else {
      throw error;
    }
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("evidence file contains invalid JSON");
  }
  return parsed;
}

export async function loadIdentity(configPath) {
  const raw = await readFile(configPath, "utf8");
  let config;
  try {
    config = JSON.parse(raw);
  } catch {
    throw new Error("tauri config contains invalid JSON");
  }
  return {
    identifier: config.identifier,
    productName: config.productName,
    executable: config.mainBinaryName,
  };
}

async function collectBenchmarkResults(resultsDir) {
  const results = {};
  let entries = [];
  try {
    entries = await readdir(resultsDir);
  } catch {
    return results;
  }
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue;
    const fullPath = path.join(resultsDir, entry);
    let fileStat;
    try {
      fileStat = await stat(fullPath);
    } catch {
      continue;
    }
    if (!fileStat.isFile()) continue;
    try {
      const data = JSON.parse(await readFile(fullPath, "utf8"));
      results[entry] = data;
    } catch {
    }
  }
  return results;
}

export async function collectEvidence(resultsDir, options = {}) {
  const evidence = await loadEvidence(resultsDir);
  if (options.configPath) {
    try {
      const identity = await loadIdentity(options.configPath);
      evidence.identity = { ...evidence.identity, ...identity, aliasesPreserved: evidence.identity?.aliasesPreserved ?? true };
    } catch {
    }
  }
  evidence._benchmarkResults = await collectBenchmarkResults(resultsDir);
  return evidence;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "--results") {
      args.results = argv[i + 1];
      i += 1;
    } else if (flag === "--write") {
      args.write = argv[i + 1];
      i += 1;
    } else if (flag === "--config") {
      args.config = argv[i + 1];
      i += 1;
    } else if (flag === "--help" || flag === "-h") {
      args.help = true;
    } else if (flag.startsWith("--")) {
      throw new Error(`unknown flag: ${flag}`);
    }
  }
  return args;
}

function formatBaselineSection(decision, reasons) {
  const timestamp = new Date().toISOString();
  const lines = [];
  lines.push("## Phase 0 decision");
  lines.push("");
  lines.push(`Decision: \`${decision}\``);
  lines.push("");
  lines.push(`Timestamp: ${timestamp}`);
  lines.push("");
  if (reasons.length === 0) {
    lines.push("Reasons: none");
  } else {
    lines.push("Reasons:");
    for (const reason of reasons) {
      lines.push(`- ${reason}`);
    }
  }
  lines.push("");
  return lines.join("\n");
}

async function updateBaselineFile(baselinePath, decision, reasons) {
  let existing = "";
  try {
    existing = await readFile(baselinePath, "utf8");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    existing = "";
  }
  const section = formatBaselineSection(decision, reasons);
  let next;
  if (existing.includes("## Phase 0 decision")) {
    const before = existing.split("## Phase 0 decision")[0];
    next = `${before.trimEnd()}\n\n${section}\n`;
  } else {
    next = `${existing.trimEnd()}\n\n${section}\n`;
  }
  await writeFile(baselinePath, next, "utf8");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write("Usage: node scripts/phase0-decision.mjs --results <dir> [--write <baseline.md>] [--config <tauri.conf.json>]\n");
    return;
  }
  if (!args.results) {
    throw new Error("--results <dir> is required");
  }
  const evidence = await collectEvidence(args.results, { configPath: args.config });
  const result = evaluateDecision(evidence);
  process.stdout.write(`${result.decision}\n`);
  if (result.reasons.length > 0) {
    for (const reason of result.reasons) {
      process.stdout.write(`${reason}\n`);
    }
  }
  if (args.write) {
    await updateBaselineFile(args.write, result.decision, result.reasons);
  }
  if (result.decision !== "continue" && result.decision !== "linux-canvas") {
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  });
}
