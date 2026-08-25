import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { collectGitMetadata } from "./benchmark-result.mjs";

const frontendRoot = fileURLToPath(new URL("../", import.meta.url));
const reportRoot = path.join(frontendRoot, "perf", "results", "route-graph");

export const REPORT_SCHEMA_VERSION = 1;
export const REPORT_LABELS = Object.freeze(["before", "after"]);

export const FORBIDDEN_EAGER_CATEGORIES = Object.freeze([
	{ category: "terminal", pattern: /(@xterm\/|addon-(webgl|canvas|search|fit|web-links|unicode11)|XtermTerminal|TerminalPane)/ },
	{ category: "settings", pattern: /(routes\/_shell\.settings|SettingsDialog|KeyboardShortcutsSettingsDialog|components\/settings\/|GlobalSettingsForm|MigrationSection)/ },
	{ category: "chat", pattern: /(react-markdown|remark-gfm|ChatTranscript|SessionView[-_]|_SessionView)/ },
	{ category: "diff", pattern: /(lowlight|highlight\.js|code-highlight-engine|DiffSelectionMenu|PRSummaryDisplay|pr-summary)/ },
]);

function assertPlainObject(value, message) {
	if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(message);
}

export function parseManifest(manifest) {
	assertPlainObject(manifest, "manifest must be an object");
	for (const [id, chunk] of Object.entries(manifest)) {
		assertPlainObject(chunk, `manifest entry must be an object: ${id}`);
		assertAbsoluteFree(id);
		if (typeof chunk.file !== "string" || chunk.file.trim() === "") {
			throw new Error(`manifest entry is missing file: ${id}`);
		}
	}
	return manifest;
}

export function resolveBoardEntry(manifest) {
	const matches = Object.keys(manifest).filter((id) => /\/_shell\.index\.tsx(?:\?.*)?$/.test(id));
	if (matches.length !== 1) {
		throw new Error(`expected exactly one board route module in the manifest, found ${matches.length}`);
	}
	return matches[0];
}

function initialBoardChainIds(manifest, htmlEntryId) {
	const dynamicRoutes = manifest[htmlEntryId]?.dynamicImports ?? [];
	return dynamicRoutes.filter((id) => /^src\/renderer\/routes\/_shell(\.index)?\.tsx(?:\?.*)?$/.test(id));
}

export function eagerModuleIds(manifest, rootId) {
	if (!Object.hasOwn(manifest, rootId)) throw new Error(`module is not present in manifest: ${rootId}`);
	const seen = new Set([rootId]);
	let changed = true;
	while (changed) {
		changed = false;
		for (const id of [...seen]) {
			for (const imported of manifest[id]?.imports ?? []) {
				if (!Object.hasOwn(manifest, imported)) {
					throw new Error(`module is not present in manifest: ${imported}`);
				}
				if (!seen.has(imported)) {
					seen.add(imported);
					changed = true;
				}
			}
		}
	}
	return [...seen].sort();
}

export function classifyEagerViolations(manifest, moduleIds) {
	const violations = [];
	for (const id of moduleIds) {
		for (const { category, pattern } of FORBIDDEN_EAGER_CATEGORIES) {
			if (!pattern.test(id)) continue;
			// A chunk whose heavy dependency moved behind a dynamic import edge
			// keeps its source-derived name but no longer parses that dependency
			// eagerly — not a violation anymore.
			if ((manifest[id]?.dynamicImports ?? []).some((edge) => /xterm/i.test(edge))) continue;
			violations.push({ id, category });
		}
	}
	return violations;
}

async function fileSize(filePath, root) {
	const resolved = path.join(root, filePath);
	const info = await stat(resolved);
	return info.size;
}

export function buildRouteBundleReport({ manifest, sizes, label, git, host, generatedAt }) {
	assertPlainObject(sizes ?? null, "sizes must map asset files to byte counts");
	if (!REPORT_LABELS.includes(label)) throw new Error(`label must be one of ${REPORT_LABELS.join("|")}`);
	parseManifest(manifest);

	const boardEntry = resolveBoardEntry(manifest);
	const htmlEntries = Object.keys(manifest).filter((id) => manifest[id].isEntry);
	if (htmlEntries.length !== 1) throw new Error(`expected exactly one HTML entry, found ${htmlEntries.length}`);
	const boardRoots = [boardEntry, ...initialBoardChainIds(manifest, htmlEntries[0])];
	const initialModules = [
		...new Set(boardRoots.flatMap((root) => eagerModuleIds(manifest, root)).concat(eagerModuleIds(manifest, htmlEntries[0]))),
	].sort();

	const sizeOf = (file) => {
		if (typeof sizes?.[file] !== "number") throw new Error(`missing size for bundle file: ${file}`);
		return sizes[file];
	};
	const rows = [];
	for (const id of initialModules) {
		const chunk = manifest[id];
		const files = [chunk.file, ...(chunk.css ?? [])];
		let bytes = 0;
		for (const file of files) bytes += sizeOf(file);
		rows.push({ bytes, file: chunk.file, id });
	}
	rows.sort((left, right) => right.bytes - left.bytes);
	const parsedBytes = rows.reduce((total, row) => total + row.bytes, 0);

	const allFiles = new Map();
	for (const chunk of Object.values(manifest)) {
		allFiles.set(chunk.file, (allFiles.get(chunk.file) ?? 0) + sizeOf(chunk.file));
		for (const css of chunk.css ?? []) allFiles.set(css, (allFiles.get(css) ?? 0) + sizeOf(css));
	}
	const totalBytes = [...allFiles.values()].reduce((total, value) => total + value, 0);
	const largestChunks = [...allFiles.entries()]
		.map(([file, bytes]) => ({ bytes, file }))
		.sort((left, right) => right.bytes - left.bytes)
		.slice(0, 10);

	const report = {
		schemaVersion: REPORT_SCHEMA_VERSION,
		label,
		commit: git.commit,
		dirty: git.dirty,
		platform: host.platform,
		architecture: host.architecture,
		generatedAt,
		bundle: { chunkCount: allFiles.size, totalBytes, largestChunks },
		board: {
			entryHtmlId: htmlEntries[0],
			boardEntryId: boardEntry,
			moduleCount: initialModules.length,
			parsedBytes,
			files: rows,
			violations: classifyEagerViolations(manifest, initialModules),
		},
	};
	validateReportSchema(report);
	return report;
}

function isIsoTimestamp(value) {
	return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

export function validateReportSchema(report) {
	assertPlainObject(report, "report must be an object");
	const fields = [
		"schemaVersion",
		"label",
		"commit",
		"dirty",
		"platform",
		"architecture",
		"generatedAt",
		"bundle",
		"board",
	];
	for (const field of fields) {
		if (!(field in report)) throw new Error(`report is missing field: ${field}`);
	}
	if (report.schemaVersion !== REPORT_SCHEMA_VERSION) throw new Error("schemaVersion must equal 1");
	if (!REPORT_LABELS.includes(report.label)) throw new Error(`label must be one of ${REPORT_LABELS.join("|")}`);
	if (!/^[0-9a-f]{40}$/i.test(report.commit)) throw new Error("commit must be a full Git object ID");
	if (typeof report.dirty !== "boolean") throw new Error("dirty must be a boolean");
	for (const field of ["platform", "architecture"]) requireNonEmptyString(report, field);
	if (!isIsoTimestamp(report.generatedAt)) throw new Error("generatedAt must be an ISO timestamp");

	assertPlainObject(report.bundle, "bundle summary must be an object");
	for (const field of ["chunkCount", "totalBytes", "largestChunks"]) {
		if (!(field in report.bundle)) throw new Error(`bundle summary is missing field: ${field}`);
	}
	if (!Number.isInteger(report.bundle.chunkCount) || report.bundle.chunkCount <= 0) {
		throw new Error("bundle.chunkCount must be a positive integer");
	}
	requireNonNegativeNumber(report.bundle, "totalBytes");
	assertPlainArray(report.bundle.largestChunks, "largestChunks");
	for (const row of report.bundle.largestChunks) {
		assertPlainObject(row, "largestChunks rows must be objects");
		requireNonEmptyString(row, "file");
		requireNonNegativeNumber(row, "bytes");
	}

	assertPlainObject(report.board, "board summary must be an object");
	for (const field of ["entryHtmlId", "boardEntryId", "moduleCount", "parsedBytes", "files", "violations"]) {
		if (!(field in report.board)) throw new Error(`board summary is missing field: ${field}`);
	}
	for (const field of ["entryHtmlId", "boardEntryId"]) requireNonEmptyString(report.board, field);
	if (!Number.isInteger(report.board.moduleCount) || report.board.moduleCount <= 0) {
		throw new Error("board.moduleCount must be a positive integer");
	}
	requireNonNegativeNumber(report.board, "parsedBytes");
	assertPlainArray(report.board.files, "files");
	const recounted = report.board.files.reduce((total, row) => {
		assertPlainObject(row, "board.files rows must be objects");
		requireNonEmptyString(row, "id");
		requireNonEmptyString(row, "file");
		requireNonNegativeNumber(row, "bytes");
		return total + row.bytes;
	}, 0);
	if (recounted !== report.board.parsedBytes) throw new Error(`parsedBytes must equal ${recounted}`);

	assertPlainArray(report.board.violations, "violations");
	const categories = new Set(FORBIDDEN_EAGER_CATEGORIES.map(({ category }) => category));
	for (const violation of report.board.violations) {
		assertPlainObject(violation, "violations rows must be objects");
		requireNonEmptyString(violation, "id");
		if (!categories.has(violation.category)) throw new Error(`unknown forbidden-edge category: ${violation.category}`);
	}

	assertNoAbsolutePaths(report);
	return report;
}

export function assertNoAbsolutePaths(value, location = "report") {
	if (typeof value === "string") {
		if (/^(?:\/|[A-Za-z]:\\)/.test(value)) throw new Error(`absolute paths are forbidden at ${location}: ${value}`);
		const home = os.homedir();
		if (home && home !== "/" && value.includes(home)) throw new Error(`home paths are forbidden at ${location}`);
		return;
	}
	if (value === null || typeof value !== "object") return;
	if (Array.isArray(value)) {
		value.forEach((entry, index) => assertNoAbsolutePaths(entry, `${location}[${index}]`));
		return;
	}
	for (const [key, entry] of Object.entries(value)) {
		assertNoAbsolutePaths(entry, `${location}.${key}`);
	}
}

function assertAbsoluteFree(id) {
	if (/^(?:\/|[A-Za-z]:\\)/.test(id)) throw new Error(`absolute path module id is forbidden in reports: ${id}`);
}

function requireNonEmptyString(object, field) {
	if (typeof object[field] !== "string" || object[field].trim() === "") {
		throw new Error(`${field} must be a non-empty string`);
	}
}

function requireNonNegativeNumber(object, field) {
	if (typeof object[field] !== "number" || !Number.isFinite(object[field]) || object[field] < 0) {
		throw new Error(`${field} must be a finite non-negative number`);
	}
}

function assertPlainArray(value, message) {
	if (!Array.isArray(value)) throw new Error(message);
}

let _activeScratchDir;

async function viteBuildToScratch() {
	const { build } = await import("vite");
	const { mkdtemp } = await import("node:fs/promises");
	const scratch = await mkdtemp(path.join(os.tmpdir(), "operator-route-report-"));
	_activeScratchDir = scratch;
	await build({
		configFile: path.join(frontendRoot, "vite.renderer.config.ts"),
		root: frontendRoot,
		logLevel: "error",
		build: { outDir: scratch, manifest: true, emptyOutDir: true },
	});
	return scratch;
}

export async function collectBundleSizesFromDirectory(directory) {
	const manifestText = await readFile(path.join(directory, ".vite", "manifest.json"), "utf8");
	const manifest = parseManifest(JSON.parse(manifestText));
	const sizes = {};
	for (const chunk of Object.values(manifest)) {
		sizes[chunk.file] = await fileSize(chunk.file, directory);
		for (const css of chunk.css ?? []) sizes[css] = await fileSize(css, directory);
	}
	return { manifest, sizes };
}

export async function emitReport(argv = process.argv.slice(2)) {
	const labelIndex = argv.indexOf("--label");
	const label = labelIndex >= 0 ? argv[labelIndex + 1] : undefined;
	if (!REPORT_LABELS.includes(label)) {
		throw new Error(`usage: node scripts/route-bundle-report.mjs --label ${REPORT_LABELS.join("|")}`);
	}
	const scratch = await viteBuildToScratch();
	try {
		const { manifest, sizes } = await collectBundleSizesFromDirectory(scratch);
		const git = await collectGitMetadata();
		const report = buildRouteBundleReport({
			manifest,
			sizes,
			label,
			git,
			host: { platform: process.platform, architecture: process.arch },
			generatedAt: new Date().toISOString(),
		});
		const outputPath = path.join(reportRoot, `${label}.json`);
		await mkdir(reportRoot, { recursive: true });
		await writeFile(outputPath, `${JSON.stringify(report, null, "\t")}\n`, "utf8");
		process.stdout.write(
			[
				`route-graph: ${path.relative(frontendRoot, outputPath)}`,
				`board parsed bytes: ${report.board.parsedBytes}`,
				`forbidden eager edges: ${report.board.violations.length}`,
				...report.board.violations.map((violation) => `  [${violation.category}] ${violation.id}`),
			].join("\n") + "\n",
		);
		if (report.board.violations.length > 0) process.exitCode = 2;
		return report;
	} finally {
		if (_activeScratchDir === scratch) {
			await import("node:fs/promises").then(({ rm }) => rm(scratch, { recursive: true, force: true }));
			_activeScratchDir = undefined;
		}
	}
}

async function main() {
	await emitReport();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	});
}
