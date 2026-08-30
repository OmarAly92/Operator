import { describe, expect, it } from "vitest";
import { createCompletionProvider } from "./index.js";

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
	listDirectory: async () => [
		{ name: "src", isDirectory: true, isHidden: false },
		{ name: "README.md", isDirectory: false, isHidden: false },
	],
};

const provider = createCompletionProvider();

const complete = (line: string, cursor = line.length) =>
	provider({ line, cursor, cwd: "/repo", host, signal: new AbortController().signal });

describe("createCompletionProvider", () => {
	it("completes a root command", async () => {
		const result = await complete("gi");
		expect(result?.items.map((item) => item.value)).toContain("git");
		expect(result?.span).toEqual({ start: 0, end: 2 });
	});

	it("completes a subcommand", async () => {
		const result = await complete("git comm");
		expect(result?.items[0]?.value).toBe("commit");
	});

	it("completes a subcommand by alias, ranked by priority", async () => {
		const result = await complete("git c");
		expect(result?.items[0]?.value).toBe("checkout");
	});

	it("completes a flag", async () => {
		const result = await complete("git commit --me");
		expect(result?.items.map((item) => item.value)).toContain("--message");
	});

	it("completes a folder for cd", async () => {
		const result = await complete("cd ");
		expect(result?.items.map((item) => item.value)).toEqual(["src/"]);
	});

	it("completes files and folders for git add", async () => {
		const result = await complete("git add ");
		expect(result?.items.map((item) => item.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("returns matched indices so the dropdown can highlight", async () => {
		const result = await complete("git cmt");
		const commit = result?.items.find((item) => item.value === "commit");
		expect(commit?.matchedIndices).toEqual([0, 2, 5]);
	});

	it("returns null for an unknown command's arguments", async () => {
		const result = await complete("kubectl get ");
		expect(result).toBeNull();
	});

	it("returns null inside a variable", async () => {
		expect(await complete("echo $HO")).toBeNull();
	});

	it("does not let a flag shift the positional argument index", async () => {
		const bare = await complete("docker build ");
		const flagged = await complete("docker build -t img ");
		expect(bare?.items.map((item) => item.value)).toEqual(["src/"]);
		expect(flagged?.items.map((item) => item.value)).toEqual(["src/"]);
	});

	it("still offers subcommands after a global flag", async () => {
		const result = await complete("git -c x ");
		expect(result?.items.map((item) => item.value)).toContain("commit");
	});

	it("never calls the host for anything but a directory listing", async () => {
		const calls: string[] = [];
		const watched = {
			...host,
			writeClipboard: async () => {
				calls.push("writeClipboard");
			},
			openLink: async () => {
				calls.push("openLink");
			},
		};
		await provider({
			line: "git add ",
			cursor: 8,
			cwd: "/repo",
			host: watched,
			signal: new AbortController().signal,
		});
		expect(calls).toEqual([]);
	});
});
