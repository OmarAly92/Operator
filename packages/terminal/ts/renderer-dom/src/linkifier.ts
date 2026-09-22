// xterm.js/src/browser/Linkifier.ts (per-line providers, cache until the buffer changes, activate on click)
import { fragmentAt, type PathLookup } from "./file-links.js";
import type { DetectedLink, LinkProvider } from "./link-providers.js";
import { logicalLineAt, rangeContains, rangesOverlap, type LogicalLineView } from "./logical-lines.js";
import type { SelectionPoint } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";

export type LinkifierDeps = Readonly<{
	rows(): TextRows;
	generation(): number;
	providers(): readonly LinkProvider[];
	pathLookup?(): PathLookup | null;
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

const PATH_CACHE_CAPACITY = 256;

export class Linkifier {
	private readonly cache = new Map<string, Promise<readonly DetectedLink[]>>();
	private readonly pathCache = new Map<string, Promise<DetectedLink | null>>();
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
				const link = links.find((candidate) => rangeContains(candidate.range, point.row, point.column));
				if (link) {
					this.setLink(link);
					return;
				}
				this.findPath(point, line);
			},
			() => undefined,
		);
	}

	private findPath(point: SelectionPoint, line: LogicalLineView): void {
		const lookup = this.deps.pathLookup?.() ?? null;
		const offset = lookup ? line.offsetAt(point.row, point.column) : null;
		if (!lookup || offset === null) {
			this.setLink(null);
			return;
		}
		const fragment = fragmentAt(line.text, offset);
		const key = `${line.blockId}:${line.firstRow}:${fragment.start}:${line.text}`;
		let pending = this.pathCache.get(key);
		if (!pending) {
			pending = lookup(line, offset).catch(() => null);
			this.pathCache.set(key, pending);
			if (this.pathCache.size > PATH_CACHE_CAPACITY) this.pathCache.delete(this.pathCache.keys().next().value as string);
		}
		void pending.then((link) => {
			if (this.point !== point) return;
			const current = logicalLineAt(this.deps.rows(), point.blockId, point.row);
			if (!current || current.firstRow !== line.firstRow || current.text !== line.text) return;
			this.setLink(link && rangeContains(link.range, point.row, point.column) ? link : null);
		});
	}

	invalidate(): void {
		this.cache.clear();
		this.pathCache.clear();
		this.refresh();
	}

	current(): DetectedLink | null {
		return this.link;
	}

	dispose(): void {
		this.cache.clear();
		this.pathCache.clear();
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
