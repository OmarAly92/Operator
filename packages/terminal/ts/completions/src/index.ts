import type {
	CompletionItem,
	CompletionProvider,
	CompletionRequest,
	CompletionResult,
} from "@operator/terminal-core";
import { locate } from "./parse.js";
import { rank, type Candidate, type Ranked } from "./rank.js";
import { SignatureRegistry } from "./registry.js";
import { commandCandidates, subcommandCandidates, argumentCandidates } from "./providers/command.js";
import { flagCandidates } from "./providers/flag.js";
import { pathCandidates } from "./providers/path.js";
import { defaultSignatures } from "./specs/index.js";
import type { CommandSpec } from "./signature.js";

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

		const ranked = rank(candidates, location.query);
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

	const position = location.commandTokens.length - resolved.consumed;
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
