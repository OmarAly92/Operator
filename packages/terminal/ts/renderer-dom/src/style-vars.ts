import type { FontConfig, TerminalTheme } from "@operator/terminal-core";

export function styleVarEntries(
	theme: TerminalTheme,
	font: FontConfig,
): readonly (readonly [string, string])[] {
	const entries: (readonly [string, string])[] = theme.ansi.map(
		(color, index) => [`--terminal-ansi-${index}`, color] as const,
	);
	entries.push(
		["--terminal-foreground", theme.foreground],
		["--terminal-background", theme.background],
		["--terminal-cursor", theme.cursor],
		["--terminal-selection", theme.selection],
		["--terminal-block-background", theme.blockBackground],
		["--terminal-block-border", theme.blockBorder],
		["--terminal-block-header-foreground", theme.blockHeaderForeground],
		["--terminal-font-family", font.family],
		["--terminal-font-size", `${font.sizePx}px`],
		["--terminal-font-weight", String(font.weight)],
		["--terminal-letter-spacing", `${font.letterSpacingPx}px`],
		["--terminal-line-height", `${font.lineHeight * font.sizePx}px`],
		["--terminal-ligatures", font.ligatures ? "common-ligatures" : "none"],
	);
	return entries;
}

export function styleVarsString(theme: TerminalTheme, font: FontConfig): string {
	return styleVarEntries(theme, font).map(([name, value]) => `${name}: ${value}`).join("; ");
}
