export type QuickFixOutputMatcher = Readonly<{
	line: RegExp;
	anchor: "top" | "bottom";
	offset: number;
	length: number;
}>;

export type QuickFixMatch = Readonly<{
	command: string;
	commandMatch: RegExpMatchArray;
	outputMatch: RegExpMatchArray | null;
	outputLines: readonly string[];
	lineIndex: number;
}>;

export type QuickFixRule = Readonly<{
	id: string;
	commandLine: RegExp;
	exit: "error" | "success" | "any";
	output?: QuickFixOutputMatcher;
	fix(match: QuickFixMatch): string | null;
}>;

export type QuickFix = Readonly<{ ruleId: string; command: string }>;

export type QuickFixInput = Readonly<{
	command: string;
	exitCode: number | null;
	output(): readonly string[];
}>;

export const QUICK_FIX_WINDOW_LIMIT = 100;
const MAX_FIX_LENGTH = 1024;

function exitMatches(rule: QuickFixRule, exitCode: number | null): boolean {
	if (rule.exit === "any") return true;
	if (exitCode === null) return false;
	return rule.exit === "error" ? exitCode !== 0 : exitCode === 0;
}

function outputWindow(lines: readonly string[], matcher: QuickFixOutputMatcher): string[] {
	const offset = Math.max(0, Math.min(matcher.offset, QUICK_FIX_WINDOW_LIMIT));
	const length = Math.max(0, Math.min(matcher.length, QUICK_FIX_WINDOW_LIMIT - offset));
	if (matcher.anchor === "top") return lines.slice(offset, offset + length);
	const end = Math.max(0, lines.length - offset);
	return lines.slice(Math.max(0, end - length), end);
}

export function safeFix(fix: string | null, original: string): string | null {
	if (fix === null) return null;
	const trimmed = fix.trim();
	if (trimmed.length === 0 || trimmed.length > MAX_FIX_LENGTH || trimmed === original.trim()) return null;
	for (const character of trimmed) {
		const code = character.codePointAt(0)!;
		if (code < 0x20 || code === 0x7f || (code >= 0x80 && code < 0xa0)) return null;
	}
	return trimmed;
}

export function findQuickFix(rules: readonly QuickFixRule[], input: QuickFixInput): QuickFix | null {
	let lines: readonly string[] | null = null;
	for (const rule of rules) {
		const commandMatch = input.command.match(rule.commandLine);
		if (!commandMatch || !exitMatches(rule, input.exitCode)) continue;
		let outputMatch: RegExpMatchArray | null = null;
		let outputLines: readonly string[] = [];
		let lineIndex = -1;
		if (rule.output) {
			lines ??= input.output();
			outputLines = outputWindow(lines, rule.output);
			for (let index = outputLines.length - 1; index >= 0; index -= 1) {
				const match = outputLines[index]!.match(rule.output.line);
				if (match) {
					outputMatch = match;
					lineIndex = index;
					break;
				}
			}
			if (!outputMatch) continue;
		}
		const command = safeFix(rule.fix({ command: input.command, commandMatch, outputMatch, outputLines, lineIndex }), input.command);
		if (command !== null) return { ruleId: rule.id, command };
	}
	return null;
}
