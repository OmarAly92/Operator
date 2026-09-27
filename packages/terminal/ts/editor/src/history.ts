export type CommandHistoryEntry = Readonly<{ command: string; at: number }>;

export type CommandHistorySource = Readonly<{
	entries(): readonly CommandHistoryEntry[];
	subscribe(listener: () => void): () => void;
	refresh?(): void;
}>;

function sameEntries(a: readonly CommandHistoryEntry[], b: readonly CommandHistoryEntry[]): boolean {
	if (a.length !== b.length) return false;
	for (let index = 0; index < a.length; index += 1) {
		if (a[index]!.command !== b[index]!.command || a[index]!.at !== b[index]!.at) return false;
	}
	return true;
}

function sameCommands(a: readonly string[], b: readonly string[]): boolean {
	return a.length === b.length && a.every((command, index) => command === b[index]);
}

export class HistoryModel {
	private readonly limit: number;
	private local: readonly string[] = [];
	private shared: readonly CommandHistoryEntry[] = [];
	private values: string[] = [];
	private recallPrefix: string | null = null;
	private recallMatches: string[] = [];
	private recallIndex = 0;

	constructor(limit = 1000) {
		this.limit = Math.max(0, Math.floor(limit));
	}

	setLocal(commands: readonly string[]): void {
		if (sameCommands(this.local, commands)) return;
		this.local = [...commands];
		this.rebuild();
	}

	setShared(entries: readonly CommandHistoryEntry[]): void {
		if (sameEntries(this.shared, entries)) return;
		this.shared = [...entries];
		this.rebuild();
	}

	suggest(prefix: string): string | null {
		if (prefix.length === 0) return null;
		for (let index = this.values.length - 1; index >= 0; index -= 1) {
			const entry = this.values[index]!;
			if (entry.length > prefix.length && entry.startsWith(prefix)) return entry;
		}
		return null;
	}

	startRecall(prefix: string): void {
		this.recallPrefix = prefix;
		this.recallMatches = this.matching(prefix);
		this.recallIndex = this.recallMatches.length;
	}

	step(direction: -1 | 1): string | null {
		if (this.recallPrefix === null || this.recallMatches.length === 0) return null;
		const next = this.recallIndex + direction;
		if (next < 0) return this.recallMatches[this.recallIndex] ?? null;
		if (next >= this.recallMatches.length) {
			this.recallIndex = this.recallMatches.length;
			return this.recallPrefix;
		}
		this.recallIndex = next;
		return this.recallMatches[next] ?? null;
	}

	endRecall(): void {
		this.recallPrefix = null;
		this.recallMatches = [];
		this.recallIndex = 0;
	}

	entries(): readonly string[] {
		return [...this.values];
	}

	private matching(prefix: string): string[] {
		return this.values.filter((entry) => entry.startsWith(prefix));
	}

	private rebuild(): void {
		const shared = this.shared.map((entry, order) => ({ entry, order }));
		shared.sort((a, b) => a.entry.at - b.entry.at || a.order - b.order);
		const merged = [...shared.map(({ entry }) => entry.command), ...this.local];
		const seen = new Set<string>();
		const newestFirst: string[] = [];
		for (let index = merged.length - 1; index >= 0 && newestFirst.length < this.limit; index -= 1) {
			const command = merged[index]!;
			if (command.length === 0 || seen.has(command)) continue;
			seen.add(command);
			newestFirst.push(command);
		}
		this.values = newestFirst.reverse();
		if (this.recallPrefix === null) return;
		const current = this.recallMatches[this.recallIndex];
		this.recallMatches = this.matching(this.recallPrefix);
		const kept = current === undefined ? -1 : this.recallMatches.lastIndexOf(current);
		this.recallIndex = kept === -1 ? this.recallMatches.length : kept;
	}
}
