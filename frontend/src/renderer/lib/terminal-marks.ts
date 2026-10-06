import { markRegexValid, type MarkRule } from "@operator/terminal-react";

export const terminalMarksStorageKey = "opr.terminal.marks";
export const MAX_TERMINAL_MARKS = 10;
export const MAX_TERMINAL_MARK_PATTERN = 200;

export const TERMINAL_MARK_COLOURS = [
	{ id: "yellow", ansi: 3 },
	{ id: "red", ansi: 1 },
	{ id: "green", ansi: 2 },
	{ id: "cyan", ansi: 6 },
	{ id: "magenta", ansi: 5 },
] as const;

export type TerminalMarkColour = (typeof TERMINAL_MARK_COLOURS)[number]["id"];

export type TerminalMark = Readonly<{ id: string; pattern: string; regex: boolean; colour: TerminalMarkColour }>;

function getLocalStorage() {
	if (typeof window === "undefined" || !window.localStorage) return null;
	return window.localStorage;
}

function isColour(value: unknown): value is TerminalMarkColour {
	return TERMINAL_MARK_COLOURS.some((colour) => colour.id === value);
}

export function terminalMarkAnsi(colour: TerminalMarkColour): number {
	return TERMINAL_MARK_COLOURS.find((entry) => entry.id === colour)?.ansi ?? 3;
}

export function terminalMarkColourCss(colour: TerminalMarkColour): string {
	return `color-mix(in srgb, var(--terminal-ansi-${terminalMarkAnsi(colour)}) 40%, transparent)`;
}

export function terminalMarkPatternValid(pattern: string, regex: boolean): boolean {
	if (!regex) return true;
	const engine = markRegexValid(pattern);
	if (engine !== null) return engine;
	try {
		new RegExp(pattern, "g");
		return true;
	} catch {
		return false;
	}
}

export function terminalMarkRules(marks: readonly TerminalMark[]): MarkRule[] {
	return marks
		.filter((mark) => mark.pattern !== "" && terminalMarkPatternValid(mark.pattern, mark.regex))
		.map((mark) => ({ pattern: mark.pattern, regex: mark.regex, colour: terminalMarkColourCss(mark.colour) }));
}

export function sanitizeTerminalMarks(value: unknown): TerminalMark[] {
	if (!Array.isArray(value)) return [];
	const out: TerminalMark[] = [];
	for (const entry of value) {
		if (out.length >= MAX_TERMINAL_MARKS) break;
		if (!entry || typeof entry !== "object") continue;
		const { id, pattern, regex, colour } = entry as Record<string, unknown>;
		if (typeof id !== "string" || id === "" || typeof pattern !== "string" || typeof regex !== "boolean" || !isColour(colour)) continue;
		if (out.some((mark) => mark.id === id)) continue;
		out.push({ id, pattern: pattern.slice(0, MAX_TERMINAL_MARK_PATTERN), regex, colour });
	}
	return out;
}

export function readStoredTerminalMarks(): TerminalMark[] {
	try {
		const raw = getLocalStorage()?.getItem(terminalMarksStorageKey);
		return raw ? sanitizeTerminalMarks(JSON.parse(raw)) : [];
	} catch {
		return [];
	}
}

export function writeStoredTerminalMarks(marks: readonly TerminalMark[]): void {
	try {
		getLocalStorage()?.setItem(terminalMarksStorageKey, JSON.stringify(marks));
	} catch {
		return;
	}
}

export function newTerminalMark(existing: readonly TerminalMark[]): TerminalMark {
	const used = new Set(existing.map((mark) => mark.colour));
	const colour = TERMINAL_MARK_COLOURS.find((entry) => !used.has(entry.id))?.id ?? TERMINAL_MARK_COLOURS[existing.length % TERMINAL_MARK_COLOURS.length]!.id;
	return { id: globalThis.crypto.randomUUID(), pattern: "", regex: false, colour };
}
