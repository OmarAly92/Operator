import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { collectBoundaryErrors } from "./check-boundaries.mjs";

async function fixture(files) {
	const root = await mkdtemp(join(tmpdir(), "terminal-boundary-"));
	try {
		for (const [relative, contents] of Object.entries(files)) {
			const absolute = join(root, relative);
			await mkdir(dirname(absolute), { recursive: true });
			await writeFile(absolute, contents);
		}
	} catch (error) {
		await rm(root, { recursive: true, force: true });
		throw error;
	}
	return root;
}

async function errorsFor(files) {
	const root = await fixture(files);
	try {
		return await collectBoundaryErrors(root);
	} finally {
		await rm(root, { recursive: true, force: true });
	}
}

test("rejects a relative import outside the package", async () => {
	const errors = await errorsFor({
		"ts/core/src/index.ts": 'import "../../../../../frontend/src/renderer/main";\n',
	});
	assert.deepEqual(errors, ["ts/core/src/index.ts: relative import escapes packages/terminal"]);
});

test("rejects forbidden package edges", async () => {
	const errors = await errorsFor({
		"ts/renderer-dom/src/index.ts": 'import "@operator/terminal-editor";\n',
		"ts/editor/src/index.ts": 'import "@operator/terminal-completions";\n',
	});
	assert.deepEqual(errors, [
		"ts/editor/src/index.ts: editor must not import completions",
		"ts/renderer-dom/src/index.ts: renderer-dom must not import editor",
	]);
});

test("rejects shell history and filesystem access from editor production code", async () => {
	const errors = await errorsFor({
		"ts/editor/src/history.ts": 'import "node:fs";\nconst path = ".zsh_history";\n',
	});
	assert.deepEqual(errors, [
		"ts/editor/src/history.ts: editor must not access shell history or the filesystem",
	]);
});

test("rejects an oversized source file", async () => {
	const errors = await errorsFor({
		"ts/core/src/large.ts": "export {};\n".repeat(601),
	});
	assert.deepEqual(errors, ["ts/core/src/large.ts: source file has 601 lines; maximum is 600"]);
});

test("rejects Cargo and Go replacements outside the package", async () => {
	const errors = await errorsFor({
		"crates/vt-core/Cargo.toml": '[dependencies]\nleak = { path = "../../../../backend" }\n',
		"go.mod": "module example.test/terminal\n\nreplace example.test/shared => ../../shared\n",
	});
	assert.deepEqual(errors, [
		"crates/vt-core/Cargo.toml: Cargo path dependency escapes packages/terminal",
		"go.mod: Go replacement escapes packages/terminal",
	]);
});

test("accepts bare third-party imports and relative imports that stay inside the package", async () => {
	const errors = await errorsFor({
		"ts/core/src/index.ts": 'import "react";\nimport "./sibling.js";\nimport "../utils.js";\n',
		"ts/renderer-dom/src/index.ts": 'import "@operator/terminal-core";\n',
		"ts/react/src/index.ts": 'import "@operator/terminal-renderer-dom";\n',
		"crates/vt-core/Cargo.toml": '[dependencies]\nunicode-width = "=0.2.2"\n',
		"go.mod": "module example.test/terminal\n",
	});
	assert.deepEqual(errors, []);
});
