#!/usr/bin/env node
import { readFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { resolve } from "node:path";

const [, , specPath, ...required] = process.argv;
if (!specPath) {
	console.error("usage: check-spec-citations.mjs <spec.md> [requiredHeading ...]");
	process.exit(2);
}

const root = resolve(process.cwd());
let text;
try {
	text = await readFile(specPath, "utf8");
} catch {
	console.error(`FAIL spec not found: ${specPath}`);
	process.exit(1);
}

const failures = [];
for (const heading of required) {
	if (!text.includes(heading)) failures.push(`missing required section: ${heading}`);
}
for (const bad of ["TBD", "TODO", "fill in", "implement later"]) {
	if (text.includes(bad)) failures.push(`placeholder present: ${bad}`);
}

const citation = /`(\/?[A-Za-z0-9_./-]+\.(?:rs|go|ts|tsx|dart|mjs|sh|css|md|yaml))(?::(\d+)(?:-(\d+))?)?(\s*\(new\))?`/g;
const seen = new Set();
let checked = 0;
for (const match of text.matchAll(citation)) {
	const [, rel, from, to, proposed] = match;
	const key = `${rel}:${from ?? ""}:${to ?? ""}`;
	if (seen.has(key)) continue;
	seen.add(key);
	if (proposed) {
		if (from) failures.push(`${rel}: a "(new)" path must not carry a line number`);
		continue;
	}
	if (!from) continue;
	const abs = rel.startsWith("/") ? rel : resolve(root, rel);
	let info = null;
	try {
		info = await stat(abs);
	} catch {
		info = null;
	}
	if (info === null || !info.isFile()) {
		failures.push(`${rel}:${from} does not exist (mark a path the design proposes creating as \`${rel} (new)\`, without a line number)`);
		continue;
	}
	checked += 1;
	const want = Number(to ?? from);
	let lines = 0;
	const reader = createInterface({ input: createReadStream(abs), crlfDelay: Infinity });
	for await (const _line of reader) lines += 1;
	if (lines < want) failures.push(`${rel}:${want} past end of file (${lines} lines)`);
}

if (failures.length > 0) {
	for (const failure of failures) console.error(`FAIL ${failure}`);
	process.exit(1);
}
console.log(`PASS spec citations: ${checked} resolved, ${required.length} sections present`);
