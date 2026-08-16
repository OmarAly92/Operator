import { describe, expect, it } from "vitest";
import { defineSkin } from "./app-skin";
import { SKIN_TOKENS } from "./token-map.generated";

const everySlot = Object.fromEntries(Object.keys(SKIN_TOKENS).map((k) => [k, "#000000"]));

describe("defineSkin", () => {
	it("resolves a fully specified skin unchanged", () => {
		const skin = defineSkin(everySlot as never);
		expect(Object.keys(skin).length).toBe(Object.keys(SKIN_TOKENS).length);
		expect(skin.statusWorking).toBe("#000000");
	});

	it("leaves no slot undefined", () => {
		const skin = defineSkin(everySlot as never);
		for (const slot of Object.keys(SKIN_TOKENS)) {
			expect(skin[slot as keyof typeof skin], `slot ${slot}`).toBeDefined();
		}
	});

	it("derives slots the author omits", () => {
		const required = Object.fromEntries(
			Object.keys(SKIN_TOKENS)
				.filter((k) => k !== "statusTerminated")
				.map((k) => [k, "#000000"]),
		);
		const skin = defineSkin({ ...required, chart3: "#123456" } as never);
		expect(skin.statusTerminated).toBe("#123456");
	});

	it("throws when a required slot is missing", () => {
		expect(() => defineSkin({} as never)).toThrow(/missing required slot/);
	});
});
