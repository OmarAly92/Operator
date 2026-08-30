import type { CommandSpec } from "./signature.js";

export type ResolvedCommand = Readonly<{ command: CommandSpec; consumed: number }>;

export class SignatureRegistry {
	private readonly byName: ReadonlyMap<string, CommandSpec>;
	private readonly roots: readonly CommandSpec[];

	private constructor(byName: ReadonlyMap<string, CommandSpec>, roots: readonly CommandSpec[]) {
		this.byName = byName;
		this.roots = roots;
	}

	static from(specs: readonly CommandSpec[]): SignatureRegistry {
		const byName = new Map<string, CommandSpec>();
		for (const spec of specs) {
			byName.set(spec.name, spec);
			for (const alias of spec.alias ?? []) byName.set(alias, spec);
		}
		return new SignatureRegistry(byName, specs);
	}

	commands(): readonly CommandSpec[] {
		return this.roots;
	}

	lookup(name: string): CommandSpec | null {
		return this.byName.get(name) ?? null;
	}

	resolve(tokens: readonly string[]): ResolvedCommand | null {
		const first = tokens[0];
		if (first === undefined) return null;
		let command = this.lookup(first);
		if (command === null) return null;
		let consumed = 1;
		while (consumed < tokens.length) {
			const next = matchSubcommand(command, tokens[consumed]!);
			if (next === null) break;
			command = next;
			consumed += 1;
		}
		return { command, consumed };
	}
}

function matchSubcommand(command: CommandSpec, token: string): CommandSpec | null {
	for (const sub of command.subcommands ?? []) {
		if (sub.name === token) return sub;
		if ((sub.alias ?? []).includes(token)) return sub;
	}
	return null;
}
