import { describe, expect, it } from "vitest";
import { argumentCandidates, commandCandidates, subcommandCandidates } from "./command.js";
import { SignatureRegistry } from "../registry.js";
import { defaultSignatures, git } from "../specs/index.js";

const registry = SignatureRegistry.from(defaultSignatures);

describe("commandCandidates", () => {
	it("offers every registered root command", () => {
		const found = commandCandidates(registry).map((entry) => entry.value);
		expect(found).toEqual(expect.arrayContaining(["cd", "git", "docker"]));
	});

	it("marks them as commands", () => {
		expect(commandCandidates(registry)[0]?.kind).toBe("command");
	});
});

describe("subcommandCandidates", () => {
	it("offers a command's subcommands", () => {
		const found = subcommandCandidates(git).map((entry) => entry.value);
		expect(found).toEqual(expect.arrayContaining(["commit", "checkout", "push"]));
	});

	it("carries descriptions through", () => {
		const commit = subcommandCandidates(git).find((entry) => entry.value === "commit");
		expect(commit?.description).toBeTruthy();
	});

	it("returns nothing for a leaf command", () => {
		expect(subcommandCandidates({ name: "pwd" })).toEqual([]);
	});
});

describe("argumentCandidates", () => {
	it("reports the template an argument asks for", () => {
		const cd = registry.lookup("cd")!;
		expect(argumentCandidates(cd, 0).template).toBe("folders");
	});

	it("reports literal suggestions declared on an argument", () => {
		const command: Parameters<typeof argumentCandidates>[0] = {
			name: "npm",
			arguments: [
				{
					name: "script",
					values: [
						{ kind: "suggestion", suggestion: { value: "start" } },
						{ kind: "suggestion", suggestion: { value: "test", priority: 20 } },
					],
				},
			],
		};
		const { literals, template } = argumentCandidates(command, 0);
		expect(literals.map((entry) => entry.value)).toEqual(["start", "test"]);
		expect(literals[1]?.priority).toBe(20);
		expect(template).toBeNull();
	});

	it("reports nothing past the last declared argument", () => {
		const cd = registry.lookup("cd")!;
		expect(argumentCandidates(cd, 3)).toEqual({ literals: [], template: null });
	});

	it("keeps offering a variadic argument past its first position", () => {
		const command: Parameters<typeof argumentCandidates>[0] = {
			name: "rm",
			arguments: [
				{
					name: "file",
					arity: {},
					values: [{ kind: "template", template: "files-and-folders" }],
				},
			],
		};
		expect(argumentCandidates(command, 4).template).toBe("files-and-folders");
	});
});
