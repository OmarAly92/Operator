import type { SelectionKind } from "@operator/terminal-renderer-dom";

export const DRAG_THRESHOLD_PX = 0.5;
const BOTTOM_VERTICAL_MARGIN = 10;
const SELECTION_SCROLLING_ACCELERATION = 1.5;

export function exceedsDragThreshold(origin: { x: number; y: number }, x: number, y: number): boolean {
	return Math.abs(x - origin.x) > DRAG_THRESHOLD_PX || Math.abs(y - origin.y) > DRAG_THRESHOLD_PX;
}

export function kindForClickCount(count: number): SelectionKind {
	if (count >= 3) return "line";
	if (count === 2) return "word";
	return "simple";
}

function accelerated(delta: number): number {
	return Math.pow(delta, SELECTION_SCROLLING_ACCELERATION) / 100;
}

export function autoScrollRows(y: number, top: number, bottom: number): number {
	const floor = bottom - BOTTOM_VERTICAL_MARGIN;
	if (y < top) return -accelerated(top - y);
	if (y > floor) return accelerated(y - floor);
	return 0;
}

export function isCopyChord(
	event: { key: string; metaKey: boolean; ctrlKey: boolean; shiftKey: boolean; altKey: boolean },
	mac: boolean,
): boolean {
	if (event.key.toLowerCase() !== "c" || event.altKey) return false;
	if (mac) return event.metaKey && !event.ctrlKey && !event.shiftKey;
	return event.ctrlKey && event.shiftKey && !event.metaKey;
}
