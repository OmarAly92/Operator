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
	it("asks the providers for the hovered line once per generation and reports the link under the pointer", async () => {
		const provider = vi.fn<LinkProvider>(async (line) => [
			{ kind: "url", text: "https://x.y", uri: "https://x.y", range: line.rangeOf(4, 15) },
		]);
		let generation = 1;
		const onChange = vi.fn();
		const linkifier = new Linkifier({ rows: () => rowsWith("see https://x.y now"), generation: () => generation, providers: () => [provider], onChange });
		linkifier.hover({ blockId: "b", row: 0, column: 6, side: "left" });
		await settle();
		expect(linkifier.current()?.uri).toBe("https://x.y");
		expect(onChange).toHaveBeenCalledTimes(1);
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		await settle();
		expect(linkifier.current()).toBeNull();
		expect(provider).toHaveBeenCalledTimes(1);
		generation = 2;
		linkifier.refresh();
		await settle();
		expect(provider).toHaveBeenCalledTimes(2);
	});
	it("asks the new providers for the hovered line when the list is swapped under it", async () => {
		let providers: LinkProvider[] = [async () => []];
		const linkifier = new Linkifier({ rows: () => rowsWith("see https://x.y now"), generation: () => 1, providers: () => providers, onChange: () => undefined });
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
		const linkifier = new Linkifier({ rows: () => rowsWith("abcdefghij"), generation: () => 1, providers: () => [first, second], onChange: () => undefined });
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
		const linkifier = new Linkifier({ rows: () => rowsWith("abc"), generation: () => 1, providers: () => [slow], onChange: () => undefined });
		linkifier.hover({ blockId: "b", row: 0, column: 1, side: "left" });
		linkifier.hover(null);
		release([{ kind: "url", text: "abc", uri: "https://late", range: { blockId: "b", startRow: 0, startCell: 0, endRow: 0, endCell: 3 } }]);
		await settle();
		expect(linkifier.current()).toBeNull();
	});
});
