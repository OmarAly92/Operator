import { describe, expect, it } from "vitest";
import { locate, tokenize } from "./parse.js";

describe("tokenize", () => {
	it("splits on whitespace and records spans", () => {
		expect(tokenize("git commit")).toEqual([
			{ text: "git", span: { start: 0, end: 3 } },
			{ text: "commit", span: { start: 4, end: 10 } },
		]);
	});

	it("keeps a double-quoted run as one token", () => {
		expect(tokenize('git commit -m "a b"')).toEqual([
			{ text: "git", span: { start: 0, end: 3 } },
			{ text: "commit", span: { start: 4, end: 10 } },
			{ text: "-m", span: { start: 11, end: 13 } },
			{ text: "a b", span: { start: 14, end: 19 } },
		]);
	});

	it("keeps a single-quoted run as one token", () => {
		expect(tokenize("echo 'x y'")).toEqual([
			{ text: "echo", span: { start: 0, end: 4 } },
			{ text: "x y", span: { start: 5, end: 10 } },
		]);
	});

	it("returns nothing for a blank line", () => {
		expect(tokenize("   ")).toEqual([]);
	});
});

describe("locate", () => {
	it("locates a command being typed", () => {
		expect(locate("gi", 2)).toEqual({
			kind: "command",
			query: "gi",
			span: { start: 0, end: 2 },
			commandTokens: [],
		});
	});

	it("locates an empty command on an empty line", () => {
		expect(locate("", 0)).toEqual({
			kind: "command",
			query: "",
			span: { start: 0, end: 0 },
			commandTokens: [],
		});
	});

	it("locates an argument after a trailing space", () => {
		expect(locate("git ", 4)).toEqual({
			kind: "argument",
			query: "",
			span: { start: 4, end: 4 },
			commandTokens: ["git"],
		});
	});

	it("locates a partially typed argument", () => {
		expect(locate("git comm", 8)).toEqual({
			kind: "argument",
			query: "comm",
			span: { start: 4, end: 8 },
			commandTokens: ["git"],
		});
	});

	it("locates a flag by its leading hyphen", () => {
		expect(locate("git commit --me", 15)).toEqual({
			kind: "flag",
			query: "--me",
			span: { start: 11, end: 15 },
			commandTokens: ["git", "commit"],
		});
	});

	it("locates a bare hyphen as a flag", () => {
		expect(locate("ls -", 4)).toEqual({
			kind: "flag",
			query: "-",
			span: { start: 3, end: 4 },
			commandTokens: ["ls"],
		});
	});

	it("locates the token the cursor sits inside, not the last one", () => {
		expect(locate("git commit -m", 7)).toEqual({
			kind: "argument",
			query: "com",
			span: { start: 4, end: 10 },
			commandTokens: ["git"],
		});
	});

	it("locates the value half of an equals-form flag", () => {
		expect(locate("docker build --file=Docker", 26)).toEqual({
			kind: "flag-value",
			query: "Docker",
			span: { start: 20, end: 26 },
			commandTokens: ["docker", "build"],
			flagName: "file",
		});
	});

	it("locates an empty equals-form value", () => {
		expect(locate("git commit --message=", 21)).toEqual({
			kind: "flag-value",
			query: "",
			span: { start: 21, end: 21 },
			commandTokens: ["git", "commit"],
			flagName: "message",
		});
	});

	it("still locates the flag name while the cursor is left of the equals", () => {
		const found = locate("docker build --file=x", 17);
		expect(found?.kind).toBe("flag");
		expect(found?.query).toBe("--fi");
	});

	it("declines a variable, which is deferred", () => {
		expect(locate("echo $HO", 8)).toBeNull();
	});

	it("declines a cursor inside leading whitespace", () => {
		expect(locate("  git", 1)).toBeNull();
	});
});
