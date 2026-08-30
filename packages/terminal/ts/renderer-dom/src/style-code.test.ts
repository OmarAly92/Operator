import { describe, expect, it } from "vitest";
import { styleCodeToCssVar } from "./style-code.js";

const INDEXED = 0x0100_0000;
const RGB = 0x0200_0000;

describe("styleCodeToCssVar", () => {
	it("keeps the sixteen ansi slots themed", () => {
		expect(styleCodeToCssVar(0)).toBe("var(--terminal-ansi-0)");
		expect(styleCodeToCssVar(15)).toBe("var(--terminal-ansi-15)");
		expect(styleCodeToCssVar(255)).toBe("var(--terminal-foreground)");
	});

	it("resolves a 256-palette index rather than throwing", () => {
		expect(styleCodeToCssVar(INDEXED | 196)).toBe("rgb(255 0 0)");
		expect(styleCodeToCssVar(INDEXED | 244)).toBe("rgb(128 128 128)");
		expect(styleCodeToCssVar(INDEXED | 16)).toBe("rgb(0 0 0)");
		expect(styleCodeToCssVar(INDEXED | 231)).toBe("rgb(255 255 255)");
	});

	it("routes a 256 index inside the ansi range back through the theme", () => {
		expect(styleCodeToCssVar(INDEXED | 9)).toBe("var(--terminal-ansi-9)");
	});

	it("renders truecolour with all three channels", () => {
		expect(styleCodeToCssVar(RGB | (205 << 16) | (214 << 8) | 244)).toBe("rgb(205 214 244)");
		expect(styleCodeToCssVar(RGB | 0)).toBe("rgb(0 0 0)");
		expect(styleCodeToCssVar(RGB | 0xffffff)).toBe("rgb(255 255 255)");
	});

	it("still rejects a code it cannot explain", () => {
		expect(() => styleCodeToCssVar(200)).toThrow(/unsupported style code/);
	});
});
