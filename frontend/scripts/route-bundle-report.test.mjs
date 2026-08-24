import assert from "node:assert/strict";
import test from "node:test";
import {
	assertNoAbsolutePaths,
	buildRouteBundleReport,
	classifyEagerViolations,
	eagerModuleIds,
	FORBIDDEN_EAGER_CATEGORIES,
	parseManifest,
	resolveBoardEntry,
	validateReportSchema,
} from "./route-bundle-report.mjs";

function violatingManifest() {
	return {
		"index.html": {
			file: "assets/index-entry.js",
			name: "index",
			src: "index.html",
			isEntry: true,
			imports: ["src/renderer/routes/__root.tsx"],
			css: ["assets/index.css"],
		},
		"src/renderer/routes/__root.tsx": {
			file: "assets/root.js",
			imports: ["src/renderer/routes/_shell.tsx"],
		},
		"src/renderer/routes/_shell.tsx": {
			file: "assets/shell.js",
			imports: [
				"src/renderer/components/TerminalPane.tsx",
				"src/renderer/components/SettingsDialog.tsx",
			],
			dynamicImports: ["src/renderer/routes/_shell.index.tsx"],
		},
		"src/renderer/components/TerminalPane.tsx": {
			file: "assets/terminal-pane.js",
			imports: [
				"src/renderer/components/XtermTerminal.tsx",
				"node_modules/@xterm/xterm/lib/xterm.js",
			],
		},
		"src/renderer/components/XtermTerminal.tsx": {
			file: "assets/xterm-component.js",
			imports: ["node_modules/@xterm/xterm/lib/xterm.js"],
		},
		"node_modules/@xterm/xterm/lib/xterm.js": {
			file: "assets/xterm.js",
		},
		"src/renderer/components/SettingsDialog.tsx": {
			file: "assets/settings-dialog.js",
		},
		"src/renderer/routes/_shell.index.tsx": {
			file: "assets/board-route.js",
			isDynamicEntry: true,
			imports: ["src/renderer/components/SessionsBoard.tsx"],
		},
		"src/renderer/components/SessionsBoard.tsx": {
			file: "assets/sessions-board.js",
		},
	};
}

function cleanManifest() {
	const manifest = violatingManifest();
	manifest["src/renderer/routes/_shell.tsx"].imports = [];
	manifest["src/renderer/routes/_shell.tsx"].dynamicImports = [
		"src/renderer/routes/_shell.index.tsx",
		"src/renderer/components/TerminalPane.tsx",
		"src/renderer/components/SettingsDialog.tsx",
	];
	return manifest;
}

const sizes = {
	"assets/index-entry.js": 1000,
	"assets/index.css": 100,
	"assets/root.js": 2000,
	"assets/shell.js": 3000,
	"assets/terminal-pane.js": 5000,
	"assets/xterm-component.js": 4000,
	"assets/xterm.js": 9000,
	"assets/settings-dialog.js": 6000,
	"assets/board-route.js": 700,
	"assets/sessions-board.js": 800,
};

function realWorldShapeManifest() {
	const manifest = {
		"index.html": {
			file: "assets/index-entry.js",
			name: "index",
			src: "index.html",
			isEntry: true,
			imports: ["_shared-vendor.js"],
			dynamicImports: [
				"src/renderer/routes/_shell.tsx?tsr-split=component",
				"src/renderer/routes/_shell.index.tsx?tsr-split=component",
				"src/renderer/routes/_shell.settings.tsx?tsr-split=component",
			],
		},
		"_shared-vendor.js": { file: "assets/shared-vendor.js" },
		"src/renderer/routes/_shell.tsx?tsr-split=component": {
			file: "assets/shell-route.js",
			imports: ["_terminal-pane-chunk.js"],
			dynamicImports: ["src/renderer/routes/_shell.settings.tsx?tsr-split=component"],
		},
		"_terminal-pane-chunk.js": {
			file: "assets/terminal-pane-chunk.js",
			imports: ["node_modules/@xterm/xterm/lib/xterm.js"],
		},
		"node_modules/@xterm/xterm/lib/xterm.js": {
			file: "assets/xterm.js",
		},
		"src/renderer/routes/_shell.index.tsx?tsr-split=component": {
			file: "assets/board-route.js",
			imports: ["src/renderer/components/SessionsBoard.tsx"],
		},
		"src/renderer/components/SessionsBoard.tsx": {
			file: "assets/sessions-board.js",
		},
		"src/renderer/routes/_shell.settings.tsx?tsr-split=component": {
			file: "assets/settings-route.js",
		},
	};
	const sizes = { "assets/index-entry.js": 1000, "assets/shared-vendor.js": 500, "assets/shell-route.js": 300, "assets/terminal-pane-chunk.js": 400, "assets/xterm.js": 9000, "assets/board-route.js": 700, "assets/sessions-board.js": 800, "assets/settings-route.js": 600 };
	return { manifest, sizes };
}

test("the report resolves tsr-split board entries and underscore chunk-file edges", () => {
	const { manifest } = realWorldShapeManifest();
	assert.equal(resolveBoardEntry(manifest), "src/renderer/routes/_shell.index.tsx?tsr-split=component");
	const report = buildRouteBundleReport({
		manifest,
		sizes: realWorldShapeManifest().sizes,
		label: "before",
		git: { commit: "d".repeat(40), dirty: false },
		host: { platform: "darwin", architecture: "arm64" },
		generatedAt: "2026-08-24T00:00:00.000Z",
	});
	const ids = report.board.files.map((row) => row.id);
	assert.ok(ids.includes("_terminal-pane-chunk.js"));
	assert.ok(ids.includes("node_modules/@xterm/xterm/lib/xterm.js"));
	assert.ok(ids.includes("src/renderer/components/SessionsBoard.tsx"));
	assert.ok(!ids.some((id) => id.includes("_shell.settings")));
	assert.ok(report.board.violations.some((violation) => violation.category === "terminal"));
	assert.equal(
		report.board.parsedBytes,
		1000 + 500 + 300 + 400 + 9000 + 700 + 800,
	);
});

test("parseManifest accepts a well-formed manifest and rejects malformed input", () => {
	const manifest = parseManifest(violatingManifest());
	assert.equal(manifest["index.html"].isEntry, true);
	assert.deepEqual(
		manifest["src/renderer/routes/_shell.tsx"].imports.sort(),
		[
			"src/renderer/components/SettingsDialog.tsx",
			"src/renderer/components/TerminalPane.tsx",
		].sort(),
	);
	assert.throws(() => parseManifest(null), /manifest must be an object/);
	assert.throws(() => parseManifest({ lone: {} }), /missing file/);
});

test("resolveBoardEntry finds exactly one board route module", () => {
	const manifest = violatingManifest();
	assert.equal(resolveBoardEntry(manifest), "src/renderer/routes/_shell.index.tsx");
	assert.throws(() => resolveBoardEntry({}), /board route module/);
});

test("eagerModuleIds follows static imports only and never dynamic imports", () => {
	const eager = eagerModuleIds(violatingManifest(), "index.html");
	assert.ok(eager.includes("src/renderer/routes/__root.tsx"));
	assert.ok(eager.includes("src/renderer/routes/_shell.tsx"));
	assert.ok(eager.includes("src/renderer/components/TerminalPane.tsx"));
	assert.ok(eager.includes("node_modules/@xterm/xterm/lib/xterm.js"));
	assert.ok(!eager.includes("src/renderer/routes/_shell.index.tsx"));

	const boardEager = eagerModuleIds(violatingManifest(), "src/renderer/routes/_shell.index.tsx");
	assert.deepEqual(boardEager, [
		"src/renderer/components/SessionsBoard.tsx",
		"src/renderer/routes/_shell.index.tsx",
	]);
	assert.throws(() => eagerModuleIds(violatingManifest(), "missing/id.tsx"), /not present in manifest/);
});

test("classifyEagerViolations flags forbidden terminal and settings edges in the before graph", () => {
	const violations = classifyEagerViolations(violatingManifest(), eagerModuleIds(violatingManifest(), "index.html"));
	const categories = new Set(violations.map((violation) => violation.category));
	assert.ok(categories.has("terminal"));
	assert.ok(categories.has("settings"));
	assert.ok(
		violations.some((violation) => violation.id === "node_modules/@xterm/xterm/lib/xterm.js"),
	);
	assert.equal(classifyEagerViolations(cleanManifest(), eagerModuleIds(cleanManifest(), "index.html")).length, 0);
});

test("a TerminalPane chunk that defers xterm behind a dynamic import edge is not a violation", () => {
	const splitManifest = cleanManifest();
	splitManifest["src/renderer/routes/_shell.tsx"].imports = ["src/renderer/components/TerminalPane.tsx"];
	splitManifest["src/renderer/components/TerminalPane.tsx"] = {
		file: "assets/terminal-pane-provider.js",
		dynamicImports: ["_XtermTerminal-split.js"],
	};
	splitManifest["_XtermTerminal-split.js"] = { file: "assets/XtermTerminal-split.js" };
	const violations = classifyEagerViolations(splitManifest, eagerModuleIds(splitManifest, "index.html"));
	assert.equal(violations.length, 0);
});

test("every forbidden category pattern matches its canonical module id", () => {
	const canonical = {
		terminal: "_TerminalPane-hZ6qon73.js",
		settings: "src/renderer/routes/_shell.settings.tsx?tsr-split=component",
		chat: "_SessionView-BcZUzEVm.js",
		diff: "src/renderer/lib/code-highlight-engine.ts",
	};
	for (const { category, pattern } of FORBIDDEN_EAGER_CATEGORIES) {
		assert.match(canonical[category], pattern);
	}
	assert.equal(FORBIDDEN_EAGER_CATEGORIES.find(({ category }) => category === "diff").pattern.test("_pr-display-KbnZFQwH.js"), false);
});

test("buildRouteBundleReport produces a schema-valid sanitized report for before and after labels", () => {
	for (const label of ["before", "after"]) {
		const report = buildRouteBundleReport({
			manifest: violatingManifest(),
			sizes,
			label,
			git: { commit: "a".repeat(40), dirty: true },
			host: { platform: "darwin", architecture: "arm64" },
			generatedAt: "2026-08-24T00:00:00.000Z",
		});
		validateReportSchema(report);
		assert.equal(report.label, label);
		assert.equal(report.board.parsedBytes, 31600);
		assert.ok(report.board.violations.length > 0);
		assert.ok(report.bundle.totalBytes >= report.board.parsedBytes);
		const orderedBytes = report.bundle.largestChunks.map((row) => row.bytes);
		assert.deepEqual([...orderedBytes].sort((left, right) => right - left), orderedBytes);
	}
});

test("validateReportSchema rejects incomplete reports, unknown labels, and inconsistent summaries", () => {
	const valid = buildRouteBundleReport({
		manifest: cleanManifest(),
		sizes,
		label: "before",
		git: { commit: "b".repeat(40), dirty: false },
		host: { platform: "darwin", architecture: "arm64" },
		generatedAt: "2026-08-24T00:00:00.000Z",
	});
	validateReportSchema(valid);

	assert.throws(() => validateReportSchema({ ...valid, label: "midway" }), /label/);
	assert.throws(() => validateReportSchema({ ...valid, board: undefined }), /board/);
	const mismatched = structuredClone(valid);
	mismatched.board.parsedBytes += 1;
	assert.throws(() => validateReportSchema(mismatched), /parsedBytes/);
	const shortCommit = structuredClone(valid);
	shortCommit.commit = "abc";
	assert.throws(() => validateReportSchema(shortCommit), /commit/);
});

test("reports refuse absolute or home-relative paths instead of emitting them", () => {
	const poisoned = cleanManifest();
	const homeManifestId = `${"/Users/somebody/dev"}/src/renderer/routes/_shell.index.tsx`;
	poisoned[homeManifestId] = poisoned["src/renderer/routes/_shell.index.tsx"];
	delete poisoned["src/renderer/routes/_shell.index.tsx"];
	assert.throws(
		() =>
			buildRouteBundleReport({
				manifest: poisoned,
				sizes,
				label: "after",
				git: { commit: "c".repeat(40), dirty: false },
				host: { platform: "darwin", architecture: "arm64" },
				generatedAt: "2026-08-24T00:00:00.000Z",
			}),
		/absolute path/,
	);
	const report = buildRouteBundleReport({
		manifest: cleanManifest(),
		sizes,
		label: "after",
		git: { commit: "c".repeat(40), dirty: false },
		host: { platform: "darwin", architecture: "arm64" },
		generatedAt: "2026-08-24T00:00:00.000Z",
	});
	assertNoAbsolutePaths(report);
});
