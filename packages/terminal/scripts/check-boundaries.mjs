import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SKIP_DIRECTORIES = new Set([
	"node_modules",
	"target",
	"dist",
	"wasm",
	".git",
]);

const SKIP_PATHS = new Set([
	"smoke/dist",
	"bench/results",
	"ts/core/wasm",
]);

const LINE_LIMITED_EXTENSIONS = new Set([
	".ts",
	".tsx",
	".js",
	".mjs",
	".cjs",
	".rs",
	".go",
	".sh",
	".fish",
	".ps1",
]);

const JS_TS_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".mjs", ".cjs"]);

const OPERATOR_PACKAGES = new Set([
	"@operator/terminal-core",
	"@operator/terminal-renderer-dom",
	"@operator/terminal-react",
	"@operator/terminal-editor",
	"@operator/terminal-completions",
]);

const LINE_LIMIT = 600;

const STATIC_IMPORT_PATTERN = /(?:^|\n)\s*(?:import|export)\s+(?:[^"';]+\s+from\s+)?["']([^"']+)["']/g;
const DYNAMIC_IMPORT_PATTERN = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
const EDITOR_HISTORY_PATTERN = /(?:node:fs(?:\/promises)?|(?:zsh|bash|fish)_history)/i;

const CARGO_PATH_DEPENDENCY_PATTERN = /path\s*=\s*"([^"]+)"/g;
const GO_REPLACE_PATTERN = /^\s*replace\s+\S+\s+=>\s+(\S+)/gm;

async function walk(root, current, files) {
	const absolute = join(root, current);
	const entries = await readdir(absolute, { withFileTypes: true });
	for (const entry of entries) {
		if (entry.isSymbolicLink()) continue;
		const name = entry.name;
		const childRelative = current ? join(current, name) : name;
		if (entry.isDirectory()) {
			if (SKIP_DIRECTORIES.has(name)) continue;
			if (SKIP_PATHS.has(childRelative)) continue;
			await walk(root, childRelative, files);
			continue;
		}
		if (entry.isFile()) {
			files.push(childRelative);
		}
	}
}

function extname(name) {
	const dot = name.lastIndexOf(".");
	return dot <= 0 ? "" : name.slice(dot);
}

function collectSpecifiers(sourceText) {
	const specifiers = new Set();
	for (const match of sourceText.matchAll(STATIC_IMPORT_PATTERN)) {
		specifiers.add(match[1]);
	}
	for (const match of sourceText.matchAll(DYNAMIC_IMPORT_PATTERN)) {
		specifiers.add(match[1]);
	}
	return [...specifiers];
}

function isRelativeSpecifier(specifier) {
	return specifier.startsWith("./") || specifier.startsWith("../");
}

function isBareSpecifier(specifier) {
	return !isRelativeSpecifier(specifier) && !specifier.startsWith("/") && !specifier.startsWith("node:");
}

function barePackageName(specifier) {
	if (specifier.startsWith("@")) {
		const firstSlash = specifier.indexOf("/");
		const secondSlash = firstSlash === -1 ? -1 : specifier.indexOf("/", firstSlash + 1);
		return secondSlash === -1 ? specifier : specifier.slice(0, secondSlash);
	}
	const slash = specifier.indexOf("/");
	return slash === -1 ? specifier : specifier.slice(0, slash);
}

function packageRoot(name) {
	if (!name.startsWith("ts/")) return null;
	const slash = name.indexOf("/", 3);
	return slash === -1 ? name : name.slice(0, slash);
}

function pkgToPackageRoot(pkg) {
	switch (pkg) {
		case "@operator/terminal-core":
			return "ts/core";
		case "@operator/terminal-renderer-dom":
			return "ts/renderer-dom";
		case "@operator/terminal-react":
			return "ts/react";
		case "@operator/terminal-editor":
			return "ts/editor";
		case "@operator/terminal-completions":
			return "ts/completions";
		default:
			return null;
	}
}

function forbiddenTargetsFor(sourceRoot) {
	if (sourceRoot === "ts/renderer-dom") {
		return new Set(["ts/editor", "ts/completions"]);
	}
	if (sourceRoot === "ts/editor") {
		return new Set(["ts/completions"]);
	}
	return new Set();
}

function messageForEdge(sourceRoot, targetRoot) {
	if (sourceRoot === "ts/renderer-dom" && targetRoot === "ts/editor") {
		return "renderer-dom must not import editor";
	}
	if (sourceRoot === "ts/renderer-dom" && targetRoot === "ts/completions") {
		return "renderer-dom must not import completions";
	}
	if (sourceRoot === "ts/editor" && targetRoot === "ts/completions") {
		return "editor must not import completions";
	}
	return null;
}

function externalBareError(specifier) {
	if (specifier === "frontend" || specifier.startsWith("frontend/")) {
		return `import of frontend is forbidden: ${specifier}`;
	}
	if (specifier === "backend" || specifier.startsWith("backend/")) {
		return `import of backend is forbidden: ${specifier}`;
	}
	if (specifier === "packages/shared" || specifier.startsWith("packages/shared/")) {
		return `import of packages/shared is forbidden: ${specifier}`;
	}
	return null;
}

function escapesRoot(root, resolvedAbsolute) {
	const rel = relative(root, resolvedAbsolute);
	return rel === "" || rel.startsWith("..");
}

function lineCount(text) {
	if (text.length === 0) return 0;
	let count = text.split("\n").length;
	if (text.endsWith("\n")) count -= 1;
	return count;
}

async function collectBoundaryErrors(rootDir) {
	const root = resolve(rootDir);
	const files = [];
	await walk(root, "", files);

	const errors = [];
	for (const relativeFile of files) {
		const extension = extname(relativeFile);
		const absolute = join(root, relativeFile);

		if (LINE_LIMITED_EXTENSIONS.has(extension)) {
			const text = await readFile(absolute, "utf8");
			const count = lineCount(text);
			if (count > LINE_LIMIT) {
				errors.push(`${relativeFile}: source file has ${count} lines; maximum is ${LINE_LIMIT}`);
			}
		}

		if (relativeFile.endsWith("/Cargo.toml")) {
			const text = await readFile(absolute, "utf8");
			for (const match of text.matchAll(CARGO_PATH_DEPENDENCY_PATTERN)) {
				const value = match[1];
				if (!value.startsWith(".")) continue;
				if (escapesRoot(root, resolve(dirname(absolute), value))) {
					errors.push(`${relativeFile}: Cargo path dependency escapes packages/terminal`);
				}
			}
			continue;
		}

		if (relativeFile === "go.mod" || relativeFile.endsWith("/go.mod")) {
			const text = await readFile(absolute, "utf8");
			for (const match of text.matchAll(GO_REPLACE_PATTERN)) {
				const value = match[1];
				if (!value.startsWith(".")) continue;
				if (escapesRoot(root, resolve(dirname(absolute), value))) {
					errors.push(`${relativeFile}: Go replacement escapes packages/terminal`);
				}
			}
			continue;
		}

		if (JS_TS_EXTENSIONS.has(extension)) {
			const text = await readFile(absolute, "utf8");
			if (
				relativeFile.startsWith("ts/editor/src/") &&
				!relativeFile.includes(".test.") &&
				EDITOR_HISTORY_PATTERN.test(text)
			) {
				errors.push(`${relativeFile}: editor must not access shell history or the filesystem`);
			}
			const specifiers = collectSpecifiers(text);
			const sourceRoot = packageRoot(relativeFile);
			const forbidden = forbiddenTargetsFor(sourceRoot);
			const sourceDir = dirname(absolute);
			for (const specifier of specifiers) {
				if (isRelativeSpecifier(specifier)) {
					const resolved = resolve(sourceDir, specifier);
					if (escapesRoot(root, resolved)) {
						errors.push(`${relativeFile}: relative import escapes packages/terminal`);
						continue;
					}
					if (forbidden.size > 0) {
						const rel = relative(root, resolved);
						const targetRoot = packageRoot(rel);
						if (targetRoot && forbidden.has(targetRoot)) {
							const message = messageForEdge(sourceRoot, targetRoot);
							if (message) errors.push(`${relativeFile}: ${message}`);
						}
					}
				} else if (isBareSpecifier(specifier)) {
					const pkg = barePackageName(specifier);
					if (OPERATOR_PACKAGES.has(pkg)) {
						if (forbidden.size > 0) {
							const targetRoot = pkgToPackageRoot(pkg);
							if (targetRoot && forbidden.has(targetRoot)) {
								const message = messageForEdge(sourceRoot, targetRoot);
								if (message) errors.push(`${relativeFile}: ${message}`);
							}
						}
					} else {
						const message = externalBareError(specifier);
						if (message) errors.push(`${relativeFile}: ${message}`);
					}
				}
			}
		}
	}

	errors.sort((left, right) => left.localeCompare(right));
	return errors;
}

const scriptPath = fileURLToPath(import.meta.url);
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
	const rootDir = process.argv[2] ? resolve(process.argv[2]) : resolve(dirname(scriptPath), "..");
	try {
		const errors = await collectBoundaryErrors(rootDir);
		if (errors.length === 0) {
			process.stdout.write("boundary check passed\n");
		} else {
			for (const error of errors) {
				process.stdout.write(`${error}\n`);
			}
			process.exitCode = 1;
		}
	} catch (error) {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	}
}

export { collectBoundaryErrors };
