export type ReverseSearchState = Readonly<{
	query: string;
	match: string | null;
	index: number;
	total: number;
}>;

export class ReverseSearch {
	private values: string[] = [];
	private query = "";
	private matches: string[] = [];
	private index = 0;
	private active = false;

	open(entries: readonly string[]): void {
		this.values = [...entries];
		this.query = "";
		this.index = 0;
		this.active = true;
		this.refresh();
	}

	type(characters: string): void {
		if (!this.active) return;
		this.query += characters;
		this.refresh();
	}

	backspace(): void {
		if (!this.active || this.query.length === 0) return;
		const points = [...this.query];
		points.pop();
		this.query = points.join("");
		this.refresh();
	}

	next(): void {
		if (!this.active || this.matches.length === 0) return;
		this.index = Math.min(this.matches.length - 1, this.index + 1);
	}

	previous(): void {
		if (!this.active || this.matches.length === 0) return;
		this.index = Math.max(0, this.index - 1);
	}

	accept(): string | null {
		if (!this.active) return null;
		const match = this.matches[this.index] ?? null;
		this.active = false;
		return match;
	}

	cancel(): void {
		this.active = false;
		this.matches = [];
		this.index = 0;
	}

	state(): ReverseSearchState {
		return {
			query: this.query,
			match: this.matches[this.index] ?? null,
			index: this.matches.length === 0 ? -1 : this.index,
			total: this.matches.length,
		};
	}

	private refresh(): void {
		this.matches = this.values.filter((entry) => entry.includes(this.query)).reverse();
		this.index = 0;
	}
}
