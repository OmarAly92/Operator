import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { parseBlock, DERIVED_SLOTS } from "../../../scripts/extract-skin-tokens.mjs";
import { SKIN_TOKENS, type SlotName } from "./token-map.generated";
import { darkSkin } from "./skins/dark";
import { lightSkin } from "./skins/light";

const css = readFileSync(path.resolve(__dirname, "../../styles/tokens.css"), "utf8");

const VAR_REF = /^var\((--[a-z0-9-]+)\)$/;

function lookupRaw(cssVar: string, blocks: Record<string, string>[]): string | undefined {
	for (const block of blocks) {
		if (cssVar in block) return block[cssVar];
	}
	return undefined;
}

function chase(cssVar: string, blocks: Record<string, string>[], depth = 5): string | undefined {
	const raw = lookupRaw(cssVar, blocks);
	if (raw === undefined) return undefined;
	const match = VAR_REF.exec(raw);
	if (match && depth > 0) return chase(match[1], blocks, depth - 1);
	return raw;
}

function resolveExpected(slot: string, cssVar: string, blocks: Record<string, string>[]): string | undefined {
	const raw = lookupRaw(cssVar, blocks);
	if (raw === undefined) return undefined;
	if (!DERIVED_SLOTS.has(slot)) return raw;
	return chase(cssVar, blocks);
}

describe("skin parity with tokens.css", () => {
	it("dark skin reproduces the base block", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			expect(darkSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(resolveExpected(slot, cssVar, [base]));
		}
	});

	it("light skin reproduces the light block, inheriting the rest from dark", () => {
		const base = parseBlock(css, ":root,\n:root.dark,\n.dark");
		const light = parseBlock(css, ':root[data-theme="light"]');
		expect(Object.keys(light).length).toBe(144);
		for (const [slot, cssVar] of Object.entries(SKIN_TOKENS)) {
			const expected = resolveExpected(slot, cssVar, [light, base]);
			expect(lightSkin[slot as SlotName], `${slot} (${cssVar})`).toBe(expected);
		}
	});
});
