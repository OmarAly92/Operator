import { describe, expect, it } from "vitest";
import { matchQuery } from "./match.js";

describe("matchQuery", () => {
	it("treats an empty query as a prefix match of everything", () => {
		expect(matchQuery("anything", "")).toEqual({ kind: "prefix", caseSensitive: true });
	});

	it("reports an exact match", () => {
		expect(matchQuery("commit", "commit")).toEqual({ kind: "exact", caseSensitive: true });
	});

	it("reports a case-insensitive exact match", () => {
		expect(matchQuery("Commit", "commit")).toEqual({ kind: "exact", caseSensitive: false });
	});

	it("reports a prefix match", () => {
		expect(matchQuery("commit", "com")).toEqual({ kind: "prefix", caseSensitive: true });
	});

	it("reports a case-insensitive prefix match", () => {
		expect(matchQuery("Commit", "com")).toEqual({ kind: "prefix", caseSensitive: false });
	});

	it("falls through to fuzzy when the query is scattered", () => {
		const result = matchQuery("commit", "cmt");
		expect(result?.kind).toBe("fuzzy");
	});

	it("returns the matched indices so the UI can highlight them", () => {
		const result = matchQuery("commit", "cmt");
		expect(result).toMatchObject({ kind: "fuzzy", indices: [0, 2, 5] });
	});

	it("returns null when the query is not a subsequence", () => {
		expect(matchQuery("commit", "xyz")).toBeNull();
	});

	it("is case-insensitive while the query is all lowercase", () => {
		expect(matchQuery("README", "readme")).toEqual({ kind: "exact", caseSensitive: false });
	});

	it("becomes case-sensitive as soon as the query has an uppercase letter", () => {
		expect(matchQuery("readme", "README")).toBeNull();
		expect(matchQuery("README", "README")).toEqual({ kind: "exact", caseSensitive: true });
	});

	it("scores a word-start match above a mid-word one", () => {
		const wordStart = matchQuery("git-commit", "gc");
		const midWord = matchQuery("gxxcxx", "gc");
		expect(wordStart?.kind).toBe("fuzzy");
		expect(midWord?.kind).toBe("fuzzy");
		expect((wordStart as { score: number }).score).toBeGreaterThan(
			(midWord as { score: number }).score,
		);
	});

	it("scores consecutive characters above scattered ones", () => {
		const consecutive = matchQuery("xxcommit", "com");
		const scattered = matchQuery("xxcxoxm", "com");
		expect((consecutive as { score: number }).score).toBeGreaterThan(
			(scattered as { score: number }).score,
		);
	});

	it("scores a camelCase boundary as a word start", () => {
		const camel = matchQuery("gitCommit", "gC");
		expect(camel?.kind).toBe("fuzzy");
		expect((camel as { score: number }).score).toBeGreaterThan(0);
	});
});
