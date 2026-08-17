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

// 6- and 8-digit hex — the skins themselves use 8-digit (#0d1117e7), so that
// form is in play. 3-digit is deliberately absent: `#318` collides with the PR
// references that appear in fixture copy.
const LITERAL = /#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?\b/;
const FUNCTIONAL = /\b(?:oklch|oklab|rgba?|hsla?|color-mix)\(/;

describe("no raw colour in components", () => {
	// The rule is about what a skin can control, not about syntax. A literal is
	// always an offence. A functional notation is fine when it composes skin
	// variables — `color-mix(in oklch, var(--secondary), var(--foreground) 5%)`
	// is fully themeable — and an offence when it mixes something the skin does
	// not own, which is the case a named recipe in theme/effects.ts should take.
	it("components use skin slots, not literal colours", () => {
		const offenders: string[] = [];
		for (const file of walk(path.resolve(__dirname, "../components"))) {
			const source = readFileSync(file, "utf8");
			source.split("\n").forEach((line, index) => {
				const composesSkinVars = /var\(--/.test(line);
				const offence = LITERAL.test(line) || (FUNCTIONAL.test(line) && !composesSkinVars);
				if (offence) offenders.push(`${path.basename(file)}:${index + 1}: ${line.trim()}`);
			});
		}
		expect(offenders, offenders.join("\n")).toEqual([]);
	});
});
