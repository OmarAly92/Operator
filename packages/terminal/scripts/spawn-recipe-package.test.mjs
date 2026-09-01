import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, mkdir, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const terminalRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const coreRoot = join(terminalRoot, "ts", "core");

test("packed terminal core loads the bash spawn recipe assets", async () => {
	const installRoot = await mkdtemp(join(tmpdir(), "terminal-core-pack-"));
	let archivePath;
	try {
		const packed = JSON.parse(execFileSync("npm", ["pack", "--json", "--workspaces=false"], { cwd: coreRoot, encoding: "utf8" }));
		archivePath = join(coreRoot, packed[0].filename);
		execFileSync("tar", ["-xzf", archivePath, "-C", installRoot]);
		const scopedModules = join(installRoot, "node_modules", "@operator");
		await mkdir(scopedModules, { recursive: true });
		await rename(join(installRoot, "package"), join(scopedModules, "terminal-core"));
		const output = execFileSync(
			process.execPath,
			["--input-type=module", "--eval", 'import { existsSync } from "node:fs"; import { spawnRecipe } from "@operator/terminal-core"; const recipe = spawnRecipe("bash", { integration: "auto", suppressPrompt: false }); const path = recipe.argv[2].match(/--rcfile "([^"]+)"/)[1]; process.stdout.write(JSON.stringify({ recipe, exists: existsSync(path) }));'],
			{ cwd: installRoot, encoding: "utf8" },
		);
		const { recipe, exists } = JSON.parse(output);
		assert.match(recipe.argv[2], /exec bash --rcfile .+\.bashrc -i$/);
		assert.equal(exists, true);
	} finally {
		if (archivePath) await rm(archivePath, { force: true });
		await rm(installRoot, { recursive: true, force: true });
	}
});
