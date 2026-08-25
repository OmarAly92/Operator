import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { validateParityLedger } from "./check-parity-ledger.mjs";

const deferredBrowserRecord = "docs/todo/browser-panel-webview.md";

const bridgeFixture = `import type { OperatorBridge } from "../../shared/operator-bridge";

export function createTauriBridge({ invoke, listen }: TauriBridgeTransports): OperatorBridge {
	const helper = () => invoke("helper");
	return {
		app: {
			getVersion: async () => "1.0.0",
			openExternal: async (url: string) => url,
		},
		browser: {
			navigate: (url: string) => url,
		},
	};
}
`;

async function fixture() {
	const rootDir = await mkdtemp(join(tmpdir(), "operator-parity-"));
	await mkdir(join(rootDir, "src", "renderer", "lib"), { recursive: true });
	await mkdir(join(rootDir, "src", "renderer", "hooks"), { recursive: true });
	await writeFile(join(rootDir, "src", "renderer", "lib", "tauri-bridge.ts"), bridgeFixture);
	await writeFile(join(rootDir, "src", "renderer", "hooks", "useMigration.ts"), `import type { Migration } from "../../main/app-state";\n`);
	await writeFile(join(rootDir, "src", "renderer", "hooks", "useBrowserView.ts"), `import type { BrowserState } from "../../main/browser-view-host";\n`);
	return rootDir;
}

function completeLedger() {
	return [
		{ source: "bridge.app", member: "getVersion", disposition: "native", owner: "tauri", task: 14, exception: null },
		{ source: "bridge.app", member: "openExternal", disposition: "native", owner: "tauri", task: 14, exception: null },
		{ source: "bridge.browser", member: "navigate", disposition: "native", owner: "tauri", task: 13, exception: null },
		{ source: "preload.browser", member: "navigate", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
		{ source: "renderer/hooks/useMigration.ts", member: "../../main/app-state", disposition: "shared type", owner: "renderer", task: 8, exception: null },
		{ source: "renderer/hooks/useBrowserView.ts", member: "../../main/browser-view-host", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
		{ source: "main", member: "app-state.ts", disposition: "native", owner: "tauri", task: 12, exception: null },
		{ source: "main", member: "browser-view-host.ts", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord },
	].map((entry) => ({ ...entry, status: "contract:test" }));
}

async function errorsFor(change, arrange = async () => {}) {
	const rootDir = await fixture();
	try {
		const ledger = completeLedger();
		await arrange(rootDir);
		change(ledger);
		return await validateParityLedger({ rootDir, ledger });
	} finally {
		await rm(rootDir, { recursive: true, force: true });
	}
}

test("rejects duplicate source and member pairs", async () => {
	const errors = await errorsFor((ledger) => ledger.push({ ...ledger[0] }));
	assert(errors.some((message) => message.includes("duplicate bridge.app/getVersion")));
});

test("requires every desktop bridge namespace member", async () => {
	const errors = await errorsFor((ledger) => ledger.splice(1, 1));
	assert(errors.some((message) => message.includes("missing bridge.app/openExternal")));
});

test("requires every renderer main-process import to stay recorded", async () => {
	const errors = await errorsFor((ledger) => ledger.splice(4, 1));
	assert(errors.some((message) => message.includes("missing renderer/hooks/useMigration.ts/../../main/app-state")));
});

test("rejects an unrecorded new desktop bridge member", async () => {
	const errors = await errorsFor(
		(ledger) => ledger.splice(2, 1),
		async (rootDir) => {
			const bridgePath = join(rootDir, "src", "renderer", "lib", "tauri-bridge.ts");
			const source = await readFile(bridgePath, "utf8");
			await writeFile(bridgePath, source.replace("openExternal:", "printPage:\n\t\t\tasync () => undefined,\n\t\t\topenExternal:"));
		},
	);
	assert(errors.some((message) => message.includes("missing bridge.app/printPage")));
});

test("accepts exceptions only for entries in the deferred Browser-panel record", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[0] = { ...ledger[0], disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord };
	});
	assert(errors.some((message) => message.includes("exception is not allowed for bridge.app/getVersion")));
});

test("rejects an unrecorded preload Browser member exception", async () => {
	const errors = await errorsFor((ledger) =>
		ledger.push({ source: "preload.browser", member: "print", disposition: "deferred", owner: null, task: null, exception: deferredBrowserRecord }),
	);
	assert(errors.some((message) => message.includes("exception is not allowed for preload.browser/print")));
});

test("rejects an unrecorded renderer Browser import exception", async () => {
	const errors = await errorsFor(
		(ledger) =>
			ledger.push({
				source: "renderer/hooks/useUnknownBrowser.ts",
				member: "../../main/browser-view-host",
				disposition: "deferred",
				owner: null,
				task: null,
				exception: deferredBrowserRecord,
			}),
		async (rootDir) => {
			await writeFile(join(rootDir, "src", "renderer", "hooks", "useUnknownBrowser.ts"), `import type { BrowserState } from "../../main/browser-view-host";\n`);
		},
	);
	assert(errors.some((message) => message.includes("exception is not allowed for renderer/hooks/useUnknownBrowser.ts/../../main/browser-view-host")));
});

test("requires a known deferred Browser entry to use the exact deferred record", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[3] = { source: "preload.browser", member: "navigate", disposition: "deferred", owner: null, task: null, exception: "../other-record.md" };
	});
	assert(errors.some((message) => message.includes("deferred Browser entry must use the exact deferred record for preload.browser/navigate")));
});

test("requires a known deferred Browser entry to keep a deferred disposition", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[3] = { source: "preload.browser", member: "navigate", disposition: "native", owner: null, task: null, exception: deferredBrowserRecord };
	});
	assert(errors.some((message) => message.includes("deferred Browser entry disposition must be deferred for preload.browser/navigate")));
});

test("requires a known deferred Browser entry to keep null owner and task", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[3] = { source: "preload.browser", member: "navigate", disposition: "deferred", owner: "tauri", task: 8, exception: deferredBrowserRecord };
	});
	assert(errors.some((message) => message.includes("deferred Browser entry owner and task must be null for preload.browser/navigate")));
});

test("keeps archived electron rows exempt from staleness while their surfaces stay deleted", async () => {
	const errors = await errorsFor(() => {});
	assert.deepEqual(errors, []);
});

test("rejects archived main-process surfaces that reappear on disk", async () => {
	const errors = await errorsFor(
		() => {},
		async (rootDir) => {
			await mkdir(join(rootDir, "src", "main"), { recursive: true });
			await writeFile(join(rootDir, "src", "main", "app-state.ts"), "export type Migration = {};\n");
		},
	);
	assert(errors.some((message) => message.includes("archived electron main-process modules reappeared under src/main")));
});

test("rejects ledger rows outside the live and archived source classes", async () => {
	const errors = await errorsFor((ledger) => ledger.push({ source: "electron", member: "ipcMain.ts", disposition: "native", owner: "tauri", task: 21, exception: null }));
	assert(errors.some((message) => message.includes("source must start with bridge. or name an archived electron surface for electron/ipcMain.ts")));
});

test("bridge inventory survives regular-expression literals and non-bridge returns", async () => {
	const errors = await errorsFor(
		(ledger) => ledger.push({ source: "bridge.app", member: "matchesBrace", disposition: "renderer utility", owner: "renderer", task: 8, exception: null, status: "contract:test" }),
		async (rootDir) => {
			const bridgePath = join(rootDir, "src", "renderer", "lib", "tauri-bridge.ts");
			const source = await readFile(bridgePath, "utf8");
			await writeFile(bridgePath, source.replace('getVersion: async () => "1.0.0",', 'getVersion: async () => "1.0.0",\n\t\t\tmatchesBrace: (text: string) => /{/.test(text),'));
		},
	);
	assert.deepEqual(errors, []);
});

test("renderer inventory accepts single-quoted main-process imports", async () => {
	const errors = await errorsFor(
		(ledger) => ledger.push({ source: "renderer/hooks/useSingleQuote.ts", member: "../../main/app-state", disposition: "shared type", owner: "renderer", task: 8, exception: null, status: "contract:test" }),
		async (rootDir) => {
			await writeFile(join(rootDir, "src", "renderer", "hooks", "useSingleQuote.ts"), "import type { Migration } from '../../main/app-state';\n");
		},
	);
	assert.deepEqual(errors, []);
});

test("renderer inventory includes main-process re-exports", async () => {
	const errors = await errorsFor(
		(ledger) => ledger.push({ source: "renderer/lib/reexport.ts", member: "../../main/feature-builds", disposition: "shared type", owner: "renderer", task: 8, exception: null, status: "contract:test" }),
		async (rootDir) => {
			await writeFile(join(rootDir, "src", "renderer", "lib", "reexport.ts"), `export type { FeatureBuild } from "../../main/feature-builds";\n`);
		},
	);
	assert.deepEqual(errors, []);
});

test("requires a task number and an allowed owner for live entries", async () => {
	const errors = await errorsFor((ledger) => {
		ledger[0] = { ...ledger[0], task: null };
		ledger[1] = { ...ledger[1], owner: "electron" };
	});
	assert(errors.some((message) => message.includes("task must be a positive integer for bridge.app/getVersion")));
	assert(errors.some((message) => message.includes("owner must be tauri, go, or renderer for bridge.app/openExternal")));
});

test("requires verification status for live entries", async () => {
	const errors = await errorsFor((ledger) => {
		delete ledger[0].status;
	});
	assert(errors.some((message) => message.includes("status must be non-empty for bridge.app/getVersion")));
});

test("accepts a complete ledger", async () => {
	const errors = await errorsFor(() => {});
	assert.deepEqual(errors, []);
});
