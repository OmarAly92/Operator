import assert from "node:assert/strict";
import test from "node:test";
import { evaluateDecision, DECISIONS } from "./phase0-decision.mjs";

function bindingMetric(values, requiredCount = 10) {
  return { ...values, observedCount: requiredCount, requiredCount, workloadSuccess: true, evidenceScope: "binding" };
}

function browserModeEvidence(overrides = {}) {
  return {
    passed: true,
    isolatedWhileRunning: true,
    cleanupPassed: true,
    stateRootRemoved: true,
    observedProcessCount: 1,
    cookieMarkerPresent: true,
    ...overrides,
  };
}

function browserEvidence(overrides = {}) {
  return {
    system: browserModeEvidence(),
    managed: browserModeEvidence(),
    crossModeCookieIsolation: true,
    ...overrides,
  };
}

function terminalWithCompositingPair(terminal, observed = true) {
  return {
    ...terminal,
    tauri: { ...terminal.tauri, compositingPairObserved: observed },
  };
}

function basePlatformEvidence(rendererKind = "webgl") {
  return {
    provenance: {
      sourceCommit: "8311fc6004cefc1146dc1ac2b13413cb801c835b",
      artifactSha256: "ab".repeat(32),
    },
    stateAudit: { passed: true, leaked: false, scannedRoots: 3, observedOutsideRoot: 0 },
    cors: { passed: true, exactAllowlist: true },
    browser: browserEvidence(),
    terminal: {
      electron: {
        terminalOpen: bindingMetric({ median: 200, p95: 250 }),
        warmStart: bindingMetric({ median: 1000, p95: 1200 }),
        firstRun: bindingMetric({ median: 2000, p95: 2400 }),
        vtebench: bindingMetric({ median: 10 }),
        largeOutput: bindingMetric({ median: 8000000 }),
        idleMemory: bindingMetric({ median: 500000000 }, 5),
        inputLatency: bindingMetric({ p95: 50 }),
        reconnect: bindingMetric({ p95: 100 }),
        activeMemory: bindingMetric({ bytes: 400000000 }, 5),
        cpuTime: bindingMetric({ ms: 1000 }),
      },
      tauri: {
        terminalOpen: bindingMetric({ median: 120, p95: 200 }),
        warmStart: bindingMetric({ median: 600, p95: 800 }),
        firstRun: bindingMetric({ median: 1500, p95: 1800 }),
        vtebench: bindingMetric({ median: 12 }),
        largeOutput: bindingMetric({ median: 9000000 }),
        idleMemory: bindingMetric({ median: 250000000 }, 5),
        inputLatency: bindingMetric({ p95: 45 }),
        reconnect: bindingMetric({ p95: 90 }),
        activeMemory: bindingMetric({ bytes: 350000000 }, 5),
        cpuTime: bindingMetric({ ms: 900 }),
        rendererKind,
      },
    },
    artifact: {
      electron: { downloadBytes: 150000000, installedBytes: 300000000, sha256: "ef".repeat(32) },
      tauri: { downloadBytes: 80000000, installedBytes: 150000000, sha256: "12".repeat(32) },
      includesACP: true,
      includesDaemon: true,
      includesBrowser: true,
      rpmExists: true,
    },
    legacyUpdate: {
      success: true,
      bridgeRequired: false,
      bridgeProven: false,
      migrationObserved: true,
      exercise: {
        kind: "electron-to-tauri",
        runner: "native-installed-update",
        legacyVersion: "0.10.0",
        targetVersion: "0.10.3",
        legacyArtifactSha256: "ef".repeat(32),
        targetArtifactSha256: "12".repeat(32),
        launchedLegacy: true,
        updateRequested: true,
        updaterExitCode: 0,
        launchedTarget: true,
        identityPreserved: true,
        statePreserved: true,
        observedAt: "2026-08-22T00:00:00.000Z",
      },
    },
    updaterSigning: {
      valid: true,
      privateKeyLeaked: false,
      signatureValid: true,
      format: "tauri-minisign",
      signer: "@tauri-apps/cli@2.11.4",
      publicKeyFingerprint: "cd".repeat(32),
      signatureSha256: "ef".repeat(32),
    },
  };
}

function validEvidence() {
  return {
    schemaVersion: 1,
    provenance: {
      kind: "phase0-ci-aggregate",
      sourceCommit: "8311fc6004cefc1146dc1ac2b13413cb801c835b",
      generatedAt: "2026-08-22T00:00:00.000Z",
      workflowRun: { repository: "OmarAly92/operator", runId: "123", attempt: 1 },
    },
    platforms: {
      darwin: basePlatformEvidence("webgl"),
      win32: basePlatformEvidence("webgl"),
      linux: { ...basePlatformEvidence("webgl"), terminal: terminalWithCompositingPair(basePlatformEvidence("webgl").terminal) },
    },
    identity: {
      identifier: "dev.operator.desktop",
      productName: "Operator",
      executable: "operator",
      aliasesPreserved: true,
    },
    updaterSigning: {
      valid: true,
      privateKeyLeaked: false,
      signatureValid: true,
      format: "tauri-minisign",
      signer: "@tauri-apps/cli@2.11.4",
      publicKeyFingerprint: "cd".repeat(32),
      signatureSha256: "ef".repeat(32),
    },
  };
}

test("missing platform evidence produces stop-port", () => {
  const evidence = validEvidence();
  delete evidence.platforms.win32;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /missing platform evidence.*win32/);
});

test("state leak produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.stateAudit.leaked = true;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /state leak/);
});

test("failed state audit produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.stateAudit.passed = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("failed standalone automation produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.browser.system.passed = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /browser/);
});

test("browser evidence must carry one record per concurrently active mode", () => {
  const flattened = validEvidence();
  flattened.platforms.darwin.browser = { passed: true, isolatedWhileRunning: true, cleanupPassed: true, stateRootRemoved: true, observedProcessCount: 1 };
  const result = evaluateDecision(flattened);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /per-mode browser/);

  const missingManaged = validEvidence();
  delete missingManaged.platforms.win32.browser.managed;
  assert.equal(evaluateDecision(missingManaged).decision, "stop-port");

  const failedManaged = validEvidence();
  failedManaged.platforms.linux.browser.managed.passed = false;
  assert.equal(evaluateDecision(failedManaged).decision, "stop-port");
});

test("cross-mode cookie isolation failure produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.browser.crossModeCookieIsolation = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /cookie isolation/);

  const leakedMarker = validEvidence();
  leakedMarker.platforms.win32.browser.system.cookieMarkerPresent = false;
  assert.equal(evaluateDecision(leakedMarker).decision, "stop-port");
});

test("cors failure produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.cors.passed = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("macOS canvas produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.rendererKind = "canvas";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /canvas/);
});

test("Windows canvas produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.terminal.tauri.rendererKind = "canvas";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("terminal throughput regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.vtebench.median = 5;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /throughput/);
});

test("terminal warm-start regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.warmStart.median = 800;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /warm-start/);
});

test("terminal idle-memory regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal.tauri.idleMemory.median = 400000000;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /idle-memory/);
});

test("terminal input latency regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.inputLatency.p95 = 60;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("terminal reconnect regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.terminal.tauri.reconnect.p95 = 150;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("active terminal memory regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.activeMemory.bytes = 500000000;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("missing ACP runtime produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.artifact.includesACP = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /ACP/);
});

test("missing RPM produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.artifact.rpmExists = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /RPM/);
});

test("missing daemon produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.artifact.includesDaemon = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /daemon/);
});

test("terminal-open median regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.terminal.tauri.terminalOpen.median = 180;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /terminal-open median/);
});

test("terminal-open p95 regression produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.terminal.tauri.terminalOpen.p95 = 300;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /terminal-open p95/);
});

test("bridge handoff with invalid signature produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.legacyUpdate = { success: false, bridgeRequired: true, bridgeProven: true, handoff: { signed: false, replacesDirectly: true } };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /bridge handoff invalid/);
});

test("bridge handoff with non-replacing proof produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.legacyUpdate = { success: false, bridgeRequired: true, bridgeProven: true, handoff: { signed: true, replacesDirectly: false } };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /bridge handoff invalid/);
});

test("changed application identity produces stop-port", () => {
  const evidence = validEvidence();
  evidence.identity.identifier = "com.example.operator";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /identity/);
});

test("changed executable name produces stop-port", () => {
  const evidence = validEvidence();
  evidence.identity.executable = "operator2";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("changed product name produces stop-port", () => {
  const evidence = validEvidence();
  evidence.identity.productName = "Operator2";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("failed legacy-update migration produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.legacyUpdate.success = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /legacy/);
});

test("invalid updater signature produces stop-port", () => {
  const evidence = validEvidence();
  evidence.updaterSigning.signatureValid = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /updater/);
});

test("private key leak produces stop-port", () => {
  const evidence = validEvidence();
  evidence.updaterSigning.privateKeyLeaked = true;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("base signed download absolute size violation produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.artifact.tauri.downloadBytes = 150000000;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /100 MiB/);
});

test("base installed footprint relative violation produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.artifact.tauri.installedBytes = 250000000;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("only documented Linux canvas exception produces linux-canvas", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal.tauri.rendererKind = "canvas";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "linux-canvas");
  assert.match(result.reasons.join(" "), /linux-canvas/);
});

test("linux canvas with terminal regression still produces stop-port not linux-canvas", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal.tauri.rendererKind = "canvas";
  evidence.platforms.linux.terminal.tauri.vtebench.median = 5;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("linux canvas plus macOS canvas produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal.tauri.rendererKind = "canvas";
  evidence.platforms.darwin.terminal.tauri.rendererKind = "canvas";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
});

test("all gates pass produces continue", () => {
  const evidence = validEvidence();
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "continue");
  assert.equal(result.reasons.length, 0);
});

test("decision is exactly one of allowed values", () => {
  const evidence = validEvidence();
  const result = evaluateDecision(evidence);
  assert.ok(DECISIONS.includes(result.decision));
  assert.equal(typeof result.reasons, "object");
  assert.ok(Array.isArray(result.reasons));
});

test("bridge-required legacy update with proven handoff still allows continue", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.legacyUpdate = {
    success: false,
    bridgeRequired: true,
    bridgeProven: true,
    handoff: { signed: true, signatureValid: true, replacesDirectly: true, exerciseObserved: true, artifactSha256: "ef".repeat(32), targetArtifactSha256: "12".repeat(32) },
  };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "continue");
  assert.match(result.reasons.join(" "), /bridge/);
});

test("malformed and incomplete evidence cannot produce continue", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin = {
    stateAudit: { passed: true, leaked: false },
    cors: { passed: true },
    browser: { passed: true },
    terminal: { electron: {}, tauri: { rendererKind: "webgl" } },
    artifact: { includesACP: true, includesDaemon: true, includesBrowser: true, rpmExists: true },
    legacyUpdate: { success: true },
    updaterSigning: {},
  };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /malformed|missing|required|provenance/);
});

test("missing aggregate provenance cannot produce continue", () => {
  const evidence = validEvidence();
  delete evidence.provenance;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /provenance/);
});

test("platform provenance must match the independently aggregated source commit", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.provenance.sourceCommit = "751744d15340c3d65166023f8c358f9a2438af78";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /source commit/);
});

test("invalid bridge evidence cannot be hidden by a valid bridge on another platform", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.legacyUpdate = {
    success: false,
    bridgeRequired: true,
    bridgeProven: true,
    handoff: { signed: false, replacesDirectly: true },
  };
  evidence.platforms.win32.legacyUpdate = {
    success: false,
    bridgeRequired: true,
    bridgeProven: true,
    handoff: { signed: true, signatureValid: true, replacesDirectly: true, exerciseObserved: true, artifactSha256: "ef".repeat(32), targetArtifactSha256: "12".repeat(32) },
  };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /invalid/);
});

test("updater evidence must prove the Tauri minisign format", () => {
  const evidence = validEvidence();
  evidence.updaterSigning.format = "raw-ed25519";
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /Tauri|minisign|format/);
});

test("terminal metrics without binding scope and complete observed counts cannot pass", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal.tauri.vtebench = { median: 12 };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /vtebench/);
});

test("boolean-reconstructed bridge handoffs cannot substitute observed evidence", () => {
  const evidence = validEvidence();
  evidence.platforms.darwin.legacyUpdate = { success: false, bridgeRequired: true, bridgeProven: true };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.doesNotMatch(result.reasons.join(" "), /proven as mandatory rollout work/);
});

test("a claimed proven bridge without retained handoff evidence cannot mint a bridge rollout decision", () => {
  const evidence = validEvidence();
  evidence.platforms.win32.legacyUpdate.bridgeRequired = true;
  evidence.platforms.win32.legacyUpdate.bridgeProven = true;
  delete evidence.platforms.win32.legacyUpdate.handoff;
  assert.equal(evaluateDecision(evidence).decision, "stop-port");
});

test("linux terminal evidence without the compositing on/off pair produces stop-port", () => {
  const evidence = validEvidence();
  evidence.platforms.linux.terminal = terminalWithCompositingPair(evidence.platforms.linux.terminal, false);
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /compositing/i);
});

test("linux compositing pair requirement does not apply to darwin or win32", () => {
  const evidence = validEvidence();
  assert.equal(evidence.platforms.darwin.terminal.tauri.compositingPairObserved, undefined);
  assert.equal(evaluateDecision(evidence).decision, "continue");
});

test("migration evidence requires the complete observed exercise and matching native artifact digests", () => {
  const missingObservation = validEvidence();
  delete missingObservation.platforms.darwin.legacyUpdate.exercise.observedAt;
  assert.equal(evaluateDecision(missingObservation).decision, "stop-port");

  const mismatchedArtifact = validEvidence();
  mismatchedArtifact.platforms.win32.legacyUpdate.exercise.targetArtifactSha256 = "34".repeat(32);
  assert.equal(evaluateDecision(mismatchedArtifact).decision, "stop-port");
});

test("partial evidence stays computable and always yields a stop-port decision object", () => {
  for (const partial of [
    undefined,
    null,
    "not-an-object",
    {},
    { schemaVersion: 1 },
    { schemaVersion: 1, provenance: { kind: "phase0-ci-aggregate" }, platforms: {} },
    {
      schemaVersion: 1,
      provenance: { kind: "phase0-ci-aggregate", sourceCommit: "8311fc6004cefc1146dc1ac2b13413cb801c835b", generatedAt: "2026-08-23T00:00:00.000Z", workflowRun: { repository: "OmarAly92/operator", runId: "123", attempt: 1 } },
      identity: null,
      updaterSigning: null,
      platforms: {
        darwin: null,
        win32: { stateAudit: { passed: true, leaked: false, scannedRoots: 3, observedOutsideRoot: 0 } },
        linux: { browser: browserEvidence() },
      },
    },
  ]) {
    const result = evaluateDecision(partial);
    assert.equal(result.decision, "stop-port");
    assert.ok(Array.isArray(result.reasons));
    assert.ok(result.reasons.length > 0);
  }
});
