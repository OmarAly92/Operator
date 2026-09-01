import { afterEach, describe, expect, it } from "vitest";
import type { BlockId, BlockView } from "@operator/terminal-core";
import { mountBlockNav } from "./block-nav";

function makeBlock(id: string, command: string): BlockView {
	return {
		id,
		firstRow: 0,
		rowCount: 2,
		source: "osc133",
		state: "finished",
		exitCode: 0,
		durationMs: 100,
		command,
		cwd: "",
		gitBranch: "",
	};
}

function keyEvent(init: Partial<KeyboardEventInit> & { key: string }): KeyboardEvent {
	return new KeyboardEvent("keydown", {
		ctrlKey: false,
		metaKey: false,
		altKey: false,
		shiftKey: false,
		bubbles: true,
		cancelable: true,
		...init,
	});
}

interface Harness {
	container: HTMLDivElement;
	blocks: BlockView[];
	pinnedIndex: number;
	altActive: boolean;
	scrolledTo: { id: BlockId; align: "start" | "center" | "end" }[];
	focusedIds: string[];
	dispose: () => void;
}

function makeHarness(initialBlocks: BlockView[], initialPinned = 0): Harness {
	const container = document.createElement("div");
	container.tabIndex = 0;
	document.body.append(container);
	for (const block of initialBlocks) {
		const section = document.createElement("section");
		section.dataset.terminalBlockId = block.id;
		container.append(section);
	}
	const scrolledTo: { id: BlockId; align: "start" | "center" | "end" }[] = [];
	const focusedIds: string[] = [];
	const handle = mountBlockNav({
		container,
		getBlocks: () => initialBlocks,
		getPinnedIndex: () => initialPinned,
		scrollToBlock: (id, align) => scrolledTo.push({ id, align }),
		isAltScreenActive: () => false,
	});
	const observer = new MutationObserver((mutations) => {
		for (const mutation of mutations) {
			if (mutation.type === "attributes" && mutation.attributeName === "class") {
				const el = mutation.target as HTMLElement;
				if (el.classList.contains("terminal-block-focused")) {
					focusedIds.push(el.dataset.terminalBlockId ?? "");
				}
			}
		}
	});
	observer.observe(container, { attributes: true, subtree: true, attributeFilter: ["class"] });
	return {
		container,
		blocks: initialBlocks,
		pinnedIndex: initialPinned,
		get altActive() {
			return false;
		},
		scrolledTo,
		focusedIds,
		dispose: () => {
			observer.disconnect();
			handle.dispose();
			container.remove();
		},
	};
}

describe("mountBlockNav", () => {
	let harness: Harness | null = null;

	afterEach(() => {
		harness?.dispose();
		harness = null;
	});

	it("is inert in the alt screen (no scroll, no focus change)", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		const altContainer = document.createElement("div");
		altContainer.tabIndex = 0;
		document.body.append(altContainer);
		for (const block of blocks) {
			const section = document.createElement("section");
			section.dataset.terminalBlockId = block.id;
			altContainer.append(section);
		}
		const altScrolled: { id: BlockId; align: "start" | "center" | "end" }[] = [];
		const altHandle = mountBlockNav({
			container: altContainer,
			getBlocks: () => blocks,
			getPinnedIndex: () => 0,
			scrollToBlock: (id, align) => altScrolled.push({ id, align }),
			isAltScreenActive: () => true,
		});
		altContainer.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		altContainer.dispatchEvent(keyEvent({ key: "ArrowDown", ctrlKey: true }));
		expect(altScrolled).toEqual([]);
		altHandle.dispose();
		altContainer.remove();
	});

	it("Cmd+ArrowDown moves to the next block and centers it", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second"), makeBlock("0:2", "third")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		expect(harness.scrolledTo).toEqual([{ id: "0:1", align: "center" }]);
	});

	it("Cmd+ArrowUp moves to the previous block", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second"), makeBlock("0:2", "third")];
		harness = makeHarness(blocks, 1);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowUp", metaKey: true }));
		expect(harness.scrolledTo).toEqual([{ id: "0:0", align: "center" }]);
	});

	it("Ctrl+ArrowUp is accepted on non-Mac hosts", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 1);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowUp", ctrlKey: true }));
		expect(harness.scrolledTo).toEqual([{ id: "0:0", align: "center" }]);
	});

	it("clamps at the top", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowUp", metaKey: true }));
		expect(harness.scrolledTo).toEqual([{ id: "0:0", align: "center" }]);
	});

	it("clamps at the bottom", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 1);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		expect(harness.scrolledTo).toEqual([{ id: "0:1", align: "center" }]);
	});

	it("ignores ArrowUp/Down without a meta or ctrl modifier", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown" }));
		expect(harness.scrolledTo).toEqual([]);
	});

	it("ignores chords that include Alt or Shift", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true, altKey: true }));
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true, shiftKey: true }));
		expect(harness.scrolledTo).toEqual([]);
	});

	it("stays put when there are no blocks", () => {
		harness = makeHarness([], 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		expect(harness.scrolledTo).toEqual([]);
	});

	it("applies the focused class to the new block section", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		const second = harness.container.querySelector('[data-terminal-block-id="0:1"]');
		expect(second?.classList.contains("terminal-block-focused")).toBe(true);
	});

	it("moves the focus class to the new block on the next key press", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second"), makeBlock("0:2", "third")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		const third = harness.container.querySelector('[data-terminal-block-id="0:2"]');
		const second = harness.container.querySelector('[data-terminal-block-id="0:1"]');
		expect(third?.classList.contains("terminal-block-focused")).toBe(true);
		expect(second?.classList.contains("terminal-block-focused")).toBe(false);
	});

	it("dispose() removes the keydown listener and clears the focus class", () => {
		const blocks = [makeBlock("0:0", "first"), makeBlock("0:1", "second")];
		harness = makeHarness(blocks, 0);
		harness.container.dispatchEvent(keyEvent({ key: "ArrowDown", metaKey: true }));
		const first = harness.container.querySelector('[data-terminal-block-id="0:0"]');
		expect(first?.classList.contains("terminal-block-focused")).toBe(false);
		const second = harness.container.querySelector('[data-terminal-block-id="0:1"]');
		expect(second?.classList.contains("terminal-block-focused")).toBe(true);
		harness.dispose();
		harness = null;
		const secondAfter = document.querySelector('[data-terminal-block-id="0:1"]');
		expect(secondAfter).toBeNull();
	});
});
