export class ElementPool {
	private readonly entries = new Map<string, HTMLElement>();

	take(id: string): HTMLElement | undefined {
		const element = this.entries.get(id);
		if (element) this.entries.delete(id);
		return element;
	}

	put(id: string, element: HTMLElement, capacity: number): void {
		this.entries.delete(id);
		this.entries.set(id, element);
		while (this.entries.size > Math.max(0, capacity)) {
			const oldest = this.entries.keys().next().value as string;
			const evicted = this.entries.get(oldest)!;
			this.entries.delete(oldest);
			evicted.replaceChildren();
		}
	}

	has(id: string): boolean {
		return this.entries.has(id);
	}

	clear(): void {
		for (const element of this.entries.values()) element.replaceChildren();
		this.entries.clear();
	}

	get size(): number {
		return this.entries.size;
	}
}
