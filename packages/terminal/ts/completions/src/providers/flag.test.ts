import { describe, expect, it } from "vitest";
import { flagCandidates } from "./flag.js";
import type { CommandSpec } from "../signature.js";

const commit: CommandSpec = {
	name: "commit",
	options: [
		{ name: ["-m", "--message"], description: "Commit message", priority: 60 },
		{ name: ["-a", "--all"], description: "Stage tracked files" },
		{ name: ["--amend"] },
	],
};

describe("flagCandidates", () => {
	it("offers every long and short form", () => {
		const found = flagCandidates(commit, []).map((entry) => entry.value);
		expect(found).toEqual(
			expect.arrayContaining(["-m", "--message", "-a", "--all", "--amend"]),
		);
	});

	it("carries the description through for the dropdown", () => {
		const message = flagCandidates(commit, []).find((entry) => entry.value === "--message");
		expect(message?.description).toBe("Commit message");
	});

	it("carries the declared priority", () => {
		const message = flagCandidates(commit, []).find((entry) => entry.value === "--message");
		expect(message?.priority).toBe(60);
	});

	it("defaults an undeclared priority to zero", () => {
		const amend = flagCandidates(commit, []).find((entry) => entry.value === "--amend");
		expect(amend?.priority).toBe(0);
	});

	it("drops an option once one of its forms is already on the line", () => {
		const found = flagCandidates(commit, ["-m"]).map((entry) => entry.value);
		expect(found).not.toContain("--message");
		expect(found).not.toContain("-m");
		expect(found).toContain("--amend");
	});

	it("returns nothing for a command with no options", () => {
		expect(flagCandidates({ name: "pwd" }, [])).toEqual([]);
	});
});
