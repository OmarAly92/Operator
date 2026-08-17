import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { skinToCssVars } from "./bridge/css-vars";
import { darkSkin } from "./skins/dark";

const styles = readFileSync(path.resolve(__dirname, "../styles.css"), "utf8");

const NON_COLOUR = /^--(size|space|radius|font|tracking|leading|z|duration|ease|breakpoint)/;
const COLOURISH = /(color|bg|text|border|term|status|sidebar|accent)/;

/**
 * Declarations that compute a value from other custom properties, e.g.
 * `--color-foreground: var(--color-text-primary)`. These live in the
 * `@theme inline` bridge and correctly follow whichever skin is active, so a
 * skin must not own them. Anything else — a literal colour declared outside a
 * skin — is a real gap, because no skin can restyle it.
 */
function derivedFromVars(css: string): Set<string> {
	const derived = new Set<string>();
	for (const match of css.matchAll(/^\s*(--[a-z0-9-]+)\s*:\s*([^;]+);/gm)) {
		const [, name, value] = match;
		if (/var\(--/.test(value)) derived.add(name);
	}
	return derived;
}

describe("css var coverage", () => {
	it("every colour var the stylesheet consumes is produced by a skin or derived from one", () => {
		const produced = new Set(Object.keys(skinToCssVars(darkSkin)));
		const derived = derivedFromVars(styles);
		const consumed = [...styles.matchAll(/var\((--[a-z0-9-]+)\)/g)].map((m) => m[1]);
		const colourish = consumed.filter((v) => COLOURISH.test(v) && !NON_COLOUR.test(v));
		const missing = [...new Set(colourish)].filter((v) => !produced.has(v) && !derived.has(v));
		expect(missing, `unproduced colour vars: ${missing.join(", ")}`).toEqual([]);
	});

	// The escape hatch above is only sound while every derivation bottoms out in
	// slots a skin owns. A derived var whose bases are all unowned would pass the
	// test above while being unthemeable in practice.
	it("every derivation the stylesheet relies on bottoms out in skin slots", () => {
		const produced = new Set(Object.keys(skinToCssVars(darkSkin)));
		const derived = derivedFromVars(styles);
		const consumed = new Set(
			[...styles.matchAll(/var\((--[a-z0-9-]+)\)/g)]
				.map((m) => m[1])
				.filter((v) => COLOURISH.test(v) && !NON_COLOUR.test(v)),
		);
		const orphans: string[] = [];
		for (const match of styles.matchAll(/^\s*(--[a-z0-9-]+)\s*:\s*([^;]+);/gm)) {
			const [, name, value] = match;
			if (!consumed.has(name) || produced.has(name) || !derived.has(name)) continue;
			const bases = [...value.matchAll(/var\((--[a-z0-9-]+)\)/g)].map((m) => m[1]);
			if (!bases.some((base) => produced.has(base) || derived.has(base))) {
				orphans.push(`${name} -> ${bases.join(", ") || "(no var bases)"}`);
			}
		}
		expect(orphans, `derivations with no skin-owned base: ${orphans.join("; ")}`).toEqual([]);
	});
});
