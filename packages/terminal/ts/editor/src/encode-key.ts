// The authoritative KeyboardEvent -> VT byte encoder.
//
// A line editor's keymap collapses a key into an *editing intent* (complete,
// accept-suggestion, history), which is the right vocabulary only while the
// editor owns the line. Re-encoding an intent back into bytes for a child
// process loses the key: Tab and Shift+Tab are both "complete", ArrowRight and
// Ctrl+E are both "accept-suggestion", and Escape has no intent at all. Every
// path that hands keys to a child -- the released line editor and the alt
// screen -- encodes the event here instead.

const CURSOR_FINALS: Record<string, string> = {
	ArrowUp: "A",
	ArrowDown: "B",
	ArrowRight: "C",
	ArrowLeft: "D",
	Home: "H",
	End: "F",
};

const TILDE_KEYS: Record<string, number> = {
	Insert: 2,
	Delete: 3,
	PageUp: 5,
	PageDown: 6,
	F5: 15,
	F6: 17,
	F7: 18,
	F8: 19,
	F9: 20,
	F10: 21,
	F11: 23,
	F12: 24,
};

const SS3_KEYS: Record<string, string> = {
	F1: "P",
	F2: "Q",
	F3: "R",
	F4: "S",
};

// xterm's modifier parameter: 1 plus a bitmask, so an unmodified key is 1 and
// is omitted from the sequence entirely.
function modifierParameter(event: KeyboardEvent): number {
	return 1 + (event.shiftKey ? 1 : 0) + (event.altKey ? 2 : 0) + (event.ctrlKey ? 4 : 0);
}

function controlCode(key: string): string | null {
	if (key === " ") return "\x00";
	if (key === "?") return "\x7f";
	if (key === "/") return "\x1f";
	if (key.length !== 1) return null;
	const code = key.toUpperCase().charCodeAt(0);
	if (code >= 64 && code <= 95) return String.fromCharCode(code - 64);
	return null;
}

export function encodeKey(event: KeyboardEvent, applicationCursorKeys = false): string | null {
	const { key, ctrlKey, altKey, metaKey, shiftKey } = event;
	if (key === "Shift" || key === "Control" || key === "Alt" || key === "Meta") return null;
	// Command belongs to the application's own shortcuts, never to the child.
	if (metaKey) return null;

	const modifier = modifierParameter(event);

	// macOS convention, and what Warp and Claude Code's own input both expect:
	// Option+Left/Right is word motion, not a modified cursor key. Only the bare
	// Alt chord -- Alt+Shift+Left stays a parameterised cursor key.
	if (altKey && !ctrlKey && !shiftKey) {
		if (key === "ArrowLeft") return "\x1bb";
		if (key === "ArrowRight") return "\x1bf";
	}

	const cursorFinal = CURSOR_FINALS[key];
	if (cursorFinal) {
		if (modifier !== 1) return `\x1b[1;${modifier}${cursorFinal}`;
		return applicationCursorKeys ? `\x1bO${cursorFinal}` : `\x1b[${cursorFinal}`;
	}

	const tilde = TILDE_KEYS[key];
	if (tilde !== undefined) {
		return modifier === 1 ? `\x1b[${tilde}~` : `\x1b[${tilde};${modifier}~`;
	}

	const ss3 = SS3_KEYS[key];
	if (ss3) {
		return modifier === 1 ? `\x1bO${ss3}` : `\x1b[1;${modifier}${ss3}`;
	}

	switch (key) {
		case "Escape":
			return "\x1b";
		case "Tab":
			return shiftKey ? "\x1b[Z" : "\t";
		case "Backspace":
			return altKey ? "\x1b\x7f" : "\x7f";
		// A bare Return submits. Shift+Return is the newline chord Claude Code's
		// own /terminal-setup installs on iTerm2 and VS Code, so send what that
		// setup sends rather than a raw \n the child cannot tell from a submit.
		case "Enter":
			return shiftKey || altKey ? "\x1b\r" : "\r";
	}

	if (ctrlKey && !altKey) {
		const code = controlCode(key);
		if (code) return code;
		return null;
	}

	if (altKey && !ctrlKey && key.length === 1) return `\x1b${key}`;
	if (ctrlKey || altKey) return null;
	if (key.length === 1) return key;
	return null;
}
