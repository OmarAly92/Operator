import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { validateBridgeHandoff, validateMigrationExercise } from "./phase0-legacy-update.mjs";

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
const TERMINAL_OPEN_MEDIAN_FACTOR = 0.75;
const TERMINAL_OPEN_P95_FACTOR = 0.9;

function pushReason(reasons, message) {
  reasons.push(message);
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function finiteNonnegative(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function validUpdaterEvidence(value) {
  return isRecord(value) &&
    value.valid === true &&
    value.signatureValid === true &&
    value.privateKeyLeaked === false &&
    value.format === "tauri-minisign" &&
    value.signer === "@tauri-apps/cli@2.11.4" &&
    /^[0-9a-f]{64}$/.test(value.publicKeyFingerprint ?? "") &&
    /^[0-9a-f]{64}$/.test(value.signatureSha256 ?? "");
}

function validMetric(profile, metric, fields) {
  const value = profile?.[metric];
  return isRecord(value) &&
    fields.every((field) => finiteNonnegative(value[field])) &&
    value.evidenceScope === "binding" &&
    value.workloadSuccess === true &&
    Number.isInteger(value.requiredCount) &&
    value.requiredCount > 0 &&
    value.observedCount === value.requiredCount;
}

function validateTerminalShape(terminal, platform, reasons) {
  if (!isRecord(terminal) || !isRecord(terminal.electron) || !isRecord(terminal.tauri)) {
    pushReason(reasons, `missing terminal evidence on ${platform}`);
    return false;
  }
  const metrics = [
    ["terminalOpen", ["median", "p95"]],
    ["warmStart", ["median", "p95"]],
    ["firstRun", ["median", "p95"]],
    ["vtebench", ["median"]],
    ["largeOutput", ["median"]],
    ["idleMemory", ["median"]],
    ["inputLatency", ["p95"]],
    ["reconnect", ["p95"]],
    ["activeMemory", ["bytes"]],
    ["cpuTime", ["ms"]],
  ];
  let valid = true;
  for (const shell of ["electron", "tauri"]) {
    for (const [metric, fields] of metrics) {
      if (!validMetric(terminal[shell], metric, fields)) {
        pushReason(reasons, `malformed terminal evidence on ${platform}: ${shell}.${metric}`);
        valid = false;
      }
    }
  }
  if (platform === "linux") {
    const tauriProfile = terminal?.tauri;
    if (!isRecord(tauriProfile) || tauriProfile.compositingPairObserved !== true) {
      pushReason(reasons, `malformed terminal evidence on ${platform}: linux requires the WEBKIT_DISABLE_COMPOSITING_MODE on/off measurement pair`);
      valid = false;
    }
  }
  return valid;
}

const BROWSER_MODES = Object.freeze(["system", "managed"]);

function validateBrowserMode(modeEvidence, platform, mode, reasons) {
  if (!isRecord(modeEvidence) || modeEvidence.passed !== true || modeEvidence.isolatedWhileRunning !== true || modeEvidence.cleanupPassed !== true || modeEvidence.stateRootRemoved !== true || !Number.isInteger(modeEvidence.observedProcessCount) || modeEvidence.observedProcessCount < 1 || modeEvidence.cookieMarkerPresent !== true) {
    pushReason(reasons, `per-mode browser evidence is malformed on ${platform}: ${mode}`);
    return false;
  }
  return true;
}

function validatePlatformShape(data, platform, sourceCommit, reasons) {
  if (!isRecord(data.provenance) || data.provenance.sourceCommit !== sourceCommit || !/^[0-9a-f]{64}$/.test(data.provenance.artifactSha256 ?? "")) {
    pushReason(reasons, `platform provenance source commit or artifact digest is invalid on ${platform}`);
  }
  if (!isRecord(data.stateAudit) || data.stateAudit.passed !== true || data.stateAudit.leaked !== false || !Number.isInteger(data.stateAudit.scannedRoots) || data.stateAudit.scannedRoots < 1 || data.stateAudit.observedOutsideRoot !== 0) {
    pushReason(reasons, `state audit evidence is malformed on ${platform}`);
  }
  if (!isRecord(data.cors) || data.cors.passed !== true || data.cors.exactAllowlist !== true) {
    pushReason(reasons, `CORS evidence is malformed on ${platform}`);
  }
  let browserShapeValid = true;
  if (!isRecord(data.browser)) {
    pushReason(reasons, `per-mode browser evidence is missing on ${platform}`);
    browserShapeValid = false;
  } else {
    for (const mode of BROWSER_MODES) {
      if (!validateBrowserMode(data.browser[mode], platform, mode, reasons)) browserShapeValid = false;
    }
    if (data.browser.crossModeCookieIsolation !== true) {
      pushReason(reasons, `cross-mode cookie isolation is not proven on ${platform}`);
      browserShapeValid = false;
    }
  }
  if (!isRecord(data.artifact) || !isRecord(data.artifact.electron) || !isRecord(data.artifact.tauri) ||
      !finiteNonnegative(data.artifact.electron.downloadBytes) || !finiteNonnegative(data.artifact.electron.installedBytes) ||
      !finiteNonnegative(data.artifact.tauri.downloadBytes) || !finiteNonnegative(data.artifact.tauri.installedBytes) ||
      !/^[0-9a-f]{64}$/.test(data.artifact.electron.sha256 ?? "") || !/^[0-9a-f]{64}$/.test(data.artifact.tauri.sha256 ?? "") ||
      data.artifact.includesACP !== true || data.artifact.includesDaemon !== true || data.artifact.includesBrowser !== true ||
      (platform === "linux" && data.artifact.rpmExists !== true)) {
    pushReason(reasons, `artifact evidence is malformed on ${platform}`);
  }
  if (!validUpdaterEvidence(data.updaterSigning)) {
    pushReason(reasons, `updater-signing evidence is malformed on ${platform}`);
  }
  const legacy = data.legacyUpdate;
  const exercise = legacy?.exercise;
  let directMigration = false;
  if (isRecord(legacy) && legacy.success === true && legacy.bridgeRequired === false && legacy.bridgeProven === false && legacy.migrationObserved === true && isRecord(exercise)) {
    try {
      validateMigrationExercise(exercise);
      directMigration = exercise.legacyArtifactSha256 === data.artifact?.electron?.sha256 && exercise.targetArtifactSha256 === data.artifact?.tauri?.sha256;
    } catch {
      directMigration = false;
    }
  }
  let bridgeMigration = false;
  if (isRecord(legacy) && legacy.success === false && legacy.bridgeRequired === true && legacy.bridgeProven === true && isRecord(legacy.handoff)) {
    try {
      validateBridgeHandoff(legacy.handoff);
      bridgeMigration = legacy.handoff.targetArtifactSha256 === data.artifact?.tauri?.sha256;
    } catch {
      bridgeMigration = false;
    }
  }
  if (!directMigration && !bridgeMigration) pushReason(reasons, `legacy-update evidence is malformed on ${platform}`);
  return validateTerminalShape(data.terminal, platform, reasons);
}

export function evaluateDecision(evidence) {
  const reasons = [];
  const bridgeAdvisories = [];
  let linuxCanvas = false;
  let hasBridgeRollout = false;

  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    return { decision: "stop-port", reasons: ["evidence is missing or malformed"] };
  }

  if (evidence.schemaVersion !== 1) pushReason(reasons, "evidence schemaVersion must equal 1");
  const provenance = evidence.provenance;
  if (!isRecord(provenance) || provenance.kind !== "phase0-ci-aggregate" || !/^[0-9a-f]{40}$/.test(provenance.sourceCommit ?? "") || !Number.isFinite(Date.parse(provenance.generatedAt ?? "")) || !isRecord(provenance.workflowRun) || typeof provenance.workflowRun.repository !== "string" || provenance.workflowRun.repository === "" || typeof provenance.workflowRun.runId !== "string" || provenance.workflowRun.runId === "" || !Number.isInteger(provenance.workflowRun.attempt) || provenance.workflowRun.attempt < 1) {
    pushReason(reasons, "missing or malformed aggregate provenance");
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
    if (evidence.identity.aliasesPreserved !== true) {
      pushReason(reasons, "application identity changed: version-free aliases not preserved");
    }
  } else {
    pushReason(reasons, "missing application identity evidence");
  }

  if (evidence.updaterSigning) {
    if (!validUpdaterEvidence(evidence.updaterSigning)) pushReason(reasons, "invalid updater signature or non-Tauri updater format");
    if (evidence.updaterSigning.privateKeyLeaked === true) pushReason(reasons, "updater private key leaked");
  } else {
    pushReason(reasons, "missing updater-signing evidence");
  }

  for (const platform of REQUIRED_PLATFORMS) {
    const data = evidence.platforms[platform];
    if (!data) continue;

    validatePlatformShape(data, platform, provenance?.sourceCommit, reasons);

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

    for (const mode of BROWSER_MODES) {
      const modeEvidence = data.browser?.[mode];
      if (!isRecord(modeEvidence) || modeEvidence.passed !== true) {
        pushReason(reasons, `standalone browser automation failed on ${platform}: ${mode}`);
      }
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
      if (isRecord(legacy.handoff)) {
        try {
          validateBridgeHandoff(legacy.handoff);
          hasBridgeRollout = true;
          bridgeAdvisories.push(`bridge handoff required on ${platform} and proven as mandatory rollout work`);
        } catch (error) {
          pushReason(reasons, `bridge handoff invalid on ${platform}: ${error.message}`);
        }
      } else {
        pushReason(reasons, `legacy-update migration failed on ${platform}`);
      }
    }

    if (!data.artifact) {
      pushReason(reasons, `missing artifact evidence on ${platform}`);
    } else {
      if (data.artifact.includesACP !== true) {
        pushReason(reasons, `missing ACP runtime on ${platform}`);
      }
      if (data.artifact.includesDaemon !== true) {
        pushReason(reasons, `missing daemon on ${platform}`);
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

    if (electron.terminalOpen && tauri.terminalOpen) {
      if (typeof tauri.terminalOpen.median === "number" && typeof electron.terminalOpen.median === "number") {
        if (tauri.terminalOpen.median > electron.terminalOpen.median * TERMINAL_OPEN_MEDIAN_FACTOR) {
          pushReason(reasons, `terminal-open median regression on ${platform}`);
        }
      }
      if (typeof tauri.terminalOpen.p95 === "number" && typeof electron.terminalOpen.p95 === "number") {
        if (tauri.terminalOpen.p95 > electron.terminalOpen.p95 * TERMINAL_OPEN_P95_FACTOR) {
          pushReason(reasons, `terminal-open p95 regression on ${platform}`);
        }
      }
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
    return { decision: "stop-port", reasons };
  }

  if (linuxCanvas) {
    return { decision: "linux-canvas", reasons: ["linux-canvas: Linux uses canvas but all terminal gates pass", ...bridgeAdvisories] };
  }

  if (hasBridgeRollout) {
    return { decision: "continue", reasons: bridgeAdvisories.length > 0 ? bridgeAdvisories : ["bridge handoff required on one or more platforms and proven as mandatory rollout work"] };
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

export async function collectEvidence(resultsDir, options = {}) {
  const evidence = await loadEvidence(resultsDir);
  if (options.configPath) {
    const identity = await loadIdentity(options.configPath);
    evidence.identity = { ...evidence.identity, ...identity, aliasesPreserved: evidence.identity?.aliasesPreserved };
  }
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
    const start = existing.indexOf("## Phase 0 decision");
    const before = existing.slice(0, start).trimEnd();
    const remainder = existing.slice(start);
    const nextHeader = remainder.indexOf("\n## ", 1);
    const after = nextHeader === -1 ? "" : remainder.slice(nextHeader);
    next = `${before}\n\n${section}${after ? after.startsWith("\n") ? after : `\n${after}` : "\n"}`;
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
  let result;
  try {
    const evidence = await collectEvidence(args.results, { configPath: args.config });
    result = evaluateDecision(evidence);
  } catch (error) {
    if (error && error.message && error.message.includes("missing evidence file")) {
      result = { decision: "stop-port", reasons: [error.message, "missing platform evidence: darwin", "missing platform evidence: win32", "missing platform evidence: linux", "missing application identity evidence", "missing updater-signing evidence"] };
    } else {
      throw error;
    }
  }
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
