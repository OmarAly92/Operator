import assert from "node:assert/strict";
import test from "node:test";
import {
  evaluateLegacyUpdate,
  validateBridgeHandoff,
  DECISION as LEGACY_DECISION,
} from "./phase0-legacy-update.mjs";

function validMigrations() {
  return {
    darwin: { directSuccess: true, bridgeRequired: false, bridgeProven: false },
    win32: { directSuccess: true, bridgeRequired: false, bridgeProven: false },
    linux: { directSuccess: true, bridgeRequired: false, bridgeProven: false },
  };
}

test("direct migration on all platforms succeeds", () => {
  const result = evaluateLegacyUpdate(validMigrations());
  assert.equal(result.success, true);
  assert.equal(result.bridgeRequired, false);
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
  const result = validateBridgeHandoff({ signed: true, replacesDirectly: true });
  assert.equal(result.valid, true);
});
