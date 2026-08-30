import { describe, expect, it } from "vitest";
import { rank, tabAction } from "./rank.js";
import type { Candidate } from "./rank.js";

const candidate = (value: string, priority?: number): Candidate => ({
	value,
	kind: "subcommand",
	priority,
});

const values = (input: readonly { candidate: Candidate }[]): string[] =>
	input.map((entry) => entry.candidate.value);

describe("rank", () => {
	it("puts an exact match first, ahead of a shorter prefix match", () => {
		const ranked = rank([candidate("commitment"), candidate("commit")], "commit");
		expect(values(ranked)).toEqual(["commit", "commitment"]);
	});

	it("puts a case-sensitive exact match ahead of a case-insensitive one", () => {
		const ranked = rank([candidate("Readme"), candidate("readme")], "readme");
		expect(values(ranked)).toEqual(["readme", "Readme"]);
	});

	it("puts every prefix match ahead of every fuzzy match", () => {
		const ranked = rank([candidate("c-m-x"), candidate("cmt")], "cm");
		expect(values(ranked)).toEqual(["cmt", "c-m-x"]);
	});

	it("orders prefix matches by priority descending", () => {
		const ranked = rank(
			[candidate("commit", 0), candidate("checkout", 50), candidate("cherry-pick", 10)],
			"c",
		);
		expect(values(ranked)).toEqual(["checkout", "cherry-pick", "commit"]);
	});

	it("breaks a priority tie by display text ascending", () => {
		const ranked = rank([candidate("cz", 5), candidate("ca", 5)], "c");
		expect(values(ranked)).toEqual(["ca", "cz"]);
	});

	it("orders fuzzy matches by score descending", () => {
		const ranked = rank([candidate("xxcxxxoxxxm"), candidate("x-com")], "com");
		expect(values(ranked)).toEqual(["x-com", "xxcxxxoxxxm"]);
	});

	it("drops candidates that do not match at all", () => {
		const ranked = rank([candidate("commit"), candidate("push")], "com");
		expect(values(ranked)).toEqual(["commit"]);
	});

	it("returns everything, priority-ordered, for an empty query", () => {
		const ranked = rank([candidate("b", 0), candidate("a", 90)], "");
		expect(values(ranked)).toEqual(["a", "b"]);
	});
});

describe("tabAction", () => {
	const span = { start: 4, end: 6 };

	it("does nothing when there is nothing to complete", () => {
		expect(tabAction([], "co", span)).toEqual({ kind: "none" });
	});

	it("inserts outright when exactly one candidate matches by prefix", () => {
		const ranked = rank([candidate("commit"), candidate("push")], "co");
		expect(tabAction(ranked, "co", span)).toEqual({
			kind: "insert",
			text: "commit",
			span,
		});
	});

	it("inserts the longest common prefix and opens when several share one", () => {
		const ranked = rank([candidate("commit"), candidate("commit-tree")], "co");
		const action = tabAction(ranked, "co", span);
		expect(action).toMatchObject({ kind: "insert-and-open", text: "commit", span });
	});

	it("opens without inserting when the common prefix adds nothing", () => {
		const ranked = rank([candidate("commit"), candidate("checkout")], "c");
		expect(tabAction(ranked, "c", { start: 4, end: 5 })).toMatchObject({ kind: "open" });
	});

	it("ignores case-insensitive matches when computing the common prefix", () => {
		const ranked = rank([candidate("Commit-tree"), candidate("commit-message")], "commit");
		const action = tabAction(ranked, "commit", { start: 4, end: 10 });
		expect(action).toMatchObject({ kind: "insert-and-open", text: "commit-message" });
	});
});
