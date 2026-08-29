import { describe, expect, it } from "vitest";
import { HistoryModel } from "./history";

describe("HistoryModel", () => {
	it("suggests the most recent entry that extends the prefix", () => {
		const history = new HistoryModel();
		history.ingest(["git status", "git commit -m wip", "ls"]);
		expect(history.suggest("git ")).toBe("git commit -m wip");
	});

	it("returns null when nothing matches", () => {
		const history = new HistoryModel();
		history.ingest(["ls"]);
		expect(history.suggest("zzz")).toBeNull();
	});

	it("never suggests for an empty prefix", () => {
		const history = new HistoryModel();
		history.ingest(["rm -rf build"]);
		expect(history.suggest("")).toBeNull();
	});

	it("keeps the most recent occurrence when a command repeats", () => {
		const history = new HistoryModel();
		history.ingest(["ls", "cd /", "ls"]);
		expect(history.entries()).toEqual(["cd /", "ls"]);
	});

	it("walks back and forward through matching entries", () => {
		const history = new HistoryModel();
		history.ingest(["git a", "git b", "git c"]);
		expect(history.recall("git", -1)).toBe("git c");
		expect(history.recall("git", -1)).toBe("git b");
		expect(history.recall("git", 1)).toBe("git c");
	});

	it("drops the oldest entries past the limit", () => {
		const history = new HistoryModel(2);
		history.ingest(["a", "b", "c"]);
		expect(history.entries()).toEqual(["b", "c"]);
	});
});
