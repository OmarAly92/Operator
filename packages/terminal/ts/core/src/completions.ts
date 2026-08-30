import type { HostCapabilities } from "./types.js";

export type CompletionItem = Readonly<{
	value: string;
	displayValue: string;
	description: string | null;
	kind: string;
	matchedIndices: readonly number[];
}>;

export type CompletionResult = Readonly<{
	items: readonly CompletionItem[];
	span: Readonly<{ start: number; end: number }>;
	query: string;
}>;

export type CompletionRequest = Readonly<{
	line: string;
	cursor: number;
	cwd: string;
	host: HostCapabilities;
	signal: AbortSignal;
}>;

export type CompletionProvider = (request: CompletionRequest) => Promise<CompletionResult | null>;

export type CompletionListener = (result: CompletionResult | null) => void;

export class CompletionDispatcher {
	private provider: CompletionProvider | null = null;
	private readonly listeners = new Set<CompletionListener>();
	private controller: AbortController | null = null;
	private generation = 0;

	constructor(
		private readonly cwd: () => string,
		private readonly host: HostCapabilities,
	) {}

	register(provider: CompletionProvider): () => void {
		this.provider = provider;
		return () => {
			if (this.provider === provider) this.provider = null;
		};
	}

	onResult(listener: CompletionListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	request(line: string, cursor: number): void {
		const generation = this.beginGeneration();
		const provider = this.provider;
		if (provider === null) {
			this.emit(generation, null);
			return;
		}
		const request: CompletionRequest = {
			line,
			cursor,
			cwd: this.cwd(),
			host: this.host,
			signal: this.controller!.signal,
		};
		provider(request).then(
			(result) => this.emit(generation, result),
			() => this.emit(generation, null),
		);
	}

	cancel(): void {
		const generation = this.beginGeneration();
		this.emit(generation, null);
	}

	dispose(): void {
		this.controller?.abort();
		this.controller = null;
		this.listeners.clear();
		this.provider = null;
	}

	private beginGeneration(): number {
		this.controller?.abort();
		this.controller = new AbortController();
		this.generation += 1;
		return this.generation;
	}

	private emit(generation: number, result: CompletionResult | null): void {
		if (generation !== this.generation) return;
		for (const listener of [...this.listeners]) listener(result);
	}
}
