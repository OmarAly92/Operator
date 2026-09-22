export type CompositionAnchor = Readonly<{ left: number; top: number; height: number }>;

export interface CompositionTarget {
	element: HTMLTextAreaElement;
	view: HTMLElement;
	focus(): void;
	isComposing(): boolean;
	dispose(): void;
}

export function anchorFromElement(parent: HTMLElement, cell: Element | null): CompositionAnchor | null {
	if (!cell) return null;
	const c = cell.getBoundingClientRect();
	const p = parent.getBoundingClientRect();
	return {
		left: c.left - p.left - parent.clientLeft + parent.scrollLeft,
		top: c.top - p.top - parent.clientTop + parent.scrollTop,
		height: c.height,
	};
}

export function createCompositionTarget(opts: {
	parent: HTMLElement;
	onCommit(text: string): void;
	anchor?: (parent: HTMLElement) => CompositionAnchor | null;
}): CompositionTarget {
	const element = document.createElement("textarea");
	element.setAttribute("aria-hidden", "true");
	element.setAttribute("data-terminal-input", "");
	element.setAttribute("autocorrect", "off");
	element.setAttribute("autocapitalize", "off");
	element.setAttribute("spellcheck", "false");
	element.tabIndex = -1;
	element.style.position = "absolute";
	element.style.left = "0";
	element.style.top = "0";
	element.style.width = "1px";
	element.style.height = "1px";
	element.style.padding = "0";
	element.style.border = "0";
	element.style.outline = "none";
	element.style.resize = "none";
	element.style.opacity = "0";
	element.style.overflow = "hidden";
	element.style.zIndex = "-1";

	const view = document.createElement("span");
	view.className = "terminal-composition-view";
	view.setAttribute("aria-hidden", "true");

	let composing = false;
	let start = 0;
	let sending = false;

	const place = () => {
		const anchor = opts.anchor?.(opts.parent) ?? null;
		if (!anchor) return;
		view.style.left = `${anchor.left}px`;
		view.style.top = `${anchor.top}px`;
		view.style.height = `${anchor.height}px`;
		view.style.lineHeight = `${anchor.height}px`;
	};
	const selectionStart = () => {
		const s = element.selectionStart ?? element.value.length;
		const e = element.selectionEnd ?? s;
		return Math.min(s, e);
	};
	const onStart = () => {
		composing = true;
		start = selectionStart();
		view.textContent = "";
		view.classList.add("active");
		place();
	};
	const onUpdate = (event: CompositionEvent) => {
		view.textContent = `‎${event.data ?? ""}‎`;
		place();
	};
	// xterm.js src/browser/input/CompositionHelper.ts:120-200 (_finalizeComposition)
	const onEnd = () => {
		composing = false;
		view.classList.remove("active");
		const finishedStart = start;
		sending = true;
		setTimeout(() => {
			if (!sending) return;
			sending = false;
			const text = composing ? element.value.substring(finishedStart, start) : element.value.substring(finishedStart);
			if (!composing) element.value = "";
			if (text !== "") opts.onCommit(text);
		}, 0);
	};
	const onBlur = () => {
		if (!composing) return;
		composing = false;
		sending = false;
		view.classList.remove("active");
		const text = element.value.substring(start);
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};

	element.addEventListener("compositionstart", onStart);
	element.addEventListener("compositionupdate", onUpdate);
	element.addEventListener("compositionend", onEnd);
	element.addEventListener("blur", onBlur);
	opts.parent.append(element, view);

	return {
		element,
		view,
		focus: () => element.focus({ preventScroll: true }),
		isComposing: () => composing,
		dispose: () => {
			sending = false;
			element.removeEventListener("compositionstart", onStart);
			element.removeEventListener("compositionupdate", onUpdate);
			element.removeEventListener("compositionend", onEnd);
			element.removeEventListener("blur", onBlur);
			element.remove();
			view.remove();
		},
	};
}
