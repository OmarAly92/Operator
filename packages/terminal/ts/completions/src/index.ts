import type {
	CompletionItem,
	CompletionProvider,
	CompletionRequest,
	CompletionResult,
} from "@operator/terminal-core";
import { locate, type CompletionLocation } from "./parse.js";
import type { Candidate, Ranked } from "./rank.js";
import { rankChunked } from "./schedule.js";
import { SignatureRegistry } from "./registry.js";
import {
	commandCandidates,
	subcommandCandidates,
	argumentCandidates,
	valuesFor,
} from "./providers/command.js";
import { flagCandidates } from "./providers/flag.js";
import { pathCandidates } from "./providers/path.js";
import { defaultSignatures } from "./specs/index.js";
import {
	optHasName,
	type ArgumentSpec,
	type CommandSpec,
	type OptSpec,
	type TemplateType,
} from "./signature.js";

export type { CommandSpec, ArgumentSpec, OptSpec, ArgumentValue } from "./signature.js";
export { SignatureRegistry } from "./registry.js";
export { rank, tabAction } from "./rank.js";
export { locate } from "./parse.js";
export { defaultSignatures } from "./specs/index.js";

export function createCompletionProvider(
	options: { signatures?: readonly CommandSpec[] } = {},
): CompletionProvider {
	const registry = SignatureRegistry.from(options.signatures ?? defaultSignatures);

	return async (request: CompletionRequest): Promise<CompletionResult | null> => {
		const location = locate(request.line, request.cursor);
		if (location === null) return null;

		const candidates = await collect(registry, location, request);
		if (candidates === null) return null;

		const ranked = await rankChunked(candidates, location.query, request.signal);
		if (ranked === null) return null;
		return {
			items: ranked.map(toItem),
			span: location.span,
			query: location.query,
		};
	};
}

async function collect(
	registry: SignatureRegistry,
	location: ReturnType<typeof locate> & object,
	request: CompletionRequest,
): Promise<Candidate[] | null> {
	if (location.kind === "command") return commandCandidates(registry);

	const resolved = registry.resolve(location.commandTokens);
	if (resolved === null) return null;

	if (location.kind === "flag") {
		const used = location.commandTokens.filter((token) => token.startsWith("-"));
		return flagCandidates(resolved.command, used);
	}

	const tail = location.commandTokens.slice(resolved.consumed);

	if (location.kind === "flag-value") {
		const option = optionNamed(resolved.command, location.flagName ?? "");
		if (option === undefined) return null;
		return await withPaths(valuesFor((option.arguments ?? [])[0]), location, request);
	}

	const pending = pendingOptionValue(resolved.command, tail);
	if (pending !== undefined) {
		return await withPaths(valuesFor(pending), location, request);
	}

	const position = positionalIndex(resolved.command, tail);
	const { literals, template } = argumentCandidates(resolved.command, position);
	const subcommands = position === 0 ? subcommandCandidates(resolved.command) : [];
	const paths =
		template === null
			? []
			: await pathCandidates({
					query: location.query,
					cwd: request.cwd,
					template,
					host: request.host,
					signal: request.signal,
				});
	return [...subcommands, ...literals, ...paths];
}

function optionNamed(command: CommandSpec, name: string): OptSpec | undefined {
	return (command.options ?? []).find((candidate) => optHasName(candidate, name));
}

function pendingOptionValue(
	command: CommandSpec,
	tokens: readonly string[],
): ArgumentSpec | undefined {
	const last = tokens[tokens.length - 1];
	if (last === undefined || !last.startsWith("-") || last.includes("=")) return undefined;
	const option = optionNamed(command, last.replace(/^--?/, ""));
	return (option?.arguments ?? [])[0];
}

async function withPaths(
	values: { literals: Candidate[]; template: TemplateType | null },
	location: CompletionLocation,
	request: CompletionRequest,
): Promise<Candidate[]> {
	if (values.template === null) return values.literals;
	const paths = await pathCandidates({
		query: location.query,
		cwd: request.cwd,
		template: values.template,
		host: request.host,
		signal: request.signal,
	});
	return [...values.literals, ...paths];
}

function positionalIndex(command: CommandSpec, tokens: readonly string[]): number {
	let position = 0;
	let index = 0;
	while (index < tokens.length) {
		const token = tokens[index]!;
		if (!token.startsWith("-")) {
			position += 1;
			index += 1;
			continue;
		}
		const name = token.replace(/^--?/, "").split("=")[0]!;
		const option = (command.options ?? []).find((candidate) => optHasName(candidate, name));
		const separate = option !== undefined && (option.arguments ?? []).length > 0;
		index += separate && !token.includes("=") ? 2 : 1;
	}
	return position;
}

function toItem(entry: Ranked): CompletionItem {
	const { candidate, match } = entry;
	return {
		value: candidate.value,
		displayValue: candidate.displayValue ?? candidate.value,
		description: candidate.description ?? null,
		kind: candidate.kind,
		matchedIndices: match.kind === "fuzzy" ? match.indices : [],
	};
}
