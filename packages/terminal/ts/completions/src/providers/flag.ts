import type { Candidate } from "../rank.js";
import { clampPriority, optHasName, type CommandSpec } from "../signature.js";

export function flagCandidates(
	command: CommandSpec,
	used: readonly string[],
): Candidate[] {
	const usedNames = used
		.map((token) => token.replace(/^--?/, ""))
		.filter((name) => name.length > 0);

	const candidates: Candidate[] = [];
	for (const option of command.options ?? []) {
		if (usedNames.some((name) => optHasName(option, name))) continue;
		for (const name of option.name) {
			candidates.push({
				value: name,
				kind: "flag",
				description: option.description,
				priority: clampPriority(option.priority),
			});
		}
	}
	return candidates;
}
