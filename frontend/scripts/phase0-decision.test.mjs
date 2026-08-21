import assert from "node:assert/strict";
import test from "node:test";
import { evaluateDecision, DECISIONS } from "./phase0-decision.mjs";

function basePlatformEvidence(rendererKind = "webgl") {
  return {
    stateAudit: { passed: true, leaked: false },
    cors: { passed: true },
    browser: { passed: true },
    terminal: {
      electron: {
        terminalOpen: { median: 200, p95: 250 },
        warmStart: { median: 1000, p95: 1200 },
        firstRun: { median: 2000, p95: 2400 },
        vtebench: { median: 10 },
        largeOutput: { median: 8000000 },
        idleMemory: { median: 500000000 },
        inputLatency: { p95: 50 },
        reconnect: { p95: 100 },
        activeMemory: { bytes: 400000000 },
        cpuTime: { ms: 1000 },
      },
      tauri: {
        terminalOpen: { median: 120, p95: 200 },
        warmStart: { median: 600, p95: 800 },
        firstRun: { median: 1500, p95: 1800 },
        vtebench: { median: 12 },
        largeOutput: { median: 9000000 },
        idleMemory: { median: 250000000 },
        inputLatency: { p95: 45 },
        reconnect: { p95: 90 },
        activeMemory: { bytes: 350000000 },
        cpuTime: { ms: 900 },
        rendererKind,
      },
    },
    artifact: {
      electron: { downloadBytes: 150000000, installedBytes: 300000000 },
      tauri: { downloadBytes: 80000000, installedBytes: 150000000 },
      includesACP: true,
      includesDaemon: true,
      includesBrowser: true,
      rpmExists: true,
    },
    legacyUpdate: { success: true, bridgeRequired: false, bridgeProven: false },
    updaterSigning: { valid: true, privateKeyLeaked: false, signatureValid: true },
  };
}

function validEvidence() {
  return {
    platforms: {
      darwin: basePlatformEvidence("webgl"),
      win32: basePlatformEvidence("webgl"),
      linux: basePlatformEvidence("webgl"),
    },
    identity: {
      identifier: "dev.operator.desktop",
      productName: "Operator",
      executable: "operator",
      aliasesPreserved: true,
    },
    updaterSigning: { valid: true, privateKeyLeaked: false, signatureValid: true },
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
  evidence.platforms.darwin.browser.passed = false;
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "stop-port");
  assert.match(result.reasons.join(" "), /browser/);
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
  evidence.platforms.win32.legacyUpdate = { success: false, bridgeRequired: true, bridgeProven: true };
  const result = evaluateDecision(evidence);
  assert.equal(result.decision, "continue");
  assert.match(result.reasons.join(" "), /bridge/);
});
