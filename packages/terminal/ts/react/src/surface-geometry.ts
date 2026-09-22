import type { DomBlockRenderer } from "@operator/terminal-renderer-dom";
import type { TerminalSnapshot } from "@operator/terminal-core";

// macOS hands a native app an already-accelerated scroll delta: a flick reports
// tens of pixels per event and keeps reporting through a momentum tail. The
// WebView hands us the raw gesture instead -- measured on a trackpad, ~1-3px per
// event at ~115 events/sec, with no tail -- so a flick and a crawl travel nearly
// the same distance and the alt screen advances a row at a time. Scale the delta
// by gesture velocity to restore the curve the platform withheld. Below the
// reference speed the gain is 1, so slow, deliberate scrolling stays exact.
export const ACCEL_REFERENCE_PX_PER_SEC = 100;
export const ACCEL_MAX_GAIN = 6;
// A gap this long means fingers left the trackpad; the next event starts a new
// gesture rather than inheriting the old one's speed.
export const GESTURE_IDLE_MS = 200;
// Velocity is averaged over recent events: a single jittery sample should not
// launch the viewport. Averaging up from zero also means a gesture has to
// sustain speed before it accelerates, so a short nudge stays a short nudge.
export const VELOCITY_SMOOTHING = 0.3;
// Events closer together than this are one frame's worth of coalesced motion,
// not evidence of speed; dividing by their sub-millisecond gap would report
// thousands of pixels per second for an ordinary scroll.
export const MIN_VELOCITY_SAMPLE_MS = 4;

export function isMacPlatform(): boolean {
	return typeof navigator !== "undefined" && /Mac|iPhone|iPad/u.test(navigator.platform);
}

export function isWindowsPlatform(): boolean {
	return typeof navigator !== "undefined" && /Win/u.test(navigator.platform);
}

export const SELECTION_CHROME =
	".terminal-block-header, .terminal-block-actions, .terminal-pinned-header, .terminal-jump-to-bottom, .terminal-find-bar, .terminal-palette";

export function accelerationGain(velocityPxPerSec: number): number {
	const gain = velocityPxPerSec / ACCEL_REFERENCE_PX_PER_SEC;
	return Math.min(Math.max(gain, 1), ACCEL_MAX_GAIN);
}

export function pointerCell(
	host: HTMLElement,
	event: MouseEvent | WheelEvent,
	renderer: DomBlockRenderer | null,
	snapshot: TerminalSnapshot,
	grid: { columns: number; rows: number },
): { column: number; row: number } {
	if (!renderer) {
		return { column: 1, row: 1 };
	}
	const metrics = renderer.measure();
	if (metrics.cellWidth <= 0 || metrics.cellHeight <= 0) {
		return { column: 1, row: 1 };
	}
	const bounds = host.getBoundingClientRect();
	const painted =
		snapshot.altScreen === null
			? renderer.rowOrigin(firstScreenRow(snapshot, grid.rows))
			: null;
	const left = painted?.left ?? bounds.left;
	const top = painted?.top ?? bounds.top;
	const column = Math.floor((event.clientX - left) / metrics.cellWidth) + 1;
	const row = Math.floor((event.clientY - top) / metrics.cellHeight) + 1;
	const columnLimit = snapshot.altScreen?.columns ?? grid.columns;
	const rowLimit = snapshot.altScreen?.rows ?? grid.rows;
	return {
		column: clampCell(column, columnLimit),
		row: clampCell(row, rowLimit),
	};
}

function clampCell(value: number, limit: number): number {
	if (limit > 0) return Math.min(Math.max(1, value), limit);
	return Math.max(1, value);
}

export function firstScreenRow(snapshot: TerminalSnapshot, rows: number): number {
	if (rows <= 0) return 0;
	return Math.max(0, snapshot.rows.length / 2 - rows);
}
