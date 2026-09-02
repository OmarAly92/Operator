const WORD_BOUNDARY = /[\s/\\:;,.\'"`|&<>()[\]{}=]/;

export class EditorBuffer {
	private value = "";
	private caret = 0;

	get text(): string {
		return this.value;
	}

	get cursor(): number {
		return this.caret;
	}

	setText(text: string, cursor = text.length): void {
		this.value = text;
		this.caret = clamp(cursor, 0, text.length);
	}

	clear(): void {
		this.setText("", 0);
	}

	insert(text: string): void {
		this.value = this.value.slice(0, this.caret) + text + this.value.slice(this.caret);
		this.caret += text.length;
	}

	deleteBackward(): void {
		if (this.caret === 0) return;
		const start = previousCodePoint(this.value, this.caret);
		this.value = this.value.slice(0, start) + this.value.slice(this.caret);
		this.caret = start;
	}

	deleteForward(): void {
		if (this.caret >= this.value.length) return;
		const end = nextCodePoint(this.value, this.caret);
		this.value = this.value.slice(0, this.caret) + this.value.slice(end);
	}

	deleteWordBackward(): void {
		if (this.caret === 0) return;
		let index = this.caret;
		while (index > 0 && WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		while (index > 0 && !WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		this.value = this.value.slice(0, index) + this.value.slice(this.caret);
		this.caret = index;
	}

	// At the start of a line this deletes the newline above instead of doing
	// nothing, so the line joins the one before it. Warp does the same
	// (editor/view/mod.rs delete_all: "if the line was empty, move to the
	// previous one"); stopping dead there is what reads as a broken key.
	deleteToLineStart(): void {
		const { column } = this.cursorLineColumn();
		if (column === 0) {
			this.deleteBackward();
			return;
		}
		const start = this.caret - column;
		this.value = this.value.slice(0, start) + this.value.slice(this.caret);
		this.caret = start;
	}

	deleteToLineEnd(): void {
		const { line } = this.cursorLineColumn();
		const lines = this.lines();
		let end = 0;
		for (let index = 0; index < line; index += 1) end += lines[index]!.length + 1;
		end += lines[line]!.length;
		if (end === this.caret) return;
		this.value = this.value.slice(0, this.caret) + this.value.slice(end);
	}

	moveTo(index: number): void {
		this.caret = clamp(index, 0, this.value.length);
	}

	moveBy(delta: number): void {
		const direction = Math.sign(delta);
		for (let moved = 0; moved < Math.abs(delta); moved += 1) {
			const next =
				direction < 0
					? previousCodePoint(this.value, this.caret)
					: nextCodePoint(this.value, this.caret);
			if (next === this.caret) return;
			this.caret = next;
		}
	}

	moveWord(direction: -1 | 1): void {
		let index = this.caret;
		if (direction < 0) {
			while (index > 0 && WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
			while (index > 0 && !WORD_BOUNDARY.test(this.value[index - 1]!)) index -= 1;
		} else {
			while (index < this.value.length && WORD_BOUNDARY.test(this.value[index]!)) index += 1;
			while (index < this.value.length && !WORD_BOUNDARY.test(this.value[index]!)) index += 1;
		}
		this.moveTo(index);
	}

	lines(): string[] {
		return this.value.split("\n");
	}

	cursorLineColumn(): { line: number; column: number } {
		const before = this.value.slice(0, this.caret).split("\n");
		return { line: before.length - 1, column: before[before.length - 1]!.length };
	}

	moveLine(direction: -1 | 1): void {
		const { line, column } = this.cursorLineColumn();
		const lines = this.lines();
		const target = clamp(line + direction, 0, lines.length - 1);
		if (target === line) return;
		let offset = 0;
		for (let index = 0; index < target; index += 1) offset += lines[index]!.length + 1;
		this.moveTo(offset + Math.min(column, lines[target]!.length));
	}

	moveHome(): void {
		const { column } = this.cursorLineColumn();
		this.moveTo(this.caret - column);
	}

	moveEnd(): void {
		const { line } = this.cursorLineColumn();
		const lines = this.lines();
		let offset = 0;
		for (let index = 0; index < line; index += 1) offset += lines[index]!.length + 1;
		this.moveTo(offset + lines[line]!.length);
	}
}

function clamp(value: number, min: number, max: number): number {
	return value < min ? min : value > max ? max : value;
}

function previousCodePoint(text: string, index: number): number {
	if (index <= 0) return 0;
	const codePoint = text.codePointAt(index - 2);
	return codePoint !== undefined && codePoint > 0xffff ? index - 2 : index - 1;
}

function nextCodePoint(text: string, index: number): number {
	if (index >= text.length) return text.length;
	const codePoint = text.codePointAt(index);
	return codePoint !== undefined && codePoint > 0xffff ? index + 2 : index + 1;
}
