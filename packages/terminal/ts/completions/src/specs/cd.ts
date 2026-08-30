import type { CommandSpec } from "../signature.js";

export const cd: CommandSpec = {
	name: "cd",
	alias: ["chdir"],
	description: "Change the working directory",
	arguments: [
		{
			name: "directory",
			description: "Directory to change to",
			optional: true,
			values: [{ kind: "template", template: "folders" }],
		},
	],
};
