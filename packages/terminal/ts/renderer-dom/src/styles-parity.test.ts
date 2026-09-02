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

	it("separates blocks with a hairline rule rather than boxing each one", () => {
		// Warp draws a 1px rule between blocks (draw_border_between_blocks, gated
		// on show_block_dividers, default true) -- never a box around each block.
		// A full border plus a radius is what made the pane read as boxy next to it.
		const block = terminalStyles.slice(
			terminalStyles.indexOf(".terminal-block {"),
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block {")),
		);
		expect(block).toContain("border-top: 1px solid var(--terminal-block-border)");
		expect(block).not.toContain("border-radius");
		expect(block).not.toMatch(/\n\tborder: /);
	});

	it("keeps the horizontal inset to a hairline", () => {
		// Warp's BlockPadding is vertical-only, so blocks span the full width. We
		// keep 4px so glyphs do not touch the pane edge; the old 16px stacked with
		// the pane's own gutter for 24px of dead space, costing ~3 columns a line.
		expect(terminalStyles).toContain("--terminal-padding-x: 4px");
		// Flush top and bottom: only the sides are inset.
		expect(terminalStyles).toContain("--terminal-padding-y: 0px");
	});

	it("resolves bundled font URLs before injecting the stylesheet", () => {
		expect(terminalStylesForDocument()).not.toContain('url("./fonts/');
	});
});
