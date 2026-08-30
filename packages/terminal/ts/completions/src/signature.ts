export type TemplateType = "files" | "folders" | "files-and-folders";

export type SuggestionSpec = Readonly<{
	value: string;
	displayValue?: string;
	description?: string;
	priority?: number;
}>;

export type ArgumentValue =
	| Readonly<{ kind: "suggestion"; suggestion: SuggestionSpec }>
	| Readonly<{ kind: "template"; template: TemplateType }>
	| Readonly<{ kind: "root-command" }>;

export type Arity = Readonly<{ limit?: number; delimiter?: string }>;

export type ArgumentSpec = Readonly<{
	name: string;
	description?: string;
	values?: readonly ArgumentValue[];
	optional?: boolean;
	arity?: Arity;
}>;

export type OptSpec = Readonly<{
	name: readonly string[];
	description?: string;
	arguments?: readonly ArgumentSpec[];
	required?: boolean;
	priority?: number;
}>;

export type CommandSpec = Readonly<{
	name: string;
	alias?: readonly string[];
	description?: string;
	arguments?: readonly ArgumentSpec[];
	subcommands?: readonly CommandSpec[];
	options?: readonly OptSpec[];
	priority?: number;
}>;

export const MIN_PRIORITY = -100;
export const MAX_PRIORITY = 100;
export const DEFAULT_PRIORITY = 0;

export function clampPriority(value: number | undefined): number {
	if (value === undefined || !Number.isFinite(value)) return DEFAULT_PRIORITY;
	return Math.min(MAX_PRIORITY, Math.max(MIN_PRIORITY, Math.trunc(value)));
}

export function optHasName(opt: Pick<OptSpec, "name">, name: string): boolean {
	return opt.name.some((declared) => {
		if (declared.startsWith("--")) return declared.slice(2) === name;
		if (declared.startsWith("-")) return declared.slice(1) === name;
		return false;
	});
}

export function isVariadic(argument: ArgumentSpec): boolean {
	return argument.arity !== undefined && argument.arity.limit === undefined;
}
