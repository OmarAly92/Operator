import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const frontendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = path.resolve(frontendRoot, "..");

const deletedPaths = [
	"frontend/src/main.ts",
	"frontend/src/preload.ts",
	"frontend/src/preload.test.ts",
	"frontend/src/annotate-preload.ts",
	"frontend/src/annotate-preload.test.ts",
	"frontend/src/main",
	"frontend/src/shared/browser-annotation-overlay.ts",
	"frontend/src/shared/browser-annotation-overlay.test.ts",
	"frontend/src/shared/browser-annotations.ts",
	"frontend/src/shared/browser-annotations.test.ts",
	"frontend/src/shared/browser-tabs.ts",
	"frontend/src/shared/daemon-attach.ts",
	"frontend/src/shared/daemon-attach.test.ts",
	"frontend/src/shared/daemon-discovery.ts",
	"frontend/src/shared/daemon-discovery.test.ts",
	"frontend/src/shared/daemon-launch.ts",
	"frontend/src/shared/daemon-launch.test.ts",
	"frontend/src/shared/daemon-takeover.ts",
	"frontend/src/shared/daemon-takeover.test.ts",
	"frontend/src/shared/shell-env.ts",
	"frontend/src/shared/shell-env.test.ts",
	"frontend/forge.config.ts",
	"frontend/vite.main.config.ts",
	"frontend/vite.preload.config.ts",
	"frontend/makers",
	"backend/internal/browserruntime",
].map((relativePath) => path.join(repoRoot, relativePath));

const deletedSharedModulePattern =
	/shared\/(browser-annotation-overlay|browser-annotations|browser-tabs|daemon-attach|daemon-discovery|daemon-launch|daemon-takeover|shell-env)/;

const electronPackagePattern = /^(electron|electron-updater|electron-installer-debian|electron-installer-redhat)$/;
const forgePackagePattern = /^@electron-forge\//;

const removedScripts = new Set(["dev", "predev", "package", "prepackage", "make", "premake", "publish"]);

const requiredScripts = [
	"build:acp-runtime",
	"browser-runtime:prepare",
	"build:daemon",
	"check:desktop-parity",
	"dev:web",
	"feed:tauri",
	"package:tauri-mac-zip",
	"tauri:build",
	"tauri:dev",
	"tauri:release",
	"test",
	"test:e2e",
	"test:e2e:renderer",
	"test:e2e:tauri",
	"typecheck",
	"typecheck:e2e",
	"typecheck:e2e-tauri",
	"verify:tauri-artifacts",
];

const sourceExtensions = /\.(?:[cm]?[jt]sx?)$/;

const legacyRecordPaths = new Set(
	["docs/superpowers", "docs/plans", "docs/todo"].map((segment) => segment.split("/")),
);

function walk(rootDir, options = {}) {
	const skip = new Set(options.skip ?? []);
	const entries = [];
	async function visit(directory) {
		for (const entry of await readdir(directory, { withFileTypes: true })) {
			if (skip.has(entry.name)) continue;
			const filePath = path.join(directory, entry.name);
			if (entry.isDirectory()) {
				await visit(filePath);
				continue;
			}
			if (!entry.isFile()) continue;
			if (options.extension && !options.extension.test(entry.name)) continue;
			entries.push(filePath);
		}
	}
	return visit(rootDir).then(() => entries);
}

function relativeToRepo(filePath) {
	return path.relative(repoRoot, filePath).split(path.sep).join("/");
}

function isLegacyRecord(relativePathSegments) {
	return legacyRecordPaths.has(relativePathSegments.slice(0, 2));
}

test("every deleted electron surface is absent from the working tree", () => {
	for (const deletedPath of deletedPaths) {
		assert.equal(existsSync(deletedPath), false, `${relativeToRepo(deletedPath)} must stay deleted`);
	}
});

test("package.json carries no electron runtime, updater, forge, or installer dependency", async () => {
	const manifest = JSON.parse(await readFile(path.join(frontendRoot, "package.json"), "utf8"));
	const sections = [
		["dependencies", manifest.dependencies],
		["devDependencies", manifest.devDependencies],
		["optionalDependencies", manifest.optionalDependencies],
	];
	for (const [section, dependencies] of sections) {
		for (const name of Object.keys(dependencies ?? {})) {
			assert.doesNotMatch(name, electronPackagePattern, `${section}.${name} must stay removed`);
			assert.doesNotMatch(name, forgePackagePattern, `${section}.${name} must stay removed`);
		}
	}
	assert.ok(!manifest.allowScripts?.electron, "allowScripts must not whitelist electron postinstall");
});

test("package.json keeps the tauri script surface that replaces electron", async () => {
	const manifest = JSON.parse(await readFile(path.join(frontendRoot, "package.json"), "utf8"));
	for (const required of requiredScripts) {
		assert.ok(typeof manifest.scripts[required] === "string", `scripts.${required} must exist`);
	}
});

test("package.json drops the electron lifecycle scripts and entry point", async () => {
	const manifest = JSON.parse(await readFile(path.join(frontendRoot, "package.json"), "utf8"));
	assert.ok(manifest.main === undefined, "an electron main entry point must not remain");
	for (const scriptName of Object.keys(manifest.scripts)) {
		assert.ok(!removedScripts.has(scriptName), `scripts.${scriptName} must stay removed`);
		assert.doesNotMatch(manifest.scripts[scriptName], /electron/i, `scripts.${scriptName} must not invoke electron`);
	}
});

test("dev:web selects the renamed renderer preview environment", async () => {
	const manifest = JSON.parse(await readFile(path.join(frontendRoot, "package.json"), "utf8"));
	assert.match(manifest.scripts["dev:web"], /VITE_RENDERER_PREVIEW=1/);
	assert.doesNotMatch(manifest.scripts["dev:web"], /VITE_NO_ELECTRON/);
});

test("preview-mode reads the renamed renderer preview flag", async () => {
	const source = await readFile(path.join(frontendRoot, "src/renderer/lib/preview-mode.ts"), "utf8");
	assert.match(source, /import\.meta\.env\.VITE_RENDERER_PREVIEW === "1"/);
	assert.doesNotMatch(source, /VITE_NO_ELECTRON/);
});

async function sourceFilesUnder(...segments) {
	return walk(path.join(repoRoot, ...segments), { extension: sourceExtensions });
}

test("frontend sources import neither electron nor deleted main-process modules", async () => {
	const files = await sourceFilesUnder("frontend", "src");
	for (const filePath of files) {
		const source = await readFile(filePath, "utf8");
		assert.doesNotMatch(source, /(?:from|require\()\s*["']electron["']/, `${relativeToRepo(filePath)} imports electron`);
		assert.doesNotMatch(source, /["'](?:\.\/|\.\.\/)+main\//, `${relativeToRepo(filePath)} imports a deleted src/main module`);
		assert.doesNotMatch(source, deletedSharedModulePattern, `${relativeToRepo(filePath)} imports a deleted shared module`);
	}
});

test("renderer and e2e fixtures expose no preload browser broker surface", async () => {
	const rendererFiles = await sourceFilesUnder("frontend", "src", "renderer");
	for (const filePath of rendererFiles) {
		const source = await readFile(filePath, "utf8");
		assert.doesNotMatch(source, /window\.operator\.browser\b/, `${relativeToRepo(filePath)} reaches the broker`);
	}
	const fakeBridge = await readFile(path.join(frontendRoot, "e2e/support/fake-bridge.ts"), "utf8");
	assert.doesNotMatch(fakeBridge, /\bbrowser:\s*\{/, "fake-bridge.ts must not fake the preload browser namespace");
	const bridgeContract = await readFile(path.join(frontendRoot, "src/shared/operator-bridge.ts"), "utf8");
	assert.doesNotMatch(bridgeContract, /\bbrowser\b/, "OperatorBridge must not declare a browser namespace");
});

test("the go browser broker package stays deleted and unimported", async () => {
	const goFiles = await walk(path.join(repoRoot, "backend"), { extension: /\.go$/, skip: [".git"] });
	for (const filePath of goFiles) {
		const source = await readFile(filePath, "utf8");
		assert.doesNotMatch(source, /internal\/browserruntime/, `${relativeToRepo(filePath)} imports the deleted broker`);
	}
});

test("app://renderer disappears from every live surface", async () => {
	const surfaces = [
		...(await sourceFilesUnder("frontend", "src")),
		...(await walk(path.join(frontendRoot, "src-tauri", "src"), { extension: /\.(rs|toml)$/ })),
		...(await walk(path.join(repoRoot, ".github", "workflows"), { extension: /\.yml$/ })),
	];
	const operationalDocs = (await readdir(path.join(repoRoot, "docs")))
		.filter((name) => name.endsWith(".md"))
		.map((name) => path.join(repoRoot, "docs", name));
	surfaces.push(...operationalDocs);
	surfaces.push(path.join(repoRoot, "RUN_APP_COMMANDS.md"));
	for (const filePath of surfaces) {
		const source = await readFile(filePath, "utf8");
		assert.doesNotMatch(source, /app:\/\/renderer/, `${relativeToRepo(filePath)} still references app://renderer`);
	}
});

test("VITE_NO_ELECTRON is renamed away from everything except dated planning records", async () => {
	const files = await walk(repoRoot, {
		skip: [
			".git",
			".claude",
			".superpowers",
			"node_modules",
			"dist",
			"target",
			"gen",
			"out",
			"release",
			".vite",
			"agent-browser",
			"daemon",
			"resources",
			"superpowers",
			"plans",
			"todo",
			"landing",
		],
	});
	for (const filePath of files) {
		if (!/\.(ts|tsx|mjs|cjs|js|json|yml|yaml|md|rs|toml)$/.test(filePath)) continue;
		if (filePath === fileURLToPath(import.meta.url)) continue;
		const segments = relativeToRepo(filePath).split("/");
		if (isLegacyRecord(segments)) continue;
		const source = await readFile(filePath, "utf8");
		assert.doesNotMatch(source, /VITE_NO_ELECTRON/, `${relativeToRepo(filePath)} still names VITE_NO_ELECTRON`);
	}
});

test("workflows reference no deleted electron artifact and the retired gate stays disabled", async () => {
	const staleTokens = [
		/frontend\/src\/main\b/,
		/src\/preload\.ts/,
		/annotate-preload/,
		/forge\.config/,
		/vite\.main\.config/,
		/vite\.preload\.config/,
		/frontend\/makers/,
		/internal\/browserruntime/,
		/@electron-forge/,
		/electron-forge\s+(start|package|make|publish)/,
		/npm run (?:dev|package|make|publish)\b/,
	];
	const workflowDir = path.join(repoRoot, ".github", "workflows");
	for (const filePath of await readdir(workflowDir)) {
		if (!filePath.endsWith(".yml")) continue;
		const source = await readFile(path.join(workflowDir, filePath), "utf8");
		if (filePath === "tauri-phase0.yml") {
			assert.doesNotMatch(source, /^on:/m, "the retired phase-zero decision gate must keep no triggers");
			continue;
		}
		for (const token of staleTokens) {
			assert.doesNotMatch(source, token, `.github/workflows/${filePath} references a deleted artifact: ${token}`);
		}
	}
});

test("tsconfig stops referencing deleted electron configs", async () => {
	const tsconfig = JSON.parse(await readFile(path.join(frontendRoot, "tsconfig.json"), "utf8"));
	for (const include of tsconfig.include ?? []) {
		assert.doesNotMatch(include, /forge\.config|makers|vite\.main\.config|vite\.preload\.config/, `tsconfig.json include ${include} points at a deleted file`);
	}
});

test("the tauri bundle keeps all three sidecar resource entries", async () => {
	const conf = JSON.parse(await readFile(path.join(frontendRoot, "src-tauri/tauri.conf.json"), "utf8"));
	const resources = conf.bundle?.resources ?? {};
	for (const sidecar of ["daemon/", "agent-browser/", "acp-runtime/"]) {
		assert.ok(Object.values(resources).includes(sidecar), `bundle.resources must map onto ${sidecar}`);
	}
});

test("the run guide instructs the tauri development path", async () => {
	const runGuide = await readFile(path.join(repoRoot, "RUN_APP_COMMANDS.md"), "utf8");
	assert.match(runGuide, /npm run tauri:dev/, "RUN_APP_COMMANDS.md must make tauri:dev the normal path");
	assert.doesNotMatch(runGuide, /npm run dev\n/, "RUN_APP_COMMANDS.md must not send readers to the electron dev script");
});
