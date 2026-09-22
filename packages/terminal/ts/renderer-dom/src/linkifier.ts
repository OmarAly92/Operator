// xterm.js/src/browser/Linkifier.ts (per-line providers, cache until the buffer changes, activate on click)
import type { DetectedLink, LinkProvider } from "./link-providers.js";
import { logicalLineAt, rangeContains, rangesOverlap } from "./logical-lines.js";
import type { SelectionPoint } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";

export type LinkifierDeps = Readonly<{
	rows(): TextRows;
	generation(): number;
	providers(): readonly LinkProvider[];
	onChange(): void;
}>;

export function mergeLinks(lists: readonly (readonly DetectedLink[])[]): DetectedLink[] {
	const accepted: DetectedLink[] = [];
	for (const list of lists) {
		for (const link of list) {
			if (accepted.some((other) => rangesOverlap(other.range, link.range))) continue;
			accepted.push(link);
		}
	}
	return accepted;
}

function sameRange(a: DetectedLink, b: DetectedLink): boolean {
	return a.range.blockId === b.range.blockId && a.range.startRow === b.range.startRow && a.range.startCell === b.range.startCell && a.range.endRow === b.range.endRow && a.range.endCell === b.range.endCell;
}

export class Linkifier {
	private readonly cache = new Map<string, Promise<readonly DetectedLink[]>>();
	private cacheGeneration = Number.NaN;
	private point: SelectionPoint | null = null;
	private link: DetectedLink | null = null;

	constructor(private readonly deps: LinkifierDeps) {}

	hover(point: SelectionPoint | null): void {
		this.point = point;
		this.refresh();
	}

	refresh(): void {
		const point = this.point;
		if (!point) {
			this.setLink(null);
			return;
		}
		const generation = this.deps.generation();
		if (generation !== this.cacheGeneration) {
			this.cache.clear();
			this.cacheGeneration = generation;
		}
		const line = logicalLineAt(this.deps.rows(), point.blockId, point.row);
		if (!line) {
			this.setLink(null);
			return;
		}
		const key = `${line.blockId}:${line.firstRow}`;
		let pending = this.cache.get(key);
		if (!pending) {
			pending = Promise.all(this.deps.providers().map((provider) => provider(line))).then(mergeLinks);
			this.cache.set(key, pending);
		}
		void pending.then(
			(links) => {
				if (this.point !== point || this.cacheGeneration !== generation) return;
				this.setLink(links.find((link) => rangeContains(link.range, point.row, point.column)) ?? null);
			},
			() => undefined,
		);
	}

	/// Drops the per-line cache and resolves the hovered line again.
	///
	/// refresh() alone reuses a line's cached answer until the buffer's
	/// generation moves, so a caller that swaps the provider list would keep
	/// serving links found by the providers it just replaced.
	invalidate(): void {
		this.cache.clear();
		this.refresh();
	}

	current(): DetectedLink | null {
		return this.link;
	}

	dispose(): void {
		this.cache.clear();
		this.point = null;
		this.link = null;
	}

	private setLink(link: DetectedLink | null): void {
		if (link === this.link) return;
		if (link && this.link && link.kind === this.link.kind && link.text === this.link.text && sameRange(link, this.link)) return;
		this.link = link;
		this.deps.onChange();
	}
}
