import { describe, expect, it } from "vitest";
import { pathCandidates, splitPathQuery } from "./path.js";

const entries = {
	"/repo": [
		{ name: "src", isDirectory: true, isHidden: false },
		{ name: "README.md", isDirectory: false, isHidden: false },
		{ name: ".git", isDirectory: true, isHidden: true },
	],
	"/repo/src": [{ name: "index.ts", isDirectory: false, isHidden: false }],
};

const host = {
	writeClipboard: async () => undefined,
	readClipboard: async () => "",
	openLink: async () => undefined,
	listDirectory: async (path: string) =>
		entries[path as keyof typeof entries] ?? [],
};

const signal = new AbortController().signal;

describe("splitPathQuery", () => {
	it("splits a bare leaf into the current directory", () => {
		expect(splitPathQuery("REA")).toEqual({ directory: ".", leaf: "REA" });
	});

	it("splits a relative path at its last separator", () => {
		expect(splitPathQuery("src/ind")).toEqual({ directory: "src", leaf: "ind" });
	});

	it("splits a trailing separator into an empty leaf", () => {
		expect(splitPathQuery("src/")).toEqual({ directory: "src", leaf: "" });
	});

	it("keeps an absolute directory absolute", () => {
		expect(splitPathQuery("/repo/sr")).toEqual({ directory: "/repo", leaf: "sr" });
	});
});

describe("pathCandidates", () => {
	it("lists files and folders from the cwd", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("suffixes a directory with a separator so the next Tab descends", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value)).toEqual(["src/"]);
	});

	it("still offers directories when the template says files", async () => {
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value).sort()).toEqual(["README.md", "src/"]);
	});

	it("resolves a subdirectory in the query against the cwd", async () => {
		const found = await pathCandidates({
			query: "src/",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value)).toEqual(["src/index.ts"]);
	});

	it("hides dotfiles until the query asks for one", async () => {
		const hidden = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(hidden.map((entry) => entry.value)).not.toContain(".git/");

		const asked = await pathCandidates({
			query: ".",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal,
		});
		expect(asked.map((entry) => entry.value)).toContain(".git/");
	});

	it("does not carry quote characters into the filesystem path", async () => {
		const asked: string[] = [];
		const quoting = {
			...host,
			listDirectory: async (path: string) => {
				asked.push(path);
				return [];
			},
		};
		await pathCandidates({
			query: '"my dir/',
			cwd: "/repo",
			template: "files-and-folders",
			host: quoting,
			signal,
		});
		expect(asked).toEqual(["/repo/my dir"]);
	});

	it("keeps the typed quote in the replacement so the line stays valid", async () => {
		const found = await pathCandidates({
			query: "'",
			cwd: "/repo",
			template: "folders",
			host,
			signal,
		});
		expect(found.map((entry) => entry.value)).toEqual(["'src/"]);
	});

	it("returns nothing when the host cannot list directories", async () => {
		const bare = { ...host, listDirectory: undefined };
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host: bare,
			signal,
		});
		expect(found).toEqual([]);
	});

	it("returns nothing once the request is aborted", async () => {
		const controller = new AbortController();
		controller.abort();
		const found = await pathCandidates({
			query: "",
			cwd: "/repo",
			template: "files-and-folders",
			host,
			signal: controller.signal,
		});
		expect(found).toEqual([]);
	});
});
