export type FillSpan = Readonly<{ left: number; right: number }>;

type Box = Readonly<{ left: number; right: number }>;

export function runFill(run: Box, rowLeft: number, span: FillSpan): FillSpan | null {
	const offset = run.left - rowLeft;
	const left = Math.max(span.left, offset) - offset;
	const right = Math.min(span.right, run.right - rowLeft) - offset;
	if (right - left <= 0.5) return null;
	return { left, right };
}

export function fillGradient(span: FillSpan, colour: string): string {
	return `linear-gradient(to right, transparent ${span.left}px, ${colour} ${span.left}px, ${colour} ${span.right}px, transparent ${span.right}px)`;
}
