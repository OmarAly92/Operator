import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const tscPath = resolve(packageRoot, "node_modules/typescript/bin/tsc");

async function compileConsumer(source, customConditions = []) {
	const dir = await mkdtemp(join(packageRoot, ".browser-types-"));
	try {
		await writeFile(join(dir, "consumer.ts"), source);
		await writeFile(
			join(dir, "tsconfig.json"),
			JSON.stringify({
				compilerOptions: {
					customConditions,
					module: "ESNext",
					moduleResolution: "Bundler",
					noEmit: true,
					skipLibCheck: true,
					strict: true,
					target: "ES2022",
				},
				files: ["consumer.ts"],
			}),
		);
		return spawnSync(process.execPath, [tscPath, "--project", join(dir, "tsconfig.json")], {
			cwd: packageRoot,
			encoding: "utf8",
		});
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
}

test("browser declarations match the browser runtime surface", async () => {
	const allowed = await compileConsumer(
		'import { createTerminalCore } from "@operator/terminal-core"; void createTerminalCore;',
		["browser"],
	);
	assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);

	const nodeOnly = await compileConsumer(
		'import { spawnRecipe } from "@operator/terminal-core"; void spawnRecipe;',
		["browser"],
	);
	assert.notEqual(nodeOnly.status, 0, "browser declarations exposed the Node-only spawnRecipe export");
	assert.match(nodeOnly.stdout + nodeOnly.stderr, /has no exported member (?:named )?'spawnRecipe'/);

	const node = await compileConsumer(
		'import { spawnRecipe } from "@operator/terminal-core"; void spawnRecipe;',
	);
	assert.equal(node.status, 0, node.stdout + node.stderr);
});
