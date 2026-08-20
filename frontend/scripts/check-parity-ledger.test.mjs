import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { validateParityLedger } from "./check-parity-ledger.mjs";

const deferredBrowserRecord = "docs/todo/browser-panel-webview.md";

async function fixture() {
	const rootDir = await mkdtemp(join(tmpdir(), "operator-parity-"));
	await mkdir(join(rootDir, "src", "main"), { recursive: true });
	await mkdir(join(rootDir, "src", "renderer", "hooks"), { recursive: true });
	await writeFile(
		join(rootDir, "src", "preload.ts"),
		`const api = {
	app: {
		getVersion: () => "1.0.0",
		openExternal: (url: string) => url,
	},
	browser: {
		navigate: (url: string) => url,
	},
};
`,
	);
	await writeFile(join(rootDir, "src", "renderer", "hooks", "useMigration.ts"), `import type { Migration } from "../../main/app-state";\n`);
	await writeFile(join(rootDir, "src", "renderer", "hooks", "useBrowser.ts"), `import type { BrowserState } from "../../main/browser-view-host";\n`);
	await writeFile(join(rootDir, "src", "main", "app-state.ts"), "export type Migration = {};\n");
	await writeFile(join(rootDir, "src", "main", "browser-view-host.ts"), "export type BrowserState = {};\n");
	await writeFile(join(rootDir, "src", "main", "app-state.test.ts"), "throw new Error();\n");
	return rootDir;
}

function completeLedger() {
	return [
		{ source: "preload.app", member: "getVersion", disposition: "native", owner: "tauri", task: 14, exception: null },
		{ source: "preload.app", member: "openExternal", disposition: "native", owner: "tauri", task: 14, exception: null },
		{ source: "preload.browser", member: "navigate", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
		{ source: "renderer/hooks/useMigration.ts", member: "../../main/app-state", disposition: "shared type", owner: "renderer", task: 8, exception: null },
		{ source: "renderer/hooks/useBrowser.ts", member: "../../main/browser-view-host", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
		{ source: "main", member: "app-state.ts", disposition: "native", owner: "tauri", task: 12, exception: null },
		{ source: "main", member: "browser-view-host.ts", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
	];
}

async function errorsFor(change) {
	const rootDir = await fixture();
	try {
		const ledger = completeLedger();
		change(ledger);
		return await validateParityLedger({ rootDir, ledger });
	} finally {
		await rm(rootDir, { recursive: true, force: true });
	}
}

test("rejects duplicate source and member pairs", async () => {
	const errors = await errorsFor((ledger) => ledger.push({ ...ledger[0] }));
	assert(errors.some((message) => message.includes("duplicate preload.app/getVersion")));
});

test("requires every preload namespace member", async () => {
	const errors = await errorsFor((ledger) => ledger.splice(1, 1));
	assert(errors.some((message) => message.includes("missing preload.app/openExternal")));
});

test("requires every renderer main-process import", async () => {
	const errors = await errorsFor((ledger) => ledger.splice(3, 1));
	assert(errors.some((message) => message.includes("missing renderer/hooks/useMigration.ts/../../main/app-state")));
});

test("requires every production main-process module and ignores tests", async () => {
	const errors = await errorsFor((ledger) => ledger.splice(5, 1));
	assert(errors.some((message) => message.includes("missing main/app-state.ts")));
	assert(!errors.some((message) => message.includes("app-state.test.ts")));
});

test("accepts exceptions only for entries in the deferred Browser-panel record", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[0] = { ...ledger[0], disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord };
	});
	assert(errors.some((message) => message.includes("exception is not allowed for preload.app/getVersion")));
});

test("requires a task number and an allowed owner for non-exception entries", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[0] = { ...ledger[0], task: null };
		ledger[1] = { ...ledger[1], owner: "electron" };
	});
	assert(errors.some((message) => message.includes("task must be a positive integer for preload.app/getVersion")));
	assert(errors.some((message) => message.includes("owner must be tauri, go, or renderer for preload.app/openExternal")));
});

test("accepts a complete ledger", async () => {
	const errors = await errorsFor(() => {});
	assert.deepEqual(errors, []);
});
