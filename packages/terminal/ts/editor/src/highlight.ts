export type TokenKind =
	| "command"
	| "argument"
	| "flag"
	| "string"
	| "operator"
	| "path"
	| "variable"
	| "comment";

export type Token = Readonly<{ start: number; end: number; kind: TokenKind }>;

const SINGLE_OPERATORS = new Set(["|", ";", ">", "<", "&"]);
const DOUBLE_OPERATORS = new Set(["&&", "||", ">>"]);

export function tokenize(text: string): Token[] {
	const tokens: Token[] = [];
	let index = 0;
	let commandPosition = true;
	while (index < text.length) {
		if (/\s/.test(text[index]!)) {
			if (text[index] === "\n") commandPosition = true;
			index += 1;
			continue;
		}

		const start = index;
		if (text[index] === "#") {
			while (index < text.length && text[index] !== "\n") index += 1;
			tokens.push({ start, end: index, kind: "comment" });
			continue;
		}

		const quote = text[index];
		if (quote === '"' || quote === "'") {
			index += 1;
			while (index < text.length && text[index] !== quote) index += 1;
			if (text[index] === quote) index += 1;
			tokens.push({ start, end: index, kind: "string" });
			commandPosition = false;
			continue;
		}

		const pair = text.slice(index, index + 2);
		if (DOUBLE_OPERATORS.has(pair)) {
			index += 2;
			tokens.push({ start, end: index, kind: "operator" });
			commandPosition = true;
			continue;
		}
		if (SINGLE_OPERATORS.has(text[index]!)) {
			index += 1;
			tokens.push({ start, end: index, kind: "operator" });
			commandPosition = true;
			continue;
		}

		while (index < text.length) {
			const character = text[index]!;
			if (/\s/.test(character) || SINGLE_OPERATORS.has(character)) break;
			index += 1;
		}
		const word = text.slice(start, index);
		let kind: TokenKind;
		if (word.startsWith("$")) kind = "variable";
		else if (word.startsWith("-")) kind = "flag";
		else if (/^(?:\.{0,2}\/|~\/)/.test(word)) kind = "path";
		else if (commandPosition) kind = "command";
		else kind = "argument";
		tokens.push({ start, end: index, kind });
		commandPosition = false;
	}
	return tokens;
}
