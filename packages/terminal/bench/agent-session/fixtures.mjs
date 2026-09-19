import { readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

export const FIXTURES_DIR = fileURLToPath(new URL("./fixtures/", import.meta.url));

export function listFixtures() {
	return readdirSync(FIXTURES_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name)
		.sort();
}

export async function loadFixture(name) {
	const dir = join(FIXTURES_DIR, name);
	const recording = new Uint8Array(await readFile(join(dir, "recording")));
	const sizes = JSON.parse(await readFile(join(dir, "size.json"), "utf8"));
	if (!Array.isArray(sizes)) throw new Error(`${name}/size.json must be a JSON array`);
	return { name, recording, sizes };
}

export function frameBoundaries(recording) {
	const esu = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c];
	const ends = [];
	for (let index = 0; index + esu.length <= recording.length; index += 1) {
		let match = true;
		for (let k = 0; k < esu.length; k += 1) {
			if (recording[index + k] !== esu[k]) {
				match = false;
				break;
			}
		}
		if (match) {
			ends.push(index + esu.length);
			index += esu.length - 1;
		}
	}
	return ends;
}
