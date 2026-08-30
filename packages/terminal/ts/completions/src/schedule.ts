import { matchQuery } from "./match.js";
import { orderByPriority, assemble, type Candidate, type Ranked } from "./rank.js";

export const FRAME_BUDGET_MS = 8;
export const CHUNK_SIZE = 256;

export type Scheduler = Readonly<{ now(): number; yield(): Promise<void> }>;

export const defaultScheduler: Scheduler = {
	now: () => Date.now(),
	yield: () =>
		new Promise((resolve) => {
			setTimeout(resolve, 0);
		}),
};

export async function rankChunked(
	candidates: readonly Candidate[],
	query: string,
	signal: AbortSignal,
	scheduler: Scheduler = defaultScheduler,
): Promise<Ranked[] | null> {
	if (signal.aborted) return null;

	const ordered = orderByPriority(candidates);
	const matched: Ranked[] = [];
	let sliceStart = scheduler.now();

	for (let index = 0; index < ordered.length; index += 1) {
		const candidate = ordered[index]!;
		const match = matchQuery(candidate.displayValue ?? candidate.value, query);
		if (match !== null) matched.push({ candidate, match });

		if ((index + 1) % CHUNK_SIZE === 0) {
			if (scheduler.now() - sliceStart >= FRAME_BUDGET_MS) {
				await scheduler.yield();
				if (signal.aborted) return null;
				sliceStart = scheduler.now();
			}
		}
	}

	return assemble(matched);
}
