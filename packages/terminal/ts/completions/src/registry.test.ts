import { describe, expect, it } from "vitest";
import { SignatureRegistry } from "./registry.js";
import type { CommandSpec } from "./signature.js";

const git: CommandSpec = {
	name: "git",
	subcommands: [
		{ name: "commit", options: [{ name: ["-m", "--message"] }] },
		{ name: "checkout", alias: ["co"] },
		{
			name: "remote",
			subcommands: [{ name: "add" }, { name: "remove", alias: ["rm"] }],
		},
	],
};

const registry = SignatureRegistry.from([git, { name: "cd", alias: ["chdir"] }]);

describe("SignatureRegistry", () => {
	it("looks a command up by name", () => {
		expect(registry.lookup("git")?.name).toBe("git");
	});

	it("looks a command up by alias", () => {
		expect(registry.lookup("chdir")?.name).toBe("cd");
	});

	it("returns null for an unknown command", () => {
		expect(registry.lookup("kubectl")).toBeNull();
	});

	it("resolves a bare command, consuming one token", () => {
		expect(registry.resolve(["git"])).toEqual({ command: git, consumed: 1 });
	});

	it("descends into a subcommand", () => {
		const resolved = registry.resolve(["git", "commit"]);
		expect(resolved?.command.name).toBe("commit");
		expect(resolved?.consumed).toBe(2);
	});

	it("descends into a subcommand by alias", () => {
		const resolved = registry.resolve(["git", "co"]);
		expect(resolved?.command.name).toBe("checkout");
		expect(resolved?.consumed).toBe(2);
	});

	it("descends through nested subcommands", () => {
		const resolved = registry.resolve(["git", "remote", "rm"]);
		expect(resolved?.command.name).toBe("remove");
		expect(resolved?.consumed).toBe(3);
	});

	it("stops descending at a token that is not a subcommand", () => {
		const resolved = registry.resolve(["git", "commit", "-m", "wip"]);
		expect(resolved?.command.name).toBe("commit");
		expect(resolved?.consumed).toBe(2);
	});

	it("returns null when the first token is unknown", () => {
		expect(registry.resolve(["kubectl", "get"])).toBeNull();
	});

	it("returns null for no tokens", () => {
		expect(registry.resolve([])).toBeNull();
	});
});
