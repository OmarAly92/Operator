export interface CompositionTarget {
	element: HTMLTextAreaElement;
	focus(): void;
	isComposing(): boolean;
	dispose(): void;
}

export function createCompositionTarget(opts: {
	parent: HTMLElement;
	onCommit(text: string): void;
}): CompositionTarget {
	const element = document.createElement("textarea");
	element.setAttribute("aria-hidden", "true");
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

	let composing = false;

	const onStart = () => {
		composing = true;
	};
	const onEnd = (event: CompositionEvent) => {
		composing = false;
		const text = event.data ?? "";
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};
	const onBlur = () => {
		if (!composing) return;
		composing = false;
		const text = element.value;
		element.value = "";
		if (text !== "") opts.onCommit(text);
	};

	element.addEventListener("compositionstart", onStart);
	element.addEventListener("compositionend", onEnd);
	element.addEventListener("blur", onBlur);
	opts.parent.append(element);

	return {
		element,
		focus: () => element.focus({ preventScroll: true }),
		isComposing: () => composing,
		dispose: () => {
			element.removeEventListener("compositionstart", onStart);
			element.removeEventListener("compositionend", onEnd);
			element.removeEventListener("blur", onBlur);
			element.remove();
		},
	};
}
