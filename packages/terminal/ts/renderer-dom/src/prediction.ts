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

function echoed(prediction: Prediction, cells: string): boolean {
	const cell = cells[prediction.at.column];
	if (cell === undefined) return prediction.text === " ";
	return cell === prediction.text;
}

export class PredictionState {
	private predictions: Prediction[] = [];
	private suppress = false;
	private probe: Prediction | null = null;
	private lastRow: number | null = null;

	register(key: KeyDescriptor, cursor: CursorPoint, nowMs: number): boolean {
		if (!isPredictable(key)) return false;
		const column = cursor.column + this.predictions.length;
		const prediction = { text: key.text, at: { row: cursor.row, column }, sentAtMs: nowMs };
		this.lastRow = cursor.row;
		if (this.suppress) {
			if (this.probe === null) this.probe = prediction;
			return false;
		}
		this.predictions.push(prediction);
		return true;
	}

	reconcile(cursor: CursorPoint, cells: string, nowMs: number, ttlMs: number = PREDICTION_TTL_MS): void {
		if (this.lastRow !== null && cursor.row !== this.lastRow) {
			this.predictions = [];
			this.probe = null;
			this.lastRow = cursor.row;
			return;
		}
		this.lastRow = cursor.row;
		const probe = this.probe;
		if (probe !== null && cursor.column > probe.at.column) {
			if (echoed(probe, cells)) this.suppress = false;
			this.probe = null;
		}
		const kept: Prediction[] = [];
		for (const prediction of this.predictions) {
			const passed = cursor.column > prediction.at.column;
			if (passed && echoed(prediction, cells)) continue;
			if (passed || nowMs - prediction.sentAtMs > ttlMs) {
				this.mispredicted(prediction);
				this.predictions = [];
				return;
			}
			kept.push(prediction);
		}
		this.predictions = kept;
	}

	expire(nowMs: number, ttlMs: number = PREDICTION_TTL_MS): void {
		const oldest = this.predictions[0];
		if (oldest === undefined || nowMs - oldest.sentAtMs <= ttlMs) return;
		this.mispredicted(oldest);
		this.predictions = [];
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
		this.probe = null;
		this.lastRow = null;
	}

	private mispredicted(prediction: Prediction): void {
		this.suppress = true;
		this.probe = prediction;
	}
}
