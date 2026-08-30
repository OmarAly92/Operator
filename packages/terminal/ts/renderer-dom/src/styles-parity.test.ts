import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { terminalStyles, terminalStylesForDocument } from "./styles.js";

describe("terminalStyles", () => {
	it("is byte-identical to the published styles.css export", () => {
		const cssPath = join(dirname(fileURLToPath(import.meta.url)), "styles.css");
		const css = readFileSync(cssPath, "utf8").replace(/\n+$/, "");
		expect(terminalStyles).toBe(css);
	});

	it("sizes the surface so a size-contained host cannot collapse to zero height", () => {
		expect(terminalStyles).toContain(".terminal-host");
		expect(terminalStyles).toContain(".terminal-alt-slot");
	});

	it("declares the bundled family so it is not a silent fallback", () => {
		expect(terminalStyles).toContain("@font-face");
		expect(terminalStyles).toContain('font-family: "Hack"');
	});

	it("resolves bundled font URLs before injecting the stylesheet", () => {
		expect(terminalStylesForDocument()).not.toContain('url("./fonts/');
	});
});
