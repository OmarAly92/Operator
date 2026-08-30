export type EditorCommand =
	| { kind: "insert"; text: string }
	| { kind: "newline" }
	| { kind: "submit" }
	| { kind: "delete-backward" }
	| { kind: "delete-forward" }
	| { kind: "delete-word-backward" }
	| { kind: "move"; delta: -1 | 1 }
	| { kind: "move-word"; direction: -1 | 1 }
	| { kind: "move-line"; direction: -1 | 1 }
	| { kind: "home" }
	| { kind: "end" }
	| { kind: "history"; direction: -1 | 1 }
	| { kind: "accept-suggestion" }
	| { kind: "complete" }
	| { kind: "reverse-search" }
	| { kind: "passthrough"; data: string };

const CTRL_PASSTHROUGH: Record<string, string> = {
	c: "\x03",
	d: "\x04",
	z: "\x1a",
	"\\": "\x1c",
};

export function mapKey(event: KeyboardEvent): EditorCommand | null {
	const { key, ctrlKey, metaKey, altKey, shiftKey } = event;
	if (key === "Shift" || key === "Control" || key === "Alt" || key === "Meta") return null;

	if (ctrlKey && !altKey && !metaKey) {
		const lower = key.toLowerCase();
		const raw = CTRL_PASSTHROUGH[lower];
		if (raw) return { kind: "passthrough", data: raw };
		switch (lower) {
			case "a":
				return { kind: "home" };
			case "e":
				return { kind: "accept-suggestion" };
			case "w":
			case "u":
				return { kind: "delete-word-backward" };
			case "r":
				return { kind: "reverse-search" };
		}
		if (key.length === 1) {
			const code = key.toUpperCase().charCodeAt(0);
			if (code >= 64 && code <= 95) return { kind: "passthrough", data: String.fromCharCode(code - 64) };
		}
	}

	switch (key) {
		case "Enter":
			return shiftKey ? { kind: "newline" } : { kind: "submit" };
		case "Backspace":
			return altKey ? { kind: "delete-word-backward" } : { kind: "delete-backward" };
		case "Delete":
			return { kind: "delete-forward" };
		case "ArrowLeft":
			return altKey ? { kind: "move-word", direction: -1 } : { kind: "move", delta: -1 };
		case "ArrowRight":
			return altKey ? { kind: "move-word", direction: 1 } : { kind: "accept-suggestion" };
		case "ArrowUp":
			return { kind: "history", direction: -1 };
		case "ArrowDown":
			return { kind: "history", direction: 1 };
		case "Home":
			return { kind: "home" };
		case "End":
			return { kind: "end" };
		case "Tab":
			return { kind: "complete" };
	}

	if (altKey && !ctrlKey && !metaKey && key.length === 1) {
		return { kind: "passthrough", data: `\x1b${key}` };
	}
	if (metaKey || altKey || ctrlKey) return null;
	if (key.length === 1) return { kind: "insert", text: key };
	return null;
}
