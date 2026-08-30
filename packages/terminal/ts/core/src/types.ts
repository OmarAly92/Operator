export type BlockId = string;

export type BlockState = "running" | "finished" | "abandoned";

export type BlockSource = "osc133" | "extension" | "synthetic";

export type LineEditorState = "unknown" | "owned" | "released";

export type BlockView = Readonly<{
	id: BlockId;
	firstRow: number;
	rowCount: number;
	state: BlockState;
	source: BlockSource;
	exitCode: number | null;
	durationMs: number | null;
	command: string;
	cwd: string;
	gitBranch: string;
}>;

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
	blocks: Uint32Array;
	blockText: Uint8Array;
	lineEditorState: number;
	altScreen: AltScreenView | null;
	applicationCursorKeys: boolean;
	sgrMouse: boolean;
	mouseTracking: boolean;
}>;

export type AltScreenView = Readonly<{
	rows: number;
	columns: number;
	content: Uint8Array;
	rowRanges: Uint32Array;
	runRanges: Uint32Array;
	stylePairs: Uint32Array;
	cursorRow: number;
	cursorColumn: number;
	cursorVisible: boolean;
}>;

export type TerminalCoreOptions = Readonly<{
	columns: number;
	scrollback: number;
	rows?: number;
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

export type ShellKind = "zsh" | "bash" | "fish";

/**
 * What the host tells the package to spawn. `argv` is passed to `execvp` as-is;
 * `env` is merged into the child's environment. The package is the only
 * authority on the spawn contract — the host never invents the argv.
 */
export type SpawnRecipe = {
	argv: string[];
	env: Record<string, string>;
};

/**
 * Which mark tier the host wants and whether the package may suppress the
 * user's prompt.
 */
export type BootstrapOptions = Readonly<{
	integration: "auto" | "osc133-only" | "off";
	suppressPrompt: boolean;
}>;

export type TerminalStrings = Readonly<{
	blockRunning: string;
	blockSucceeded: string;
	blockFailed: string;
	blockAbandoned: string;
	copyCommand: string;
	copyOutput: string;
	rerunCommand: string;
	shellBlocksUnavailable: string;
	searchHistory: string;
	searchNoMatches: string;
}>;

export const defaultStrings: TerminalStrings = Object.freeze({
	blockRunning: "Running",
	blockSucceeded: "Succeeded",
	blockFailed: "Failed",
	blockAbandoned: "Abandoned",
	copyCommand: "Copy command",
	copyOutput: "Copy output",
	rerunCommand: "Re-run",
	shellBlocksUnavailable: "Shell blocks are unavailable in this terminal.",
	searchHistory: "Search history",
	searchNoMatches: "No matches",
});

export type HostCapabilities = Readonly<{
	writeClipboard(text: string): Promise<void>;
	readClipboard(): Promise<string>;
	openLink(url: string): Promise<void>;
	notify?(title: string, body: string): void;
}>;

export type HistoryStore = {
	load(): Promise<readonly string[]>;
	save(entries: readonly string[]): Promise<void>;
};
