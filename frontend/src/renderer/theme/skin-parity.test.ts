import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseBlock } from "../../../scripts/extract-skin-tokens.mjs";
import { SKIN_TOKENS, type SlotName } from "./token-map.generated";
import { darkSkin } from "./skins/dark";
import { lightSkin } from "./skins/light";

const css = readFileSync(path.resolve(__dirname, "../../styles/tokens.css"), "utf8");

describe("skin parity with tokens.css", () => {
	it("dark skin reproduces the base block", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			expect(darkSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(base[cssVar]);
		}
	});

	it("light skin reproduces the light block, inheriting the rest from dark", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		const light = parseBlock(css, ':root[data-theme="light"]');
		expect(Object.keys(light).length).toBe(144);
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			const expected = light[cssVar] ?? base[cssVar];
			expect(lightSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(expected);
		}
	});
});
