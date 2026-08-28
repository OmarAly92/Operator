export type BlockId = string;

export type RowRange = Readonly<{ start: number; end: number }>;

export type FontConfig = Readonly<{
	family: string;
	sizePx: number;
	lineHeight: number;
	weight: number;
	letterSpacingPx: number;
	ligatures: boolean;
}>;

export type TerminalTheme = Readonly<{
	ansi: readonly [
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
		string,
	];
	foreground: string;
	background: string;
	cursor: string;
	selection: string;
	blockBackground: string;
	blockBorder: string;
	blockHeaderForeground: string;
}>;

export type TerminalSnapshot = Readonly<{
	generation: number;
	content: Uint8Array;
	rows: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
}>;

export type TerminalCoreOptions = Readonly<{
	columns: number;
	scrollback: number;
}>;

export type ChangeListener = (generation: number) => void;

export interface BlockRenderer {
	mount(container: HTMLElement, core: import("./terminal-core").TerminalCore): void;
	setTheme(theme: TerminalTheme): void;
	setFont(font: FontConfig): void;
	invalidate(range: RowRange): void;
	measure(): { cellWidth: number; cellHeight: number };
	scrollToBlock(id: BlockId, align: "start" | "center" | "end"): void;
	dispose(): void;
}

export function validateRowRange(range: RowRange): void {
	if (!Number.isFinite(range.start) || !Number.isFinite(range.end)) {
		throw new Error("row range must be finite");
	}
	if (range.start < 0 || range.end < 0) {
		throw new Error("row range must be non-negative");
	}
	if (range.end < range.start) {
		throw new Error("row range end must be greater than or equal to start");
	}
}
