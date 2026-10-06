const PAINT_INTERVAL_MS = 1000 / 60;
const FRAME_EPSILON_MS = 0.25;

export function tooSoonToPaint(timestamp: number, lastPaintAt: number | null): boolean {
	return lastPaintAt !== null &&
		timestamp - lastPaintAt + FRAME_EPSILON_MS < PAINT_INTERVAL_MS;
}
