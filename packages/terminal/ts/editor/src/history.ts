export class HistoryModel {
	private readonly limit: number;
	private values: string[] = [];
	private recallPrefix: string | null = null;
	private recallMatches: string[] = [];
	private recallIndex = 0;

	constructor(limit = 1000) {
		this.limit = Math.max(0, Math.floor(limit));
	}

	ingest(commands: readonly string[]): void {
		for (const command of commands) {
			if (command.length === 0) continue;
			this.values = this.values.filter((entry) => entry !== command);
			this.values.push(command);
		}
		if (this.values.length > this.limit) {
			this.values = this.values.slice(this.values.length - this.limit);
		}
		this.resetRecall();
	}

	suggest(prefix: string): string | null {
		if (prefix.length === 0) return null;
		for (let index = this.values.length - 1; index >= 0; index -= 1) {
			const entry = this.values[index]!;
			if (entry.length > prefix.length && entry.startsWith(prefix)) return entry;
		}
		return null;
	}

	recall(prefix: string, direction: -1 | 1): string | null {
		if (prefix !== this.recallPrefix) {
			this.recallPrefix = prefix;
			this.recallMatches = this.values.filter((entry) => entry.startsWith(prefix));
			this.recallIndex = this.recallMatches.length;
		}
		if (this.recallMatches.length === 0) return null;
		this.recallIndex = Math.max(
			0,
			Math.min(this.recallMatches.length - 1, this.recallIndex + direction),
		);
		return this.recallMatches[this.recallIndex] ?? null;
	}

	entries(): readonly string[] {
		return [...this.values];
	}

	private resetRecall(): void {
		this.recallPrefix = null;
		this.recallMatches = [];
		this.recallIndex = 0;
	}
}
