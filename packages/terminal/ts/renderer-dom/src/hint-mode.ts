import { computeLabelsForAlphabet, DEFAULT_HINT_ALPHABET } from "./hint-labels.js";
import { fileLineFields, type HintRule } from "./hint-rules.js";
import type { LinkRange, LogicalLineView } from "./logical-lines.js";

export type HintMatch = Readonly<{ ruleId: string; text: string; path?: string; line?: number; range: LinkRange }>;
export type HintEvent = Readonly<{ ruleId: string; text: string; path?: string; line?: number }>;

export function collectHintMatches(lines: readonly LogicalLineView[], rules: readonly HintRule[]): HintMatch[] {
	const out: HintMatch[] = [];
	for (const line of lines) {
		const taken: Array<readonly [number, number]> = [];
		const found: HintMatch[] = [];
		for (const rule of rules) {
			const regex = new RegExp(rule.regex.source, rule.regex.flags.includes("g") ? rule.regex.flags : `${rule.regex.flags}g`);
			for (const match of line.text.matchAll(regex)) {
				const whole = match[0];
				const wholeStart = match.index ?? 0;
				let text = whole;
				let start = wholeStart;
				if (rule.capture === "last") {
					for (let group = match.length - 1; group >= 1; group -= 1) {
						if (match[group] === undefined) continue;
						text = match[group]!;
						start = wholeStart + whole.indexOf(text);
						break;
					}
				}
				const end = start + text.length;
				if (taken.some(([from, to]) => start < to && from < end)) continue;
				taken.push([wholeStart, wholeStart + whole.length]);
				const fields = rule.id === "file-line" ? fileLineFields(match as RegExpExecArray) : null;
				found.push({ ruleId: rule.id, text, path: fields?.path, line: fields?.line, range: line.rangeOf(start, end) });
			}
		}
		found.sort((a, b) => a.range.startRow - b.range.startRow || a.range.startCell - b.range.startCell);
		out.push(...found);
	}
	return out;
}

export class HintSession {
	private readonly labels: string[];
	private prefix = "";

	constructor(
		private readonly matches: readonly HintMatch[],
		alphabet: string = DEFAULT_HINT_ALPHABET,
	) {
		const byText = new Map<string, number>();
		for (const match of matches) {
			if (!byText.has(match.text)) byText.set(match.text, byText.size);
		}
		const pool = computeLabelsForAlphabet(alphabet, byText.size);
		this.labels = matches.map((match) => pool[byText.size - 1 - byText.get(match.text)!] ?? "");
	}

	labelled(): readonly { label: string; match: HintMatch }[] {
		return this.matches
			.map((match, index) => ({ label: this.labels[index]!, match }))
			.filter((entry) => entry.label !== "" && entry.label.startsWith(this.prefix));
	}

	type(character: string): HintMatch | null {
		const next = this.prefix + character.toLowerCase();
		const exact = this.labels.findIndex((label) => label === next);
		if (exact >= 0) {
			this.prefix = "";
			return this.matches[exact]!;
		}
		this.prefix = this.labels.some((label) => label.startsWith(next)) ? next : "";
		return null;
	}

	backspace(): void {
		this.prefix = this.prefix.slice(0, -1);
	}

	typed(): string {
		return this.prefix;
	}
}
