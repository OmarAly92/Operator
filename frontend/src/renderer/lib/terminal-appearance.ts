import type { CellSize } from "@operator/terminal-react";
import type { TerminalAppearance } from "./terminal-mux";

export type TerminalColors = Readonly<{ foreground: string; background: string }>;

export function terminalAppearance(cell: CellSize, colors: TerminalColors, devicePixelRatio: number): TerminalAppearance {
	const scale = Number.isFinite(devicePixelRatio) && devicePixelRatio > 0 ? devicePixelRatio : 1;
	return {
		cellWidth: Math.round(cell.width * scale),
		cellHeight: Math.round(cell.height * scale),
		foreground: colors.foreground,
		background: colors.background,
	};
}
