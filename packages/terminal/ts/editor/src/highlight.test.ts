import { describe, expect, it } from "vitest";
import { tokenize } from "./highlight";

const kinds = (text: string) =>
	tokenize(text).map((token) => `${token.kind}:${text.slice(token.start, token.end)}`);

describe("tokenize", () => {
	it("marks the first word as the command and the rest as arguments", () => {
		expect(kinds("git status")).toEqual(["command:git", "argument:status"]);
	});

	it("marks flags", () => {
		expect(kinds("ls -la --color")).toEqual(["command:ls", "flag:-la", "flag:--color"]);
	});

	it("marks quoted strings as one token including the quotes", () => {
		expect(kinds(`echo "hello world"`)).toEqual(["command:echo", `string:"hello world"`]);
	});

	it("marks an unterminated quote as a string to the end", () => {
		expect(kinds(`echo "oops`)).toEqual(["command:echo", `string:"oops`]);
	});

	it("marks operators and starts a new command after them", () => {
		expect(kinds("cat f | wc -l")).toEqual([
			"command:cat",
			"argument:f",
			"operator:|",
			"command:wc",
			"flag:-l",
		]);
	});

	it("marks variables and paths", () => {
		expect(kinds("cd $HOME/src")).toEqual(["command:cd", "variable:$HOME/src"]);
		expect(kinds("cat ./notes.txt")).toEqual(["command:cat", "path:./notes.txt"]);
	});

	it("marks a comment to end of line", () => {
		expect(kinds("ls # list")).toEqual(["command:ls", "comment:# list"]);
	});
});
