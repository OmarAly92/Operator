import type { HostCapabilities } from "./types.js";

export type ProgramNotification = Readonly<{ title: string; body: string }>;

export type ProgramMessageEvent =
	| Readonly<{ kind: "title"; title: string }>
	| Readonly<{ kind: "pointer"; shape: string }>
	| Readonly<{ kind: "notification"; notification: ProgramNotification }>;

export type ProgramMessageListener = (event: ProgramMessageEvent) => void;

export type ProgramMessageSource = {
	program_generation(): number;
	title(): string;
	pointer_shape(): string;
	take_notifications(): string[];
};

export class ProgramMessages {
	private readonly source: ProgramMessageSource;
	private readonly host: HostCapabilities;
	private readonly listeners = new Set<ProgramMessageListener>();
	private generation = 0;
	private currentTitle = "";
	private currentPointer = "";

	constructor(source: ProgramMessageSource, host: HostCapabilities) {
		this.source = source;
		this.host = host;
	}

	title(): string {
		return this.currentTitle;
	}

	pointerShape(): string {
		return this.currentPointer;
	}

	onMessage(listener: ProgramMessageListener): () => void {
		this.listeners.add(listener);
		return () => {
			this.listeners.delete(listener);
		};
	}

	poll(): void {
		const generation = this.source.program_generation();
		if (generation === this.generation) return;
		this.generation = generation;
		const title = this.source.title();
		if (title !== this.currentTitle) {
			this.currentTitle = title;
			this.emit({ kind: "title", title });
		}
		const shape = this.source.pointer_shape();
		if (shape !== this.currentPointer) {
			this.currentPointer = shape;
			this.emit({ kind: "pointer", shape });
		}
		const flat = this.source.take_notifications();
		for (let index = 0; index + 1 < flat.length; index += 2) {
			const notification = { title: flat[index]!, body: flat[index + 1]! };
			this.host.notify?.(notification.title, notification.body);
			this.emit({ kind: "notification", notification });
		}
	}

	dispose(): void {
		this.listeners.clear();
	}

	private emit(event: ProgramMessageEvent): void {
		for (const listener of [...this.listeners]) listener(event);
	}
}
