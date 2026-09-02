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

	it("leaves the horizontal inset to the block, so it totals Warp's 16px", () => {
		// Warp insets the terminal view by PADDING_LEFT = 16 and gives blocks no
		// horizontal padding of their own. We do the reverse -- the block carries
		// the 16px so the dividers still span the full pane -- but the content must
		// land at the same 16px, which means nothing extra here.
		expect(terminalStyles).toContain("--terminal-padding-x: 0px");
		expect(terminalStyles).toContain("--terminal-padding-y: 0px");
	});

	it("paints the cursor behind the glyph, in the cursor colour, the way Warp does", () => {
		const cursor = terminalStyles.slice(
			terminalStyles.indexOf(".terminal-cursor {"),
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-cursor {")),
		);
		expect(cursor).toContain("background: var(--terminal-cursor)");
		expect(cursor).toContain("z-index: -1");
		expect(cursor).not.toContain("opacity");
		const row = terminalStyles.slice(
			terminalStyles.indexOf(".terminal-row {"),
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-row {")),
		);
		// Without a stacking context of its own the row lets the cursor fall
		// behind the block's background, where nothing can see it.
		expect(row).toContain("position: relative");
		expect(row).toContain("z-index: 0");
	});

	// A desktop shell that sets `user-select: none` on the body -- the usual
	// convention, and what this one does -- otherwise makes the whole transcript
	// unselectable through inheritance, with nothing in the terminal's own
	// stylesheet to say otherwise.
	it("keeps the transcript selectable whatever the host does to the body", () => {
		const block = terminalStyles.slice(
			terminalStyles.indexOf(".terminal-block,"),
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block,")),
		);
		expect(block).toContain(".terminal-alt-surface");
		expect(block).toContain("user-select: text");
		expect(block).toContain("-webkit-user-select: text");
	});

	it("leaves the chrome around it unselectable", () => {
		const chrome = terminalStyles.slice(
			terminalStyles.indexOf(".terminal-block-header,"),
			terminalStyles.indexOf("}", terminalStyles.indexOf(".terminal-block-header,")),
		);
		for (const name of [
			".terminal-block-actions",
			".terminal-pinned-header",
			".terminal-jump-to-bottom",
			".terminal-find-bar",
			".terminal-palette",
		]) {
			expect(chrome).toContain(name);
		}
		expect(chrome).toContain("user-select: none");
	});

	it("resolves bundled font URLs before injecting the stylesheet", () => {
		expect(terminalStylesForDocument()).not.toContain('url("./fonts/');
	});
});
