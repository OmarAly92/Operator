export type Span = Readonly<{ start: number; end: number }>;

export type Token = Readonly<{ text: string; span: Span }>;

export type CompletionLocation = Readonly<{
	kind: "command" | "flag" | "argument";
	query: string;
	span: Span;
	commandTokens: readonly string[];
}>;

export function tokenize(line: string): Token[] {
	const tokens: Token[] = [];
	let index = 0;
	while (index < line.length) {
		while (index < line.length && line[index] === " ") index += 1;
		if (index >= line.length) break;
		const start = index;
		let text = "";
		let quote: string | null = null;
		while (index < line.length) {
			const ch = line[index]!;
			if (quote !== null) {
				if (ch === quote) quote = null;
				else text += ch;
			} else if (ch === '"' || ch === "'") {
				quote = ch;
			} else if (ch === " ") {
				break;
			} else {
				text += ch;
			}
			index += 1;
		}
		tokens.push({ text, span: { start, end: index } });
	}
	return tokens;
}

export function locate(line: string, cursor: number): CompletionLocation | null {
	const clamped = Math.min(Math.max(cursor, 0), line.length);
	const tokens = tokenize(line);
	const index = tokens.findIndex(
		(token) => clamped >= token.span.start && clamped <= token.span.end,
	);

	if (index === -1) {
		if (clamped > 0 && line[clamped - 1] !== " ") return null;
		if (tokens.some((token) => token.span.start >= clamped)) return null;
		const commandTokens = tokens
			.filter((token) => token.span.end < clamped)
			.map((token) => token.text);
		const span = { start: clamped, end: clamped };
		if (commandTokens.length === 0) {
			return { kind: "command", query: "", span, commandTokens: [] };
		}
		return { kind: "argument", query: "", span, commandTokens };
	}

	const token = tokens[index]!;
	const query = line.slice(token.span.start, clamped);
	if (query.startsWith("$")) return null;
	const commandTokens = tokens.slice(0, index).map((entry) => entry.text);
	if (index === 0) {
		return { kind: "command", query, span: token.span, commandTokens: [] };
	}
	const kind = query.startsWith("-") ? "flag" : "argument";
	return { kind, query, span: token.span, commandTokens };
}
