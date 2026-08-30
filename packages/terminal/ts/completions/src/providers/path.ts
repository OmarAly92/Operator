import type { HostCapabilities } from "@operator/terminal-core";
import type { Candidate } from "../rank.js";
import type { TemplateType } from "../signature.js";

export type PathInput = Readonly<{
	query: string;
	cwd: string;
	template: TemplateType;
	host: HostCapabilities;
	signal: AbortSignal;
}>;

export function splitPathQuery(query: string): { directory: string; leaf: string } {
	const index = query.lastIndexOf("/");
	if (index === -1) return { directory: ".", leaf: query };
	const directory = index === 0 ? "/" : query.slice(0, index);
	return { directory, leaf: query.slice(index + 1) };
}

export async function pathCandidates(input: PathInput): Promise<Candidate[]> {
	const list = input.host.listDirectory;
	if (list === undefined) return [];
	if (input.signal.aborted) return [];

	const { directory, leaf } = splitPathQuery(input.query);
	const absolute = directory.startsWith("/")
		? directory
		: directory === "."
			? input.cwd
			: `${input.cwd}/${directory}`;

	const entries = await list.call(input.host, absolute);
	if (input.signal.aborted) return [];

	const prefix = input.query.slice(0, input.query.length - leaf.length);
	const wantsHidden = leaf.startsWith(".");

	const candidates: Candidate[] = [];
	for (const entry of entries) {
		if (entry.isHidden && !wantsHidden) continue;
		if (input.template === "folders" && !entry.isDirectory) continue;
		const name = entry.isDirectory ? `${entry.name}/` : entry.name;
		candidates.push({
			value: `${prefix}${name}`,
			displayValue: name,
			kind: "path",
			isDirectory: entry.isDirectory,
		});
	}
	return candidates;
}
