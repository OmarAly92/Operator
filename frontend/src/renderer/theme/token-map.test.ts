import { describe, expect, it } from "vitest";
import { SKIN_TOKENS } from "./token-map.generated";

describe("token map", () => {
	it("covers every colour token in the base block plus the hand-added slots", () => {
		expect(Object.keys(SKIN_TOKENS).length).toBe(238);
	});

	it("maps camelCase slot names to their CSS variable", () => {
		expect(SKIN_TOKENS.statusWorking).toBe("--color-status-working");
		expect(SKIN_TOKENS.background).toBe("--background");
		expect(SKIN_TOKENS.sidebarAccent).toBe("--sidebar-accent");
	});

	it("has no duplicate CSS variable targets", () => {
		const vars = Object.values(SKIN_TOKENS);
		expect(new Set(vars).size).toBe(vars.length);
	});
});
