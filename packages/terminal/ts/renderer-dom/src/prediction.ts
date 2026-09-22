export const PREDICTION_TTL_MS = 500;

export type KeyDescriptor = Readonly<{
	text: string;
	ctrlKey: boolean;
	altKey: boolean;
	metaKey: boolean;
	isComposing: boolean;
}>;

export type CursorPoint = Readonly<{ row: number; column: number }>;

export type Prediction = Readonly<{ text: string; at: CursorPoint; sentAtMs: number }>;

// wezterm/wezterm-client/src/pane/renderable.rs predict_from_key_event
// vscode/src/vs/workbench/contrib/terminalContrib/typeAhead/browser/terminalTypeAheadAddon.ts
function isPredictable(key: KeyDescriptor): boolean {
	if (key.isComposing || key.ctrlKey || key.altKey || key.metaKey) return false;
	if ([...key.text].length !== 1) return false;
	const code = key.text.codePointAt(0)!;
	if (code < 0x20 || code === 0x7f) return false;
	if (code > 0x7e) return false;
	return true;
}

export class PredictionState {
	private predictions: Prediction[] = [];
	private suppress = false;
	private lastCursor: CursorPoint | null = null;

	register(key: KeyDescriptor, cursor: CursorPoint, nowMs: number): boolean {
		if (this.suppress || !isPredictable(key)) return false;
		const column = cursor.column + this.predictions.length;
		this.predictions.push({ text: key.text, at: { row: cursor.row, column }, sentAtMs: nowMs });
		this.lastCursor = cursor;
		return true;
	}

	reconcile(cursor: CursorPoint, rowText: string, nowMs: number): void {
		if (this.lastCursor !== null && cursor.row !== this.lastCursor.row) {
			this.predictions = [];
			this.lastCursor = cursor;
			return;
		}
		const kept: Prediction[] = [];
		for (const prediction of this.predictions) {
			const landed = cursor.column > prediction.at.column && rowText[prediction.at.column] === prediction.text;
			if (landed) {
				this.suppress = false;
				continue;
			}
			if (nowMs - prediction.sentAtMs > PREDICTION_TTL_MS) {
				this.suppress = true;
				continue;
			}
			kept.push(prediction);
		}
		this.predictions = kept;
		if (this.lastCursor !== null && cursor.column > this.lastCursor.column) this.suppress = false;
		this.lastCursor = cursor;
	}

	pending(): readonly Prediction[] {
		return this.predictions;
	}

	suppressed(): boolean {
		return this.suppress;
	}

	clear(): void {
		this.predictions = [];
		this.suppress = false;
		this.lastCursor = null;
	}
}
