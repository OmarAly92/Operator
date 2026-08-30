import type { Candidate } from "../rank.js";
import type { SignatureRegistry } from "../registry.js";
import {
	clampPriority,
	isVariadic,
	type ArgumentSpec,
	type CommandSpec,
	type TemplateType,
} from "../signature.js";

export function commandCandidates(registry: SignatureRegistry): Candidate[] {
	return registry.commands().map((command) => ({
		value: command.name,
		kind: "command",
		description: command.description,
		priority: clampPriority(command.priority),
	}));
}

export function subcommandCandidates(command: CommandSpec): Candidate[] {
	return (command.subcommands ?? []).map((sub) => ({
		value: sub.name,
		kind: "subcommand",
		description: sub.description,
		priority: clampPriority(sub.priority),
	}));
}

export function valuesFor(
	argument: ArgumentSpec | undefined,
): { literals: Candidate[]; template: TemplateType | null } {
	if (argument === undefined) return { literals: [], template: null };

	const literals: Candidate[] = [];
	let template: TemplateType | null = null;
	for (const value of argument.values ?? []) {
		if (value.kind === "suggestion") {
			literals.push({
				value: value.suggestion.value,
				displayValue: value.suggestion.displayValue,
				description: value.suggestion.description,
				kind: "argument",
				priority: clampPriority(value.suggestion.priority),
			});
		} else if (value.kind === "template") {
			template = value.template;
		}
	}
	return { literals, template };
}

export function argumentCandidates(
	command: CommandSpec,
	position: number,
): { literals: Candidate[]; template: TemplateType | null } {
	const args = command.arguments ?? [];
	const last = args[args.length - 1];
	return valuesFor(args[position] ?? (last !== undefined && isVariadic(last) ? last : undefined));
}
