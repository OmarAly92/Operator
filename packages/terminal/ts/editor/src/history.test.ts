import { describe, expect, it } from "vitest";
import { HistoryModel } from "./history";

describe("HistoryModel", () => {
	it("suggests the most recent entry that extends the prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["git status", "git commit -m wip", "ls"]);
		expect(history.suggest("git ")).toBe("git commit -m wip");
	});

	it("returns null when nothing matches", () => {
		const history = new HistoryModel();
		history.setLocal(["ls"]);
		expect(history.suggest("zzz")).toBeNull();
	});

	it("never suggests for an empty prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["rm -rf build"]);
		expect(history.suggest("")).toBeNull();
	});

	it("keeps the most recent occurrence when a command repeats", () => {
		const history = new HistoryModel();
		history.setLocal(["ls", "cd /", "ls"]);
		expect(history.entries()).toEqual(["cd /", "ls"]);
	});

	it("walks back and forward through matching entries and returns to the typed prefix", () => {
		const history = new HistoryModel();
		history.setLocal(["git a", "git b", "git c"]);
		history.startRecall("git");
		expect(history.step(-1)).toBe("git c");
		expect(history.step(-1)).toBe("git b");
		expect(history.step(1)).toBe("git c");
		expect(history.step(1)).toBe("git");
	});

	it("stays on the oldest entry when stepping past it", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b"]);
		history.startRecall("");
		expect([history.step(-1), history.step(-1), history.step(-1)]).toEqual(["b", "a", "a"]);
	});

	it("drops the oldest entries past the limit", () => {
		const history = new HistoryModel(2);
		history.setLocal(["a", "b", "c"]);
		expect(history.entries()).toEqual(["b", "c"]);
	});

	it("orders shared entries by time and puts this pane's own commands after them, without repeats", () => {
		const history = new HistoryModel();
		history.setShared([
			{ command: "ls", at: 30 },
			{ command: "make", at: 10 },
			{ command: "npm test", at: 50 },
		]);
		history.setLocal(["ls", "git push"]);
		expect(history.entries()).toEqual(["make", "npm test", "ls", "git push"]);
	});

	it("keeps the entry on screen when shared history lands during a walk", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b", "c"]);
		history.startRecall("");
		expect(history.step(-1)).toBe("c");
		expect(history.step(-1)).toBe("b");
		history.setShared([
			{ command: "old", at: 1 },
			{ command: "newer", at: 100 },
		]);
		expect(history.step(-1)).toBe("a");
		expect(history.step(-1)).toBe("newer");
		expect(history.step(-1)).toBe("old");
		expect(history.step(1)).toBe("newer");
		expect(history.step(1)).toBe("a");
		expect(history.step(1)).toBe("b");
	});

	it("starts a new walk from the newest entry", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b", "c"]);
		history.startRecall("");
		history.step(-1);
		history.step(-1);
		history.endRecall();
		history.startRecall("");
		expect(history.step(-1)).toBe("c");
	});

	it("does not rebuild when the same entries arrive again", () => {
		const history = new HistoryModel();
		history.setLocal(["a", "b"]);
		history.startRecall("");
		expect(history.step(-1)).toBe("b");
		history.setLocal(["a", "b"]);
		expect(history.step(-1)).toBe("a");
	});

	it("recalls a multi-line command whole", () => {
		const history = new HistoryModel();
		history.setShared([{ command: "for f in *; do\n  echo $f\ndone", at: 5 }]);
		history.startRecall("");
		expect(history.step(-1)).toBe("for f in *; do\n  echo $f\ndone");
	});
});
