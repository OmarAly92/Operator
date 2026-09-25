export function callEach<T>(listeners: Iterable<(value: T) => void>, value: T, failures: unknown[]): void {
	for (const listener of [...listeners]) {
		try {
			listener(value);
		} catch (error) {
			failures.push(error);
		}
	}
}

export function attempt(step: () => unknown, failures: unknown[]): void {
	try {
		step();
	} catch (error) {
		failures.push(error);
	}
}

export function throwFailures(failures: readonly unknown[], message: string): void {
	if (failures.length > 0) throw new AggregateError(failures, message);
}
