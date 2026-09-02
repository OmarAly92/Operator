import { describe, expect, it } from "vitest";
import { warpDarkTheme } from "./dom-block-renderer";

// Values taken from Warp itself, warp/app/src/themes/default_themes.rs.
describe("warpDarkTheme", () => {
	it("matches Warp's bundled dark theme chrome", () => {
		// dark_theme(): Fill::Solid(0x050505FF), foreground 0xffffffff,
		// accent Fill::Solid(0x19AAD8FF).
		expect(warpDarkTheme.background).toBe("#050505");
		expect(warpDarkTheme.blockBackground).toBe("#050505");
		expect(warpDarkTheme.foreground).toBe("#ffffff");
		expect(warpDarkTheme.cursor).toBe("#19aad8");
	});

	it("keeps the block divider translucent, never the foreground colour", () => {
		// Warp's outline() is fg_overlay_2 -- the foreground at 10% opacity. The
		// renderer once mapped blockBorder straight to the foreground, which drew
		// an opaque white box around every block.
		expect(warpDarkTheme.blockBorder).toBe("rgb(255 255 255 / 0.1)");
		expect(warpDarkTheme.blockBorder).not.toBe(warpDarkTheme.foreground);
		expect(warpDarkTheme.blockBorder).toMatch(/\/\s*0?\.\d+\s*\)$/);
	});
});
