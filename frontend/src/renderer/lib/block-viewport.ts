export const PINNED_SLACK_PX = 24;

export const ESTIMATED_BLOCK_HEIGHT = 96;

export const BLOCK_OVERSCAN = 6;

export const VIRTUALIZATION_THRESHOLD = 100;

export function virtualizationThreshold(): number {
	const override = (globalThis as typeof globalThis & {
		__OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD?: unknown;
	}).__OPERATOR_E2E_BLOCK_VIRTUALIZATION_THRESHOLD;
	return Number.isFinite(override) ? (override as number) : VIRTUALIZATION_THRESHOLD;
}

export type TopItem = { index: number; start: number; size: number };

export function topItemFor(items: readonly TopItem[], scrollTop: number): TopItem | undefined {
	return items.find((item) => item.start <= scrollTop && item.start + item.size > scrollTop);
}

export function headerSticks(blockHeight: number, viewportHeight: number): boolean {
	return viewportHeight > 0 && blockHeight <= viewportHeight;
}

export function isPinned(scrollTop: number, totalSize: number, viewportHeight: number): boolean {
	return scrollTop >= totalSize - viewportHeight - PINNED_SLACK_PX;
}

export function nextBoundary(current: number | undefined, count: number): number | undefined {
	if (count === 0) return undefined;
	if (current === undefined) return 0;
	const next = current + 1;
	return next >= count ? undefined : next;
}

export function previousBoundary(current: number | undefined, count: number): number | undefined {
	if (count === 0 || current === undefined) return undefined;
	const previous = current - 1;
	return previous < 0 ? undefined : previous;
}

export function previousTarget(
	top: TopItem | undefined,
	scrollTop: number,
	count: number,
): number | undefined {
	if (top === undefined) return undefined;
	if (scrollTop - top.start > 1) return top.index;
	return previousBoundary(top.index, count);
}
