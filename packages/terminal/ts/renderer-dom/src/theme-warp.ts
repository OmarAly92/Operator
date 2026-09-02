import type { TerminalTheme } from "@operator/terminal-core";

export const warpDarkTheme: TerminalTheme = {
	ansi: [
		"#616161", "#ff8272", "#b4fa72", "#fefdc2",
		"#a5d5fe", "#ff8ffd", "#d0d1fe", "#f1f1f1",
		"#8e8e8e", "#ffc4bd", "#d6fcb9", "#fefdd5",
		"#c1e3fe", "#ffb1fe", "#e5e6fe", "#feffff",
	],
	// Chrome taken from Warp's own bundled dark theme, warp/app/src/themes/
	// default_themes.rs dark_theme(): background 0x050505, foreground 0xffffff,
	// accent 0x19AAD8. The ansi rows above are already byte-identical to Warp's
	// DARK_MODE_NORMAL_COLORS / DARK_MODE_BRIGHT_COLORS.
	foreground: "#ffffff",
	background: "#050505",
	cursor: "#19aad8",
	selection: "rgb(25 170 216 / 0.35)",
	blockBackground: "#050505",
	// Warp's outline(), which is what draw_border_between_blocks paints, is
	// fg_overlay_2 -- the foreground at 10% opacity. It must stay translucent:
	// at full opacity this is a white box around every block.
	blockBorder: "rgb(255 255 255 / 0.1)",
	blockHeaderForeground: "#f1f1f1",
};
