import { describe, expect, it } from "vitest";
import { collectHintMatches, HintSession } from "./hint-mode";
import { DEFAULT_HINT_RULES } from "./hint-rules";
import { logicalLineAt } from "./logical-lines";
import type { TextRows } from "./selection-text";

function lines(...texts: string[]) {
	const rows: TextRows = {
		blockIds: ["b"],
		firstRow: () => 0,
		rowCount: () => texts.length,
		rowText: (_id, row) => texts[row] ?? "",
		rowSpans: () => [],
		rowWrapped: () => false,
	};
	return texts.map((_text, row) => logicalLineAt(rows, "b", row)!);
}

describe("collectHintMatches", () => {
	it("finds every rule's matches in order and does not overlap them", () => {
		const matches = collectHintMatches(lines("open https://x.y/a and src/a.ts:42 now"), DEFAULT_HINT_RULES);
		expect(matches.map((match) => [match.ruleId, match.text])).toEqual([
			["url", "https://x.y/a"],
			["file-line", "src/a.ts:42"],
		]);
		expect(matches[1]).toMatchObject({ path: "src/a.ts", line: 42 });
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 5, endRow: 0, endCell: 18 });
	});
	it("prefers path:line over the bare path at the same start", () => {
		const matches = collectHintMatches(lines("src/a.ts:42"), DEFAULT_HINT_RULES);
		expect(matches.map((match) => match.ruleId)).toEqual(["file-line"]);
	});
	it("spans a wrapped logical line as one candidate", () => {
		const rows: TextRows = {
			blockIds: ["b"],
			firstRow: () => 0,
			rowCount: () => 2,
			rowText: (_id, row) => (row === 0 ? "go https://x.y/aaa" : "bbb done"),
			rowSpans: () => [],
			rowWrapped: (_id, row) => row === 0,
		};
		const matches = collectHintMatches([logicalLineAt(rows, "b", 0)!], DEFAULT_HINT_RULES);
		expect(matches[0]!.text).toBe("https://x.y/aaabbb");
		expect(matches[0]!.range).toEqual({ blockId: "b", startRow: 0, startCell: 3, endRow: 1, endCell: 3 });
	});
});

describe("HintSession", () => {
	const match = (text: string) => ({ ruleId: "url", text, range: { blockId: "b", startRow: 0, startCell: 0, endRow: 0, endCell: 1 } });

	it("labels from the last match backwards and shares a label between identical texts", () => {
		const session = new HintSession([match("one"), match("two"), match("one")], "abcd");
		expect(session.labelled().map((entry) => [entry.label, entry.match.text])).toEqual([
			["b", "one"],
			["a", "two"],
			["b", "one"],
		]);
	});
	it("narrows on typed characters, un-types on backspace and resolves a full label", () => {
		const session = new HintSession(Array.from({ length: 6 }, (_v, index) => match(`m${index}`)), "abcd");
		expect(session.labelled().map((entry) => entry.label)).toEqual(["dc", "db", "da", "c", "b", "a"]);
		expect(session.type("d")).toBeNull();
		expect(session.typed()).toBe("d");
		expect(session.labelled().map((entry) => entry.label)).toEqual(["dc", "db", "da"]);
		session.backspace();
		expect(session.typed()).toBe("");
		expect(session.labelled()).toHaveLength(6);
		expect(session.type("a")?.text).toBe("m5");
	});
	it("resets the typed prefix when a character matches no label", () => {
		const session = new HintSession([match("only")], "abcd");
		expect(session.type("z")).toBeNull();
		expect(session.typed()).toBe("");
		expect(session.labelled()).toHaveLength(1);
	});
});
