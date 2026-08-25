import assert from "node:assert/strict";
import { test } from "node:test";

import {
	DRIVER_MARKER,
	REGISTRATION_CALLS,
	REGISTRATION_GUARD,
	assertFeatureIsolation,
	binaryContainsDriver,
	cargoTreeCrates,
	registrationErrors,
} from "./e2e-tauri-build-contract.mjs";

const TREE_WITHOUT = `
operator_lib v0.10.3 (/x/frontend/src-tauri)
├── base64 v0.22.1
├── chrono v0.4.45
├── global-hotkey v0.8.0
├── tauri v2.11.5
├── tauri-plugin-clipboard-manager v2.3.2
├── tauri-plugin-dialog v2.7.2
├── tauri-plugin-global-shortcut v2.3.2
├── tauri-plugin-notification v2.3.3
├── tauri-plugin-opener v2.5.4
├── tauri-plugin-updater v2.10.1
└── tokio v1.53.1
`;

const TREE_WITH = `${TREE_WITHOUT.replace("└── tokio v1.53.1", "├── tauri-plugin-wdio v1.3.0\n├── tauri-plugin-wdio-webdriver v1.3.0\n└── tokio v1.53.1")}`;

function guardedLibRs() {
	return `
    } else {
        #[cfg(feature = "e2e")]
        {
            builder = builder
                .plugin(tauri_plugin_wdio::init())
                .plugin(tauri_plugin_wdio_webdriver::init());
        }
        builder = builder.invoke_handler(tauri::generate_handler![
`;
}

test("cargoTreeCrates extracts crate names from cargo tree output", () => {
	const names = cargoTreeCrates(TREE_WITH);
	assert.ok(names.includes("tauri-plugin-wdio"));
	assert.ok(names.includes("tauri-plugin-wdio-webdriver"));
	assert.ok(names.includes("tauri"));
	assert.ok(!names.includes("v2.11.5"));
});

test("feature isolation holds for the pinned plugin crates", () => {
	assert.deepEqual(assertFeatureIsolation(TREE_WITHOUT, TREE_WITH), []);
});

test("feature isolation fails when a plugin leaks into default features", () => {
	const leaked = TREE_WITHOUT.replace("└── tokio v1.53.1", "├── tauri-plugin-wdio v1.3.0\n└── tokio v1.53.1");
	const errors = assertFeatureIsolation(leaked, TREE_WITH);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /resolves tauri-plugin-wdio; it must be e2e-only/);
});

test("feature isolation fails when the feature resolves nothing", () => {
	const errors = assertFeatureIsolation(TREE_WITHOUT, TREE_WITHOUT);
	assert.equal(errors.length, 2);
	assert.match(errors.join("\n"), /does not resolve tauri-plugin-wdio;/);
});

test("guarded registration passes the source scan", () => {
	assert.deepEqual(registrationErrors(guardedLibRs()), []);
});

test("registration outside the e2e guard fails the source scan", () => {
	const unguarded = guardedLibRs().replaceAll(`#[cfg(feature = "e2e")]`, "// removed guard");
	const errors = registrationErrors(unguarded);
	assert.equal(errors.length, REGISTRATION_CALLS.length);
	assert.match(errors[0], /outside a/);
});

test("a missing registration call fails the source scan", () => {
	const missing = guardedLibRs().replace("tauri_plugin_wdio_webdriver::init()", "todo!()");
	const errors = registrationErrors(missing);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /never registers tauri_plugin_wdio_webdriver/);
});

test("the driver marker is detected in binary buffers exactly", () => {
	const marker = Buffer.from(`... ${DRIVER_MARKER} 4445 ...`, "utf8");
	assert.equal(binaryContainsDriver(marker), true);
	assert.equal(binaryContainsDriver(Buffer.from("no driver here", "utf8")), false);
});

test("the contract constants stay aligned with the implementation they scan", () => {
	assert.equal(REGISTRATION_GUARD, '#[cfg(feature = "e2e")]');
	assert.equal(REGISTRATION_CALLS.length, 2);
	assert.match(DRIVER_MARKER, /^WDIO WebDriver plugin initialized/);
});
