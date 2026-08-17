import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

function walk(dir: string): string[] {
	return readdirSync(dir).flatMap((entry) => {
		const full = path.join(dir, entry);
		if (statSync(full).isDirectory()) return walk(full);
		return /\.tsx?$/.test(entry) && !/\.test\./.test(entry) ? [full] : [];
	});
}

describe("no raw colour in components", () => {
	it("components use skin slots, not literal colours", () => {
		const offenders: string[] = [];
		for (const file of walk(path.resolve(__dirname, "../components"))) {
			const source = readFileSync(file, "utf8");
			for (const match of source.matchAll(/#[0-9a-fA-F]{6}\b|oklch\(/g)) {
				offenders.push(`${path.basename(file)}: ${match[0]}`);
			}
		}
		expect(offenders, offenders.join("\n")).toEqual([]);
	});
});
