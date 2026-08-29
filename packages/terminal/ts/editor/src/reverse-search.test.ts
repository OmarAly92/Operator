import { describe, expect, it } from "vitest";
import { ReverseSearch } from "./reverse-search";

describe("ReverseSearch", () => {
	it("matches a substring anywhere in the entry, newest first", () => {
		const search = new ReverseSearch();
		search.open(["git status", "npm run build", "git commit"]);
		search.type("g");
		search.type("i");
		search.type("t");
		expect(search.state().match).toBe("git commit");
		search.next();
		expect(search.state().match).toBe("git status");
	});

	it("reports no match instead of falling back to an unrelated entry", () => {
		const search = new ReverseSearch();
		search.open(["ls"]);
		search.type("z");
		expect(search.state().match).toBeNull();
	});

	it("accept returns the match and cancel returns null", () => {
		const search = new ReverseSearch();
		search.open(["make test"]);
		search.type("test");
		expect(search.accept()).toBe("make test");
		search.open(["make test"]);
		search.type("test");
		search.cancel();
		expect(search.accept()).toBeNull();
	});

	it("backspace widens the match set again", () => {
		const search = new ReverseSearch();
		search.open(["alpha", "beta"]);
		search.type("a");
		search.type("l");
		expect(search.state().total).toBe(1);
		search.backspace();
		expect(search.state().total).toBe(2);
	});
});
