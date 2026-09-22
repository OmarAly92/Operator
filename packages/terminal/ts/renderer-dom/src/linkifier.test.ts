import { describe, expect, it, vi } from "vitest";
import { Linkifier } from "./linkifier";
import type { DetectedLink, LinkProvider } from "./link-providers";
import type { TextRows } from "./selection-text";

function rowsWith(text: string): TextRows {
	return { blockIds: ["b"], firstRow: () => 0, rowCount: () => 1, rowText: () => text, rowSpans: () => [], rowWrapped: () => false };
}

async function settle(): Promise<void> {
	await new Promise((resolve) => setTimeout(resolve, 0));
}

describe("Linkifier", () => {
	it("asks the providers with the hovered offset and reports the link under the pointer", async () => {
		const provider = vi.fn<LinkProvider>(async (line) => [
			{ kind: "url", text: "https://x.y", uri: "https://x.y", range: line.rangeOf(4, 15) },
		]);
		const onChange = vi.fn();
		const linkifier = new Linkifier({ rows: () => rowsWith("see https://x.y now"), providers: () => [provider], onChange });
		linkifier.hover({ blockId: "b", row: 0, column: 6, side: "left" });
		await settle();
		expect(linkifier.current()?.uri).toBe("https://x.y");
		expect(onChange).toHaveBeenCalledTimes(1);
		expect(provider).toHaveBeenLastCalledWith(expect.objectContaining({ text: "see https://x.y now" }), 6);
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
		expect(provider).toHaveBeenLastCalledWith(expect.anything(), 1);
	});
	it("keeps its answer for the hovered cell across repaints that leave the line's text alone", async () => {
		const provider = vi.fn<LinkProvider>(async (line) => [{ kind: "path", text: "a.ts", path: "/a.ts", range: line.rangeOf(0, 4) }]);
		let text = "a.ts is here";
		const linkifier = new Linkifier({ rows: () => rowsWith(text), providers: () => [provider], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		await settle();
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "right" });
		linkifier.refresh();
		await settle();
		expect(provider).toHaveBeenCalledTimes(1);
		expect(linkifier.current()?.path).toBe("/a.ts");
		text = "a.ts is gone";
		linkifier.refresh();
		await settle();
		expect(provider).toHaveBeenCalledTimes(2);
	});
	it("asks the new providers for the hovered line when the list is swapped under it", async () => {
		let providers: LinkProvider[] = [async () => []];
		const linkifier = new Linkifier({ rows: () => rowsWith("see https://x.y now"), providers: () => providers, onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 6, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
		providers = [async (line) => [{ kind: "url", text: "https://x.y", uri: "https://x.y", range: line.rangeOf(4, 15) }]];
		linkifier.invalidate();
		await settle();
		expect(linkifier.current()?.uri).toBe("https://x.y");
	});
	it("prefers an earlier provider's link when a later one overlaps it", async () => {
		const first: LinkProvider = async (line) => [{ kind: "hyperlink", text: "a", uri: "https://first", range: line.rangeOf(0, 5) }];
		const second: LinkProvider = async (line) => [{ kind: "url", text: "b", uri: "https://second", range: line.rangeOf(3, 9) }];
		const linkifier = new Linkifier({ rows: () => rowsWith("abcdefghij"), providers: () => [first, second], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 4, side: "left" });
		await settle();
		expect(linkifier.current()?.uri).toBe("https://first");
		linkifier.hover({ blockId: "b", row: 0, column: 7, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
	});
	it("ignores a resolution that lands after the pointer moved on", async () => {
		let release: (links: DetectedLink[]) => void = () => undefined;
		const slow: LinkProvider = () => new Promise((resolve) => { release = resolve; });
		const linkifier = new Linkifier({ rows: () => rowsWith("abc"), providers: () => [slow], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		linkifier.hover(null);
		release([{ kind: "url", text: "abc", uri: "https://late", range: { blockId: "b", startRow: 0, startCell: 0, endRow: 0, endCell: 3 } }]);
		await settle();
		expect(linkifier.current()).toBeNull();
	});
});
