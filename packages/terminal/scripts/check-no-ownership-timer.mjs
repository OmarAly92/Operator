import { access, readdir, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REQUIRED_FILES = [
	"crates/vt-core/src/line_editor.rs",
	"crates/vt-core/src/lib.rs",
];
const FORBIDDEN_PATTERNS = [
	"setTimeout",
	"setInterval",
	"requestIdleCallback",
	"Duration::from_millis",
	"sleep",
];

async function exists(path) {
	try {
		await access(path, constants.F_OK);
		return true;
	} catch {
		return false;
	}
}

async function editorFiles(directory, files = []) {
	for (const entry of await readdir(directory, { withFileTypes: true })) {
		const path = join(directory, entry.name);
		if (entry.isDirectory()) {
			await editorFiles(path, files);
		} else if (entry.isFile()) {
			files.push(path);
		}
	}
	return files;
}

async function ownershipFiles() {
	const files = REQUIRED_FILES.map((file) => join(ROOT, file));
	for (const file of files) {
		if (!(await exists(file))) {
			throw new Error(`required ownership file is missing: ${relative(ROOT, file)}`);
		}
	}
	const editorDirectory = join(ROOT, "ts/editor/src");
	if (await exists(editorDirectory)) {
		for (const file of await editorFiles(editorDirectory)) {
			const source = await readFile(file, "utf8");
			if (source.includes("lineEditorState") || source.includes("LineEditorState")) {
				files.push(file);
			}
		}
	}
	if (files.length === 0) {
		throw new Error("zero ownership files scanned");
	}
	return files;
}

const files = await ownershipFiles();
const violations = [];
for (const file of files) {
	const lines = (await readFile(file, "utf8")).split("\n");
	for (const [index, line] of lines.entries()) {
		for (const pattern of FORBIDDEN_PATTERNS) {
			if (line.includes(pattern)) {
				violations.push(`${relative(ROOT, file)}:${index + 1}: ${line}`);
			}
		}
	}
}

if (violations.length > 0) {
	for (const violation of violations) {
		process.stderr.write(`${violation}\n`);
	}
	process.exitCode = 1;
} else {
	process.stdout.write(`no ownership timers found (${files.length} files scanned)\n`);
}
