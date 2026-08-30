import type { CompletionItem, CompletionResult } from "@operator/terminal-core";

export class CompletionsDropdown {
	private container: HTMLElement | null = null;
	private element: HTMLElement | null = null;
	private current: CompletionResult | null = null;
	private index = 0;

	mount(container: HTMLElement): void {
		this.container = container;
	}

	setResult(result: CompletionResult | null): void {
		if (result === null || result.items.length === 0) {
			this.close();
			return;
		}
		this.current = result;
		this.index = 0;
		this.ensureElement();
		this.renderItems();
	}

	selected(): CompletionItem | null {
		if (this.current === null) return null;
		return this.current.items[this.index] ?? null;
	}

	isOpen(): boolean {
		return this.current !== null;
	}

	currentResult(): CompletionResult | null {
		return this.current;
	}

	handleKey(event: KeyboardEvent): boolean {
		if (this.current === null) return false;
		switch (event.key) {
			case "ArrowDown":
				this.move(1);
				return true;
			case "ArrowUp":
				this.move(-1);
				return true;
			case "Escape":
				this.close();
				return true;
		}
		return false;
	}

	close(): void {
		this.current = null;
		this.index = 0;
		if (this.element) {
			this.element.remove();
			this.element = null;
		}
	}

	dispose(): void {
		this.close();
		this.container = null;
	}

	private move(delta: 1 | -1): void {
		if (this.current === null) return;
		const total = this.current.items.length;
		if (total === 0) return;
		this.index = (this.index + delta + total) % total;
		this.renderItems();
	}

	private ensureElement(): void {
		if (this.element) return;
		const container = this.container;
		if (container === null) return;
		const element = document.createElement("div");
		element.className = "terminal-completions";
		element.setAttribute("data-terminal-completions", "");
		container.append(element);
		this.element = element;
	}

	private renderItems(): void {
		const element = this.element;
		if (element === null || this.current === null) return;
		const fragment = document.createDocumentFragment();
		this.current.items.forEach((item, itemIndex) => {
			const row = document.createElement("div");
			row.className = "terminal-completion-row";
			row.setAttribute("data-completion-row", "");
			row.setAttribute("data-selected", itemIndex === this.index ? "true" : "false");
			const label = document.createElement("span");
			label.className = "terminal-completion-label";
			this.appendLabelChars(label, item);
			row.append(label);
			if (item.description !== null) {
				const description = document.createElement("span");
				description.className = "terminal-completion-description";
				description.textContent = item.description;
				row.append(description);
			}
			fragment.append(row);
		});
		element.replaceChildren(fragment);
	}

	private appendLabelChars(parent: HTMLElement, item: CompletionItem): void {
		const display = item.displayValue;
		const matched = new Set(item.matchedIndices);
		let run = "";
		let runMatched: boolean | null = null;
		const flush = () => {
			if (run.length === 0) return;
			if (runMatched) {
				const mark = document.createElement("span");
				mark.setAttribute("data-completion-match", "");
				mark.textContent = run;
				parent.append(mark);
			} else {
				parent.append(document.createTextNode(run));
			}
			run = "";
			runMatched = null;
		};
		for (let i = 0; i < display.length; i += 1) {
			const isMatched = matched.has(i);
			if (runMatched === null) {
				runMatched = isMatched;
				run = display[i]!;
			} else if (runMatched === isMatched) {
				run += display[i]!;
			} else {
				flush();
				runMatched = isMatched;
				run = display[i]!;
			}
		}
		flush();
	}
}
