import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { skinToCssVars } from "./bridge/css-vars";
import { darkSkin } from "./skins/dark";

const styles = readFileSync(path.resolve(__dirname, "../styles.css"), "utf8");

const NON_COLOUR = /^--(size|space|radius|font|tracking|leading|z|duration|ease|breakpoint)/;
const COLOURISH = /(color|bg|text|border|term|status|sidebar|accent)/;

function declaredIn(css: string): Set<string> {
	return new Set([...css.matchAll(/^\s*(--[a-z0-9-]+)\s*:/gm)].map((m) => m[1]));
}

describe("css var coverage", () => {
	it("every colour var the stylesheet consumes is produced by a skin", () => {
		const produced = new Set(Object.keys(skinToCssVars(darkSkin)));
		const declared = declaredIn(styles);
		const consumed = [...styles.matchAll(/var\((--[a-z0-9-]+)\)/g)].map((m) => m[1]);
		const colourish = consumed.filter((v) => COLOURISH.test(v) && !NON_COLOUR.test(v));
		const missing = [...new Set(colourish)].filter((v) => !produced.has(v) && !declared.has(v));
		expect(missing, `unproduced colour vars: ${missing.join(", ")}`).toEqual([]);
	});
});
