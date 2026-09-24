export class ListenerSet<T extends unknown[] = []> {
	private readonly listeners = new Set<(...args: T) => void>();

	add(listener: (...args: T) => void): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	emit(...args: T): void {
		for (const listener of [...this.listeners]) {
			listener(...args);
		}
	}

	clear(): void {
		this.listeners.clear();
	}
}
