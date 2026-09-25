import type { OlderOutput, TerminalStrings } from "@operator/terminal-core";

const CLASS_BUTTON = "terminal-load-older";
const ATTR_BUTTON = "data-terminal-load-older";

export const LOAD_OLDER_RETRY_MS = 10_000;

export type LoadOlderSource = Readonly<{
	canLoad(): boolean;
	firstStableRow(): number;
	altScreenActive(): boolean;
	olderOutput(): OlderOutput;
}>;

export type LoadOlderOptions = Readonly<{
	container: HTMLElement;
	source: LoadOlderSource;
	strings: TerminalStrings;
	load(beforeStableRow: number): void;
}>;

export type LoadOlder = Readonly<{
	update(): void;
	setStrings(strings: TerminalStrings): void;
	dispose(): void;
	isButtonVisible(): boolean;
}>;

type Pending = { marks: number; front: number };

export function mountLoadOlder(options: LoadOlderOptions): LoadOlder {
	const { container, source, load } = options;
	let pending: Pending | null = null;
	let retryTimer: ReturnType<typeof setTimeout> | null = null;
	let disposed = false;

	const button = document.createElement("button");
	button.type = "button";
	button.className = CLASS_BUTTON;
	button.setAttribute(ATTR_BUTTON, "");
	button.style.position = "absolute";
	button.style.top = "8px";
	button.style.left = "50%";
	button.style.transform = "translateX(-50%)";
	button.style.zIndex = "10";
	button.style.padding = "2px 10px";
	button.style.borderRadius = "4px";
	button.style.border = "1px solid var(--terminal-block-border, currentColor)";
	button.style.background = "var(--terminal-block-background, transparent)";
	button.style.color = "var(--terminal-block-header-foreground, inherit)";
	button.style.font = "12px var(--terminal-font-family, ui-monospace, monospace)";
	button.style.cursor = "pointer";

	const setStrings = (strings: TerminalStrings): void => {
		button.textContent = strings.loadOlderOutput;
		button.title = strings.loadOlderOutput;
	};
	setStrings(options.strings);

	const clearRetry = (): void => {
		if (retryTimer !== null) clearTimeout(retryTimer);
		retryTimer = null;
	};

	const available = (): boolean => {
		if (!source.canLoad() || source.altScreenActive()) return false;
		const { floor } = source.olderOutput();
		return floor !== null && floor < source.firstStableRow();
	};

	const settlePending = (): void => {
		if (!pending) return;
		if (source.olderOutput().marks !== pending.marks || source.firstStableRow() !== pending.front) {
			pending = null;
			clearRetry();
		}
	};

	const update = (): void => {
		if (disposed) return;
		settlePending();
		const show = pending === null && available();
		const shown = button.parentElement === container;
		if (show && !shown) container.append(button);
		else if (!show && shown) button.remove();
	};

	const onClick = (event: MouseEvent): void => {
		event.preventDefault();
		event.stopPropagation();
		if (pending || !available()) return;
		const front = source.firstStableRow();
		pending = { marks: source.olderOutput().marks, front };
		clearRetry();
		retryTimer = setTimeout(() => {
			retryTimer = null;
			pending = null;
			update();
		}, LOAD_OLDER_RETRY_MS);
		update();
		load(front);
	};

	button.addEventListener("click", onClick);
	update();

	return {
		update,
		setStrings,
		dispose: () => {
			if (disposed) return;
			disposed = true;
			clearRetry();
			button.removeEventListener("click", onClick);
			button.remove();
			pending = null;
		},
		isButtonVisible: () => button.parentElement === container,
	};
}
