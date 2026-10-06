// xterm.js/src/browser/Linkifier.ts (providers asked for the hovered line, activate on click)
import type { DetectedLink, LinkProvider } from "./link-providers.js";
import { logicalLineAt, rangeContains, rangesOverlap } from "./logical-lines.js";
import type { SelectionPoint } from "./selection-model.js";
import type { TextRows } from "./selection-text.js";

export type LinkifierDeps = Readonly<{
	rows(): TextRows;
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
	private memo: Readonly<{ key: string; pending: Promise<readonly DetectedLink[]> }> | null = null;
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
		const line = logicalLineAt(this.deps.rows(), point.blockId, point.row);
		const offset = line?.offsetAt(point.row, point.column) ?? null;
		if (!line || offset === null) {
			this.setLink(null);
			return;
		}
		const runs = line.linkRuns.map((run) => `${run.startOffset}-${run.endOffset}-${run.linkId}`).join(",");
		const key = [line.blockId, line.firstRow, line.rowOffsets.join(","), runs, offset, line.text].join("\u0000");
		if (this.memo?.key !== key) {
			this.memo = { key, pending: Promise.all(this.deps.providers().map((provider) => provider(line, offset))).then(mergeLinks) };
		}
		const memo = this.memo;
		void memo.pending.then(
			(links) => {
				if (this.point !== point || this.memo !== memo) return;
				this.setLink(links.find((link) => rangeContains(link.range, point.row, point.column)) ?? null);
			},
			() => undefined,
		);
	}

	invalidate(): void {
		this.memo = null;
		this.refresh();
	}

	current(): DetectedLink | null {
		return this.link;
	}

	dispose(): void {
		this.memo = null;
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
