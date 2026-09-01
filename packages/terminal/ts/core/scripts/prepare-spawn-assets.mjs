import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const coreRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const terminalRoot = join(coreRoot, "..", "..");
const assetsRoot = join(coreRoot, "assets");
const shellRoot = join(terminalRoot, "shell");

await rm(assetsRoot, { recursive: true, force: true });
await mkdir(join(assetsRoot, "shell"), { recursive: true });
await cp(join(terminalRoot, "protocol", "recipes.json"), join(assetsRoot, "recipes.json"));
for (const script of ["bash.sh", "fish.fish", "zsh.sh"]) {
	await cp(join(shellRoot, script), join(assetsRoot, "shell", script));
}
for (const startup of ["bash.sh.d", "zsh.sh.d"]) {
	await cp(join(shellRoot, startup), join(assetsRoot, "shell", startup), { recursive: true });
}
