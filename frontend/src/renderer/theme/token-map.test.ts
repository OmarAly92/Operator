import { describe, expect, it } from "vitest";
import { SKIN_TOKENS } from "./token-map.generated";

describe("token map", () => {
	it("covers every colour token in the base block plus the hand-added slots", () => {
		expect(Object.keys(SKIN_TOKENS).length).toBe(231);
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

	// A skin describes colour. Sizes, line-heights and blurs belong to
	// tokens.css, where one declaration serves every skin instead of
	// sixteen files having to agree.
	it("contains no non-colour tokens", () => {
		const nonColour = /^--(size|space|radius|font|tracking|leading|line-height|z|duration|ease|breakpoint|blur|width|height|inset)/;
		const offenders = Object.values(SKIN_TOKENS).filter((cssVar) => nonColour.test(cssVar));
		expect(offenders, `non-colour tokens in the skin contract: ${offenders.join(", ")}`).toEqual([]);
	});
});
